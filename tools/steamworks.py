"""Small Windows x64 binding to Valve's flat Steamworks API.

All calls, including callback pumping, belong to one thread. Structures follow
the Steamworks public headers; no Python callbacks are installed in native code.
The caller supplies its own legally installed steam_api64.dll.
"""
import ctypes as C
import os
import re
import time
from pathlib import Path

APP_ID = 4464990
I, U, Q, P, B, S = C.c_int, C.c_uint32, C.c_uint64, C.c_void_p, C.c_bool, C.c_char_p


class Identity(C.Structure):
    _pack_ = 1
    _fields_ = [('kind', I), ('size', I), ('data', C.c_byte * 128)]


class MessagePrefix(C.Structure):
    _fields_ = [('data', P), ('size', I), ('connection', U), ('identity', Identity)]


class Callback(C.Structure):
    _fields_ = [('user', I), ('kind', I), ('data', P), ('size', I)]


class Completed(C.Structure):
    _fields_ = [('call', Q), ('kind', I), ('size', U)]


class Created(C.Structure):
    _fields_ = [('result', I), ('lobby', Q)]


class Entered(C.Structure):
    _fields_ = [('lobby', Q), ('permissions', U), ('locked', B), ('result', U)]


class LobbyList(C.Structure):
    _fields_ = [('count', U)]


class FriendGame(C.Structure):
    _fields_ = [('game', Q), ('ip', U), ('port', C.c_uint16),
                ('query_port', C.c_uint16), ('lobby', Q)]


def lobby_argument(text):
    match = re.search(r'(?:^|\s)\+connect_lobby\s+(\d{1,20})(?:\s|$)', text)
    value = int(match[1]) if match else 0
    return value if 0 < value < 2**64 else 0


def find_dll(explicit=None):
    choices = [explicit, os.environ.get('ROWEMOD_STEAM_API'),
               Path(__file__).parent / 'deps' / 'steam_api64.dll',
               Path(r'E:\unreal\UE_5.4\Engine\Binaries\ThirdParty\Steamworks\Steamv157\Win64\steam_api64.dll')]
    for choice in choices:
        if choice and Path(choice).is_file():
            return Path(choice).resolve()
    raise RuntimeError('Steamworks DLL missing. Set ROWEMOD_STEAM_API to your steam_api64.dll, '
                       'or put it in tools/deps. See docs/steam-online.md.')


class Steam:
    def __init__(self, dll=None):
        if os.name != 'nt' or C.sizeof(P) != 8:
            raise RuntimeError('64-bit Windows Python is required')
        os.environ['SteamAppId'] = os.environ['SteamGameId'] = str(APP_ID)
        self.dll = C.CDLL(str(find_dll(dll)))
        self.cache, self.pending, self.events = {}, {}, []
        self.closed = True
        if not self.fn('SteamAPI_Init', B)():
            raise RuntimeError('Steam could not initialize. Sign into Steam with an account that owns Rollout Inline.')
        self.closed = False
        try:
            user = next((v for v in (23, 22, 21) if hasattr(self.dll, f'SteamAPI_SteamUser_v{v:03}')), None)
            if user is None:
                raise RuntimeError('Unsupported SteamUser interface')
            versions = {'User': f'SteamUser_v{user:03}', 'Utils': 'SteamUtils_v010',
                        'Friends': 'SteamFriends_v017', 'Apps': 'SteamApps_v008',
                        'Matchmaking': 'SteamMatchmaking_v009',
                        'NetworkingMessages': 'SteamNetworkingMessages_SteamAPI_v002',
                        'NetworkingUtils': 'SteamNetworkingUtils_SteamAPI_v004'}
            self.interfaces = {k: self.fn('SteamAPI_' + v, P)() for k, v in versions.items()}
            if not all(self.interfaces.values()):
                raise RuntimeError('Steamworks returned a missing interface')
            if self.call('Utils', 'GetAppID', U) != APP_ID or not self.call('User', 'BLoggedOn', B):
                raise RuntimeError('Steam is offline or initialized for the wrong game')
            self.user = self.call('User', 'GetSteamID', Q)
            self.name = self.call('Friends', 'GetPersonaName', S).decode('utf-8', 'replace')
            self.fn('SteamAPI_ManualDispatch_Init', None)()
            self.pipe = self.fn('SteamAPI_GetHSteamPipe', I)()
            self.call('NetworkingUtils', 'InitRelayNetworkAccess', None)
        except Exception:
            self.close()
            raise

    def fn(self, name, result, *args):
        if name not in self.cache:
            f = getattr(self.dll, name)
            f.restype, f.argtypes = result, list(args)
            self.cache[name] = f
        return self.cache[name]

    def call(self, interface, method, result, types=(), values=()):
        return self.fn('SteamAPI_ISteam' + interface + '_' + method, result, P, *types)(
            self.interfaces[interface], *values)

    def mm(self, method, result, types=(), values=()):
        return self.call('Matchmaking', method, result, types, values)

    def async_call(self, handle, kind, layout, done):
        if not handle:
            raise RuntimeError('Steam rejected the request')
        self.pending[handle] = (kind, layout, done, time.monotonic() + 20)

    def pump(self):
        self.fn('SteamAPI_ManualDispatch_RunFrame', None, I)(self.pipe)
        cb = Callback()
        for _ in range(256):
            if not self.fn('SteamAPI_ManualDispatch_GetNextCallback', B, I, C.POINTER(Callback))(self.pipe, C.byref(cb)):
                break
            try:
                if cb.kind == 703 and cb.size == C.sizeof(Completed):
                    completed = Completed.from_buffer_copy(C.string_at(cb.data, cb.size))
                    pending = self.pending.pop(completed.call, None)
                    if pending:
                        kind, layout, done, _ = pending
                        data, failed = layout(), B()
                        ok = completed.kind == kind and completed.size == C.sizeof(layout)
                        if ok:
                            ok = self.fn('SteamAPI_ManualDispatch_GetAPICallResult', B, I, Q, P, I, I, C.POINTER(B))(
                                self.pipe, completed.call, C.byref(data), C.sizeof(data), kind, C.byref(failed))
                        done(data if ok and not failed.value else None)
                elif 0 <= cb.size <= 8192:
                    self.events.append((cb.kind, C.string_at(cb.data, cb.size)))
            finally:
                self.fn('SteamAPI_ManualDispatch_FreeLastCallback', None, I)(self.pipe)
        for handle, (_, _, done, deadline) in list(self.pending.items()):
            if time.monotonic() >= deadline:
                del self.pending[handle]
                done(None)
        events, self.events = self.events, []
        return events

    def metadata(self, lobby, key):
        value = self.mm('GetLobbyData', S, (Q, S), (lobby, key.encode()))
        return (value or b'').decode('utf-8', 'replace')

    def set_metadata(self, lobby, key, value):
        if not self.mm('SetLobbyData', B, (Q, S, S), (lobby, key.encode(), str(value).encode())):
            raise RuntimeError('Steam could not update lobby metadata: ' + key)

    def members(self, lobby):
        count = self.mm('GetNumLobbyMembers', I, (Q,), (lobby,))
        return {self.mm('GetLobbyMemberByIndex', Q, (Q, I), (lobby, i)) for i in range(min(count, 8))}

    def owner(self, lobby):
        return self.mm('GetLobbyOwner', Q, (Q,), (lobby,))

    def presence(self, lobby):
        value = ('+connect_lobby ' + str(lobby)).encode() if lobby else None
        self.call('Friends', 'SetRichPresence', B, (S, S), (b'connect', value))

    def launch_lobby(self):
        buf = C.create_string_buffer(4096)
        self.call('Apps', 'GetLaunchCommandLine', I, (P, I), (buf, len(buf)))
        return lobby_argument(buf.value.decode('utf-8', 'replace'))

    def friends(self):
        result = []
        count = self.call('Friends', 'GetFriendCount', I, (I,), (4,))
        for i in range(max(0, count)):
            friend = self.call('Friends', 'GetFriendByIndex', Q, (I, I), (i, 4))
            game = FriendGame()
            if self.call('Friends', 'GetFriendGamePlayed', B, (Q, C.POINTER(FriendGame)), (friend, C.byref(game))):
                if game.game & 0xFFFFFF == APP_ID and game.lobby:
                    name = self.call('Friends', 'GetFriendPersonaName', S, (Q,), (friend,))
                    result.append({'id': game.lobby, 'name': (name or b'Friend').decode('utf-8', 'replace'),
                                   'map': 'Validates when joining', 'players': '?', 'source': 'Friend'})
        return result

    def identity(self, steam_id):
        value = Identity()
        self.fn('SteamAPI_SteamNetworkingIdentity_SetSteamID64', None, C.POINTER(Identity), Q)(C.byref(value), steam_id)
        return value

    def identity_id(self, value):
        return self.fn('SteamAPI_SteamNetworkingIdentity_GetSteamID64', Q, C.POINTER(Identity))(C.byref(value))

    def accept(self, steam_id):
        value = self.identity(steam_id)
        return self.call('NetworkingMessages', 'AcceptSessionWithUser', B, (C.POINTER(Identity),), (C.byref(value),))

    def disconnect(self, steam_id):
        value = self.identity(steam_id)
        self.call('NetworkingMessages', 'CloseSessionWithUser', B, (C.POINTER(Identity),), (C.byref(value),))

    def send(self, steam_id, payload, channel, reliable=False):
        value = self.identity(steam_id)
        # NoNagle; unreliable messages use NoDelay to avoid stale queues while connecting.
        flags = 9 if reliable else 5
        return self.call('NetworkingMessages', 'SendMessageToUser', I,
                         (C.POINTER(Identity), P, U, I, I),
                         (C.byref(value), payload, len(payload), flags, channel))

    def receive(self, channel, limit=32):
        ptrs = (P * limit)()
        count = self.call('NetworkingMessages', 'ReceiveMessagesOnChannel', I,
                          (I, C.POINTER(P), I), (channel, ptrs, limit))
        result = []
        for i in range(max(0, count)):
            try:
                message = C.cast(ptrs[i], C.POINTER(MessagePrefix)).contents
                if 0 < message.size <= 524288:
                    result.append((self.identity_id(message.identity), C.string_at(message.data, message.size)))
            finally:
                self.fn('SteamAPI_SteamNetworkingMessage_t_Release', None, P)(ptrs[i])
        return result

    def close(self):
        if not self.closed:
            self.closed = True
            self.fn('SteamAPI_Shutdown', None)()

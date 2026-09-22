"""Steam lobby controller and authenticated host relay for the existing mailbox."""
import ctypes as C
import json
import re
import struct
import time
import zlib

from rowemod_mp import Mailbox, MAX_FRAME, PROTO_VER, pack, unpack, write_status
from steamworks import B, I, Q, S, Created, Entered, LobbyList, Identity, lobby_argument

MOD = 'rowemod-gameplay'
WIRE_VERSION = 'steam-1'
CHANNEL = 27461
HEADER = struct.Struct('!4sQQ')
MOVEMENT = {'F', 'T', 'G*'}
KINDS = MOVEMENT | {'H', 'M', 'MREQ', 'MACK', 'Bye', 'G+', 'G-', 'A', 'B', 'L'}


def peer_id(steam_id):
    return f'{steam_id:032x}'


def encode_packet(lobby, sequence, peer, line):
    raw = pack(peer, line)
    if len(raw) > MAX_FRAME:
        raise ValueError('Frame exceeds transport limit')
    wire = HEADER.pack(b'RMS1', lobby, sequence) + zlib.compress(raw, 1)
    if len(wire) > MAX_FRAME:
        raise ValueError('Compressed frame exceeds Steam limit')
    return wire


def decode_packet(data, lobby):
    if not HEADER.size < len(data) <= MAX_FRAME:
        return None
    magic, room, sequence = HEADER.unpack_from(data)
    if magic != b'RMS1' or room != lobby:
        return None
    try:
        decoder = zlib.decompressobj()
        raw = decoder.decompress(data[HEADER.size:], MAX_FRAME + 1)
        if len(raw) > MAX_FRAME or not decoder.eof or decoder.unused_data or decoder.unconsumed_tail:
            return None
        parsed = unpack(raw)
        if not parsed:
            return None
        peer, line = parsed
        if not re.fullmatch('[0-9a-f]{32}', peer) or any(c in line for c in '\r\n\0'):
            return None
        kind = line.split('|', 1)[0]
        if kind not in KINDS or (kind != 'F' and len(line) > 2048):
            return None
        if kind == 'H':
            parts = line.split('|')
            if len(parts) != 5 or parts[3] != PROTO_VER:
                return None
        return sequence, peer, line
    except (ValueError, zlib.error):
        return None


class RateLimit:
    """Bound processing before decompression. Eight peers maximum per lobby."""
    def __init__(self):
        self.entries = {}

    def allow(self, peer, size, now, streams=1):
        started, count, total = self.entries.get(peer, (now, 0, 0))
        if now - started >= 1:
            started, count, total = now, 0, 0
        count, total = count + 1, total + size
        self.entries[peer] = started, count, total
        streams = max(1, min(7, streams))
        return count <= 160 * streams and total <= 4 * 1024 * 1024 * streams


class SteamBridge:
    def __init__(self, steam, root):
        self.steam, self.box = steam, Mailbox(root)
        self.lobby = self.host = 0
        self.mode, self.message = 'idle', 'Choose Host, Friends, or Public sessions'
        self.members, self.peers, self.hellos = set(), {}, {}
        self.last_sequence, self.rate = {}, RateLimit()
        self.origin_rate = RateLimit()
        self.movement, self.last_sent = {}, {}
        self.peer_stats, self.send_results = {}, {}
        self.rate_drops = 0
        self.map, self.generation = 'unknown', 0
        # A quick process restart can rejoin before the host observes the leave.
        # Avoid restarting the transport sequence at zero in that case.
        self.sequence = time.time_ns()
        self.rx = self.tx = self.dropped = 0
        self.next_heartbeat = self.next_status = self.next_members = 0
        self.rows, self.busy = [], False
        self.closed = False
        self.self_id = peer_id(steam.user)
        self.write_status()

    def error(self, message):
        self.message = str(message)

    def valid_lobby(self, lobby):
        return (self.steam.metadata(lobby, 'mod') == MOD and
                self.steam.metadata(lobby, 'protocol') == WIRE_VERSION and
                self.steam.metadata(lobby, 'game_protocol') == PROTO_VER)

    def host_session(self, name, visibility='friends'):
        self.leave()
        generation = self.generation
        self.busy = True
        self.message = 'Creating Steam lobby...'
        def created(result):
            if generation != self.generation:
                if result and result.result == 1:
                    self.steam.mm('LeaveLobby', None, (Q,), (result.lobby,))
                return
            self.busy = False
            if not result or result.result != 1:
                self.error('Steam lobby creation failed: ' + str(result.result if result else 'timeout/API failure'))
                return
            self.lobby, self.host, self.mode = result.lobby, self.steam.user, 'host'
            try:
                for key, value in {'mod': MOD, 'protocol': WIRE_VERSION, 'game_protocol': PROTO_VER,
                                   'host': str(self.host), 'name': name.strip()[:80] or 'Rollout session',
                                   'map': self.map}.items():
                    self.steam.set_metadata(self.lobby, key, value)
                self.steam.presence(self.lobby)
                self.message = 'Hosting ' + visibility + ' session. Launch the game and load a map.'
                self.refresh_members()
                self.write_status()
            except Exception as e:
                self.leave()
                self.error(e)
        types = {'private': 0, 'friends': 1, 'public': 2}
        if visibility not in types:
            raise ValueError('Unknown lobby visibility')
        self.steam.async_call(self.steam.mm('CreateLobby', Q, (I, I), (types[visibility], 8)), 513, Created, created)

    def join(self, lobby):
        lobby = int(lobby)
        if not 0 < lobby < 2**64:
            raise ValueError('Invalid lobby ID')
        if lobby == self.lobby:
            return
        self.leave()
        generation = self.generation
        self.busy = True
        self.message = 'Joining Steam lobby...'
        def entered(result):
            if generation != self.generation:
                if result and result.result == 1:
                    self.steam.mm('LeaveLobby', None, (Q,), (result.lobby,))
                return
            self.busy = False
            if not result or result.result != 1:
                reasons = {2: 'no longer exists', 3: 'access denied', 4: 'full', 5: 'Steam error', 6: 'banned'}
                self.error('Join failed: ' + reasons.get(result.result if result else 0, 'timeout or unavailable'))
                return
            self.lobby = result.lobby
            host = self.steam.owner(self.lobby)
            if (not self.valid_lobby(self.lobby) or
                    self.steam.metadata(self.lobby, 'host') != str(host) or host == self.steam.user):
                self.leave()
                self.error('Incompatible session or original host has left')
                return
            self.host, self.mode = host, 'join'
            self.steam.presence(self.lobby)
            self.refresh_members()
            self.message = 'Joined lobby; connecting to host...'
            self.next_heartbeat = 0
            self.write_status()
        self.steam.async_call(self.steam.mm('JoinLobby', Q, (Q,), (lobby,)), 504, Entered, entered)

    def browse(self):
        if self.busy:
            return
        self.busy = True
        generation = self.generation
        self.message = 'Searching public sessions...'
        for key, value in {'mod': MOD, 'protocol': WIRE_VERSION, 'game_protocol': PROTO_VER}.items():
            self.steam.mm('AddRequestLobbyListStringFilter', None, (S, S, I), (key.encode(), value.encode(), 0))
        self.steam.mm('AddRequestLobbyListDistanceFilter', None, (I,), (3,))
        self.steam.mm('AddRequestLobbyListResultCountFilter', None, (I,), (50,))
        def listed(result):
            if generation != self.generation:
                return
            self.busy = False
            if not result:
                self.error('Steam session search failed or timed out')
                return
            self.rows = []
            for i in range(min(result.count, 50)):
                lobby = self.steam.mm('GetLobbyByIndex', Q, (I,), (i,))
                if self.valid_lobby(lobby):
                    count = self.steam.mm('GetNumLobbyMembers', I, (Q,), (lobby,))
                    maximum = self.steam.mm('GetLobbyMemberLimit', I, (Q,), (lobby,))
                    self.rows.append({'id': lobby, 'name': self.steam.metadata(lobby, 'name'),
                                      'map': self.steam.metadata(lobby, 'map'), 'players': f'{count}/{maximum}',
                                      'source': 'Public'})
            self.message = f'{len(self.rows)} compatible public sessions found'
        self.steam.async_call(self.steam.mm('RequestLobbyList', Q), 510, LobbyList, listed)

    def friends(self):
        self.rows = self.steam.friends()
        self.message = f'{len(self.rows)} friends in Rollout lobbies; compatibility checked when joining'

    def refresh_members(self):
        if not self.lobby:
            return
        members = self.steam.members(self.lobby)
        if self.steam.owner(self.lobby) != self.host or self.host not in members:
            self.leave()
            self.error('Host left. Session ended.')
            return
        for member in self.members - members:
            self.drop(peer_id(member))
            self.steam.disconnect(member)
        self.members = members

    def hello(self):
        name = re.sub(r'[|\r\n\x00]', '_', self.steam.name)[:64]
        return f'H|0|{name}|{PROTO_VER}|{self.map}'

    def targets(self):
        return list(self.members - {self.steam.user}) if self.mode == 'host' else ([self.host] if self.host else [])

    def send(self, peer, line, targets):
        if not self.lobby:
            return
        self.sequence += 1
        packet = encode_packet(self.lobby, self.sequence, peer, line)
        kind = line.split('|', 1)[0]
        reliable = kind not in MOVEMENT
        for target in targets:
            if not reliable:
                # One newest pose per origin/destination, including the host.
                # Sending relays immediately always put the host at the back of
                # a congested NoDelay connection, potentially forever.
                self.movement[target, peer, kind] = (packet, time.monotonic())
                continue
            result = self.steam.send(target, packet, CHANNEL, reliable)
            if result == 1:
                self.tx += 1
            elif reliable:
                self.error('Steam send failed (result ' + str(result) + '); retrying with heartbeat')

    def flush_movement(self):
        now = time.monotonic()
        targets = set(self.targets())
        for key, (_, queued) in list(self.movement.items()):
            if key[0] not in targets or int(key[1], 16) not in self.members or now - queued > .25:
                del self.movement[key]
        for target in sorted(targets):
            keys = sorted(k for k in self.movement if k[0] == target)
            previous = self.last_sent.get(target)
            if previous is not None:
                keys = [k for k in keys if k > previous] + [k for k in keys if k <= previous]
            for key in keys:
                packet, _ = self.movement[key]
                result = self.steam.send(target, packet, CHANNEL, False)
                result_key = str(result)
                self.send_results[result_key] = self.send_results.get(result_key, 0) + 1
                stats = self.peer_stats.setdefault(key[1], {'frames_in': 0, 'poses_sent': 0, 'send_deferred': 0})
                if result == 1:
                    self.tx += 1
                    stats['poses_sent'] += 1
                    self.last_sent[target] = key
                    del self.movement[key]
                else:
                    stats['send_deferred'] += 1
                    self.dropped += 1
                    # Retain only the latest snapshot. Next tick starts after
                    # the last successful origin, so one skater cannot hog it.

    def receive(self, sender, payload):
        if not self.lobby or sender not in self.members or sender == self.steam.user:
            return
        if self.mode == 'join' and sender != self.host:
            return
        now = time.monotonic()
        streams = max(1, len(self.members) - 1) if self.mode == 'join' else 1
        if not self.rate.allow(sender, len(payload), now, streams):
            self.dropped += 1
            self.rate_drops += 1
            return
        parsed = decode_packet(payload, self.lobby)
        if not parsed:
            self.dropped += 1
            return
        sequence, peer, line = parsed
        kind = line.split('|', 1)[0]
        if peer == self.self_id or int(peer, 16) not in self.members:
            return
        # A client cannot impersonate anyone. Relayed origins are trusted only
        # from the lobby's original authenticated host.
        if self.mode == 'host' and (peer != peer_id(sender) or kind == 'MREQ'):
            return
        if kind == 'MREQ' and peer != peer_id(self.host):
            return
        # The authenticated host carries several origins. Keep a separate
        # per-origin cap without charging the whole lobby as a single player.
        if not self.origin_rate.allow(peer, len(payload), now):
            self.dropped += 1
            self.rate_drops += 1
            return
        key = (peer, kind)
        if sequence <= self.last_sequence.get(key, -1):
            return
        self.last_sequence[key] = sequence
        if peer not in self.peers and kind != 'H':
            return
        if kind == 'H':
            self.hellos[peer] = line
        elif kind in {'M', 'MACK'} and peer in self.hellos:
            parts = line.split('|')
            if len(parts) >= 3:
                hello = self.hellos[peer].split('|')
                hello[4] = parts[2]
                self.hellos[peer] = '|'.join(hello)
        stats = self.peer_stats.setdefault(peer, {'frames_in': 0, 'poses_sent': 0, 'send_deferred': 0})
        if kind == 'F':
            stats['frames_in'] += 1
        self.peers[peer] = time.monotonic()
        self.rx += 1
        self.box.push_in(line, peer)
        if self.mode == 'host':
            self.send(peer, line, [p for p in self.targets() if p != sender])
        if kind == 'Bye':
            self.drop(peer)

    def drop(self, peer):
        if peer in self.peers:
            self.box.push_in('Bye|0', peer)
        self.peers.pop(peer, None)
        self.hellos.pop(peer, None)
        self.rate.entries.pop(int(peer, 16), None)
        self.origin_rate.entries.pop(peer, None)
        self.peer_stats.pop(peer, None)
        self.last_sent.pop(int(peer, 16), None)
        self.movement = {k: v for k, v in self.movement.items() if k[1] != peer and k[0] != int(peer, 16)}
        self.last_sequence = {k: v for k, v in self.last_sequence.items() if k[0] != peer}

    def observe(self, line):
        parts = line.split('|')
        old = self.map
        if parts[0] == 'H' and len(parts) >= 5:
            self.map = parts[4]
        elif parts[0] == 'M' and len(parts) >= 3:
            self.map = parts[2]
        if self.map != old and self.mode == 'host' and self.lobby:
            self.steam.set_metadata(self.lobby, 'map', self.map[:128])

    def tick(self):
        for kind, data in self.steam.pump():
            if kind == 333 and len(data) == 16:  # GameLobbyJoinRequested
                self.join(struct.unpack_from('<Q', data)[0])
            elif kind == 337 and len(data) >= 9:  # Rich presence Join Game
                lobby = lobby_argument(data[8:].split(b'\0', 1)[0].decode('utf-8', 'replace'))
                if lobby:
                    self.join(lobby)
            elif kind == 1251 and len(data) == C.sizeof(Identity):
                sender = self.steam.identity_id(Identity.from_buffer_copy(data))
                self.refresh_members()
                if sender in self.members and sender != self.steam.user and (self.mode == 'host' or sender == self.host):
                    self.steam.accept(sender)
                else:
                    self.steam.disconnect(sender)
            elif kind == 1252:
                self.error('Steam peer connection failed. Check the connection, then leave and rejoin.')
            elif kind == 512 and len(data) >= 8 and struct.unpack_from('<Q', data)[0] == self.lobby:
                self.leave()
                self.error('Removed from the lobby')
        now = time.monotonic()
        if now >= self.next_members:
            self.next_members = now + .5
            self.refresh_members()
        for sender, payload in self.steam.receive(CHANNEL):
            self.receive(sender, payload)
        lines = self.box.poll_out()
        # A delayed UI tick must not dump a queue of stale poses onto the network.
        latest = {line.split('|', 1)[0]: i for i, line in enumerate(lines) if line.split('|', 1)[0] in MOVEMENT}
        for i, line in enumerate(lines):
            self.observe(line)
            kind = line.split('|', 1)[0]
            if kind not in KINDS or (kind in MOVEMENT and latest[kind] != i):
                continue
            if self.mode == 'join' and kind == 'MREQ':
                continue
            if self.lobby:
                self.send(self.self_id, self.hello() if kind == 'H' else line, self.targets())
        if self.lobby and now >= self.next_heartbeat:
            self.next_heartbeat = now + 1
            self.send(self.self_id, self.hello(), self.targets())
            # Heartbeats restore the roster after Lua reload, including relayed peers.
            if self.mode == 'host':
                for peer, hello in list(self.hellos.items()):
                    self.send(peer, hello, [p for p in self.targets() if p != int(peer, 16)])
            for peer, last in list(self.peers.items()):
                if now - last > 8:
                    self.drop(peer)
        self.flush_movement()
        if now >= self.next_status:
            self.next_status = now + 1
            self.write_status()

    def write_status(self):
        write_status(self.box.root, f'{self.mode} transport=steam lobby={self.lobby} peers={len(self.peers)} rx={self.rx} tx={self.tx}')
        (self.box.root / 'connected.txt').write_text('1\n' if self.peers else '0\n', encoding='ascii')
        status = {'transport': 'steam', 'role': self.mode, 'lobby': str(self.lobby), 'peers': len(self.peers),
                  'rx': self.rx, 'tx': self.tx, 'dropped': self.dropped, 'map': self.map, 'message': self.message,
                  'rate_drops': self.rate_drops, 'pending_poses': len(self.movement),
                  'movement_send_results': self.send_results, 'peer_streams': self.peer_stats}
        (self.box.root / 'steam_status.json').write_text(json.dumps(status, indent=2), encoding='utf-8')

    def leave(self):
        self.generation += 1
        self.busy = False
        if self.lobby:
            try:
                self.send(self.self_id, 'Bye|0', self.targets())
            finally:
                if self.mode == 'host':
                    self.steam.mm('SetLobbyJoinable', B, (Q, B), (self.lobby, False))
                self.steam.mm('LeaveLobby', None, (Q,), (self.lobby,))
                self.steam.presence(0)
        for member in self.members - {self.steam.user}:
            self.steam.disconnect(member)
        for peer in list(self.peers):
            self.drop(peer)
        self.members.clear()
        self.rate.entries.clear()
        self.origin_rate.entries.clear()
        self.movement.clear()
        self.last_sent.clear()
        self.peer_stats.clear()
        self.lobby = self.host = 0
        self.mode, self.message = 'idle', 'Disconnected'
        self.write_status()

    def close(self):
        if not self.closed:
            self.closed = True
            try:
                self.leave()
            finally:
                self.steam.close()

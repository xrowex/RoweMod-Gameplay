"""Check Steamworks availability without creating lobbies or inviting anyone.

Uses an explicitly supplied, locally installed Steamworks redistributable.
Does not alter the game installation, running LAN bridges, or Steam settings.
"""
import argparse
import ctypes as C
import json
import os
import struct
import time
from pathlib import Path


class AuthStatus(C.Structure):
    _fields_ = [('availability', C.c_int), ('debug', C.c_char * 256)]


class RelayStatus(C.Structure):
    _fields_ = [('availability', C.c_int), ('measuring', C.c_int),
                ('network_config', C.c_int), ('any_relay', C.c_int),
                ('debug', C.c_char * 256)]


def probe(dll_path, app_id=4464990, timeout=15):
    if os.name != 'nt' or struct.calcsize('P') != 8:
        raise RuntimeError('This probe requires 64-bit Windows Python')
    os.environ['SteamAppId'] = str(app_id)
    os.environ['SteamGameId'] = str(app_id)
    sdk = C.CDLL(str(Path(dll_path).resolve(strict=True)))

    def bind(name, result, *args):
        fn = getattr(sdk, name)
        fn.restype, fn.argtypes = result, list(args)
        return fn

    initialize = bind('SteamAPI_Init', C.c_bool)
    shutdown = bind('SteamAPI_Shutdown', None)
    callbacks = bind('SteamAPI_RunCallbacks', None)
    report = {'requested_app_id': app_id, 'initialized': bool(initialize()),
              'creates_lobbies': False, 'sends_invites': False,
              'cross_account_connection_tested': False}
    if not report['initialized']:
        return report
    try:
        # The engine's bundled binary can predate its SDK headers. Only these
        # user interface versions are used, through the stable flat BLoggedOn API.
        user_getter = next((name for name in ('SteamAPI_SteamUser_v023',
                           'SteamAPI_SteamUser_v022', 'SteamAPI_SteamUser_v021')
                            if hasattr(sdk, name)), None)
        if user_getter is None:
            report['error'] = 'No supported SteamUser interface export'
            return report
        getters = {'user': user_getter,
                   'utils': 'SteamAPI_SteamUtils_v010',
                   'lobbies': 'SteamAPI_SteamMatchmaking_v009',
                   'messages': 'SteamAPI_SteamNetworkingMessages_SteamAPI_v002',
                   'sockets': 'SteamAPI_SteamNetworkingSockets_SteamAPI_v012',
                   'network_utils': 'SteamAPI_SteamNetworkingUtils_SteamAPI_v004'}
        report['interface_exports'] = getters
        missing = [export for export in getters.values() if not hasattr(sdk, export)]
        if missing:
            report['missing_exports'] = missing
            return report
        interfaces = {name: bind(export, C.c_void_p)() for name, export in getters.items()}
        report['interfaces'] = {name: bool(ptr) for name, ptr in interfaces.items()}
        if not all(interfaces.values()):
            return report
        report['actual_app_id'] = bind('SteamAPI_ISteamUtils_GetAppID', C.c_uint32, C.c_void_p)(interfaces['utils'])
        report['logged_on'] = bool(bind('SteamAPI_ISteamUser_BLoggedOn', C.c_bool, C.c_void_p)(interfaces['user']))
        if report['actual_app_id'] != app_id:
            return report
        bind('SteamAPI_ISteamNetworkingSockets_InitAuthentication', C.c_int, C.c_void_p)(interfaces['sockets'])
        bind('SteamAPI_ISteamNetworkingUtils_InitRelayNetworkAccess', None, C.c_void_p)(interfaces['network_utils'])
        auth_query = bind('SteamAPI_ISteamNetworkingSockets_GetAuthenticationStatus', C.c_int, C.c_void_p, C.POINTER(AuthStatus))
        relay_query = bind('SteamAPI_ISteamNetworkingUtils_GetRelayNetworkStatus', C.c_int, C.c_void_p, C.POINTER(RelayStatus))
        auth, relay = AuthStatus(), RelayStatus()
        end = time.monotonic() + timeout
        while True:
            callbacks()
            auth_query(interfaces['sockets'], C.byref(auth))
            relay_query(interfaces['network_utils'], C.byref(relay))
            if (auth.availability == 100 and relay.availability == 100) or time.monotonic() >= end:
                break
            time.sleep(.1)
        report['authentication'] = {'availability': auth.availability, 'detail': auth.debug.decode(errors='replace')}
        report['relay'] = {'availability': relay.availability, 'network_config': relay.network_config,
                           'any_relay': relay.any_relay, 'detail': relay.debug.decode(errors='replace')}
        return report
    finally:
        shutdown()


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--steam-api', required=True, type=Path)
    parser.add_argument('--app-id', type=int, default=4464990)
    parser.add_argument('--out', type=Path)
    args = parser.parse_args()
    result = probe(args.steam_api, args.app_id)
    text = json.dumps(result, indent=2) + '\n'
    print(text)
    if args.out:
        args.out.parent.mkdir(parents=True, exist_ok=True)
        args.out.write_text(text, encoding='utf-8')

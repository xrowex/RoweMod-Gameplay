"""Steam bridge policy tests; fake backend models authenticated API identities."""
import ctypes as C
import sys
import tempfile
import unittest
import zlib
from pathlib import Path
from types import SimpleNamespace

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'tools'))
from steam_mp import SteamBridge, MOD, WIRE_VERSION, HEADER, MAX_FRAME, RateLimit, encode_packet, decode_packet, peer_id
from steamworks import Callback, Created, Entered, Identity, FriendGame, MessagePrefix, lobby_argument
from rowemod_mp import pack


class FakeSteam:
    user = 11
    name = 'Test skater'

    def __init__(self):
        self.roster = {11, 22, 33}
        self.host = 11
        self.metadata_values = {'mod': MOD, 'protocol': WIRE_VERSION, 'game_protocol': '3', 'host': '11'}
        self.sent, self.closed, self.calls, self.pending = [], [], [], []
        self.incoming, self.accepted = [], []

    def mm(self, method, result, types=(), values=()):
        self.calls.append((method, values))
        return 99

    def async_call(self, handle, kind, layout, done):
        self.pending.append(done)

    def metadata(self, lobby, key):
        return self.metadata_values.get(key, '')

    def set_metadata(self, lobby, key, value):
        self.metadata_values[key] = value

    def members(self, lobby):
        return set(self.roster)

    def owner(self, lobby):
        return self.host

    def presence(self, lobby):
        pass

    def send(self, target, payload, channel, reliable):
        self.sent.append((target, decode_packet(payload, 100), reliable))
        return 1

    def disconnect(self, peer):
        self.closed.append(peer)

    def accept(self, peer):
        self.accepted.append(peer)

    def pump(self):
        return []

    def receive(self, channel):
        pending, self.incoming = self.incoming, []
        return pending

    def close(self):
        pass


class SteamPolicyTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.api = FakeSteam()
        self.bridge = SteamBridge(self.api, Path(self.temp.name))
        self.bridge.lobby, self.bridge.host, self.bridge.mode = 100, 11, 'host'
        self.bridge.members = {11, 22, 33}

    def send(self, sender, peer=None, line='H|0|Remote|3|Park', sequence=1, lobby=100):
        self.bridge.receive(sender, encode_packet(lobby, sequence, peer_id(peer or sender), line))

    def test_host_binds_origin_to_authenticated_sender(self):
        self.send(22, peer=33)
        self.send(99)
        self.assertFalse(self.bridge.peers)
        self.assertEqual(self.bridge.box.drain_in(), [])
        self.send(22)
        self.assertIn(peer_id(22), self.bridge.peers)
        self.assertEqual(self.api.sent[0][0], 33)
        self.assertEqual(self.api.sent[0][1][1], peer_id(22))

    def test_client_cannot_announce_host_map(self):
        self.send(22)
        self.bridge.box.drain_in()
        self.send(22, line='MREQ|1|OtherPark', sequence=2)
        self.assertEqual(self.bridge.box.drain_in(), [])

    def test_join_accepts_only_host_and_lobby_member_origins(self):
        self.bridge.mode, self.bridge.host = 'join', 22
        self.send(33)
        self.send(22, peer=99)
        self.assertEqual(self.bridge.box.drain_in(), [])
        self.send(22, peer=33)
        self.assertEqual(self.bridge.box.drain_in()[0][0], peer_id(33))
        self.send(22, peer=33, line='MREQ|1|WrongPark', sequence=2)
        self.assertEqual(self.bridge.box.drain_in(), [])
        self.send(22)
        self.bridge.box.drain_in()
        self.send(22, line='MREQ|1|HostPark', sequence=3)
        self.assertEqual(self.bridge.box.drain_in()[0][1], 'MREQ|1|HostPark')

    def test_stale_frames_duplicate_frames_and_old_lobby_rejected(self):
        self.send(22)
        self.bridge.box.drain_in()
        self.send(22, line='F|9|test', sequence=9)
        self.send(22, line='F|8|test', sequence=8)
        self.send(22, line='F|9|test', sequence=9)
        self.send(22, sequence=20, lobby=999)
        self.assertEqual(len(self.bridge.box.drain_in()), 1)

    def test_protocol_mismatch_and_pose_before_hello_rejected(self):
        self.send(22, line='H|0|Remote|2|Park')
        self.send(22, line='F|2|test', sequence=2)
        self.assertEqual(self.bridge.box.drain_in(), [])

    def test_membership_removal_cleans_up_avatar_and_transport(self):
        self.send(22)
        self.bridge.box.drain_in()
        self.api.roster.remove(22)
        self.bridge.refresh_members()
        self.assertEqual(self.bridge.box.drain_in(), [(peer_id(22), 'Bye|0')])
        self.assertIn(22, self.api.closed)
        self.assertNotIn(peer_id(22), self.bridge.peers)

    def test_host_departure_ends_session_instead_of_migrating(self):
        self.api.host = 22
        self.bridge.refresh_members()
        self.assertEqual(self.bridge.lobby, 0)
        self.assertEqual(self.bridge.mode, 'idle')
        self.assertIn('Host left', self.bridge.message)

    def test_late_create_result_after_cancel_is_left(self):
        self.bridge.host_session('Test', 'private')
        callback = self.api.pending[-1]
        self.bridge.leave()
        callback(SimpleNamespace(result=1, lobby=321))
        self.assertEqual(self.bridge.lobby, 0)
        self.assertIn(('LeaveLobby', (321,)), self.api.calls)

    def test_incompatible_join_is_left(self):
        self.bridge.join(200)
        self.api.metadata_values['protocol'] = 'old-version'
        self.api.pending[-1](SimpleNamespace(result=1, lobby=200))
        self.assertEqual(self.bridge.lobby, 0)
        self.assertIn('Incompatible', self.bridge.message)

    def test_movement_uses_unreliable_control_uses_reliable(self):
        self.bridge.send(peer_id(11), 'F|1|test', [22])
        self.bridge.flush_movement()
        self.bridge.send(peer_id(11), 'MREQ|1|Park', [22])
        self.assertFalse(self.api.sent[0][2])
        self.assertTrue(self.api.sent[1][2])

    def test_three_player_mailbox_relay_keeps_origins_independent(self):
        clients = []
        for user in (22, 33):
            api = FakeSteam()
            api.user = user
            bridge = SteamBridge(api, Path(self.temp.name) / str(user))
            bridge.lobby, bridge.host, bridge.mode = 100, 11, 'join'
            bridge.members = {11, 22, 33}
            clients.append(bridge)
        self.send(22)
        self.send(33)
        for target, parsed, reliable in self.api.sent:
            sequence, peer, line = parsed
            receiver = clients[0] if target == 22 else clients[1]
            receiver.receive(11, encode_packet(100, sequence, peer, line))
        self.api.sent.clear()
        self.send(22, line='F|2|independent-pose-A', sequence=2)
        self.send(33, line='F|2|independent-pose-B', sequence=2)
        self.bridge.flush_movement()
        for target, parsed, reliable in self.api.sent:
            sequence, peer, line = parsed
            receiver = clients[0] if target == 22 else clients[1]
            receiver.receive(11, encode_packet(100, sequence, peer, line))
        self.assertIn((peer_id(33), 'F|2|independent-pose-B'), clients[0].box.drain_in())
        self.assertIn((peer_id(22), 'F|2|independent-pose-A'), clients[1].box.drain_in())

    def test_four_players_share_congested_downlink_without_starvation(self):
        # Model Steam NoDelay accepting only one pose per flush on a slow link.
        # The old relay always attempted client 22 first and the host last.
        self.bridge.members = self.api.roster = {11, 22, 33, 44}
        accepted, budget = [], [1]
        original_send = self.api.send
        def constrained(target, payload, channel, reliable):
            if target == 44 and not reliable:
                if not budget[0]:
                    return 41  # k_EResultIgnored
                budget[0] -= 1
                accepted.append(decode_packet(payload, 100)[1])
            return original_send(target, payload, channel, reliable)
        self.api.send = constrained
        for sender in (22, 33, 44):
            self.send(sender)
        for tick in range(12):
            budget[0] = 1
            self.send(22, line=f'F|{tick+2}|A', sequence=tick+2)
            self.send(33, line=f'F|{tick+2}|B', sequence=tick+2)
            self.bridge.send(peer_id(11), f'F|{tick+2}|Host', self.bridge.targets())
            self.bridge.flush_movement()
        self.assertEqual(set(accepted), {peer_id(11), peer_id(22), peer_id(33)})
        for peer in set(accepted):
            self.assertEqual(accepted.count(peer), 4)

    def test_relay_rate_budget_counts_all_origins(self):
        self.bridge.mode, self.bridge.host = 'join', 22
        self.bridge.members = {11, 22, 33, 44}
        for origin in (22, 33, 44):
            self.send(22, peer=origin)
        self.bridge.box.drain_in()
        # Each origin is below its own budget, while aggregate exceeds one user.
        from unittest.mock import patch
        with patch('steam_mp.time.monotonic', return_value=100):
            self.bridge.rate.entries.clear()
            for seq in range(2, 72):
                for origin in (22, 33, 44):
                    self.send(22, peer=origin, line=f'F|{seq}|pose', sequence=seq)
        lines = self.bridge.box.drain_in()
        self.assertEqual(len(lines), 210)

    def test_replayed_hello_uses_latest_announced_map(self):
        self.send(22, line='H|0|Remote|3|StartMenu')
        self.send(22, line='M|2|OutdoorSkatepark', sequence=2)
        self.assertEqual(self.bridge.hellos[peer_id(22)], 'H|0|Remote|3|OutdoorSkatepark')

    def test_four_player_sustained_mailboxes_and_late_join(self):
        from unittest.mock import patch
        users = {11, 22, 33, 44}
        bridges = {11: self.bridge}
        for user in sorted(users - {11}):
            api = FakeSteam(); api.user = user
            bridge = SteamBridge(api, Path(self.temp.name) / str(user))
            bridge.lobby, bridge.host, bridge.mode = 100, 11, 'join'
            bridges[user] = bridge
        for bridge in bridges.values():
            bridge.members = bridge.steam.roster = users
        def route():
            for sender, bridge in bridges.items():
                packets, bridge.steam.sent = bridge.steam.sent, []
                for target, (seq, peer, line), _ in packets:
                    bridges[target].steam.incoming.append((sender, encode_packet(100, seq, peer, line)))
        seen = {user: {} for user in users}
        for tick in range(120):
            with patch('steam_mp.time.monotonic', return_value=100 + tick * .05):
                for user, bridge in bridges.items():
                    # Last skater starts a second later than the rest.
                    if user == 44 and tick < 20:
                        continue
                    if tick in (0, 20):
                        bridge.box.write_out(f'H|1|Skater{user}|3|OutdoorSkatepark')
                    bridge.box.write_out(f'F|{tick+2}|pose-{user}-{tick}')
                    bridge.tick()
                route()
                for user, bridge in bridges.items():
                    for peer, line in bridge.box.drain_in():
                        if line.startswith('F|'):
                            seen[user][peer] = line
        for user in users:
            self.assertEqual(set(seen[user]), {peer_id(p) for p in users - {user}})
            for peer, line in seen[user].items():
                self.assertIn(f'pose-{int(peer,16)}-', line)
                self.assertGreater(int(line.rsplit('-', 1)[1]), 110)

    def test_pending_poses_replace_expire_and_clear_on_leave(self):
        from unittest.mock import patch
        with patch('steam_mp.time.monotonic', return_value=100):
            for seq in range(20):
                self.bridge.send(peer_id(11), f'F|{seq}|pose', [22])
            self.assertEqual(len(self.bridge.movement), 1)
            self.bridge.flush_movement()
            self.assertEqual(self.api.sent[-1][1][2], 'F|19|pose')
            self.bridge.send(peer_id(11), 'F|20|old', [22])
        count = len(self.api.sent)
        with patch('steam_mp.time.monotonic', return_value=101):
            self.bridge.flush_movement()
        self.assertEqual(len(self.api.sent), count)
        self.bridge.send(peer_id(11), 'F|21|pending', [22])
        self.bridge.leave()
        self.assertFalse(self.bridge.movement)

    def test_single_origin_cannot_use_entire_relay_budget(self):
        from unittest.mock import patch
        self.bridge.mode, self.bridge.host = 'join', 22
        self.bridge.members = {11, 22, 33, 44}
        with patch('steam_mp.time.monotonic', return_value=100):
            self.send(22)
            self.bridge.box.drain_in()
            for seq in range(2, 180):
                self.send(22, line=f'F|{seq}|pose', sequence=seq)
        self.assertLessEqual(len(self.bridge.box.drain_in()), 160)
        self.assertGreater(self.bridge.rate_drops, 0)

    def test_full_mailbox_path_flows_both_directions(self):
        """Exercise the same mailbox->bridge->mailbox route each game uses."""
        client_api = FakeSteam()
        client_api.user = 22
        client = SteamBridge(client_api, Path(self.temp.name) / 'client')
        client.lobby, client.host, client.mode = 100, 11, 'join'
        client.members = {11, 22}
        self.api.roster = {11, 22}
        self.bridge.members = {11, 22}

        # Host game writes its hello and pose; the joining game receives both.
        self.bridge.box.write_out('H|1|Host|3|OutdoorSkatepark')
        self.bridge.box.write_out('F|2|host-pose')
        self.bridge.tick()
        for target, (sequence, peer, line), _ in self.api.sent:
            if target == 22:
                client.receive(11, encode_packet(100, sequence, peer, line))
        client_inbox = client.box.drain_in()
        self.assertIn((peer_id(11), 'H|0|Test skater|3|OutdoorSkatepark'), client_inbox)
        self.assertIn((peer_id(11), 'F|2|host-pose'), client_inbox)

        # The joining game writes its hello and pose; the host receives both.
        client.box.write_out('H|1|Joiner|3|OutdoorSkatepark')
        client.box.write_out('F|2|joiner-pose')
        client.tick()
        for target, (sequence, peer, line), _ in client_api.sent:
            if target == 11:
                self.bridge.receive(22, encode_packet(100, sequence, peer, line))
        host_inbox = self.bridge.box.drain_in()
        self.assertIn((peer_id(22), 'H|0|Test skater|3|OutdoorSkatepark'), host_inbox)
        self.assertIn((peer_id(22), 'F|2|joiner-pose'), host_inbox)


class SteamWireTests(unittest.TestCase):
    def test_bounded_decompression_and_trailing_data(self):
        bomb = HEADER.pack(b'RMS1', 100, 1) + zlib.compress(b'A' * (MAX_FRAME + 1))
        self.assertIsNone(decode_packet(bomb, 100))
        good = encode_packet(100, 1, peer_id(22), 'H|0|User|3|Park')
        self.assertIsNone(decode_packet(good + b'junk', 100))
        self.assertIsNone(decode_packet(good[:-1], 100))
        self.assertIsNotNone(decode_packet(good, 100))

    def test_line_injection_invalid_origin_and_bad_control_rejected(self):
        for peer, line in [(peer_id(22), 'H|0|User|3|Park\nMREQ|1|Hack'), ('@evil', 'Bye|1'),
                           (peer_id(22), 'EVAL|1|script'), (peer_id(22), 'H|0|' + 'x' * 3000 + '|3|Park')]:
            packet = HEADER.pack(b'RMS1', 100, 1) + zlib.compress(pack(peer, line))
            self.assertIsNone(decode_packet(packet, 100))

    def test_rate_limit_reset(self):
        limit = RateLimit()
        for _ in range(160):
            self.assertTrue(limit.allow(22, 10, 0))
        self.assertFalse(limit.allow(22, 10, .5))
        self.assertTrue(limit.allow(22, 10, 1))
        self.assertFalse(limit.allow(22, 5 * 1024 * 1024, 2))

    def test_native_abi_and_safe_launch_argument(self):
        self.assertEqual(C.sizeof(Identity), 136)
        self.assertEqual(C.sizeof(Callback), 24)
        self.assertEqual(C.sizeof(Created), 16)
        self.assertEqual(C.sizeof(Entered), 24)
        self.assertEqual(C.sizeof(FriendGame), 24)
        self.assertEqual(MessagePrefix.identity.offset, 16)
        self.assertEqual(lobby_argument('-windowed +connect_lobby 12345'), 12345)
        for value in ['+connect_lobby 123&evil', '+connect_lobby 18446744073709551616', '+connect_lobby -1']:
            self.assertEqual(lobby_argument(value), 0)


if __name__ == '__main__':
    unittest.main()

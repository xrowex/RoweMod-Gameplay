"""Exercise the real v3 fragmentation, identity and host relay implementation."""
import os
import sys
import tempfile
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'tools'))
import rowemod_mp as mp


class FragmentTests(unittest.TestCase):
    def test_reordered_fragments_and_missing_frame_recovery(self):
        line = 'F|1|' + os.urandom(24000).hex()
        packets = mp.fragments('a' * 32, line, 1)
        self.assertGreater(len(packets), 2)
        rx = mp.Reassembler()
        addr = ('127.0.0.1', 123)
        for p in packets[:-1]:
            self.assertIsNone(rx.feed(p, addr, now=0))
        # An incomplete old frame must not block the next complete frame.
        result = None
        for p in reversed(mp.fragments('a' * 32, line, 2)):
            result = rx.feed(p, addr, now=.1)
        self.assertEqual(result, ('a' * 32, line))
        self.assertIsNone(rx.feed(packets[-1], addr, now=3))

    def test_truncated_or_oversized_frame_is_rejected(self):
        rx = mp.Reassembler()
        self.assertIsNone(mp.unpack(mp.pack('a', 'hello')[:-1]))
        with self.assertRaises(ValueError):
            mp.fragments('a' * 32, 'x' * mp.MAX_FRAME, 1)
        corrupt = mp.FRAG_HEADER.pack(b'RMF3', 1, 0, 1) + b'not zlib'
        self.assertIsNone(rx.feed(corrupt, ('127.0.0.1', 123)))


class RelayTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.hub = mp.UdpHub(0, mp.Mailbox(Path(self.tmp.name)), 'same', None)
        self.sent = []
        self.hub._send = lambda peer, line, targets: self.sent.append((peer, line, list(targets)))

    def tearDown(self):
        self.hub.sock.close()
        self.tmp.cleanup()

    def test_same_names_keep_independent_identity_and_relay_source(self):
        a, b = 'a' * 32, 'b' * 32
        aa, ba = ('127.0.0.1', 10001), ('127.0.0.1', 10002)
        self.hub._receive(a, 'H|0|same|3|Park', aa)
        self.hub._receive(b, 'H|0|same|3|Park', ba)
        self.assertEqual(len(self.hub.peers), 2)
        self.hub.mailbox.drain_in()
        self.sent.clear()
        self.hub._receive(a, 'F|1|pose', aa)
        self.assertEqual(self.sent, [(a, 'F|1|pose', [ba])])
        self.assertEqual(self.hub.mailbox.drain_in(), [(a, 'F|1|pose')])
        self.hub._receive(a, 'F|2|spoof', ba)
        self.assertEqual(self.hub.mailbox.drain_in(), [])
        self.hub._receive(b, 'MREQ|3|WrongMap', ba)
        self.assertEqual(self.hub.mailbox.drain_in(), [])
        self.hub._receive(b, 'Bye|4', ba)
        self.assertNotIn(b, self.hub.peers)
        self.hub._receive(b, 'H|0|same|3|Park', ba)
        self.assertEqual(len(self.hub.peers), 2)

    def test_join_accepts_only_configured_host_and_host_map_authority(self):
        self.hub.mode = 'join'
        addr = self.hub.remote = ('127.0.0.1', 27045)
        host, other = 'a' * 32, 'b' * 32
        self.hub._receive(host, 'HOST|' + host, ('127.0.0.1', 111))
        self.assertIsNone(self.hub.host_id)
        self.hub._receive(host, 'HOST|' + host, addr)
        self.hub._receive(other, 'MREQ|1|Wrong', addr)
        self.assertEqual(self.hub.mailbox.drain_in(), [])
        self.hub._receive(host, 'MREQ|2|Park', addr)
        self.assertEqual(self.hub.mailbox.drain_in(), [(host, 'MREQ|2|Park')])


if __name__ == '__main__':
    unittest.main()

import os
import sys
import tempfile
import time
import unittest
from pathlib import Path
from types import SimpleNamespace
from unittest.mock import Mock

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'tools'))
import menu_control as menu


class MenuControlTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.bridge = Mock(box=SimpleNamespace(root=self.root))

    def write(self, name, data):
        folder = self.root / 'control'
        folder.mkdir(exist_ok=True)
        path = folder / name
        path.write_text(data, encoding='utf-8')
        return path

    def test_host_and_exact_64_bit_join(self):
        self.write('1.txt', 'action\thost\nname\tTest%09session\nvisibility\tfriends\n')
        self.write('2.txt', 'action\tjoin\nlobby\t109775244182498723\n')
        menu.consume(self.bridge, Mock())
        self.bridge.host_session.assert_called_once_with('Testsession', 'friends')
        self.bridge.join.assert_called_once_with(109775244182498723)
        self.assertEqual(list((self.root / 'control').iterdir()), [])

    def test_expired_oversized_partial_and_invalid_do_not_connect(self):
        stale = self.write('1.txt', 'action\tjoin\nlobby\t123\n')
        os.utime(stale, (time.time()-120, time.time()-120))
        self.write('2.txt', 'x'*4097)
        self.write('3.tmp', 'action\thost\n')
        self.write('4.txt', 'action\tjoin\nlobby\t18446744073709551616\n')
        self.write('5.txt', 'action\tunknown\n')
        self.write('6.txt', 'action\thost\naction\tjoin\n')
        menu.consume(self.bridge, Mock())
        self.bridge.join.assert_not_called()
        self.bridge.host_session.assert_not_called()
        self.assertEqual(self.bridge.error.call_count, 3)
        self.assertTrue((self.root/'control/3.tmp').exists())

    def test_browser_leave_and_legacy_show(self):
        for n, action in enumerate(('friends', 'browse', 'leave')):
            self.write(f'{n}.txt', f'action\t{action}\n')
        self.write('show.json', '{"action":"show"}')
        show = Mock()
        menu.consume(self.bridge, show)
        for action in ('friends', 'browse', 'leave'):
            getattr(self.bridge, action).assert_called_once_with()
        show.assert_called_once_with()

    def test_snapshot_preserves_ids_and_escapes_untrusted_names(self):
        b = SimpleNamespace(box=SimpleNamespace(root=self.root), message='ready', mode='host',
                            map='park', lobby=109775244182498723, peers={}, members=[1], busy=False,
                            rows=[dict(id=109775244182498723, name='hello\nroom\t%20', map='park', players=1, source='friends')])
        menu.publish(b)
        data = (self.root/'menu_state.txt').read_text()
        self.assertIn('lobby\t109775244182498723\n', data)
        self.assertIn('hello%0Aroom%09%2520', data)
        self.assertFalse((self.root/'menu_state.tmp').exists())


if __name__ == '__main__':
    unittest.main()

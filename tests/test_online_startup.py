import sys
import tempfile
import unittest
from pathlib import Path
from types import SimpleNamespace
from unittest.mock import Mock, patch

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'tools'))
import mp_online


class StartupTests(unittest.TestCase):
    def test_background_steam_failure_publishes_error_and_releases_lock(self):
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            lock = Mock(file=True)
            window, dialog = Mock(), Mock()
            tk = SimpleNamespace(Tk=Mock(return_value=window), messagebox=SimpleNamespace(showerror=dialog))
            def fail(*args):
                self.assertIn('phase\tstarting', (root/'menu_state.txt').read_text())
                raise RuntimeError('Steam client unavailable')
            with patch.object(sys, 'argv', ['mp_online', '--background', '--mailbox', folder]), \
                 patch.dict(sys.modules, {'tkinter': tk}), \
                 patch.object(mp_online, 'InstanceLock', return_value=lock), \
                 patch.object(mp_online, 'Steam', side_effect=fail):
                mp_online.main()
            self.assertIn('phase\terror', (root/'menu_state.txt').read_text())
            self.assertIn('Steam client unavailable', (root/'menu_state.txt').read_text())
            self.assertIn('RuntimeError', (root/'online-error.txt').read_text())
            dialog.assert_not_called()
            lock.close.assert_called_once()

    def test_tk_failure_is_also_visible_without_a_hidden_modal(self):
        with tempfile.TemporaryDirectory() as folder:
            lock = Mock(file=True)
            tk = SimpleNamespace(Tk=Mock(side_effect=RuntimeError('UI bootstrap failed')), messagebox=Mock())
            with patch.object(sys, 'argv', ['mp_online', '--background', '--mailbox', folder]), \
                 patch.dict(sys.modules, {'tkinter': tk}), \
                 patch.object(mp_online, 'InstanceLock', return_value=lock):
                mp_online.main()
            self.assertIn('UI bootstrap failed', (Path(folder)/'menu_state.txt').read_text())
            lock.close.assert_called_once()


if __name__ == '__main__':
    unittest.main()

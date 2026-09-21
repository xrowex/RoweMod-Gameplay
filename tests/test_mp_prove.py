#!/usr/bin/env python3
"""Integration: prove UDP host↔join connection path."""

from __future__ import annotations

import importlib.util
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


def load_prove():
    spec = importlib.util.spec_from_file_location("mp_prove", ROOT / "tools" / "mp_prove.py")
    assert spec and spec.loader
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


class ProveConnectionTests(unittest.TestCase):
    def test_prove_pass(self):
        prove = load_prove()
        report = prove.prove(verbose=False)
        if not report["ok"]:
            self.fail(f"connection prove failed: {report.get('errors')} checks={report.get('checks')}")
        self.assertTrue(report["checks"]["bridge_connected"])
        self.assertTrue(report["checks"]["host_got_join_transform"])
        self.assertTrue(report["checks"]["join_got_host_grind"])

    def test_map_mismatch_still_connects(self):
        prove = load_prove()
        report = prove.prove_map_mismatch(verbose=False)
        if not report["ok"]:
            self.fail(f"mapmiss prove failed: {report}")
        self.assertTrue(report["checks"]["bridge_connected_despite_map_mismatch"])
        self.assertTrue(report["checks"]["host_saw_peer_map_b"])


if __name__ == "__main__":
    unittest.main()

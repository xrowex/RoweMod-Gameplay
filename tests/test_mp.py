#!/usr/bin/env python3
"""Protocol + mailbox unit tests (no game required)."""

from __future__ import annotations

import importlib.util
import sys
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "tools"))

# Load rowemod_mp as a module
spec = importlib.util.spec_from_file_location("rowemod_mp", ROOT / "tools" / "rowemod_mp.py")
assert spec and spec.loader
rmp = importlib.util.module_from_spec(spec)
spec.loader.exec_module(rmp)


def encode_transform(seq, t):
    return (
        f"T|{seq}|{t['x']:.4f}|{t['y']:.4f}|{t['z']:.4f}|"
        f"{t['pitch']:.3f}|{t['yaw']:.3f}|{t['roll']:.3f}|"
        f"{t['vx']:.3f}|{t['vy']:.3f}|{t['vz']:.3f}"
    )


def decode_line(line: str) -> dict:
    p = line.split("|")
    kind = p[0]
    if kind == "T":
        return {
            "type": "transform",
            "seq": int(p[1]),
            "x": float(p[2]),
            "y": float(p[3]),
            "z": float(p[4]),
        }
    if kind == "G+":
        return {
            "type": "grind_enter",
            "seq": int(p[1]),
            "railId": p[2],
            "splineT": float(p[3]),
            "stance": p[4],
            "balance": float(p[5]),
        }
    if kind == "G-":
        return {"type": "grind_exit", "seq": int(p[1]), "reason": p[2]}
    if kind == "A":
        return {"type": "grab", "seq": int(p[1]), "grabId": p[2]}
    raise AssertionError(f"unknown {line}")


class ProtocolTests(unittest.TestCase):
    def test_transform_roundtrip_shape(self):
        line = encode_transform(
            3, {"x": 1.5, "y": -2, "z": 10, "pitch": 0, "yaw": 90, "roll": 0, "vx": 1, "vy": 0, "vz": 0}
        )
        msg = decode_line(line)
        self.assertEqual(msg["type"], "transform")
        self.assertEqual(msg["seq"], 3)
        self.assertAlmostEqual(msg["x"], 1.5, places=3)

    def test_grind_enter(self):
        line = "G+|9|Rail_Foo|0.2500|souls|0.8000"
        msg = decode_line(line)
        self.assertEqual(msg["type"], "grind_enter")
        self.assertEqual(msg["railId"], "Rail_Foo")
        self.assertEqual(msg["stance"], "souls")

    def test_pack_unpack(self):
        blob = rmp.pack("alice", "G+|1|r|0.1|st|0.5")
        peer, line = rmp.unpack(blob)
        self.assertEqual(peer, "alice")
        self.assertTrue(line.startswith("G+"))


class MailboxTests(unittest.TestCase):
    def test_out_to_in(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            a = rmp.Mailbox(root / "A")
            b = rmp.Mailbox(root / "B")
            # Simulate game writing an out message
            out = a.out_dir / "000001.msg"
            out.write_text("T|1|0|0|0|0|0|0|0|0|0\n", encoding="utf-8")
            lines = a.poll_out()
            self.assertEqual(len(lines), 1)
            b.push_in(lines[0], "A")
            msgs = list((b.in_dir).glob("*.msg"))
            self.assertEqual(len(msgs), 1)
            body = msgs[0].read_text(encoding="utf-8")
            self.assertTrue(body.startswith("@A|T|"))


if __name__ == "__main__":
    unittest.main()

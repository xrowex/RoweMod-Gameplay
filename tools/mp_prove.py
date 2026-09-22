#!/usr/bin/env python3
"""Prove RoweMod MP peer connections end-to-end (no game required).

Spins up a UDP host + joiner with separate mailboxes, simulates game
hello/map/transform/grind packets, and asserts bidirectional delivery.

Exit 0 = PASS, 1 = FAIL.
"""

from __future__ import annotations

import argparse
import importlib.util
import json
import socket
import sys
import tempfile
import time
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


def load_rmp():
    spec = importlib.util.spec_from_file_location("rowemod_mp", ROOT / "tools" / "rowemod_mp.py")
    assert spec and spec.loader
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


def free_port() -> int:
    with socket.socket(socket.AF_INET, socket.SOCK_DGRAM) as s:
        s.bind(("127.0.0.1", 0))
        return s.getsockname()[1]


def wait_until(pred, timeout=5.0, interval=0.05) -> bool:
    deadline = time.time() + timeout
    while time.time() < deadline:
        if pred():
            return True
        time.sleep(interval)
    return False


def collect_kinds(messages: list[tuple[str, str]]) -> dict[str, list[tuple[str, str]]]:
    out: dict[str, list[tuple[str, str]]] = {}
    for peer, line in messages:
        kind = line.split("|", 1)[0]
        out.setdefault(kind, []).append((peer, line))
    return out


def prove(verbose: bool = True) -> dict:
    rmp = load_rmp()
    report = {
        "ok": False,
        "checks": {},
        "errors": [],
        "host_rx": 0,
        "join_rx": 0,
        "host_inbox": [],
        "join_inbox": [],
    }

    port = free_port()
    with tempfile.TemporaryDirectory(prefix="rowemod_mp_prove_") as tmp:
        base = Path(tmp)
        host_box = rmp.Mailbox(base / "host")
        join_box = rmp.Mailbox(base / "join")

        host = rmp.UdpHub(port, host_box, "HostSkater", None, map_id="ProvePark")
        join = rmp.UdpHub(port, join_box, "JoinSkater", "127.0.0.1", map_id="ProvePark")
        host.start()
        time.sleep(0.05)
        join.start()

        try:
            # 1) Bridge-level connection (PING/HELLO heard)
            connected = wait_until(
                lambda: (base / "host" / "connected.txt").exists()
                and (base / "host" / "connected.txt").read_text().strip() == "1"
                and (base / "join" / "connected.txt").exists()
                and (base / "join" / "connected.txt").read_text().strip() == "1",
                timeout=6.0,
            )
            report["checks"]["bridge_connected"] = connected
            if not connected:
                report["errors"].append("bridges never set connected.txt=1")

            # 2) Simulate games writing hello + map + transform + grind
            host_box.write_out("H|10|HostSkater|2|ProvePark")
            host_box.write_out("M|11|ProvePark")
            host_box.write_out("MREQ|12|ProvePark")
            host_box.write_out("T|13|100.0000|200.0000|50.0000|0.000|90.000|0.000|5.000|0.000|0.000")
            host_box.write_out("G+|14|ProvePark#Rail_A|0.2500|souls|0.8000")

            join_box.write_out("H|20|JoinSkater|2|ProvePark")
            join_box.write_out("M|21|ProvePark")
            join_box.write_out("T|22|10.0000|20.0000|30.0000|0.000|0.000|0.000|1.000|0.000|0.000")
            join_box.write_out("G+|23|ProvePark#Rail_A|0.1000|alley|0.5000")
            join_box.write_out("A|24|indy")

            # Drain inboxes until we see the important kinds (or timeout)
            host_msgs: list[tuple[str, str]] = []
            join_msgs: list[tuple[str, str]] = []

            def enough() -> bool:
                hk = collect_kinds(host_msgs)
                jk = collect_kinds(join_msgs)
                return (
                    "H" in hk
                    and "T" in hk
                    and ("G+" in hk or "A" in hk)
                    and "H" in jk
                    and "T" in jk
                    and "G+" in jk
                )

            deadline = time.time() + 6.0
            while time.time() < deadline and not enough():
                host_msgs.extend(host_box.drain_in())
                join_msgs.extend(join_box.drain_in())
                time.sleep(0.05)
            # final drain
            host_msgs.extend(host_box.drain_in())
            join_msgs.extend(join_box.drain_in())

            report["host_inbox"] = [f"{p}|{l}" for p, l in host_msgs[:40]]
            report["join_inbox"] = [f"{p}|{l}" for p, l in join_msgs[:40]]
            report["host_rx"] = host.rx_count
            report["join_rx"] = join.rx_count

            hk = collect_kinds(host_msgs)
            jk = collect_kinds(join_msgs)

            # Host should see joiner hello/transform/grind
            report["checks"]["host_got_join_hello"] = any(
                p == join.self_id and l.startswith("H|") for p, l in host_msgs
            )
            report["checks"]["host_got_join_transform"] = "T" in hk and any(
                p == join.self_id for p, _ in hk.get("T", [])
            )
            report["checks"]["host_got_join_grind_or_grab"] = ("G+" in hk) or ("A" in hk)

            # Join should see host hello/mapreq/transform/grind
            report["checks"]["join_got_host_hello"] = any(
                p == host.self_id and l.startswith("H|") for p, l in join_msgs
            )
            report["checks"]["join_got_host_transform"] = "T" in jk and any(
                p == host.self_id for p, _ in jk.get("T", [])
            )
            report["checks"]["join_got_host_grind"] = "G+" in jk
            report["checks"]["join_got_map_signal"] = ("M" in jk) or ("MREQ" in jk) or any(
                "ProvePark" in l for _, l in join_msgs if l.startswith("H|")
            )

            # peers.json present
            host_peers = base / "host" / "peers.json"
            join_peers = base / "join" / "peers.json"
            report["checks"]["host_peers_json"] = host_peers.exists()
            report["checks"]["join_peers_json"] = join_peers.exists()
            if host_peers.exists():
                data = None
                for _ in range(20):
                    try:
                        text = host_peers.read_text(encoding="utf-8").strip()
                        if text:
                            data = json.loads(text)
                            break
                    except (OSError, json.JSONDecodeError):
                        pass
                    time.sleep(0.05)
                if data is not None:
                    report["checks"]["host_peers_connected_flag"] = bool(data.get("connected"))
                    report["host_peers"] = data

            failed = [k for k, v in report["checks"].items() if not v]
            report["ok"] = connected and not failed
            if failed:
                report["errors"].append("failed checks: " + ", ".join(failed))

        finally:
            host.stop()
            join.stop()
            time.sleep(0.05)

    if verbose:
        print("=== RoweMod MP connection prove ===")
        for k, v in report["checks"].items():
            print(f"  [{'PASS' if v else 'FAIL'}] {k}")
        print(f"  host_rx={report['host_rx']} join_rx={report['join_rx']}")
        if report["errors"]:
            for e in report["errors"]:
                print(f"  ERROR: {e}")
        print("RESULT:", "PASS" if report["ok"] else "FAIL")
    return report


def prove_map_mismatch(verbose: bool = True) -> dict:
    """Peers on different maps still connect at the bridge, and mapIds differ on hello."""
    rmp = load_rmp()
    report = {"ok": False, "checks": {}, "errors": []}
    port = free_port()
    with tempfile.TemporaryDirectory(prefix="rowemod_mp_mapmiss_") as tmp:
        base = Path(tmp)
        host_box = rmp.Mailbox(base / "host")
        join_box = rmp.Mailbox(base / "join")
        host = rmp.UdpHub(port, host_box, "HostSkater", None, map_id="ParkA")
        join = rmp.UdpHub(port, join_box, "JoinSkater", "127.0.0.1", map_id="ParkB")
        host.start()
        time.sleep(0.05)
        join.start()
        try:
            connected = wait_until(
                lambda: (base / "host" / "connected.txt").read_text().strip() == "1"
                if (base / "host" / "connected.txt").exists()
                else False,
                timeout=5.0,
            )
            report["checks"]["bridge_connected_despite_map_mismatch"] = connected

            host_box.write_out("H|1|HostSkater|2|ParkA")
            join_box.write_out("H|1|JoinSkater|2|ParkB")

            host_msgs: list[tuple[str, str]] = []
            join_msgs: list[tuple[str, str]] = []
            deadline = time.time() + 4.0
            while time.time() < deadline:
                host_msgs.extend(host_box.drain_in())
                join_msgs.extend(join_box.drain_in())
                if any(l.startswith("H|") and "ParkB" in l for _, l in host_msgs) and any(
                    l.startswith("H|") and "ParkA" in l for _, l in join_msgs
                ):
                    break
                time.sleep(0.05)

            report["checks"]["host_saw_peer_map_b"] = any("ParkB" in l for _, l in host_msgs if l.startswith("H|"))
            report["checks"]["join_saw_peer_map_a"] = any("ParkA" in l for _, l in join_msgs if l.startswith("H|"))
            report["checks"]["maps_differ"] = True  # by construction
            failed = [k for k, v in report["checks"].items() if not v]
            report["ok"] = not failed
            if failed:
                report["errors"].append("failed: " + ", ".join(failed))
        finally:
            host.stop()
            join.stop()
            time.sleep(0.05)

    if verbose:
        print("=== RoweMod MP map-mismatch prove ===")
        for k, v in report["checks"].items():
            print(f"  [{'PASS' if v else 'FAIL'}] {k}")
        print("RESULT:", "PASS" if report["ok"] else "FAIL")
    return report


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description="Prove RoweMod MP connections")
    parser.add_argument("--json", action="store_true", help="print full JSON report")
    parser.add_argument("--quiet", action="store_true")
    parser.add_argument("--out", type=Path, default=None, help="write report JSON")
    parser.add_argument(
        "--suite",
        choices=("connect", "mapmiss", "all"),
        default="all",
        help="which prove suite to run",
    )
    args = parser.parse_args(argv)

    reports = {}
    ok = True
    if args.suite in ("connect", "all"):
        reports["connect"] = prove(verbose=not args.quiet)
        ok = ok and reports["connect"]["ok"]
    if args.suite in ("mapmiss", "all"):
        reports["mapmiss"] = prove_map_mismatch(verbose=not args.quiet)
        ok = ok and reports["mapmiss"]["ok"]

    payload = reports if args.suite == "all" else reports.get(args.suite) or reports
    if args.json:
        print(json.dumps(payload, indent=2))
    if args.out:
        args.out.parent.mkdir(parents=True, exist_ok=True)
        args.out.write_text(json.dumps(payload, indent=2) + "\n", encoding="utf-8")
    if not args.quiet and args.suite == "all":
        print("SUITE:", "PASS" if ok else "FAIL")
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main())

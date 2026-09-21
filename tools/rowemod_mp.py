#!/usr/bin/env python3
"""RoweMod MP link — bridges the UE4SS mailbox to LAN peers (UDP).

Usage:
  python tools/rowemod_mp.py host [--port 27045] [--mailbox %TEMP%/RoweModMP]
  python tools/rowemod_mp.py join --host 192.168.1.10 [--port 27045]
  python tools/rowemod_mp.py loopback   # two local mailboxes for testing

Mailbox layout (written by the Lua mod + this bridge):
  <mailbox>/out/*.msg   game → network
  <mailbox>/in/*.msg    network → game
  <mailbox>/bridge_status.txt
"""

from __future__ import annotations

import argparse
import os
import socket
import sys
import threading
import time
from pathlib import Path

DEFAULT_PORT = 27045
MAGIC = b"RMP1"


def default_mailbox() -> Path:
    tmp = os.environ.get("TEMP") or os.environ.get("TMP") or os.environ.get("TMPDIR") or "."
    return Path(tmp) / "RoweModMP"


def ensure_dirs(root: Path) -> tuple[Path, Path]:
    out_dir = root / "out"
    in_dir = root / "in"
    out_dir.mkdir(parents=True, exist_ok=True)
    in_dir.mkdir(parents=True, exist_ok=True)
    return out_dir, in_dir


def write_status(root: Path, text: str) -> None:
    (root / "bridge_status.txt").write_text(text + "\n", encoding="utf-8")
    # Convenience for Lua role=auto
    role = "host" if text.startswith("host") else "join" if text.startswith("join") else "unknown"
    (root / "role.txt").write_text(role + "\n", encoding="utf-8")


def append_manifest(in_dir: Path, name: str) -> None:
    manifest = in_dir / "manifest.txt"
    with manifest.open("a", encoding="utf-8") as f:
        f.write(name + "\n")


class Mailbox:
    def __init__(self, root: Path, peer_tag: str = "self") -> None:
        self.root = root
        self.peer_tag = peer_tag
        self.out_dir, self.in_dir = ensure_dirs(root)
        self._in_seq = int(time.time()) % 100000 * 100
        self._seen_out: set[str] = set()

    def poll_out(self) -> list[str]:
        lines: list[str] = []
        for path in sorted(self.out_dir.glob("*.msg")):
            name = path.name
            if name in self._seen_out:
                continue
            try:
                text = path.read_text(encoding="utf-8", errors="replace").strip()
                path.unlink(missing_ok=True)
                self._seen_out.add(name)
                if text:
                    for line in text.splitlines():
                        line = line.strip()
                        if line:
                            lines.append(line)
            except OSError:
                continue
        return lines

    def push_in(self, line: str, from_peer: str) -> None:
        self._in_seq += 1
        name = f"{self._in_seq:06d}.msg"
        payload = f"@{from_peer}|{line}\n"
        path = self.in_dir / name
        tmp = path.with_suffix(".tmp")
        tmp.write_text(payload, encoding="utf-8")
        tmp.replace(path)
        append_manifest(self.in_dir, name)


def pack(peer_id: str, line: str) -> bytes:
    body = f"{peer_id}\n{line}".encode("utf-8")
    return MAGIC + len(body).to_bytes(4, "big") + body


def unpack(data: bytes) -> tuple[str, str] | None:
    if len(data) < 8 or not data.startswith(MAGIC):
        return None
    size = int.from_bytes(data[4:8], "big")
    body = data[8 : 8 + size]
    try:
        text = body.decode("utf-8")
    except UnicodeDecodeError:
        return None
    peer, _, line = text.partition("\n")
    if not peer or not line:
        return None
    return peer, line


class UdpHub:
    """Simple mesh: host keeps peer addresses; all datagrams are rebroadcast."""

    def __init__(self, port: int, mailbox: Mailbox, name: str, host_addr: str | None) -> None:
        self.port = port
        self.mailbox = mailbox
        self.name = name
        self.sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        self.sock.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
        self.peers: dict[str, tuple[str, int]] = {}
        self.self_id = name.replace("|", "_")[:32] or "player"
        self._stop = threading.Event()
        if host_addr is None:
            self.sock.bind(("0.0.0.0", port))
            self.mode = "host"
            self.remote: tuple[str, int] | None = None
        else:
            self.sock.bind(("0.0.0.0", 0))
            self.mode = "join"
            self.remote = (host_addr, port)
            self.peers["host"] = self.remote

    def start(self) -> None:
        write_status(self.mailbox.root, f"{self.mode} name={self.self_id} port={self.port}")
        threading.Thread(target=self._rx_loop, name="rmp-rx", daemon=True).start()
        threading.Thread(target=self._tx_loop, name="rmp-tx", daemon=True).start()
        print(f"[rowemod_mp] {self.mode} as {self.self_id} mailbox={self.mailbox.root}")
        if self.mode == "host":
            print(f"[rowemod_mp] listening UDP :{self.port} — friends: join --host <your-lan-ip>")
        else:
            print(f"[rowemod_mp] joining {self.remote}")
        # Announce presence
        self._broadcast(f"H|0|{self.self_id}|1")

    def _broadcast(self, line: str, exclude: tuple[str, int] | None = None) -> None:
        packet = pack(self.self_id, line)
        targets = set(self.peers.values())
        if self.remote:
            targets.add(self.remote)
        for addr in targets:
            if exclude and addr == exclude:
                continue
            try:
                self.sock.sendto(packet, addr)
            except OSError as exc:
                print(f"[rowemod_mp] send error {addr}: {exc}")

    def _rx_loop(self) -> None:
        self.sock.settimeout(0.5)
        while not self._stop.is_set():
            try:
                data, addr = self.sock.recvfrom(65535)
            except socket.timeout:
                continue
            except OSError:
                break
            parsed = unpack(data)
            if not parsed:
                continue
            peer, line = parsed
            if peer == self.self_id:
                continue
            self.peers[peer] = addr
            # Rebroadcast from host so join↔join works through host.
            if self.mode == "host":
                self._broadcast_raw(data, exclude=addr)
            self.mailbox.push_in(line, peer)

    def _broadcast_raw(self, data: bytes, exclude: tuple[str, int] | None = None) -> None:
        for addr in set(self.peers.values()):
            if exclude and addr == exclude:
                continue
            try:
                self.sock.sendto(data, addr)
            except OSError:
                pass

    def _tx_loop(self) -> None:
        while not self._stop.is_set():
            for line in self.mailbox.poll_out():
                self._broadcast(line)
            write_status(
                self.mailbox.root,
                f"{self.mode} name={self.self_id} peers={len(self.peers)} port={self.port}",
            )
            time.sleep(0.01)

    def stop(self) -> None:
        self._stop.set()
        try:
            self._broadcast("Bye|0")
        except OSError:
            pass
        self.sock.close()


def run_loopback() -> int:
    """Two mailboxes linked in-process — no sockets. For protocol smoke tests."""
    base = default_mailbox()
    a = Mailbox(base / "A", "A")
    b = Mailbox(base / "B", "B")
    write_status(a.root, "loopback A")
    write_status(b.root, "loopback B")
    print(f"[rowemod_mp] loopback A={a.root}")
    print(f"[rowemod_mp] loopback B={b.root}")
    print("Point two game configs at these mailbox dirs, or write .msg files into out/")
    stop = False

    def pump(src: Mailbox, dst: Mailbox, tag: str) -> None:
        nonlocal stop
        while not stop:
            for line in src.poll_out():
                dst.push_in(line, tag)
                print(f"[loopback] {tag} -> {line}")
            time.sleep(0.01)

    t1 = threading.Thread(target=pump, args=(a, b, "A"), daemon=True)
    t2 = threading.Thread(target=pump, args=(b, a, "B"), daemon=True)
    t1.start()
    t2.start()
    try:
        while True:
            time.sleep(1)
    except KeyboardInterrupt:
        stop = True
        print("\n[rowemod_mp] loopback stopped")
    return 0


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description="RoweMod multiplayer LAN bridge")
    sub = parser.add_subparsers(dest="cmd", required=True)

    def add_common(p: argparse.ArgumentParser) -> None:
        p.add_argument("--port", type=int, default=DEFAULT_PORT)
        p.add_argument("--mailbox", type=Path, default=None)
        p.add_argument("--name", default=os.environ.get("USERNAME") or os.environ.get("USER") or "skater")

    ph = sub.add_parser("host", help="Host a LAN session")
    add_common(ph)
    pj = sub.add_parser("join", help="Join a host")
    add_common(pj)
    pj.add_argument("--host", required=True, help="Host LAN IP")
    sub.add_parser("loopback", help="Link two local mailboxes (dev)")

    args = parser.parse_args(argv)
    if args.cmd == "loopback":
        return run_loopback()

    mailbox_root = args.mailbox or default_mailbox()
    box = Mailbox(mailbox_root)
    if args.cmd == "host":
        hub = UdpHub(args.port, box, args.name, None)
    else:
        hub = UdpHub(args.port, box, args.name, args.host)
    hub.start()
    try:
        while True:
            time.sleep(1)
    except KeyboardInterrupt:
        print("\n[rowemod_mp] stopping")
        hub.stop()
    return 0


if __name__ == "__main__":
    sys.exit(main())

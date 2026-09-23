#!/usr/bin/env python3
"""RoweMod MP link — bridges the UE4SS mailbox to LAN peers (UDP).

Usage:
  python tools/rowemod_mp.py host [--port 27045] [--mailbox %TEMP%/RoweModMP]
  python tools/rowemod_mp.py join --host 192.168.1.10 [--port 27045]
  python tools/rowemod_mp.py loopback
  python tools/rowemod_mp.py prove   # (prefer tools/mp_prove.py)

Mailbox layout (written by the Lua mod + this bridge):
  <mailbox>/out/*.msg   game → network
  <mailbox>/in/*.msg    network → game
  <mailbox>/bridge_status.txt
  <mailbox>/peers.txt
  <mailbox>/connected.txt   # "1" when ≥1 remote peer heard from
"""

from __future__ import annotations

import argparse
import json
import uuid
import zlib
import struct
import re
import os
import socket
import sys
import threading
import time
from pathlib import Path

DEFAULT_PORT = 27045
MAGIC = b"RMP1"
PROTO_VER = "3"


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
    status = root / "bridge_status.txt"
    temporary = status.with_suffix('.tmp')
    temporary.write_text(text + "\n", encoding="utf-8")
    temporary.replace(status)
    role = "host" if text.startswith("host") else "join" if text.startswith("join") else "unknown"
    (root / "role.txt").write_text(role + "\n", encoding="utf-8")


def write_peers(root: Path, peers: dict[str, tuple[str, int]], last_seen: dict[str, float]) -> None:
    now = time.time()
    lines = []
    for name, addr in sorted(peers.items()):
        age = now - last_seen.get(name, now)
        lines.append(f"{name} {addr[0]}:{addr[1]} age={age:.1f}s")
    (root / "peers.txt").write_text("\n".join(lines) + ("\n" if lines else ""), encoding="utf-8")
    live = [n for n, t in last_seen.items() if now - t < 5.0 and n in peers]
    (root / "connected.txt").write_text(("1" if live else "0") + "\n", encoding="utf-8")
    (root / "peers.json").write_text(
        json.dumps(
            {
                "connected": bool(live),
                "peers": [
                    {"name": n, "addr": f"{peers[n][0]}:{peers[n][1]}", "age": now - last_seen.get(n, now)}
                    for n in sorted(peers)
                ],
            },
            indent=2,
        )
        + "\n",
        encoding="utf-8",
    )


def append_manifest(in_dir: Path, name: str) -> None:
    manifest = in_dir / "manifest.txt"
    with manifest.open("a", encoding="utf-8") as f:
        f.write(name + "\n")


class Mailbox:
    def __init__(self, root: Path, peer_tag: str = "self") -> None:
        self.root = root
        self.peer_tag = peer_tag
        self.out_dir, self.in_dir = ensure_dirs(root)
        self._in_seq = int(time.time() * 1000) % 100000000
        self._out_seq = 0

    def write_out(self, line: str) -> Path:
        """Simulate a game write (also used by prove harness)."""
        self._out_seq += 1
        name = f"{self._out_seq:06d}.msg"
        path = self.out_dir / name
        tmp = path.with_suffix(".tmp")
        tmp.write_text(line.rstrip() + "\n", encoding="utf-8")
        tmp.replace(path)
        return path

    def poll_out(self) -> list[str]:
        lines: list[str] = []
        for path in sorted(self.out_dir.glob("*.msg")):
            try:
                text = path.read_text(encoding="utf-8", errors="replace").strip()
                path.unlink(missing_ok=True)
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

    def drain_in(self) -> list[tuple[str, str]]:
        """Read all inbox messages as (peer, line). Consumes files."""
        results: list[tuple[str, str]] = []
        for path in sorted(self.in_dir.glob("*.msg")):
            try:
                text = path.read_text(encoding="utf-8", errors="replace")
                path.unlink(missing_ok=True)
            except OSError:
                continue
            for raw in text.splitlines():
                raw = raw.strip()
                if not raw:
                    continue
                if raw.startswith("@") and "|" in raw:
                    peer, _, line = raw[1:].partition("|")
                    results.append((peer, line))
                else:
                    results.append(("?", raw))
        # clear manifest
        manifest = self.in_dir / "manifest.txt"
        if manifest.exists():
            manifest.write_text("", encoding="utf-8")
        return results


def pack(peer_id: str, line: str) -> bytes:
    body = f"{peer_id}\n{line}".encode("utf-8")
    return MAGIC + len(body).to_bytes(4, "big") + body


def unpack(data: bytes) -> tuple[str, str] | None:
    if len(data) < 8 or not data.startswith(MAGIC):
        return None
    size = int.from_bytes(data[4:8], "big")
    if size != len(data)-8 or size > 524288: return None
    body = data[8 : 8 + size]
    try:
        text = body.decode("utf-8")
    except UnicodeDecodeError:
        return None
    peer, _, line = text.partition("\n")
    if not peer or not line:
        return None
    return peer, line


MAX_FRAME = 524288
CHUNK = 1100
FRAG_HEADER = struct.Struct("!4sQHH")


def fragments(peer, line, sequence):
    raw = pack(peer, line)
    if len(raw) > MAX_FRAME:
        raise ValueError("frame too large")
    body = zlib.compress(raw, 1)
    count = (len(body) + CHUNK - 1) // CHUNK
    return [FRAG_HEADER.pack(b"RMF3", sequence, i, count) + body[i*CHUNK:(i+1)*CHUNK]
            for i in range(count)]


class Reassembler:
    def __init__(self):
        self.pending = {}

    def feed(self, data, addr, now=None):
        now = time.monotonic() if now is None else now
        self.pending = {k:v for k,v in self.pending.items() if now-v[0] < 2}
        if len(data) < FRAG_HEADER.size or len(data) > FRAG_HEADER.size+CHUNK:
            return None
        magic, seq, index, count = FRAG_HEADER.unpack_from(data)
        if magic != b"RMF3" or not 1 <= count <= 480 or index >= count:
            return None
        key = (addr, seq)
        if key not in self.pending:
            if len(self.pending) >= 64:
                return None
            self.pending[key] = (now, count, {})
        _, expected, parts = self.pending[key]
        if expected != count:
            return None
        parts[index] = data[FRAG_HEADER.size:]
        if len(parts) != count:
            return None
        del self.pending[key]
        try:
            dec = zlib.decompressobj()
            raw = dec.decompress(b"".join(parts[i] for i in range(count)), MAX_FRAME+1)
            if len(raw)>MAX_FRAME or not dec.eof or dec.unused_data:
                return None
            return unpack(raw)
        except zlib.error:
            return None


class UdpHub:
    """Host relay with per-connection identity; joins send only to their host."""
    def __init__(self, port, mailbox, name, host_addr, map_id="unknown"):
        self.port, self.mailbox, self.name, self.map_id = port, mailbox, name, map_id
        self.self_id = uuid.uuid4().hex
        self.mode = "host" if host_addr is None else "join"
        self.remote = None if host_addr is None else (socket.gethostbyname(host_addr), port)
        self.sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        self.sock.bind(("0.0.0.0", port if self.mode=="host" else 0))
        self.sock.settimeout(.01)
        self.peers, self.last_seen, self.hellos = {}, {}, {}
        self._stop = threading.Event()
        self.rx_count = self.tx_count = 0
        self._wire_seq = time.time_ns() & ((1<<63)-1)
        self._rx = Reassembler()
        self.host_id = None
        self._thread = None

    def _hello_line(self):
        name = self.name.replace("|","_").replace("\\n"," ")[:64]
        return f"H|0|{name}|{PROTO_VER}|{self.map_id}"

    def _observe_game_line(self, line):
        p=line.split("|")
        if p[0]=="H" and len(p)>=5: self.map_id=p[4]
        elif p[0]=="M" and len(p)>=3: self.map_id=p[2]
        elif p[0]=="Bye": self.map_id="unknown"

    def _send(self, peer, line, targets):
        self._wire_seq += 1
        for packet in fragments(peer,line,self._wire_seq):
            for addr in set(targets):
                try:
                    self.sock.sendto(packet,addr)
                    self.tx_count+=1
                except OSError:
                    pass

    def _broadcast(self, line, exclude=None):
        targets = [self.remote] if self.remote else list(self.peers.values())
        self._send(self.self_id,line,[a for a in targets if a!=exclude])

    def start(self):
        self._status()
        self._thread=threading.Thread(target=self._loop,name="rmp-hub",daemon=True)
        self._thread.start()
        print(f"[rowemod_mp] {self.mode} {self.name} id={self.self_id} mailbox={self.mailbox.root}",flush=True)

    def _status(self):
        write_status(self.mailbox.root,f"{self.mode} name={self.name} id={self.self_id} peers={len(self.peers)} rx={self.rx_count} tx={self.tx_count} port={self.port}")
        write_peers(self.mailbox.root,dict(self.peers),dict(self.last_seen))

    def _deliver(self, peer, line):
        if line.startswith("PING|") or line.startswith("PONG|"): return
        self.mailbox.push_in(line,peer)

    def _receive(self, peer, line, addr):
        if peer==self.self_id or not re.fullmatch(r"[0-9a-f]{32}",peer): return
        if self.remote and addr!=self.remote: return
        kind=line.split("|",1)[0]
        if self.mode=="host":
            if peer in self.peers and self.peers[peer]!=addr: return
            if peer not in self.peers:
                if kind!="H" or len(self.peers)>=7: return
                # Same endpoint reconnect: remove its old identity before registering.
                for old in [p for p,a in self.peers.items() if a==addr]:
                    self._drop(old)
                self.peers[peer]=addr
                self._send(self.self_id,"HOST|"+self.self_id,[addr])
                self._send(self.self_id,self._hello_line(),[addr])
                for other,hello in self.hellos.items():
                    self._send(other,hello,[addr])
            if kind in ("MREQ","HOST"): return  # only the host has map authority
        else:
            if kind=="HOST":
                if line!="HOST|"+peer: return
                self.host_id=peer
                return
            if not self.host_id: return
            if kind=="MREQ" and peer!=self.host_id: return
            self.peers[peer]=addr
        self.last_seen[peer]=time.time()
        self.rx_count+=1
        if kind=="H": self.hellos[peer]=line
        if self.mode=="host":
            self._send(peer,line,[a for a in self.peers.values() if a!=addr])
        self._deliver(peer,line)
        if kind=="Bye": self._drop(peer,announce=False)

    def _drop(self,peer,announce=True):
        self.peers.pop(peer,None); self.last_seen.pop(peer,None); self.hellos.pop(peer,None)
        if announce:
            self._deliver(peer,"Bye|0")
            if self.mode=="host": self._send(peer,"Bye|0",self.peers.values())

    def _loop(self):
        heartbeat=status=0
        while not self._stop.is_set():
            now=time.monotonic()
            if now>=heartbeat:
                heartbeat=now+1
                if self.mode=="host":
                    self._broadcast("HOST|"+self.self_id)
                self._broadcast(self._hello_line())
                for p in list(self.peers):
                    if time.time()-self.last_seen.get(p,time.time())>5: self._drop(p)
            for line in self.mailbox.poll_out():
                self._observe_game_line(line)
                if self.mode=="join" and line.startswith("MREQ|"): continue
                self._broadcast(line)
            try:
                data,addr=self.sock.recvfrom(1200)
                parsed=self._rx.feed(data,addr)
                if parsed: self._receive(*parsed,addr)
            except socket.timeout: pass
            except OSError:
                if self._stop.is_set(): break
            if now>=status:
                status=now+.5
                self._status()

    def stop(self):
        self._stop.set()
        if self._thread: self._thread.join(timeout=2)
        self._broadcast("Bye|0")
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
        p.add_argument("--map", default="unknown", help="initial mapId; updated from the game")

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
        hub = UdpHub(args.port, box, args.name, None, map_id=args.map)
    else:
        hub = UdpHub(args.port, box, args.name, args.host, map_id=args.map)
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

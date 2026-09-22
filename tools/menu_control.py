"""Bounded local text protocol for the native in-game UMG menu."""
import json
import time
from urllib.parse import unquote


def encode(value):
    return str(value).replace('%', '%25').replace('\t', '%09').replace('\r', '%0D').replace('\n', '%0A')


def read_command(path):
    if time.time() - path.stat().st_mtime > 60 or path.stat().st_size > 4096:
        return None
    raw = path.read_text(encoding='utf-8')
    if path.suffix == '.json':
        value = json.loads(raw)
        if not isinstance(value, dict):
            raise ValueError('Invalid menu request')
        return value
    result = {}
    for line in raw.splitlines():
        key, value = line.split('\t', 1)
        if key in result:
            raise ValueError('Duplicate menu request field')
        result[key] = unquote(value)
    return result


def apply_command(bridge, command, show):
    action = command.get('action')
    if action == 'host':
        visibility = command.get('visibility', 'friends')
        if visibility not in ('friends', 'public', 'private'):
            raise ValueError('Invalid session visibility')
        name = ''.join(c for c in str(command.get('name', 'RoweMod session')) if c.isprintable()).strip()[:80]
        bridge.host_session(name or 'RoweMod session', visibility)
    elif action == 'join':
        lobby = str(command.get('lobby', ''))
        if not lobby.isascii() or not lobby.isdecimal() or not 0 < int(lobby) < 2**64:
            raise ValueError('Enter a valid lobby ID')
        bridge.join(int(lobby))
    elif action == 'leave':
        bridge.leave()
    elif action == 'friends':
        bridge.friends()
    elif action == 'browse':
        bridge.browse()
    elif action == 'show':
        show()
    else:
        raise ValueError('Unknown menu request')


def consume(bridge, show):
    folder = bridge.box.root / 'control'
    folder.mkdir(parents=True, exist_ok=True)
    paths = sorted((p for p in folder.iterdir() if p.suffix in ('.txt', '.json')), key=lambda p: p.name)
    for path in paths[:16]:
        try:
            command = read_command(path)
            if command:
                apply_command(bridge, command, show)
        except Exception as error:
            bridge.error(error)
        finally:
            try:
                path.unlink(missing_ok=True)
            except OSError:
                pass


def publish(bridge):
    values = dict(updated=int(time.time()), phase='ready', message=bridge.message, role=bridge.mode,
                  map=bridge.map, lobby=str(bridge.lobby or 0), peers=len(bridge.peers),
                  players=len(bridge.members), busy=int(bool(bridge.busy)))
    lines = ['\t'.join((key, encode(value))) for key, value in values.items()]
    for row in bridge.rows[:50]:
        # Preserve 64-bit lobby IDs as text across Lua and Python.
        lines.append('\t'.join(encode(value) for value in
                              ('room', row['id'], str(row['name'])[:100], str(row['map'])[:100], row['players'], row['source'])))
    path = bridge.box.root / 'menu_state.txt'
    tmp = path.with_suffix('.tmp')
    tmp.write_text('\n'.join(lines) + '\n', encoding='utf-8')
    tmp.replace(path)


def publish_startup(root, phase, message):
    """Expose bootstrap failures even when Steam/Tk never reaches its update loop."""
    root.mkdir(parents=True, exist_ok=True)
    path = root / 'menu_state.txt'
    tmp = path.with_suffix('.tmp')
    values = dict(updated=int(time.time()), phase=phase, message=str(message)[:2000])
    tmp.write_text(''.join(key + '\t' + encode(value) + '\n' for key, value in values.items()), encoding='utf-8')
    tmp.replace(path)

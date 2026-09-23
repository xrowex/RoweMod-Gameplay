"""Bounded local text protocol for the native in-game UMG menu."""
import json
import sys
import time
from pathlib import Path
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


def installed_version():
    base = Path(sys.executable).parent if getattr(sys, 'frozen', False) else Path(__file__).parent
    for path in (base/'version.json', base.parent/'version.json'):
        try:
            return str(json.loads(path.read_text(encoding='utf-8-sig'))['version'])[:32]
        except (OSError, ValueError, KeyError):
            pass
    return 'unknown'


def diagnostics(bridge):
    """Bounded support report; aliases replace account IDs and the session code."""
    roster = bridge.roster()
    aliases = {row['id']: 'Player ' + str(i+1) for i, row in enumerate(roster)}
    def clean(value):
        text = str(value)
        for peer, alias in aliases.items():
            text = text.replace(peer, alias).replace(str(int(peer, 16)), alias)
        if bridge.lobby:
            text = text.replace(str(bridge.lobby), '[session]')
        text = text.replace(str(Path.home()), '[user]').replace(Path.home().as_posix(), '[user]')
        return text[:512]
    health = {}
    try:
        with (bridge.box.root/'player_health.txt').open(encoding='utf-8') as stream:
            raw = stream.read(65537)
        if len(raw) > 65536:
            raise ValueError('Game diagnostics exceed size limit')
        health = {'updated': 0, 'lobby': '0', 'players': []}
        for line in raw.splitlines():
            fields = [unquote(p) for p in line.split('\t')]
            if len(fields) == 2 and fields[0] in ('updated', 'lobby'):
                health[fields[0]] = fields[1]
            elif len(fields) == 7 and fields[0] == 'player' and fields[1] in aliases:
                health['players'].append(dict(player=aliases[fields[1]], status=clean(fields[2]),
                    map=clean(fields[3]), received=clean(fields[4]), applied=clean(fields[5]), detail=clean(fields[6])))
        if health['lobby'] != str(bridge.lobby) or time.time()-int(health['updated']) > 6:
            health = {'message': 'Game diagnostics are stale or belong to another session'}
        else:
            del health['lobby']
    except (OSError, ValueError):
        health = {'message': 'Game diagnostics unavailable'}
    report = dict(version=installed_version(), role=bridge.mode, map=clean(bridge.map),
        rx=bridge.rx, tx=bridge.tx, dropped=bridge.dropped, rate_drops=bridge.rate_drops,
        pending_poses=len(bridge.movement), steam_send_results=bridge.send_results,
        players=[dict(player=aliases[r['id']], host=r['host'], local=r['local'],
            connected=r['connected'], map=clean(r['map']), stream=bridge.peer_stats.get(r['id'], {})) for r in roster],
        game=health)
    return 'RoweMod multiplayer diagnostics\n' + json.dumps(report, indent=2)


def apply_command(bridge, command, show, copy=None):
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
    elif action == 'diagnostics':
        report = diagnostics(bridge)
        (bridge.box.root/'diagnostics-copy.txt').write_text(report, encoding='utf-8')
        if copy is None:
            bridge.message = 'Diagnostics saved to diagnostics-copy.txt; clipboard unavailable'
        else:
            try:
                copy(report)
                bridge.message = 'Diagnostics copied. Paste them into your support message.'
            except Exception:
                bridge.message = 'Clipboard unavailable. Diagnostics saved to diagnostics-copy.txt.'
    else:
        raise ValueError('Unknown menu request')


def consume(bridge, show, copy=None):
    folder = bridge.box.root / 'control'
    folder.mkdir(parents=True, exist_ok=True)
    paths = sorted((p for p in folder.iterdir() if p.suffix in ('.txt', '.json')), key=lambda p: p.name)
    for path in paths[:16]:
        try:
            command = read_command(path)
            if command:
                apply_command(bridge, command, show, copy)
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
    values['version'] = installed_version()
    lines = ['\t'.join((key, encode(value))) for key, value in values.items()]
    for player in bridge.roster()[:8]:
        lines.append('\t'.join(encode(value) for value in ('player', player['id'], player['name'],
            int(player['host']), int(player['local']), player['map'], int(player['connected']))))
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

"""RoweMod Online companion: Steam friends, public lobbies, and game launcher."""
import argparse
import json
import os
import re
import subprocess
import sys
import time
import threading
import traceback
import uuid
from pathlib import Path

from rowemod_mp import default_mailbox
from steamworks import Steam, lobby_argument
from steam_mp import SteamBridge
import menu_control


def request(root, action, **values):
    control = root / 'control'
    control.mkdir(parents=True, exist_ok=True)
    target = control / (uuid.uuid4().hex + '.json')
    tmp = target.with_suffix('.tmp')
    tmp.write_text(json.dumps(dict(action=action, **values)), encoding='utf-8')
    tmp.replace(target)


def find_game(explicit=None):
    if explicit:
        path = Path(explicit)
        if not path.is_file():
            raise RuntimeError('Game executable does not exist')
        return path.resolve()
    import winreg
    libraries = [Path(os.environ.get('ProgramFiles(x86)', r'C:\Program Files (x86)')) / 'Steam']
    try:
        with winreg.OpenKey(winreg.HKEY_CURRENT_USER, r'Software\Valve\Steam') as key:
            libraries.insert(0, Path(winreg.QueryValueEx(key, 'SteamPath')[0]))
    except OSError:
        pass
    for steam in list(libraries):
        vdf = steam / 'steamapps' / 'libraryfolders.vdf'
        if vdf.is_file():
            libraries.extend(Path(p.replace('\\\\', '\\')) for p in re.findall(r'"path"\s+"([^"]+)"', vdf.read_text(encoding='utf-8')))
    for library in libraries:
        exe = library / 'steamapps/common/RolloutInline/RollerSkate/Binaries/Win64/RollerSkate-Win64-Shipping.exe'
        if exe.is_file():
            return exe
    raise RuntimeError('Rollout Inline was not found. Start with --game followed by its shipping executable path.')


class InstanceLock:
    def __init__(self, root):
        import msvcrt
        root.mkdir(parents=True, exist_ok=True)
        self.file = (root / 'online.lock').open('a+b')
        self.file.seek(0, 2)
        if self.file.tell() == 0:
            self.file.write(b'0')
            self.file.flush()
        self.file.seek(0)
        try:
            msvcrt.locking(self.file.fileno(), msvcrt.LK_NBLCK, 1)
        except OSError:
            self.file.close()
            self.file = None

    def close(self):
        if self.file:
            self.file.close()
            self.file = None


class OnlineWindow:
    def __init__(self, window, bridge, game=None, background=False):
        import tkinter as tk
        from tkinter import ttk
        self.window, self.bridge, self.game = window, bridge, game
        self.game_process = None
        self.last_rows = None
        self.last_ui = 0
        self.closed = False
        self.background = background
        self.background_game_closed = False
        self.buttons = []
        window.title('RoweMod Online')
        window.geometry('980x730')
        window.minsize(820, 650)
        window.configure(bg='#111820')
        style = ttk.Style()
        style.theme_use('clam')
        style.configure('.', font=('Segoe UI', 10), background='#111820', foreground='#e3eaf2')
        style.configure('TButton', background='#293847', padding=(14, 9))
        style.map('TButton', background=[('active', '#3b5167'), ('disabled', '#202932')])
        style.configure('TEntry', fieldbackground='#1e2a37', foreground='#f5f8fc', padding=8)
        style.configure('TCombobox', fieldbackground='#1e2a37', background='#293847', foreground='#f5f8fc', padding=7)
        style.map('TCombobox', fieldbackground=[('readonly', '#1e2a37')], foreground=[('readonly', '#f5f8fc')])
        style.configure('Treeview', background='#1a2531', fieldbackground='#1a2531', foreground='#e3eaf2', rowheight=34, borderwidth=0)
        style.configure('Treeview.Heading', background='#293847', font=('Segoe UI', 10, 'bold'), padding=9)
        style.map('Treeview', background=[('selected', '#23577b')])
        outer = ttk.Frame(window, padding=24)
        outer.pack(fill='both', expand=True)
        outer.columnconfigure(0, weight=1)
        outer.rowconfigure(5, weight=1)
        ttk.Label(outer, text='ROWEMOD / ONLINE', font=('Segoe UI', 11, 'bold'), foreground='#79c9ef').grid(row=0, sticky='w')
        ttk.Label(outer, text='Skate together.', font=('Segoe UI', 28, 'bold')).grid(row=1, sticky='w', pady=(5, 3))
        ttk.Label(outer, text='Host a session or join a friend. Keep this window open while playing.', foreground='#a7b9c9').grid(row=2, sticky='w')
        host = ttk.Frame(outer)
        host.grid(row=3, sticky='ew', pady=(22, 16))
        self.name = tk.StringVar(value=bridge.steam.name + "'s session")
        self.visibility = tk.StringVar(value='Friends only')
        ttk.Entry(host, textvariable=self.name).pack(side='left', fill='x', expand=True)
        ttk.Combobox(host, textvariable=self.visibility, values=['Friends only', 'Public'], state='readonly', width=15).pack(side='left', padx=10)
        self.button(host, 'Host session', self.host).pack(side='left')
        actions = ttk.Frame(outer)
        actions.grid(row=4, sticky='ew', pady=(0, 10))
        self.button(actions, 'Friends', bridge.friends).pack(side='left')
        self.button(actions, 'Public sessions', bridge.browse).pack(side='left', padx=10)
        self.button(actions, 'Join selected', self.join_selected).pack(side='right')
        columns = ('name', 'map', 'players', 'source')
        self.tree = ttk.Treeview(outer, columns=columns, show='headings', selectmode='browse', height=7)
        for key, label, width in [('name', 'Session / friend', 340), ('map', 'Map', 250), ('players', 'Players', 85), ('source', 'Visibility', 100)]:
            self.tree.heading(key, text=label)
            self.tree.column(key, width=width, minwidth=70, stretch=key in ('name', 'map'))
        self.tree.grid(row=5, sticky='nsew')
        self.tree.bind('<Double-1>', lambda event: self.perform(self.join_selected))
        direct = ttk.Frame(outer)
        direct.grid(row=6, sticky='ew', pady=(12, 8))
        ttk.Label(direct, text='Lobby ID').pack(side='left')
        self.lobby_entry = tk.StringVar()
        ttk.Entry(direct, textvariable=self.lobby_entry, width=24).pack(side='left', padx=10)
        self.button(direct, 'Join ID', lambda: bridge.join(self.lobby_entry.get().strip())).pack(side='left')
        self.button(direct, 'Copy my lobby ID', self.copy_lobby).pack(side='right')
        self.status = tk.StringVar()
        self.detail = tk.StringVar()
        self.status_label = ttk.Label(outer, textvariable=self.status, wraplength=880, foreground='#91d9f1')
        self.status_label.grid(row=7, sticky='w', pady=(8, 3))
        ttk.Label(outer, textvariable=self.detail, foreground='#a7b9c9').grid(row=8, sticky='w')
        bottom = ttk.Frame(outer)
        bottom.grid(row=9, sticky='ew', pady=(14, 0))
        ttk.Button(bottom, text='Leave session', command=lambda: self.perform(bridge.leave)).pack(side='left')
        ttk.Button(bottom, text='Launch Rollout', command=lambda: self.perform(self.launch)).pack(side='right')
        window.protocol('WM_DELETE_WINDOW', self.close)
        window.after(15, self.tick)
        if background:
            threading.Thread(target=self.watch_background_game, daemon=True).start()

    def watch_background_game(self):
        # This worker never calls Tk or Steam. Hidden companions leave cleanly
        # when the game exits so pending updates can replace the executable.
        absent = 0
        while not self.closed and self.background:
            try:
                result = subprocess.run(['tasklist.exe', '/FI', 'IMAGENAME eq RollerSkate-Win64-Shipping.exe', '/FO', 'CSV', '/NH'],
                                        stdout=subprocess.PIPE, stderr=subprocess.DEVNULL, timeout=10,
                                        creationflags=subprocess.CREATE_NO_WINDOW)
                running = b'rollerskate-win64-shipping.exe' in result.stdout.lower()
                absent = 0 if running or result.returncode != 0 else absent + 1
                if result.returncode == 0 and absent >= 3:
                    self.background_game_closed = True
                    return
            except (OSError, subprocess.TimeoutExpired):
                absent = 0
            time.sleep(5)

    def button(self, parent, text, action):
        from tkinter import ttk
        button = ttk.Button(parent, text=text, command=lambda: self.perform(action))
        self.buttons.append(button)
        return button

    def perform(self, action):
        try:
            action()
        except Exception as e:
            self.bridge.error(e)

    def host(self):
        self.bridge.host_session(self.name.get(), 'public' if self.visibility.get() == 'Public' else 'friends')

    def join_selected(self):
        selection = self.tree.selection()
        if not selection:
            raise ValueError('Select a session first')
        self.bridge.join(int(selection[0]))

    def copy_lobby(self):
        if not self.bridge.lobby:
            raise ValueError('Host or join a session first')
        self.window.clipboard_clear()
        self.window.clipboard_append(str(self.bridge.lobby))
        self.bridge.message = 'Lobby ID copied'

    def launch(self):
        if self.game_process and self.game_process.poll() is None:
            raise ValueError('The game launched by this window is already running')
        exe = find_game(self.game)
        if not (exe.parent / 'ue4ss/Mods/RoweModGameplay/Scripts/mp/online.lua').is_file():
            raise RuntimeError('Install the online update first: run install.ps1 from the mod folder.')
        env = dict(os.environ, ROUEMOD_MP_MAILBOX=str(self.bridge.box.root), ROUEMOD_MP_ROLE='auto',
                   ROUEMOD_MP_NAME=self.bridge.steam.name, ROUEMOD_MP_ONLINE='1',
                   SteamAppId='4464990', SteamGameId='4464990')
        self.game_process = subprocess.Popen([str(exe)], cwd=str(exe.parent), env=env)
        self.bridge.message = 'Game launched. Load the same map as the host; multiplayer starts automatically.'

    def controls(self):
        def show():
            self.background = False
            self.window.deiconify()
            self.window.lift()
        menu_control.consume(self.bridge, show)
        menu_control.publish(self.bridge)

    def tick(self):
        if self.closed:
            return
        if self.background and self.background_game_closed:
            self.close()
            return
        self.perform(self.bridge.tick)
        now = time.monotonic()
        if now - self.last_ui >= .25:
            self.last_ui = now
            self.perform(self.controls)
            self.status.set(self.bridge.message)
            self.detail.set(f'{self.bridge.mode.upper()}  |  Remote skaters: {len(self.bridge.peers)}  |  '
                            f'Map: {self.bridge.map}  |  Received: {self.bridge.rx}  Sent: {self.bridge.tx}')
            for button in self.buttons:
                button.configure(state='disabled' if self.bridge.busy else 'normal')
            if self.last_rows != self.bridge.rows:
                self.last_rows = [dict(row) for row in self.bridge.rows]
                self.tree.delete(*self.tree.get_children())
                for row in self.bridge.rows:
                    if not self.tree.exists(str(row['id'])):
                        self.tree.insert('', 'end', iid=str(row['id']), values=(row['name'], row['map'], row['players'], row['source']))
        self.window.after(15, self.tick)

    def close(self):
        self.closed = True
        try:
            self.bridge.close()
        finally:
            self.window.destroy()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--steam-api')
    parser.add_argument('--game')
    parser.add_argument('--background', action='store_true')
    parser.add_argument('--check-updates', action='store_true')
    parser.add_argument('--mailbox', type=Path, default=default_mailbox() / 'Steam')
    args, launch_args = parser.parse_known_args()
    if args.check_updates:
        import online_updater
        online_updater.check(find_game(args.game).parent)
        return
    root = args.mailbox.resolve()
    lobby = lobby_argument(' '.join(launch_args))
    lock = InstanceLock(root)
    if not lock.file:
        if lobby or not args.background:
            request(root, 'join' if lobby else 'show', **({'lobby': str(lobby)} if lobby else {}))
        return
    window = bridge = steam = None
    failed = False
    try:
        menu_control.publish_startup(root, 'starting', 'Connecting to Steam...')
        import tkinter as tk
        from tkinter import messagebox
        window = tk.Tk()
        window.withdraw()
        steam = Steam(args.steam_api)
        bridge = SteamBridge(steam, root)
        OnlineWindow(window, bridge, args.game, args.background)
        lobby = lobby or steam.launch_lobby()
        if lobby:
            bridge.join(lobby)
        if not args.background:
            window.deiconify()
        window.mainloop()
    except Exception as e:
        failed = True
        menu_control.publish_startup(root, 'error', 'Steam startup failed: ' + str(e))
        (root / 'online-error.txt').write_text(traceback.format_exc(), encoding='utf-8')
        if not args.background and window is not None:
            messagebox.showerror('RoweMod Online', str(e), parent=window)
    finally:
        try:
            if bridge:
                bridge.close()
            elif steam:
                steam.close()
        finally:
            lock.close()
            if not failed:
                menu_control.publish_startup(root, 'closed', 'Steam companion is closed. Start Steam connection.')


if __name__ == '__main__':
    main()

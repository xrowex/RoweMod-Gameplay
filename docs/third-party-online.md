# Online launcher runtimes

RoweMod source is covered by the repository's MIT license. Third-party runtime
components retain their own licenses; the MIT license does not replace them.

- Valve `steam_api64.dll`, from the locally installed Unreal Steamworks runtime.
  Copyright Valve Corporation. This package contains the runtime redistributable,
  not the Steamworks SDK. Steam client login and ownership of Rollout Inline are
  required. [Steamworks runtime integration](https://partner.steamgames.com/doc/sdk/api).
- CPython 3.8 runtime, Python Software Foundation. See `licenses/Python.txt` in
  the packaged ZIP.
- Tcl/Tk 8.6. See `licenses/Tcl.txt` and `licenses/Tk.txt` in the packaged ZIP.
- PyInstaller bootloader, GPL with an exception allowing distribution of the
  generated executable under the application's license. See `licenses/PyInstaller.txt`.

- Native menu construction techniques adapted from Matthew Arvidson's MIT [ue4ss-ModMenu](https://github.com/mattdavida/ue4ss-ModMenu). See `docs/licenses/ModMenu.txt`.

The tested UE4SS runtime is included under its MIT license: `tools/deps/ue4ss-runtime/ue4ss/LICENSE`. Source: https://github.com/UE4SS-RE/RE-UE4SS/tree/f6d5f942. Game assets are not included.

- Anatomical skeleton surfaces adapted from Z-Anatomy / BodyParts3D, with adapted surfaces under CC BY-SA 4.0. See `docs/licenses/Skeleton.txt` and `assets/skeleton/SOURCE-LICENSE.txt`. This asset license is separate from the mod code license.

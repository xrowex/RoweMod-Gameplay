# Realistic skeleton body — prototype

Adds **Skeleton** to Rollout Inline's existing character customization **Body** selector. It is an additional body; normal bodies remain available. Clothing and skates use the game's existing controls. The model has articulated hands and uses the existing animation rig and ragdoll asset. Bone surfaces use a separate material slot so native skin colouring should not replace them.

Prototype 2 corrects the chest protruding through tops: the ribs and sternum are fitted inside the stock torso with a 14 mm front margin and use interpolated stock body weights instead of rigidly following one spine joint. Offline hoodie checks cover neutral, forward/back lean, twisting and side bending. These do not replace a check with the game's actual animations and other tops.

## Install and test

1. Install or update RoweMod 0.5.7 or newer. The normal installer and automatic updater include the skeleton; no separate body installer is needed. Existing users: launch the game to download the update, close Rollout and RoweMod Online for installation, then launch again.
2. Start Rollout and select **Skeleton** under character customization > Body. Use the normal clothing controls to expose the body if desired.
3. Check skating, crouching, jumps, grabs, falls, changing maps, and returning to a normal body. Check hands, feet/skate alignment, materials, and saved selection after restarting.
4. For multiplayer, install the same add-on on every player's PC, by updating everyone to the same RoweMod version. The existing appearance system sends mesh/material paths; it does not download missing body assets. Verify the skeleton from both host and guest views.

The body is bundled with RoweMod starting in 0.5.7. Cooking, package validation and bone-pose comparison do not prove in-game animation, clothing, ragdoll or multiplayer appearance. Those checks still require native play testing.

To remove it, first select a normal body and save, close the game, then remove only `RoweSkeleton_P.pak`, `RoweSkeleton_P.utoc`, and `RoweSkeleton_P.ucas` from `RollerSkate/Content/Paks/~mods`. The installer backs up earlier files under `%LOCALAPPDATA%\RoweMod\Backups`; normal update backups store them under `GameContent/Paks/~mods`. Future RoweMod installs will restore the bundled body files.

The package overrides the body-selection table. Another mod changing that table may conflict; build against the intended installed mod set. The builder preserves existing rows and adds `rowe-skeleton-mod`.

## Rebuild / adapt

In the gameplay repository, run `tools/bodies/build_skeleton.ps1`. Parameters select the game directory, clothing tool checkout, Blender executable, and Unreal 5.4 directory. Requires Python, .NET 8, Blender 4.4, Unreal 5.4, and the existing clothing tool checkout (CUE4Parse, mappings, retoc, DtPatcher, and rig-verification script).

The build downloads a checksum-pinned anatomical model, extracts the current game's reference rig and body table, fits and simplifies the model, restores native joint axes after Blender export, imports into an isolated Unreal project, cooks it, compares all 87 bones against the native rig, and creates a separate add-on ZIP under `dist`. Previous isolated Unreal projects are backed up under `build`. It does not start the game or publish a release.

Editable fitted source: `build/skeleton-source/RoweSkeleton.blend`. Geometry and bone assignments: `build/skeleton-source/adaptation.json`. These generated files are excluded from Git; the source download and adaptation scripts are tracked. Only the custom mesh, two materials, preview texture, and body table enter the game package. Cook-time placeholder rig/physics packages are excluded, leaving references to the installed game's originals.

Model preview images are renders of the adapted mesh, not in-game screenshots.

## Attribution

Anatomical surfaces are adapted from [Z-Anatomy / BodyParts3D](https://github.com/LluisV/Z-Anatomy/tree/6c7f9016bd5899ac8edafd31b9900c151df42ed6/Resources/Models). See `docs/licenses/Skeleton.txt` and `assets/skeleton/SOURCE-LICENSE.txt` in the complete RoweMod ZIP. Standalone developer builds include the same notices as `ATTRIBUTION.txt` and `SOURCE-LICENSE.txt`. Retain those notices when sharing this add-on. The adapted surfaces are CC BY-SA 4.0.

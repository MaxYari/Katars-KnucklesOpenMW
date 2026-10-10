# Katars tools

The scripts that build Katars & Knuckles' plugins, hybrid definitions, animations, off-hand
bone and effects. None of them ship with the mod. The Blender scripts that bake the textures and
export the meshes, and the release tooling, are in [tools/](../../tools/README.md); how everything
works is in the [technical notes](../DEVELOPMENT.md).

Run everything from the repository root.

## What they need

- **Python 3**, and **numpy** for the ones that do rig maths (`patch_skeleton.py`,
  `mirror_weapon_track.py`, `mirror_bone.py`, `charge_fx.py`, `import_h2h_set.py`).
- **The es3 NIF library** from [Greatness7's io_scene_mw](https://github.com/Greatness7/io_scene_mw),
  for any script that reads or writes a `.nif` or `.kf`. It is found in the installed Blender add-on;
  otherwise set `IO_SCENE_MW` to the add-on's `lib` folder.
- **Blender 5.1** for the ones marked *Blender*. They work on the open `Reanimv  starts Katsr.blend`:
  open the script in Blender's Text Editor and run it, or run it headless as shown.
- **ReAnimation's repository**, in a folder next to this one whose name starts with "ReAnimation", for
  the animation tools: they use its moveset builder and its FBA merge. `--reanimation` points them
  somewhere else.
- **Morrowind's Data Files**: the masters, and Morrowind.bsa for the vanilla animations and effects.

## Plugins and definitions

**`make_plugin.py`** writes `Katars&Knuckles.omwaddon`: every weapon and its shop-enchanted versions, the
uniques' enchantments (stand-ins that `content.lua` replaces in game), Bound Fist and its weapons, the
note, the vanilla levelled lists with the weapons added, and the two shop chests. Give it the masters
in load order:

```
python3 Sources/Tools/make_plugin.py -o "Katars&Knuckles.omwaddon" --master "<Data Files>/Morrowind.esm" \
    --master "<Data Files>/Tribunal.esm" --master "<Data Files>/Bloodmoon.esm"
```

After it, re-run the three below: they read its tables or record its size.

**`make_tr_plugin.py`** writes `Katars&Knuckles_TamrielRebuilt.omwaddon`, Tamriel Data's Morrowind lists
extended the same way:

```
python3 Sources/Tools/make_tr_plugin.py --master "<Data Files>/Morrowind.esm" \
    --tamriel-data "<path>/Tamriel_Data.esm"
```

**`make_hybrid_definitions.py`** writes `HybridWeaponDefinitions/<id>.yaml` for every weapon
`make_plugin.py` makes:

```
python3 Sources/Tools/make_hybrid_definitions.py
```

**`make_test_crate.py`** writes `Katars&Knuckles_FOR_TESTING_ONLY_Crate_With_All_Items.omwaddon`, a
crate with one of every item by the stump near the Seyda Neen lighthouse. For testing; it is never released.

```
python3 Sources/Tools/make_test_crate.py --master "<Data Files>/Morrowind.esm"
```

`Katars&Knuckles_WorldPlacements.omwaddon` has no script: it is placed by hand in OpenMW-CS. The CS
saves it in its own data folder (`~/.local/share/openmw/data/` on Linux), which outranks this one in game, so copy
it back into `00 Core/` before committing.

## Animations

The first-person set lives in the blend. In order, after changing it:

1. **`reseat_weapon_bones.py`** (*Blender*) - after moving `Weapon Bone` in `[Raw] Katar Idle`: gives
   every katar action holding the old seat the new one, and keys `Weapon Bone.L` at its mirror.

   ```
   blender -b "Reanimv  starts Katsr.blend" --python Sources/Tools/reseat_weapon_bones.py -- --save
   ```

2. **`snap_attack_ends.py`** (*Blender*) - after changing the first frame of `[Raw] Katar Idle`: ends
   every attack on that pose.

   ```
   blender -b "Reanimv  starts Katsr.blend" --python Sources/Tools/snap_attack_ends.py -- --save
   ```

3. **`export_katar_anims.py`** (*Blender*) - exports every `[Raw] Katar` action to
   `00 Core/Animations/xbase_anim.1st` as `.kf`, and checks the footsteps and the one-handed loops.
   `-- --only Idle` exports only the actions whose name contains it.

   ```
   blender -b "Reanimv  starts Katsr.blend" --python Sources/Tools/export_katar_anims.py
   ```

4. **`make_katar_1h_movement.py`** (*Blender*) - after changing the katar walk or sneak: lays them out
   as the first-person one-handed walk and sneak are (`[Raw] Katar Walk 1h`, `[Raw] Katar Sneak 1h`),
   and with `--export` exports them too.

   ```
   blender -b "Reanimv  starts Katsr.blend" --python Sources/Tools/make_katar_1h_movement.py -- \
       --save --export "00 Core/Animations/xbase_anim.1st"
   ```

5. **`make_third_person_anims.py`** - the third-person sets, `Animations/xbase_anim` and
   `Animations/xbase_animkna`, made from the first-person one. Re-run it after every first-person
   export. It finds Morrowind.bsa from `openmw.cfg` (`--data-files` otherwise) and copies each
   animation's blending rules (`<name>.yaml`) along. It uses `third_person_fingers.py`.

   ```
   python3 Sources/Tools/make_third_person_anims.py
   ```

The blending rules in `Animations/xbase_anim.1st` are ReAnimation's own hand-to-hand ones,
`xh2hJump.yaml`, `xh2hSlash.yaml` and `xh2hThrust.yaml`, under the katar's names. There are only
those three because ReAnimation has only those three.

Also:

- **`import_h2h_actions.py`** (*Blender*) - brings ReAnimation's hand-to-hand `[Raw]` actions into the
  blend as the katar's. Only for starting over from ReAnimation; the actions are this mod's since.

  ```
  blender -b "Reanimv  starts Katsr.blend" --python Sources/Tools/import_h2h_actions.py -- \
      --source "<ReAnimation>/Sources/Reanimv3.blend" --save
  ```

- **`footstep_refs.py`** - renames the `SoundGen` keys in `.kf` files to `SoundGenRef`, or back. The
  blend's markers are `SoundGenRef` already.

  ```
  python3 Sources/Tools/footstep_refs.py <.kf files, or folders of them>
  ```

## The off-hand bone

**`patch_skeleton.py`** writes `Animations/<skeleton>/h2h_weapon_bone_l.nif`, which grafts
`Weapon Bone.L` onto that skeleton, for each skeleton it is given. A player whose skeleton replacer
loads a skeleton under a new file name gets no off-hand weapon: run this on that skeleton, with
`--bones-out` pointing at the mod's `Animations` folder.

```
python3 Sources/Tools/patch_skeleton.py <skeleton .nif files, or a folder of them> --bones-out Animations
```

`-o <meshes folder>` writes patched copies of the skeletons instead, which conflict with any other
mod that ships them.

**`mirror_weapon_track.py`** gives `Weapon Bone.L` the mirrored track of `Weapon Bone` in `.kf`
files. The katar's own animations carry it already; this is for anyone else's animations, without
which the off-hand weapon sits at rest:

```
python3 Sources/Tools/mirror_weapon_track.py <.kf files, or folders of them>
```

**`mirror_bone.py`** holds the mirroring both use. Run on its own, it tests itself:

```
python3 Sources/Tools/mirror_bone.py
```

**`add_weapon_bone_l.py`** (*Blender*) puts `Weapon Bone.L` on the blend's `Bip01` armature, with an
Auto-Rig Pro controller to pose it by.

## Effects and patches

**`venom_fx.py`** builds Ebony Rose's purple poison, its hit and area effects, textures and spell
icon, from the vanilla poison ones in Morrowind.bsa. It needs OpenMW's `bsatool`.

```
python3 Sources/Tools/venom_fx.py --data "<Data Files>" --bsatool <OpenMW folder>/bsatool
```

**`charge_fx.py`** makes Mage Fury's crystal translucent, and builds the glow that shows inside it
while it is charged (`<mesh>_charged.nif`, next to the weapon's mesh):

```
python3 Sources/Tools/charge_fx.py --alpha "00 Core/meshes/mage_fury.nif" --shape Crystal
python3 Sources/Tools/charge_fx.py --effect "00 Core/meshes/mage_fury_charged.nif" --from-mesh "00 Core/meshes/mage_fury.nif" --between
```

**`glowset_patch.py`** writes `01 Glass Glowset Patch/meshes/glass_katar.nif`: the glass katar with
the glow map Glass Glowset gives each of its vanilla textures, in the glow slot. OpenMW only reads a
glow map from the mesh, never by file name. Glowset's maps are not shipped, so the patch needs
Glowset installed. Re-run it after every export of the glass katar.

```
python3 Sources/Tools/glowset_patch.py
```

## Tests

**`tests/run.sh`** runs the script tests: the mod's real Lua against fakes of the OpenMW API
(`tests/stubs.lua`), under Lua 5.4. It finds ReAnimation in a folder next to this repository, or at
`H2H_REANIMATION`.

```
bash Sources/Tools/tests/run.sh
```

## Retired

- **`export_weapons.py`** (*Blender*) - the first mesh exporter, superseded by `tools/mw_export.py`.
  Kept because it documents the grip-bar centring the weapon records depend on.
- **`import_h2h_set.py`** - made the katar moveset by patching ReAnimation's exported `.kf` files.
  The blend has been the source since.

[SKELETON_BONES.md](SKELETON_BONES.md) is the investigation behind the grafted off-hand bone.

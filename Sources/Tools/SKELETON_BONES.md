# Handover: replace the patched skeletons with animation-source bones

**Owner:** whoever maintains `patch_skeleton.py` / `mirror_bone.py` / `mirror_weapon_track.py`
**Status:** implemented; the patched skeletons are already gone from `meshes/`, so the grafted bone
is the only route and the in-game check below is what is left. The findings supersede parts of the
original note further down.

## Findings, from the engine source

The direction of this note is right; two of its specifics were not, and its open questions have
answers. From `apps/openmw/mwrender/animation.cpp` and `components/nifosg/nifloader.cpp`:

- **Only marked nodes are grafted.** `Animation::injectCustomBones` scans every `.nif` in the folder
  and copies the nodes that carry the user description `CustomBone`, which the loader gives a node
  with an `NiStringExtraData` reading `BONE` (`nifloader.cpp:712`). Each is deep-copied under the
  skeleton's node named like its parent in the source file. **None of the katar animation `.nif`
  files mark `Weapon Bone.L`**, so they contribute nothing: first-person male did *not* already work
  this way - it, like every other skeleton, got the bone from the patched `xbase_anim.1st.nif`.
- **The folder is named after the skeleton file the engine loads** (open question 1): that model's
  path with `meshes` swapped for `animations` and the extension for a slash. And the file it loads is
  not always the one `getActorSkeleton` names: `correctActorModelPath` swaps in the `x` twin whenever
  `x<name>.kf` exists, which in vanilla is every rig but the female first-person one. So third-person
  male is `xbase_anim.nif` -> `animations/xbase_anim/`, beast first-person `xbase_animkna.1st.nif` ->
  `animations/xbase_animkna.1st/`, female first-person stays `base_anim_female.1st.nif`. (The first
  version of this work wrote the plain names and so fed only two of the six rigs - found from an
  in-game "no Weapon Bone.L" once the patched skeletons were gone. It also means the patched plain
  `base_anim*.nif` never reached a third-person actor.) NPCs with a custom model also get their
  race's default skeleton's folder injected.
- **One file per folder** (open question 2): every marked copy is grafted, with no de-duplication, so
  two files marking the same bone make two nodes. The animation `.nif` files must stay unmarked.
- **Several mods** (open question 3): the same - each marked node from each file is added. The node
  map is filled first-found, so the skeleton's own node, if it has one, wins over grafted copies;
  that is also why shipping both routes at once is harmless.
- **Only with "use additional animation sources" on**, and only for NPCs and bipedal creatures
  (`Animation::setObjectRoot`). ReAnimation requires that setting anyway.

## Done

`python3 Sources/Tools/patch_skeleton.py <vanilla skeletons> --bones-out Animations` writes
`Animations/<skeleton>/h2h_weapon_bone_l.nif` for every skeleton the engine can load, plain and `x`
alike - ten folders; only the one actually loaded is read, so none adds twice: `Bip01 L Hand` with
`Weapon Bone.L` under it, marked `BONE`, at the plain conjugation of `Weapon Bone` - no half turn,
which is the katar's and lives in its animation tracks (see the last section). All pass `niftest`; the plain and `x` rigs give identical transforms, and
first-person male comes out at `[5.334, 0.699, -1.412]`, as the patched skeleton had it. The
vanilla skeletons come from Morrowind.bsa (`bsatool extract`).

## Left

1. In game - the patched skeletons have since been removed from `meshes/` - on each race and in
   both views, the off-hand weapon must appear.
2. Then drop those meshes from the repo, and `.nexusignore`'s special case for shipping
   `patch_skeleton.py` to users with skeleton replacers.

---

The original note follows.

## Summary

`Weapon Bone.L` is currently delivered by **shipping patched copies of Morrowind's actor
skeletons** in `meshes/`. That works, but it costs ~8 MB of vanilla meshes in the release and
hard-conflicts with any mod that replaces the same skeletons.

OpenMW has supported a non-conflicting way to do this since **0.46**. The mod already uses it for
one skeleton. Extending it to the rest would let `meshes/base_anim*.nif` and
`meshes/xbase_anim.1st.nif` be dropped from the release entirely.

## Evidence that the supported mechanism exists

From the shipped `CHANGELOG.txt` of OpenMW 0.51, both entries under **0.46.0**:

```
Feature #5131: Custom skeleton bones
Bug #4747: Bones are not read from X.NIF file for NPC animation
```

The second is the mechanism. OpenMW scans `animations/<basename>/` for additional animation
sources, and since 0.46 it reads the **bone hierarchy from the source's companion `X.NIF`**, not
only from the actor's skeleton. Any number of mods can each drop their own pair there and
contribute bones; none of them has to replace a skeleton.

### Do not repeat this mistake

This log line looks like proof that the Animations folder cannot add bones:

```
addAnimSource: can't find bone 'bip01 l toe0' in meshes/xbase_anim.nif
               (referenced by animations/xbase_anim/xanim_bodybuilding.kf)
```

It is not. Read which file it searched: `meshes/xbase_anim.nif`, the stock animation nif. That mod
shipped a **`.kf` only**, so OpenMW had no source nif to take bones from and fell back to the stock
one. It says nothing about the case where a source brings its own `.nif` — which is exactly what
#4747 added. Generalising from the `.kf`-only case is what produced the wrong conclusion the first
time round.

## What is already in place

`Animations/xbase_anim.1st/` already ships the correct thing:

```
xKatarIdle.nif            Weapon Bone.L present
xKatarSlash.nif           Weapon Bone.L present
xKatarSlashMirrored.nif   Weapon Bone.L present
```

Structure of `xKatarIdle.nif` (7 KB, 57 nodes) — a skeleton subset, not a full copy:

```
NiNode 'Bip01'                      t=[0.00, 0.00, 76.72]
  ...
    NiNode 'Bip01 L Hand'           t=[16.94, 0.00, 0.00]
      NiNode 'Weapon Bone.L'        t=[5.33, 0.70, -1.41]
      NiNode 'Weapon Bone'          t=[5.50, 1.16, 0.51]
```

That translation matches what `patch_skeleton.py` writes into `xbase_anim.1st.nif`
(`[5.334, 0.699, -1.412]`), so the two routes already agree for this skeleton. **This file is the
template** for the others.

## The gap

`patch_skeleton.py` covers seven skeletons. `Animations/` covers one.

| skeleton (`MWRender::getActorSkeleton`) | patched in `meshes/` | animation source |
| --- | --- | --- |
| `xbase_anim.1st.nif` — male, 1st person | yes | **yes** |
| `base_anim.nif` — male, 3rd person | yes | no |
| `base_anim_female.nif` — female, 3rd person | yes | no |
| `base_animkna.nif` — beast, 3rd person | yes | no |
| `base_anim_female.1st.nif` — female, 1st person | yes | no |
| `base_animkna.1st.nif` — beast, 1st person | yes | no |
| `base_anim.1st.nif` — patched "harmlessly", never loaded as a skeleton | yes | n/a |

So first-person male already works the supported way; every other case is currently carried by the
replaced skeletons.

## What needs doing

1. **Emit animation-source pairs instead of patching skeletons.** For each remaining skeleton,
   produce an `x<name>.nif` + `x<name>.kf` pair under `Animations/<folder>/` containing a node
   hierarchy with `Weapon Bone.L` parented under `Bip01 L Hand`. It does not need to be a full
   skeleton — see the 57-node template above.

2. **Reuse the existing transform maths.** `mirror_bone.py` already derives the bone's local
   transform (`conjugate()` for `S · M · S`, then `apply_spin()` for the half turn about the blade
   axis). `mirror_weapon_track.py` already writes the matching `.kf` track. Neither needs changing;
   only the thing that *consumes* them does.

3. **Keep both routes working during the transition.** `player.lua` already guards with
   `animation.hasBone(omwself, "Weapon Bone.L")` and prints a useful message when it is absent, so
   a partial migration degrades cleanly rather than breaking.

4. **Once every skeleton is covered**, drop `meshes/base_anim*.nif` and `meshes/xbase_anim.1st.nif`
   from the release and simplify or retire `patch_skeleton.py`. Check `.nexusignore` too — it
   currently makes a point of shipping `patch_skeleton.py` for users with skeleton replacers, which
   stops being necessary.

## Open questions to resolve first

- **Folder naming.** Observed in the log: `animations/xbase_anim/`, `animations/xbase_anim_female/`,
  `animations/xbase_animkna/`, and this mod's `Animations/xbase_anim.1st/`. The folder is named
  after the *animation* file's basename, which is not always the skeleton's: 3rd-person male uses
  skeleton `base_anim.nif` but animations from `xbase_anim.nif`. The first-person female and beast
  rigs use `base_`-prefixed skeleton names, so their animation folder names need checking rather
  than assuming an `x` prefix.

- **Does the bone need to be in every source nif, or just one?** All three existing katar sources
  carry it. If one is enough, the other two can stop carrying it; if each source's nif is consumed
  independently, they all need it. Worth establishing before generating five more sets.

- **Load order between sources.** If several mods add the same bone name, confirm what the engine
  does — last wins, first wins, or a warning.

## How to verify

- In game, on each race and in both views: `animation.hasBone(actor, "Weapon Bone.L")` should be
  true, and the off-hand weapon should appear.
- Move `meshes/base_anim*.nif` and `meshes/xbase_anim.1st.nif` out of the mod folder and confirm the
  off-hand weapon still shows. That is the whole point of the exercise — if it does, they can go.
- Watch `openmw.log` for `addAnimSource` warnings naming `Weapon Bone.L`.

## Context on the half turn

**Update:** the half turn is no longer on the bone. It turns about the katar's blade axis (X), but
vanilla weapons are modelled blade up +Y, and the turn flips Y - so on the bone it hung every
vanilla weapon upside down (a longsword's tip came out at Z +62 in the left hand where a true
mirror puts it at -67; the plain conjugation puts it within 0.2 units). The bone is now the plain
conjugation, which flips Z, across which vanilla weapons are symmetric, and the turn is applied by
`mirror_weapon_track.py` to the katar's own `Weapon Bone.L` tracks only. Where no katar animation
plays - third person, other animation mods - the off-hand katar has no turn. The Blender file
matches: io_scene_mw corrects "Bip01" bones' axes and every other bone's differently, so there the
plain mirror flips `diag(1, -1, 1)` on the weapon's side (`add_weapon_bone_l.py`), and
`import_h2h_actions.py` keys the turn into the katar actions. The history below is why the turn
exists at all.

`patch_skeleton.py` and `mirror_weapon_track.py` both apply `mirror_bone.apply_spin()` — a 180°
rotation about the blade axis (`SPIN_AXIS = 0`, X). This is needed because `S · M · S` is a
similarity transform and so preserves handedness: the off-hand frame is a *rotation* of the
main-hand one, never a reflection, which left the weapon's outward face pointing across the body.
A true mirror is not available — a NIF node carries one uniform `float32` scale, so there is no
per-axis negative scale, and a reflection would invert triangle winding without OpenMW reversing
face culling to match. Any replacement for `patch_skeleton.py` has to keep applying the same spin,
or the off-hand weapon goes back to being flipped.

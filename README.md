# Katars and Knuckledusters

Hand-to-hand weapons for OpenMW: five katars and six sets of knuckledusters that you fight with
using the **Hand to Hand** skill, not the weapon skill the engine files them under.

Morrowind has no hand-to-hand weapon type. A katar has to be a short blade and knuckledusters have
to be a blunt weapon, or the engine will not let you hold them. So each of the things that follows
from that is put back by a script: the skill the hit chance is rolled against, where the experience
goes, the fatigue damage a punch would do, the second weapon in your off hand, and the sword-drawing
sound your fists should not make.

## Requirements

- **OpenMW 0.49 or newer.**
- **[ReAnimation](https://www.nexusmods.com/morrowind/mods/52596) 3.2 or newer** - required. The
  katar moveset is registered through it.
- **[Max Yari's Script Services (MSS)](https://www.nexusmods.com/morrowind/mods/60256)** - required.
  ReAnimation needs it too.
- **[Inventory Extender](https://www.nexusmods.com/morrowind/mods/59205)** - optional. Adds the
  hand-to-hand type and the fatigue damage to item tooltips.

In the OpenMW launcher, under Settings -> Visuals -> Animations, **Use Additional Animation
Sources** must be on. ReAnimation needs it as well.

## Install

Add the mod folder as a data directory, then enable, in this order:

```
content=ReAnimation_API.omwscripts
content=ReAnimation_v3.omwscripts
content=Katar.omwaddon
content=H2HWeapons.omwscripts
```

`H2HWeapons.omwscripts` has to come after `ReAnimation_API.omwscripts`: it talks to ReAnimation's
interface as it loads.

## What the weapons do

Both trade health damage for fatigue damage against the shortsword they are cut from.

**Katars** are short blades. They hit for 80% of the vanilla shortsword of their material, and take
half the fatigue a bare fist would.

**Knuckledusters** are blunt weapons. They hit for 50% of that shortsword, and take three quarters
of the fatigue - they are made for bruising.

- **Damage:** katars 80% of that shortsword, knuckledusters 50%.
- **Fatigue damage:** katars 50% of a bare-fisted hit, knuckledusters 75%.
- **Engine weapon type:** katars Short Blade, knuckledusters Blunt Weapon. Both one handed.
- **Skill you actually use:** Hand to Hand, for both.

Eleven weapons, in iron, chitin, steel, silver, orcish, ebony and daedric. Their stats are derived
from the vanilla shortswords rather than picked by hand - see `Sources/Tools/make_plugin.py`, which
is what writes `Katar.omwaddon`.

Weight and enchantment capacity are both measured against the **dagger** of the same material
rather than the shortsword, at different shares.

**Weight** is what a swing costs you. The engine charges the attacker
`fFatigueAttackBase (2.0) + weight × swing strength × fWeaponFatigueMult (0.25)`, and bare fists pay
only the flat 2.0, having no weapon at all - so weight is tuned against that floor rather than
against the blade these are cut from. A knuckleduster is **half a dagger** and a katar **nine tenths
of one**, which puts a full-strength swing 19% and 34% over a fist's cost at the iron/steel tier
(a steel dagger is 38%).

**Capacity** is a different question - how much weapon there is to enchant - and there a katar is
two thirds of a dagger and a knuckleduster a third. The engine has no formula for capacity at all,
it reads the number off the record; but within any one vanilla weapon line it is a fixed multiple of
the weight, with the material carrying the weight (daggers run at 6.67 points per unit, shortswords
at 5.0, right across iron through daedric), and these follow that.

### Hit chance

The engine rolls a melee hit against whatever skill the weapon says it uses. For the length of every
swing, that skill *is* your Hand to Hand: the difference is written into the weapon skill's modifier
when the swing winds up and taken back out when it follows through, so the roll the engine makes is
the one it would make with your fists.

Keeping the weapon skill up alongside it pays, and the bonus is a share of **that** skill, so
letting it rot costs you twice over - a smaller share of a smaller number. While Short Blade (or
Blunt Weapon) is within **10 points** of your Hand to Hand, or ahead of it, you get **15% of the
weapon skill** on top. Past that it tapers over the next 20 points down to **5%** - a floor, not a
cutoff. The result is rounded down to whole skill points, so the number the tooltip shows is exactly
the one a swing applies. Every number there is a setting.

### Experience

A successful hit gives **70% to Hand to Hand and 30% to the weapon skill** the engine thinks you
used. The split is a setting.

### Fatigue damage

Every hit also costs the target fatigue, using the engine's own unarmed formula
(`MWMechanics::getHandToHandDamage`):

```
hand to hand skill * (fMinHandToHandMult + (fMaxHandToHandMult - fMinHandToHandMult) * swing strength)
```

scaled by 50% for a katar or 75% for knuckledusters. If you have the launcher's **strength
influences hand to hand** option on (Advanced -> Combat), set this mod's copy of it to match -
nothing can read the real one from a script, so the mod has to be told.

This works for NPCs swinging these weapons as well as for you.

### The off-hand weapon

A second copy of the weapon is put in your left hand while the weapon is drawn, hanging off a
`Weapon Bone.L` bone that this mod's skeleton meshes add beside the engine's own weapon bone. See
*Compatibility* below, and turn it off in the settings if it gets in the way.

### The draw sound

Drawing a short blade or a blunt weapon plays a sound. Bare hands do not, and neither do these.

## Settings

Options -> Scripts -> Katars and Knuckledusters.

- **Strength influences hand to hand** (default off) - must match the launcher option of the same name.
- **Hand to Hand experience share** (0.7) - the rest goes to the weapon skill.
- **Weapon skill bonus** (0.15) - share of the weapon skill added while it keeps up.
- **Weapon skill bonus floor** (0.05) - the share a neglected weapon skill is still worth.
- **Weapon skill bonus grace** (10) - points it may fall behind before the share starts tapering.
- **Weapon skill bonus falloff** (20) - points past the grace over which it reaches the floor.
- **Show the off-hand weapon** (on).
- **Silence the draw and sheathe sound** (on).

These are shared by every actor, so they live in the save rather than in your settings file.

## Compatibility

**Skeletons.** The actor skeletons are shipped here, patched to add one bone. Which file the engine
loads depends on the view and the race (`MWRender::getActorSkeleton`): third person is
`base_anim.nif`, `base_anim_female.nif` or `base_animkna.nif`; first person is
**`xbase_anim.1st.nif`** for a male human, `base_anim_female.1st.nif` or `base_animkna.1st.nif`
otherwise. Note that first-person male one - `base_anim.1st.nif` is never loaded as a skeleton at
all, despite the name.

Anything else that replaces these - another skeleton replacer, a body mod - will conflict, and
whichever loads last wins. If this mod loses, the off-hand weapon quietly does not appear and
everything else still works. To have both, patch the other mod's skeletons instead:

```
python3 Sources/Tools/patch_skeleton.py <that mod>/meshes -o <that mod>/meshes
```

It needs [Greatness7's io_scene_mw](https://github.com/Greatness7/io_scene_mw) Blender add-on
installed, for the NIF library inside it, and it is safe to run twice.

**One-handed attacks.** The katar moveset and ReAnimation's own one-handed set both live on the
`weapononehand` animation group, and only one may be active at a time. This mod stands ReAnimation's
down while a katar or knuckleduster is in hand, through `I.ReAnimation.addOverrideCondition`. Any
other mod adding a moveset to that group needs to do the same.

**Textures.** Vanilla ones (Morrowind.bsa and Tribunal.bsa) are used as they are and nothing is
overwritten, so retexture packs carry straight over. Textures baked for this mod live under
`textures/katars/`.

<!-- nexus-skip-start -->

## Building from source

`Reanimv  starts Katsr.blend` holds the weapons and the rig. Everything built from it is built by a
script, so a rebuild is reproducible:

- `Sources/Tools/export_weapons.py` - exports every weapon empty to its own `.nif`, centred on the
  grip bar. Superseded by `tools/mw_export.py`, which is what produces the shipped meshes now; this
  one is kept because it documents the grip-bar centring the records depend on.
- `Sources/Tools/patch_skeleton.py` - adds `Weapon Bone.L` to the vanilla skeletons.
- `Sources/Tools/make_plugin.py` - writes `Katar.omwaddon` from the vanilla shortsword table.
- `Sources/Tools/add_weapon_bone_l.py` - builds the ARP controller for that bone in the Blender file.
- `Sources/Tools/tests/run.sh` - runs the script tests against fakes for the openmw API.

The weapon exporter runs inside Blender:

```
blender -b "Reanimv  starts Katsr.blend" --python Sources/Tools/export_weapons.py -- meshes
```

`textures/` is not in the repo: every texture these meshes use ships with the game, and the folder
is only there so the Blender file has something to preview against. Extract them from Morrowind.bsa
and Tribunal.bsa if you want them back.

### The rig

The Blender file carries the vanilla `Bip01` armature driven by an Auto-Rig Pro rig, exactly as
ReAnimation's own source does. `Weapon Bone.L` exists on both: as a deform bone on `Bip01`,
constrained to a matching ARP custom controller (`cc` bone) under `hand.l`, so it can be posed like
any other controller.

The game learns about the bone from the patched skeletons, not from the animations - OpenMW builds
its bone map once, from the skeleton, and nothing a `.kf` adds later appears in it.

Its placement is not a mirror. `Weapon Bone.L` carries `Weapon Bone`'s transform *within its own
hand's frame*, copied straight across, because `Bip01 L Hand` and `Bip01 R Hand` are already
anatomical mirrors of each other - so the same offset inside the hand comes out mirrored in the
world, with the blade still leading the punch. Mirroring it explicitly gets it wrong, and so does
deriving it from `Shield Bone`, the one mirror pair vanilla actually ships: a shield is not held the
way a blade is, and the blade ends up pointing back through the forearm. Both the Blender rig and
`patch_skeleton.py` say this the same way, and the patcher refuses to write a file whose blade would
point backwards - measured against that rig's own forearm, as the right hand's does.

<!-- nexus-skip-end -->

## Credits

- Meshes, animations and scripts: Max Yari
- Textures: Bethesda (Morrowind, Tribunal)
- NIF library: [Greatness7](https://github.com/Greatness7/io_scene_mw)

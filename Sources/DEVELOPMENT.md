# Katars and Knuckledusters - technical notes

How the mod works, in detail, and how to build it: for modders and anyone curious. The user-facing
README is at the repository root. This covers the uniques' magic and everything else in full, so it
is one long spoiler.

Paths are from the repository root.

## What the weapons do

Both trade health damage for fatigue damage against the shortsword they are cut from.

**Katars** are short blades. They hit for 80% of the vanilla shortsword of their material, and take
half the fatigue a bare fist would.

**Knuckledusters** are blunt weapons. They hit for 50% of that shortsword, and take three quarters
of the fatigue - they are made for bruising.

- **Damage:** katars 80% of that shortsword, knuckledusters 50% - and the same whichever way you
  swing, as a fist's is: one range for chop, slash and thrust alike, the shortsword's best attack
  (the one the game picks with "always use best attack").
- **Fatigue damage:** katars 50% of a bare-fisted hit, knuckledusters 75%.
- **Engine weapon type:** katars Short Blade, knuckledusters Blunt Weapon. Both one handed.
- **Skill you actually use:** Hand to Hand, for both.

Thirteen weapons, in wood, iron, chitin, steel, silver, orcish, ebony and daedric. Their stats are
derived from the vanilla shortswords rather than picked by hand - see `Sources/Tools/make_plugin.py`,
which is what writes `Katar.omwaddon`.

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

scaled by 50% for a katar or 75% for knuckledusters - at Hand to Hand 50, a full swing bruises for
25 with a bare fist, 12.5 with a katar and 18.75 with knuckledusters.

With the launcher's **strength influences hand to hand** option on (Advanced -> Combat), that is
multiplied by Strength / 40, as a fist's is. No script can read that option, so this mod has a
mirror of it in its settings: set it to match the launcher.

It behaves as a fist's does in every other way too:

- A **blocked** hit bruises nobody.
- A **critical strike** - yours, on someone who has not noticed you - bruises four times over
  (`fCombatCriticalStrikeMult`), as it multiplies the weapon's own damage.
- Fatigue driven below zero knocks the target out, and once they are down - knocked down, knocked
  out or paralysed - the bruising lands on their health instead, at a tenth of its value
  (`fHandtoHandHealthPer`), and half again on a knocked-down target (`fCombatKODamageMult`), which the
  engine gives every hit on one - the weapon's own damage included.

This works for NPCs swinging these weapons as well as for you.

### The off-hand weapon

A second copy of the weapon is put in your left hand while the weapon is drawn, hanging off a
`Weapon Bone.L` bone that this mod's skeleton meshes add beside the engine's own weapon bone. See
*Compatibility* below, and turn it off in the settings if it gets in the way.

Animations pose the weapon bone to seat a weapon in the grip, so the off-hand one needs the same
track or it sits wherever the skeleton's rest pose left it. This mod's own animations carry it. Any
animation that does not - anything from another animation mod, and third person, where this mod has
no animations of its own - leaves the off-hand weapon at rest, which reads as it sitting low or loose
in the hand, and for a katar with a decorated face, as that face turned in.
`Sources/Tools/mirror_weapon_track.py` adds the track to a `.kf`, and can be pointed at any animation
folder:

```
python3 Sources/Tools/mirror_weapon_track.py <animation folder>
```

### The draw sound

Drawing a short blade or a blunt weapon plays a sound. Bare hands do not, and neither do these.

## The uniques

Three: Ebony Rose, Mage Fury, and the wooden knuckles - which hit for half the iron set but take an
enchantment as well as silver does, since it is the medium, not the metal, that holds one. None of
the three is in any levelled list: nobody sells them and no chest rolls them.

Ebony Rose and Mage Fury are enchanted with magic effects of this mod's own, so their tooltips and your active effects
name and explain what they do. The engine carries those effects the way it carries any other -
duration, visuals, the area burst, the hostile reaction and the crime it can be - and the scripts add
only what the engine keys to its built-in effects and so cannot give a new one.

**Ebony Rose** (`katar_ebony_rose`) - a slim ebony katar, quicker and lighter than the guarded one.

- Every strike leaves a violet **poison**: 3 points a second for 3 seconds.
- Every strike also starts a **3-second countdown**, and the next strike on the same enemy before it
  runs out renews it. **The third strike in such a run bursts**, if that enemy is poisoned - by the
  venom or by any other poison: **Volatile Venom, 20 points for 1 second on everyone within 10 feet**
  of them. Never on you - the engine never applies an area spell to its caster. Striking someone else,
  letting the countdown run out, or a burst starts the count over.
- The tooltip says as much in its own lines: the burst has one of its own in the enchantment, an
  effect that only names it.
- **Charge:** 160, at 16 a strike and 40 for a burst - 10 strikes without bursts, fewer with them.
- The burst is a real area enchantment, so everything an area spell does, it does: the explosion,
  hostility and crime for whoever it catches. An item cannot change its enchantment, so for that one
  swing you hold a copy of the katar carrying the burst, and the original goes back into your hand -
  with the swing's charge and wear - as soon as it follows through. It never leaves your inventory,
  so hotkeys keep working.
- The venom's damage is dealt by script, since the engine only deals damage for its own effects. It
  honours **Resist Poison** and **Weakness to Poison**; **Cure Poison** does not wash it out. A
  killing blow is handed to the engine as a Damage Health cast by whoever poisoned the victim, so the
  kill is theirs by the engine's own rules - murder included, when it is one.

**Mage Fury** (`knuckle_mage_fury`) - iron knuckledusters with a crystal set in them.

- **Cast a harmful spell successfully with them equipped** and they take a charge of it: the crystal
  lights up, and "Channeled Spell" shows in your active effects with the strikes left.
- The **next 3 strikes** deal damage in proportion to that spell: each carries a third of its harmful
  effects - its magnitude, or its duration for an effect that has none - into whoever it hits.
  Applied by the engine, so resistances, reflection and kill credit are the spell's own.
- **Charge:** 160. A strike that carries the spell costs 16 - 10 of them to a full charge - and any
  other strike costs nothing. With too little left, the game refuses the strike's enchantment as it
  would any weapon's, and the spell stays in the knuckles until they are recharged.
- The charge fades **30 seconds** after the cast or the last strike.

Both recharge as any enchanted item does - by themselves, slowly, or with a soul gem - and every
cost comes down with your Enchant skill, 1% for each point above 10.

To get them:

```
player->additem katar_ebony_rose 1
player->additem knuckle_mage_fury 1
```

## Bound Fist

A conjuration spell. For 60 seconds it binds a daedric hand-to-hand weapon to your fists, and which
one depends on your **Conjuration** when you cast it:

| Conjuration | Weapon |
| --- | --- |
| under 40 | Bound Knuckles (daedric knuckledusters) |
| 40 - 64 | Bound Spiked Knuckles |
| 65 and up | Bound Katar |

It works like any bound weapon: the weapon goes into your hand and is drawn, and when the spell ends
it returns to Oblivion and whatever you held before is back in hand. And like every vanilla bound
weapon, which fortifies its own skill by 10, it carries a constant **Fortify Hand-to-hand 10** - the
skill these are swung with, so it raises both the hit chance and the bruising. NPCs who know the
spell cast it too.

**Scaling** follows [Unofficial Tamriel Rebuilt Spells](https://www.nexusmods.com/morrowind/mods/58693)'
bound item settings, so a bound fist scales exactly as that mod's bound weapons do - damage, weight
and the enchantment with Conjuration, in 5-point steps, with no ceiling. This mod has no settings of
its own for it; its settings page shows what it found. Turn on "Scale bound items" in that mod's
settings, which is off by default. Without that mod, its defaults are used and scaling is on: 50% of
the daedric weapon's damage at Conjuration 0, 0.7% more per point - the daedric weapon's own at about
75, 120% at 100 - and the same for the Fortify Hand-to-hand, from 5 to 12.

**Where to buy it:** half of the spell merchants who sell Bound Dagger or Bound Mace, about one per
town - in Vvardenfell, Masalinie Merian (Balmora, Guild of Mages), Heem-La (Ald-ruhn, Guild of Mages),
Diren Vendu (Tel Mora) and Urtiso Faryon (Sadrith Mora); with Tamriel Rebuilt, seventeen more, mostly
Temple and Imperial Cult priests and Mages Guild conjurers. The full list, and the one place to change
it, is `scripts/MaxYari/H2HWeapons/traders/list.lua`. Merchants learn it as they come into the world,
so their NPC records are never overridden and nothing conflicts with mods that edit them.

```
player->addspell h2h_bound_fist
```

## Settings

Options -> Scripts -> Katars and Knuckledusters.

- **Strength influences hand to hand** (default Off) - must match the launcher option of the same
  name.
- **Hand to Hand experience share** (0.7) - the rest goes to the weapon skill.
- **Weapon skill bonus** (0.15) - share of the weapon skill added while it keeps up.
- **Weapon skill bonus floor** (0.05) - the share a neglected weapon skill is still worth.
- **Weapon skill bonus grace** (10) - points it may fall behind before the share starts tapering.
- **Weapon skill bonus falloff** (20) - points past the grace over which it reaches the floor.
- **Show the off-hand weapon** (on).
- **Silence the draw and sheathe sound** (on).

These are shared by every actor, so they live in the save rather than in your settings file. Below
them, read-only, is where Bound Fist's scaling comes from.

## Performance

One script, `actor.lua`, runs on every NPC and creature. It has to: the bruising, the venom and Mage
Fury's spell are added to the hit inside the struck actor's own hit handler - the only place a script
can add damage to a weapon hit - and anyone can be struck. It has no per-frame handler at all. It runs
on a hit (and leaves at once unless the weapon is one of these), when an NPC casts (to notice Bound
Fist), and a few times a second only while that actor is poisoned by Ebony Rose or holds a Bound Fist.

The per-frame work is the player's: the stance, the camera mode, and the equipped weapon, which Max
Yari's Script Services reads for this mod and ReAnimation both, at most ten times a second.

## Compatibility

**Skeletons.** The off-hand weapon hangs off a `Weapon Bone.L` that vanilla skeletons do not have.
This mod adds it the way that cannot conflict: a small file per skeleton,
`Animations/<skeleton>/h2h_weapon_bone_l.nif`, whose bone OpenMW grafts onto that skeleton when it
loads it (it takes any node marked `BONE` from the `.nif` files in `animations/<skeleton name>/`;
"use additional animation sources" has to be on, which ReAnimation needs anyway). The skeleton name is
the file actually loaded, which is the `x` twin (`xbase_anim.nif`) whenever an `x…kf` exists, so there
is a folder for both names of every rig. Which skeleton the
engine loads depends on the view and the race (`MWRender::getActorSkeleton`): third person is
`base_anim.nif`, `base_anim_female.nif` or `base_animkna.nif`; first person is
**`xbase_anim.1st.nif`** for a male human, `base_anim_female.1st.nif` or `base_animkna.1st.nif`
otherwise. Note that first-person male one - `base_anim.1st.nif` is never loaded as a skeleton at
all, despite the name.

No skeleton is replaced, so skeleton and body replacers do not conflict with this: the bone is grafted
onto whatever skeleton they provide, as long as it keeps vanilla's bone names.

A replacer that loads a skeleton under a new file name gets no bone, since there is no folder of that
name here; the off-hand weapon then quietly does not appear, and everything else still works. Give
it one with:

```
python3 Sources/Tools/patch_skeleton.py <its skeleton .nif> --bones-out Animations
```

It needs [Greatness7's io_scene_mw](https://github.com/Greatness7/io_scene_mw) Blender add-on
installed, for the NIF library inside it, and it is safe to run twice.

**The moveset.** Katars and knuckledusters move and fight with ReAnimation's own hand-to-hand
animations - idle, walk, run, sneak, jump, draw and sheathe, and every punch with its mirrored
variant - imported under the katar's names by `Sources/Tools/import_h2h_set.py`, with the weapon
bones seated for the grip on the way. They keep the fist's timing: the engine's one-handed attack
underneath is re-timed to them, not the other way round, so a hit still lands on the frame it
should. That is also why these weapons have such low speeds - 0.9 for katars, 1.0 for
knuckledusters: the fist's animations are quick to begin with, and at 1.0 about as quick as a
sword's at 2.0.

**One-handed attacks.** The katar moveset and ReAnimation's own one-handed set both live on the
`weapononehand` animation group, and only one may be active at a time. This mod's set is registered
with `overridePriority = 1`, one above ReAnimation's, so ReAnimation's stands down while a katar or
knuckleduster is in hand. Any other mod adding a moveset to that group does the same.

**Loot and merchants.** The weapons are added to vanilla's own levelled lists, each wherever the
vanilla weapon it stands in for is - its material's shortsword - at the
same level: the `random_<material>_weapon` lists that chests and crates draw on, and the
`l_n_wpn_melee_*` lists that merchants' stock and NPCs' weapons come from. The uniques and the bound
weapons are in no list. A plugin can only replace a levelled list, not add to it, so a mod loaded
later that edits one of the same lists wins it; with such a mod, run a merged-lists tool
([DeltaPlugin](https://gitlab.com/bmwinger/delta-plugin), OMWLLF) as you would for any mod that adds
loot. Tamriel Data, Tamriel Rebuilt and OAAB leave these lists alone. Tamriel Rebuilt's own merchants
and containers use lists of their own, so there these turn up only where vanilla lists are used.

**Spellcasting mods.** Bound Fist and Mage Fury notice a cast however it is made: the engine's own,
or one made by [Spell Framework Plus](https://www.nexusmods.com/morrowind/mods/58652) - which is how
Oblivion-Style Spell Casting casts, for the player and for NPCs - from the report it sends the caster.
Anything else still binds the player's Bound Fist, from the effect itself, within half a second.

**Textures.** Vanilla ones (Morrowind.bsa and Tribunal.bsa) are used as they are and nothing is
overwritten, so retexture packs carry straight over. Textures baked for this mod live under
`textures/katars/`, and the venom's violet recolours of the vanilla poison effects under
`textures/katars_vfx/` - their own files, so the ordinary poison is untouched.


## Building from source

`Reanimv  starts Katsr.blend` holds the weapons and the rig. Everything built from it is built by a
script, so a rebuild is reproducible:

- `Sources/Tools/export_weapons.py` - exports every weapon empty to its own `.nif`, centred on the
  grip bar. Superseded by `tools/mw_export.py`, which is what produces the shipped meshes now; this
  one is kept because it documents the grip-bar centring the records depend on.
- `Sources/Tools/import_h2h_set.py` - makes the katar moveset from ReAnimation's hand-to-hand
  animations: renames their groups, seats the weapon bone, and mirrors it onto `Weapon Bone.L`.
- `Sources/Tools/patch_skeleton.py` - adds `Weapon Bone.L`: `--bones-out Animations` writes the
  grafted-bone files, `-o meshes` the patched skeleton copies.
- `Sources/Tools/mirror_weapon_track.py` - gives `Weapon Bone.L` the mirrored keyframe track of
  `Weapon Bone` in a `.kf`. Run it over the animations after every export.
- `Sources/Tools/mirror_bone.py` - the one definition of how this rig mirrors, shared by both of
  the above. Run it directly to self-test the quaternion maths.
- `Sources/Tools/make_plugin.py` - writes `Katar.omwaddon` from the vanilla shortsword table, with
  vanilla stand-ins for the uniques' enchantments. The real ones use custom magic effects, which an
  ESM file cannot name, so `scripts/MaxYari/H2HWeapons/content.lua` replaces them when the game starts.
- `Sources/Tools/venom_fx.py` - builds the venom's violet hit and area effects, textures and icon
  from the vanilla poison ones in Morrowind.bsa.
- `Sources/Tools/charge_fx.py` - makes a weapon's crystal translucent, and builds the glow that
  shows inside it while it is charged (`<mesh>_charged.nif`).
- `Sources/Tools/add_weapon_bone_l.py` - builds the ARP controller for that bone in the Blender file.
- `Sources/Tools/import_h2h_actions.py` - brings ReAnimation's hand-to-hand `[Raw]` actions into the
  Blender file as the katar's, the Blender side of `import_h2h_set.py`: renamed actions and text
  keys, the weapon bone seated, and `Weapon Bone.L` keyed at the mirrored seat with the katar's turn.
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

The game learns about the bone from the skeleton it loads, and nothing a `.kf` adds later appears in
its bone map. What can add to the skeleton is a `.nif` in `animations/<skeleton name>/` whose node is
marked with an `NiStringExtraData` reading `BONE` (`nifloader.cpp`, `Animation::injectCustomBones`):
that node is copied onto the skeleton under the node its parent is named after. The katar animation
`.nif` files are not marked, so they add nothing; `h2h_weapon_bone_l.nif` is, and is the only one
per folder that may be - every marked copy is grafted.

Its placement is a conjugation, not a reflection. Morrowind's rig does not give the two hands the
same local frame, and it does not give them mirrored ones either: for any bone whose parent is also
half of a mirrored pair, the two sides are related by `local_left = S · local_right · S` with `S` a
diagonal sign matrix. Every vanilla skeleton uses `diag(1, 1, -1)`, a flip of the bone's local Z.

The bone is that mirror and nothing more, so any weapon modelled the vanilla way, blade up its
+Y, hangs from it the right way up. The katar needs a half turn about its blade on top, or the face
that should point away from the body points across it - and that turn is the katar's, so it lives in
the katar's animations (`mirror_weapon_track.py` adds it to the track), not in the bone. In the
Blender file the same mirror flips a different axis on the weapon's side, `diag(1, -1, 1)`, because
io_scene_mw corrects the axes of `Bip01` bones and of every other bone differently;
`add_weapon_bone_l.py` works that out from the importer's own matrices.

`Sources/Tools/mirror_bone.py` holds that rule, and fits `S` from each rig's own left/right bone
pairs rather than assuming it - `diag(1, 1, -1)` wins by 5x on the posed first-person skeleton, 13x
to 58x on the others and 368x in the Blender source. Both the skeleton patcher and the keyframe
mirroring go through it, because a rest pose and a track that disagree are worse than either being
wrong alone.


## Credits

- Meshes, animations and scripts: Max Yari
- Textures: Bethesda (Morrowind, Tribunal); the venom's are recoloured from their poison effects
- NIF library: [Greatness7](https://github.com/Greatness7/io_scene_mw)
- ["Rose"](https://skfb.ly/oWDnS) by Lisa3Dart - Hespera_3d is licensed under
  [Creative Commons Attribution](http://creativecommons.org/licenses/by/4.0/).

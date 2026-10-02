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

- **Damage:** katars 80% of that shortsword, knuckledusters 50%, rounded to the nearest (never
  below 1) - and the same whichever way you swing, as a fist's is: one range for chop, slash and
  thrust alike, the shortsword's best attack (the one the game picks with "always use best attack").
  Two materials don't use their own vanilla shortsword, which sits out of line with the rest of the
  material there. **Silver** is steel's with the top 30% higher and the bottom 1 lower, as vanilla's
  silver spear is over its steel one. **Daedric** is ebony's with the top 20% higher, as daedric
  weapons run over ebony ones across vanilla (the daedric shortsword alone comes out below ebony's).
- **Weight:** the same share of that shortsword's as the damage - katars 80%, knuckledusters 50%.
- **Fatigue damage:** katars 50% of a bare-fisted hit, knuckledusters 75%.
- **Engine weapon type:** katars Short Blade, knuckledusters Blunt Weapon. Both one handed.
- **Skill you actually use:** Hand to Hand, for both.

Thirteen weapons, in wood, iron, chitin, steel, silver, orcish, ebony and daedric. Their stats are
derived from the vanilla shortswords rather than picked by hand - see `Sources/Tools/make_plugin.py`,
which is what writes `Katar.omwaddon`.

**Weight** goes with damage: the same share of the shortsword - a katar 80% of its weight, a
knuckleduster half. It is also what a swing costs you: the engine charges the attacker
`fFatigueAttackBase (2.0) + weight × swing strength × fWeaponFatigueMult (0.25)`, and bare fists pay
only the flat 2.0, having no weapon at all. At the iron/steel tier that puts a full-strength swing
80% over a fist's cost with a katar and 50% with a knuckleduster (a steel dagger is 38%, a steel
shortsword 100%).

**Capacity** is a different question - how much weapon there is to enchant. It runs from the **dagger**
of the same material to its shortsword, which in vanilla holds about twice as much: a knuckleduster
holds what the dagger does, a katar halfway between the two. The dagger's is vanilla's own where there
is one; orcish and ebony have none, and theirs is worked out as Bethesda wrote every line - a fixed
multiple of the weight (daggers run at 6.67 points per unit, shortswords at 5.0, right across iron
through daedric), on a dagger weighing 0.375 of its shortsword. The game shows a tenth of the raw
number and drops what is left over (`Enchanting::getMaxEnchantValue`), so the result is rounded to
whole points, halves up, and nothing is lost: the silver katar's 2.6 holds 3, the silver knuckles' 1.6
holds 2.

### Shop-enchanted versions

Seven of the weapons also come weakly enchanted, the way vanilla's Flameblades and Sparkmaces are -
plain weapons with a little magic that casts on strike, dealt from the same lists vanilla deals those
from. Each enchantment is the weaker of two: the vanilla enchanted weapon of that material and element,
and the most that fits three quarters of a point under the weapon's own capacity - so one bought is
always a little weaker than one enchanted by hand (the enchanting menu takes anything that rounds
down to the capacity). Where the vanilla one is the weaker, its own record is used, so a mod that
rebalances it rebalances these too. Daedric has none, as vanilla has no weak daedric ones.

| Weapon | Enchanted version | On strike | Enchantment |
| --- | --- | --- | --- |
| Chitin Knuckles | Chitin Shardfang | Frost 1-3 | `h2h_chitin_shard_en` - the least anything costs, 1 point |
| Iron Knuckles | Iron Sparkfist | Shock 1-4 | vanilla's `spark_enu` (Iron Sparkmace) |
| Steel Katar | Smouldering Katar | Fire 3-7 | vanilla's `cruel flame_en` (Steel Flameblade) |
| Silver Katar | Silver Ice Talon | Frost 3-7 | vanilla's `dire shard_en` (Silver Shardblade) |
| Silver Knuckles | Silver Shardknuckle | Frost 3-6 | `h2h_silver_shard_en` |
| Orcish Knuckles | Orcish Smoulderfist | Fire 1-20 | vanilla's `wild flame_en` (Wild Flameblade) |
| Ebony Katar | Ebony Sparkneedle | Shock 1-20 | vanilla's `wild spark_en` (Wild Sparkblade) |

In every other stat each is its plain weapon. The price is the plain one's plus what vanilla adds for
that enchantment over the same weapon without it - Iron Mace 24 to Iron Sparkmace 45, Silver
Shortsword 80 to Silver Shardblade 120, and so on - which comes to 10, 31, 47, 104, 80, 500 and 8100.

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
track or it sits wherever the skeleton's rest pose left it. This mod's own animations carry it, in
first person and third. Any animation that does not - anything from another animation mod - leaves
the off-hand weapon at rest, which reads as it sitting low or loose in the hand, and for a katar with
a decorated face, as that face turned in.
`Sources/Tools/mirror_weapon_track.py` adds the track to a `.kf`, and can be pointed at any animation
folder:

```
python3 Sources/Tools/mirror_weapon_track.py <animation folder>
```

### The draw sound

Drawing a short blade or a blunt weapon plays a sound. Bare hands do not, and neither do these.

### NPCs

NPCs carry these as they carry any weapon - bought, looted, from the levelled lists - and choose and
swing them by the skill the engine gives them: Short Blade for a katar, Blunt Weapon for
knuckledusters. There is no Hand to Hand swap for them and no experience to split, but everything
that shows is the same as yours: the second weapon in the off hand, the katar moveset, the silent
draw, the bruising on whoever they hit, and Ebony Rose's burst. They never channel a spell into Mage
Fury, and its strikes cost them nothing.

In third person - an NPC, or you with the camera pulled back - the moveset is the first-person one
with vanilla's third-person hand-to-hand legs under it (see *Building from source*): the arms keep
their first-person guard, fists up, the head keeps looking ahead through every swing, and the hips,
legs and footwork are the game's own. Walking, running and sneaking, only the upper body is ours:
the legs are the one-handed walk's, so the pace and the footsteps are exactly what they are with any
one-handed weapon. It plays for male, female and beast bodies, beasts with their own legs.

### Creatures

A creature that is two-legged and fights with weapons - dremora, golden saints, liches, skeletons -
uses these as an NPC does, and several already carry them: the plugin puts katars and knuckledusters
on the levelled lists they draw from (dremora's excellent melee weapons, skeletons' silver and iron
ones). The engine gives such a creature everything an NPC has here: an inventory it equips from, the
NPC animations - `xbase_anim` and its animation folder, so the katar moveset too - and the bones
grafted from that folder, `Weapon Bone.L` among them (`CreatureAnimation`, `Animation::setObjectRoot`).
So `animations.lua` and `npc.lua` run on them as on an NPC. The moveset also needs ReAnimation's API on
them, which a ReAnimation newer than 3.2 attaches to such creatures; with an older one they swing
these with the one-handed animations. A creature has one Combat value for every combat skill, so its
hit chance needs nothing, and its bruising is worked out from that Combat
(`formulas.handToHandFatigue`). Any other creature is let go at once: see *Performance*.

## The uniques

Three: Ebony Rose, Mage Fury, and the Driftwood Beater (`knuckle_wood`), wooden knuckles - which hit for two points less than the iron set at each end (2-4) but take an
enchantment better than any knuckleduster short of orcish and daedric (3), since it is the medium, not the metal,
that holds one. None of
the three is in any levelled list: nobody sells them and no chest rolls them. They are placed in the
world by `KatarWorldPlacements.omwaddon`, which is made by hand in OpenMW-CS - unlike `Katar.omwaddon`,
it is not generated, so edit it there. Ebony Rose also has an owner, below.

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
- **Its owner** is Dandras Vules, the Dark Brotherhood's master in Mournhold (Tribunal). He is handed
  it the first time he comes into the world, by script rather than by editing his record, and fights
  with it - bursts and all. The combat AI picks its weapon before every swing, by damage and by what
  the enchantment casts on a strike (`weaponpriority.cpp`), and his own Adamantium Jinkblade of
  Wounds - Paralyze and 10 points of Poison on every strike - would win that easily. An enchantment
  without the charge for one more cast is not counted, so each time he comes into the world while he
  has the Rose, the Jinkblade is left without charge: it takes a quarter of an hour to recharge that
  far, and until then he fights with the Rose. It is still on him, and recharges as any enchanted
  weapon does once taken.

**Mage Fury** (`knuckle_mage_fury`) - iron knuckledusters with a crystal set in them, hitting for a
point less than the iron set at each end (3-5).

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

Two more run on every NPC and creature, for those who wield these. On a creature that cannot hold them
(`weapons.canWield`: anything but a two-legged one that fights with weapons) both return in their
first lines, before loading anything, and leave no handler behind - ReAnimation's API does the same -
so a rat costs nothing. `npc.lua` has no per-frame handler either: it hangs off the actor's own
animation events, and looks at the hand twice a second only while a one-handed weapon is out.
`animations.lua` registers the moveset with ReAnimation, whose own per-frame check only runs while
the actor has a weapon drawn.

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

The walk, run and sneak are kept in step with what they play over by how far through its loop each
one is. Katars move over ReAnimation's short blade set, one step cycle to the loop like the fist's.
Knuckledusters have no blunt set and move over the one-handed one, which in first person is laid out
differently: the walk and run an 8-frame lead-in and then three step cycles to the loop, the sneak
two cycles. One cycle cannot follow that, and drifted off the footsteps. So there, and only in first
person, they play the fist's cycles laid out the same way (`xKatar1hMovement.kf` and
`xKatar1hSneakMovement.kf`, `walkforwardkatar1h`, `sneakforwardkatar1h` and so on). The walk's text
keys are the one-handed walk's to the frame; the sneak's cycle is stretched to 34 frames, which puts
both its loops within 2% of the one-handed sneak's and every footstep within about a frame of theirs
- ReAnimation's moveset builder scales the directions by fixed factors, and the one-handed sneak was
not built with them. Third person plays the plain ones: every one-handed loop there is one cycle too.

In third person they play on the upper body only, over the one-handed walk's legs, hips and spine.
The engine moves an actor by the root of whatever animation plays its lower body, so ours - the
fist's legs, on a loop of another length - walked it slower than the footsteps it heard.

A loop of the same steps can still be longer or shorter than the one it plays over - the katar walk
is 21% longer than the third-person one-handed walk, and a few percent off the short blade walk and
the one-handed sneak - so it plays at the ratio of the two lengths, read from their start and stop
keys, and keeps up rather than trailing behind, arms in time with the legs. Past a third longer or
shorter the two are not the same steps, and it plays at the parent's speed.

None of them sound their own footsteps. The animation underneath still plays and sounds its own, and
the engine sounds a `SoundGen` key from any animation that has one - as do the Lua mods listening
for them - so the fist's footsteps in ours sounded every step twice. They are kept as `SoundGenRef`
keys, which nothing listens for: a record of where our steps fall, which the third-person build
matches its legs by.

The third-person set is the same animations under the same names, with vanilla's hand-to-hand legs
merged in (`Sources/Tools/make_third_person_anims.py`), in the folders of the third-person skeletons:
`Animations/xbase_anim` for everyone, and `Animations/xbase_animkna` over it for beasts, with their
own legs. So one set of registrations covers both views and every NPC - whichever the engine has
loaded is what plays.

**Sneaking idle.** ReAnimation's own first-person sneak idles (`idle1hsneak`, `idle1ssneak`) play
over the same one-handed idle as ours whenever the player sneaks, unranked, so nothing stops them;
the engine shows whichever has the higher priority on each bone group, and on a tie the one whose
name sorts first - theirs. In first person the katar's sneak idle is set one above them on every
bone group.

**One-handed attacks.** The katar moveset and ReAnimation's own one-handed set both live on the
`weapononehand` animation group, and only one may be active at a time. This mod's set is registered
with `overridePriority = 1`, one above ReAnimation's, so ReAnimation's stands down while a katar or
knuckleduster is in hand. Any other mod adding a moveset to that group does the same.

**Loot and merchants.** The weapons are added to vanilla's own levelled lists, each wherever the
vanilla weapon it stands in for is - its material's shortsword - at the same level: the
`random_<material>_weapon` lists, and the `l_n_wpn_melee_*` ones NPCs' own weapons come from.
Merchants sell what they carry and what is in the chests they own in their shop (`getContainersOwnedBy`),
and most weapon merchants' stock comes from such chests rolling the `random_*` lists; so does loot.
Knuckledusters go on the blunt list where their stand-in is on the short blade one. Vanilla has no
orcish shortsword, so the orcish knuckles follow the dwarven one, and the orcish warhammer into
`random_orcish_weapons` too. The shop-enchanted versions go where vanilla deals its own weak enchanted
weapons - `l_m_wpn_melee_short blade`, `l_m_wpn_melee_blunt` and `random_loot_special` - each only where
its material is already on offer at least twice, at the middle of those weapons' levels
(`ENCHANTED_LEVELLED` in `make_plugin.py`). The uniques and the bound weapons are in no list.

A shop is stocked once: the engine rolls a merchant's levelled entries when they first come into the
world, and a chest's when it is first opened, and from then on restocks what it rolled. Shops met
before the mod was installed keep what they had.

A plugin can only replace a levelled list, not add to it, so a mod loaded later that edits one of the
same lists wins it; with such a mod, run a merged-lists tool
([DeltaPlugin](https://gitlab.com/bmwinger/delta-plugin), OMWLLF) as you would for any mod that adds
loot. Tamriel Data, Tamriel Rebuilt and OAAB leave these lists alone.

**Tamriel Rebuilt** deals its weapons from Tamriel Data's lists, and `KatarTamrielRebuilt.omwaddon`
extends those the same way: the `t_mw` ones, which are Morrowind's - the rest are other provinces'
- leaving out guards', Dwemer centurions' and Dwemer ruins' lists, and two-handed ones
(`make_tr_plugin.py`). Tamriel Data has an orcish shortsword of its own, and the orcish knuckles
follow it too. It needs Tamriel Data and `Katar.omwaddon` as masters, and goes after both.

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
- `Sources/Tools/make_third_person_anims.py` - makes the third-person moveset from the first-person
  one, with ReAnimation's FBA merge (`Sources/Tools/FBACompat/fba_merge.py` in its repository, found
  beside this mod): our upper body over the legs, hips and root motion of vanilla's third-person
  hand-to-hand, their time warped through the text keys both share so ours are kept exactly - the
  attack timings are ours - and footsteps matched to footsteps. No chest lean, the whole hip lunge.
  Morrowind's skeletons hang the thighs (and a beast's tail) off `Bip01 Spine`, so when the merge
  turns the spine to keep our upper body upright, they are turned back. The walk, run and sneak are
  different: in game they play from the chest up only, over the one-handed walk's legs and spine, so
  their chest (`Bip01 Spine1`, where the engine's upper body starts) is keyed to sit on the vanilla
  one-handed walk's spine as it is on average, taking that walk's sway and lean with it. The upper body's bone offsets are moved from the first-person skeleton's to the third-person
  one's. Through every swing and draw the head keeps looking ahead as it does in the idle: in first
  person the head turns into a punch with the rest of the upper body, up to 95 degrees, which the
  camera never shows. The engine's head tracking still turns it toward whoever an NPC fights. Reads
  the vanilla animations out of Morrowind.bsa. Re-run it after every export of the
  first-person set. There are no katar turns: in third person `animations.lua` narrows the one-handed
  turn to the lower body while a katar or knuckleduster is in hand, and the katar idle, which the
  engine keeps playing through a turn, shows above it.
- `Sources/Tools/patch_skeleton.py` - adds `Weapon Bone.L`: `--bones-out Animations` writes the
  grafted-bone files, `-o meshes` the patched skeleton copies.
- `Sources/Tools/mirror_weapon_track.py` - gives `Weapon Bone.L` the mirrored keyframe track of
  `Weapon Bone` in a `.kf`. Run it over the animations after every export.
- `Sources/Tools/mirror_bone.py` - the one definition of how this rig mirrors, shared by both of
  the above. Run it directly to self-test the quaternion maths.
- `Sources/Tools/make_test_crate.py` - writes `Katars_FOR_TESTING_ONLY_Crate_With_All_Items.omwaddon`:
  a crate with one of every item this mod adds, by the stump with the axe in it near the Seyda Neen
  lighthouse. For testing only, left out of the release. Re-run it after adding an item.
- `Sources/Tools/make_plugin.py` - writes `Katar.omwaddon` from the vanilla shortsword table, with
  vanilla stand-ins for the uniques' enchantments. The real ones use custom magic effects, which an
  ESM file cannot name, so `scripts/MaxYari/H2HWeapons/content.lua` replaces them when the game starts.
- `Sources/Tools/make_tr_plugin.py` - writes `KatarTamrielRebuilt.omwaddon`, Tamriel Data's lists
  extended as `make_plugin.py` extends vanilla's. Re-run it after `make_plugin.py`.

  ```
  python3 Sources/Tools/make_tr_plugin.py --master "<Data Files>/Morrowind.esm" \
      --tamriel-data "<path>/Tamriel_Data.esm"
  ```
- `Sources/Tools/venom_fx.py` - builds the venom's violet hit and area effects, textures and icon
  from the vanilla poison ones in Morrowind.bsa.
- `Sources/Tools/charge_fx.py` - makes a weapon's crystal translucent, and builds the glow that
  shows inside it while it is charged (`<mesh>_charged.nif`).
- `Sources/Tools/add_weapon_bone_l.py` - builds the ARP controller for that bone in the Blender file.
- `Sources/Tools/import_h2h_actions.py` - brings ReAnimation's hand-to-hand `[Raw]` actions into the
  Blender file as the katar's, the Blender side of `import_h2h_set.py`: renamed actions and text
  keys, the weapon bone seated, and `Weapon Bone.L` keyed at the mirrored seat with the katar's turn.
- `Sources/Tools/footstep_refs.py` - renames `SoundGen` keys to `SoundGenRef` in the `.kf` files it
  is given, or back. `import_h2h_set.py`, `make_katar_1h_movement.py` and
  `make_third_person_anims.py` all run it on what they write; safe to run twice.
- `Sources/Tools/make_katar_1h_movement.py` - lays `[Raw] Katar Walk` and `[Raw] Katar Sneak` out as
  the first-person one-handed walk and sneak are, as `[Raw] Katar Walk 1h` and `[Raw] Katar Sneak 1h`,
  and with `--export` runs ReAnimation's own `build_and_export_moveset.py` (from its
  `Sources/Reanimv3.blend`) on them - bake, moveset builder, export - then mirrors `Weapon Bone.L` in
  and checks the loops against ReAnimation's `x1hMovement.kf` and `x1hSneakMovement.kf`. Re-run it
  after changing the katar walk or sneak. First person only: the third-person build leaves the files
  out.

  ```
  blender -b "Reanimv  starts Katsr.blend" --python Sources/Tools/make_katar_1h_movement.py -- \
      --save --export Animations/xbase_anim.1st
  ```
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

# ⚔ Katars and Knuckles

![Katars & Knuckles](imgs/banner.png)

Hand-to-hand weapons for OpenMW. Katars and Knuckledusters. They mostly use a **Hand to Hand** skill but also receive a small bonus from blunt/blade skill. Same goes for skill leveling.

**13 weapons**: 5 katars and 8 sets of knuckledusters, in wood, chitin, iron, steel, silver, orcish,
ebony and daedric. **3 of them are rare**, with a trick of their own each - finding them and working
out what they do is up to you. The rest turn up the way ordinary weapons do: in merchants' stock, on
NPCs and in chests.

For conjurers there is **Bound Fist**, a new conjuration spell that binds a daedric hand-to-hand
weapon to your fists. Which weapon you get depends on your Conjuration - there are visually different
ones to reach as your skill grows. A few spell merchants teach it.

Developed for OpenMW. **Requires OpenMW 0.51+**.

<p><a href="https://ko-fi.com/maxyari"><img src="imgs/morrowind_kofi_banner_left_half_bright124.gif" width="25.72%" align="top" alt="Support me on Ko-fi"></a><a href="https://ko-fi.com/maxyari"><img src="imgs/banner_right.png" width="73.88%" align="top" alt="Support me on Ko-fi"></a><br><a href="https://ko-fi.com/maxyari"><img src="imgs/banner_glow.png" width="99.6%" align="top" alt=""></a></p>

## ⚔ What they do

- "Officially" Katars are shortblades and knuckledusters are blunt weapons, that what you will see on a tooltip in the world. Dont trust that - they use and level Hand to Hand and they also damage victim's stamina akin to regular H2H.
- Yet countrary to regular H2H they also deal damage, albeit small. In general knuckleduster deal lower physical damage but higher stamina damage and Katars are the opposite.
- Most of the new weapons are available at your weapon traders as well as random loot. Uniques are... well... unique and need to be found in the world.
- Conjured fist weapons change their looks based on your conjuration skill.

If you want to know more details and know what to expect, look under the spoilers below, otherwise just play the game :)

<details>
<summary>How all the weapons look like</summary>

![All the weapons](imgs/all_katars.png)

</details>

<details>
<summary>Where to find uniques (only light spoilers with vague tips)</summary>

- The lesser of uniques (barely a unique) is made of driftwood by someone with a lot of time on their hands to watch ships in the sea.

- The middle of the uniqes is of an arcane origin and as such is drawn to places of high magic. It also rather fancies inland lakes.

- The highest of the three is of a dark and vicious nature, its kiss is poison and its owner schemes deep undergound. 

<details>
<summary>Concrete locations: (full spoilers)</summary>

 Aaaaaaah, you sneaky bastard, I didn't fill this in yet. Go play the game, cmon.

</details>

</details>

## ⚔ Recommended mods

- [The Combat Juice](https://github.com/MaxYari/TheCombatJuiceOpenMW), also by me - a layer of
  subtle "oomph" all over the combat, visual and audible, without touching any mechanics - every
  punch feels like it lands.
- [Inventory Extender](https://www.nexusmods.com/morrowind/mods/59205) - shows the Hand to Hand type
  and the fatigue damage in weapon tooltips.


## ⚔ How to install

**Requires OpenMW 0.51+**

1) Install the dependencies: [ReAnimation](https://www.nexusmods.com/morrowind/mods/52596) (3.2 or
newer) and [Max Yari's Script Services (MSS)](https://www.nexusmods.com/morrowind/mods/60256).

2) Install this mod **with a mod organiser**: download the archive and drag and drop it into your mod
organiser of choice (e.g [Mod Organizer 2](https://github.com/ModOrganizer2/modorganizer/releases)
on Windows or [Nerevarine Organizer](https://github.com/grazelandsnomad/nerevarine_organizer/releases/tag/v0.70)
on Linux).
**Or**: [read this tutorial](https://modding-openmw.com/tips/installing-mods/) on how to install mods
using the launcher or completely manually (it's also very easy).

3) Enable these in the "Content Files" tab of the OpenMW launcher, after ReAnimation:
   - `Katar.omwaddon`
   - `KatarWorldPlacements.omwaddon` - puts the rare weapons in the world. Needs Tribunal.
   - `H2HWeapons.omwscripts`
   - `H2HWeapons_SpellTraders.omwscripts` - optional, it is what lets spell merchants teach Bound Fist.

4) OpenMW Launcher -> Settings -> Visuals -> Animations: "Use Additional Animation Sources" must be
enabled.

5) The weapons are added to the game's loot and merchant lists. If you use other mods that add to
those lists too, merge your lists once your load order is set, as you would for any such mods:
   - Windows: [TES3Merge](https://github.com/NullCascade/TES3Merge) or
     [DeltaPlugin](https://gitlab.com/bmwinger/delta-plugin)
   - Linux: [DeltaPlugin](https://gitlab.com/bmwinger/delta-plugin)

6) If you have the launcher's "Strength influences hand to hand" option on (Settings -> Gameplay),
set the mod's copy of it to match: Options -> Scripts -> Katars and Knuckledusters. The rest of the
mod's settings are there too.

Optional:
- [Unofficial Tamriel Rebuilt Spells](https://www.nexusmods.com/morrowind/mods/58693) - Bound Fist
  then grows stronger with your Conjuration, following that mod's bound item settings (turn on its
  "Scale bound items").
- **PBR**: the weapons come with PBR maps (normal and specular), so metal and crystal catch the light
  properly under [Wareya's PBR shaders](https://github.com/wareya/OpenMW-PBR/tree/0.51) - a small
  replacement for OpenMW's own lighting shaders. Recommended together with
  [Aesthetically Shiny Things](https://www.nexusmods.com/morrowind/mods/52114), which gives the rest
  of the game the same treatment. None of it is required: without them the weapons look fine with
  OpenMW's default shaders.

Have fun!

## ⚔ Mod compatibility

- **Skeleton and body replacers**: compatible - no skeleton is replaced.
- **Tamriel Rebuilt**: its spell merchants teach Bound Fist too.
- **[Oblivion-Style Spell Casting](https://www.nexusmods.com/morrowind/mods/58653)**: supported.
- **Retextures**: vanilla textures are used as they are, so retexture packs carry over.
- **Other animation mods**: fine, unless they also replace ReAnimation's one-handed attacks while a
  katar or knuckleduster is in hand.

## ⚔ Credits

- Meshes, animations and scripts: Max Yari
- Textures: Bethesda (Morrowind, Tribunal)
- NIF library: [Greatness7](https://github.com/Greatness7/io_scene_mw)
- ["Rose"](https://skfb.ly/oWDnS) by Lisa3Dart - Hespera_3d is licensed under
  [Creative Commons Attribution](http://creativecommons.org/licenses/by/4.0/).

## ⚔ For modders

The mod exposes a small interface, `I.H2HWeapons`, for asking what kind of hand-to-hand weapon an item
is. How everything works - and how to build the plugin, meshes and animations from source - is written
up in the [technical notes](Sources/DEVELOPMENT.md) in the git repository.

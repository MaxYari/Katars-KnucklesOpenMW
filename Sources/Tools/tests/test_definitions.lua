-- Hybrid weapon definitions from other mods: any melee weapon type, any two skills, the three scalings,
-- YAML and JSON, and what is refused - and the swing sounds a definition gives Combat Sounds Overhaul.
package.path = arg[0]:gsub("[^/]*$", "") .. "?.lua;" .. package.path
local stubs = require("stubs")
local K, R = stubs.findMods()
stubs.addRoot(R); stubs.addRoot(K)

local st = stubs.state
local fails, checks = 0, 0
local function check(ok, msg, extra)
    checks = checks + 1
    if not ok then fails = fails + 1; print("FAIL: " .. msg .. (extra and ("  [" .. tostring(extra) .. "]") or "")) end
end

-- Another mod's weapons, with their definitions. The folder is listed once, on first use, so they are
-- all in place before anything asks.
st.vfsText = {
    -- A blunt weapon that hits with the fists' skill and the caster's: as good as the weaker of the two.
    ["hybridweapondefinitions/mace_of_fire.yaml"] = [[
# a comment, as a modder would leave one
primarySkill: Hand to Hand          # names, in any case and spelling
secondarySkill: destruction
primaryExperience: 70%
secondaryExperience: 0.5
scaling: lowest skill
moveset: default
]],
    -- In a subfolder, and in JSON: a spear as good as the better of its two.
    ["hybridweapondefinitions/somemod/spear_of_will.json"] = [[
{ "primarySkill": "conjuration", "secondarySkill": "spear", "primaryExperience": 0.6,
  "secondaryExperience": 0.4, "scaling": "highestSkill",
  "tooltip": "Conjured edge: %{primarySkill} %{primary}, %{secondarySkill} %{secondary}, best %{highest}, %{primaryExperience}" }
]],
    -- The hand-to-hand moveset and an off-hand copy on a two-handed weapon: it keeps the default
    -- moveset, and gets no copy.
    ["hybridweapondefinitions/great_fists.yaml"] = [[
primarySkill: handtohand
secondarySkill: bluntweapon
moveset: handToHand
offHandCopy: true
scaling: sideways
]],
    -- Fists' animations, both hands, no copy in the left one.
    ["hybridweapondefinitions/fist_mace.yaml"] = [[
primarySkill: handtohand
secondarySkill: bluntweapon
moveset: handToHand
twoHanded: true
]],
    -- A copy in the left hand, with the file forgetting that it takes that hand.
    ["hybridweapondefinitions/copy_only.yaml"] = [[
primarySkill: handtohand
secondarySkill: shortblade
offHandCopy: true
]],
    -- Ranged weapons cannot be hybrids.
    ["hybridweapondefinitions/hybrid_bow.yaml"] = "primarySkill: marksman\nsecondarySkill: illusion\n",
    -- Nor can a file that names no skill, or one that is not YAML at all.
    ["hybridweapondefinitions/no_skill.yaml"] = "primarySkill: swordplay\nsecondarySkill: spear\n",
    ["hybridweapondefinitions/broken.yaml"] = "primarySkill: [handtohand\n",
    -- Swing sounds CSO does not have are left out.
    ["hybridweapondefinitions/odd_whoosh.yaml"] = [[
primarySkill: handtohand
secondarySkill: axe
swingSounds:
  - sound: Kazoo
    volume: 1
  - sound: own
]],
    ["hybridweapondefinitions/fist_blade.yaml"] = [[
primarySkill: handtohand
secondarySkill: shortblade
swingSounds:
  - sound: HandToHand
  - sound: ShortBlade
    volume: 0.5
]],
    -- And a definition for a weapon nothing loaded has.
    ["hybridweapondefinitions/missing_weapon.yaml"] = "primarySkill: handtohand\nsecondarySkill: axe\n",
}
st.weaponRecords["mace_of_fire"] = { type = 3, model = "meshes/w/mace_fire.nif" }
st.weaponRecords["spear_of_will"] = { type = 6, model = "meshes/w/spear_will.nif" }
st.weaponRecords["great_fists"] = { type = 4, model = "meshes/w/great_fists.nif" }
st.weaponRecords["hybrid_bow"] = { type = 9, model = "meshes/w/bow.nif" }
st.weaponRecords["no_skill"] = { type = 0, model = "meshes/w/x.nif" }
st.weaponRecords["broken"] = { type = 0, model = "meshes/w/y.nif" }
st.weaponRecords["odd_whoosh"] = { type = 7, model = "meshes/w/axe.nif" }
st.weaponRecords["fist_blade"] = { type = 0, model = "meshes/w/fist_blade.nif" }
st.weaponRecords["fist_mace"] = { type = 3, model = "meshes/w/fist_mace.nif" }
st.weaponRecords["copy_only"] = { type = 0, model = "meshes/w/copy_only.nif" }
st.weaponRecords["katar_steel"] = { type = 0, model = "meshes/steel_katar.nif" }
st.weaponRecords["knuckle_iron"] = { type = 3, model = "meshes/iron_knuckle.nif" }
st.skills = {
    handtohand = { base = 50, modifier = 0, damage = 0 },
    destruction = { base = 30, modifier = 0, damage = 0 },
    bluntweapon = { base = 10, modifier = 0, damage = 0 },
    conjuration = { base = 60, modifier = 0, damage = 0 },
    spear = { base = 25, modifier = 0, damage = 0 },
}

--- reading the files ------------------------------------------------------------------------------------
local definitions = require("scripts.MaxYari.H2HWeapons.scripts.definitions")
local def, problems = definitions.parse({ primarySkill = "Short Blade", secondarySkill = "HAND-TO-HAND" })
check(def and def.primarySkill == "shortblade" and def.secondarySkill == "handtohand",
      "skill names are read in any case and spelling")
check(def and def.primaryExperience == 0.7 and def.secondaryExperience == 0.3 and def.scaling == "minorSecondaryBonus"
      and def.moveset == "default" and def.fatigueDamage == 0 and def.silentDraw == false and def.swingSounds == nil
      and def.twoHanded == false and def.offHandCopy == false,
      "and everything left out has its default")
check(#problems == 0, "with nothing to say about it", problems[1])
def, problems = definitions.parse({ primarySkill = "spear", secondarySkill = "Spear" })
check(def == nil and problems[1]:find("same skill"), "the same skill twice is refused", problems[1])
def, problems = definitions.parse({ primarySkill = "spear" })
check(def == nil and problems[1]:find("secondarySkill"), "and so is a missing secondary skill", problems[1])
def, problems = definitions.parse({ primarySkill = "spear", secondarySkill = "axe", primaryExperience = -1,
                                    moveset = "kungfu", silentDraw = "yes", twoHanded = "both" })
check(def and def.primaryExperience == 0.7 and def.moveset == "default" and def.silentDraw == false
      and def.twoHanded == false, "a bad optional field keeps its default")
check(#problems == 4, "and is said", #problems)

--- what the weapons are ---------------------------------------------------------------------------------
local weapons = require("scripts.MaxYari.H2HWeapons.scripts.weapons")
local mace = weapons.hybridOfId("mace_of_fire")
check(mace and mace.primarySkill == "handtohand" and mace.secondarySkill == "destruction", "a blunt weapon on two other skills")
check(mace and mace.weaponSkill == "bluntweapon", "which the engine still swings as a blunt weapon")
check(mace and mace.primaryExperience == 0.7 and mace.secondaryExperience == 0.5, "70% read as 0.7")
check(mace and mace.scaling == "lowestSkill" and not mace.handToHand, "the lowest of the two, with its own animations")
check(mace and not mace.twoHanded and not mace.offHandCopy, "one-handed, with nothing in the left hand")
local spear = weapons.hybridOfId("spear_of_will")
check(spear and spear.scaling == "highestSkill" and spear.weaponSkill == "spear", "a JSON file in a subfolder")
local great = weapons.hybridOfId("great_fists")
check(great and great.moveset == "default" and not great.handToHand, "a two-handed weapon cannot swing as fists")
check(great and great.twoHanded and not great.offHandCopy, "nor hold a copy, and takes both hands as its type does")
local fistMace = weapons.hybridOfId("fist_mace")
check(fistMace and fistMace.handToHand and fistMace.twoHanded and not fistMace.offHandCopy,
      "fists' animations, both hands, no copy")
local copyOnly = weapons.hybridOfId("copy_only")
check(copyOnly and copyOnly.offHandCopy and copyOnly.twoHanded and not copyOnly.handToHand,
      "a copy in the left hand makes it two-handed")
check(great and great.scaling == "minorSecondaryBonus", "and a scaling there is none of is the default one")
check(weapons.hybridOfId("hybrid_bow") == false, "a bow cannot be a hybrid")
check(weapons.hybridOfId("no_skill") == false, "nor a weapon whose file names no skill")
check(weapons.hybridOfId("broken") == false, "nor one whose file cannot be read")

-- What the global script says about them, once.
local printed = {}
local realPrint = print
print = function(line) printed[#printed + 1] = line end
weapons.report()
print = realPrint
local log = table.concat(printed, "\n")
local function logged(text) return log:find(text, 1, true) ~= nil end
check(logged("hybrid_bow.yaml: the weapon is not a melee weapon"), "the log says the bow is not melee", log)
check(logged("no_skill.yaml: primarySkill 'swordplay' is not a skill"), "names the skill that is not one")
check(logged("broken.yaml: could not be read"), "and the file that could not be read")
check(logged("great_fists.yaml: the handToHand moveset needs a one-handed weapon"), "and the moveset it could not use")
check(logged("great_fists.yaml: scaling 'sideways'"), "and the scaling there is none of")
check(logged("great_fists.yaml: offHandCopy needs a one-handed weapon"), "and the copy it could not have")
check(logged("copy_only.yaml: offHandCopy needs twoHanded: true"), "and the copy that needed the left hand")
check(logged("missing_weapon") and logged("left unused"), "and lists definitions with no weapon loaded")
check(logged("hybrid weapons defined"), "and how many there are")
check(not logged("katar_steel.yaml"), "and nothing about the files this mod ships", log)

--- swinging them -----------------------------------------------------------------------------------------
local api = require("scripts.MaxYari.ReAnimation_v3.ReAnimationAPI")
stubs.I.ReAnimation = api.interface
stubs.enableInventoryExtender()
st.stance = 1
st.bones = { ["Weapon Bone"] = true, ["Weapon Bone.L"] = true }
st.equipped = { recordId = "mace_of_fire" }
local player = require("scripts.MaxYari.H2HWeapons.player")
local onUpdate = player.engineHandlers.onUpdate
for _ = 1, 4 do onUpdate(0.016) end

local function play(group, startKey)
    stubs.I.AnimationController.playBlendedAnimation(group,
        { startKey = startKey, startkey = startKey, stopKey = "x", stopkey = "x", speed = 1, priority = 7, blendMask = 15 })
end

check(st.vfxById["H2HWeapons_OffHand"] == nil, "a hybrid on its own moveset gets no off-hand copy")
play("weapononehand", "chop start")
-- hand-to-hand 50, destruction 30: the lower is 30; blunt weapon is 10, so a modifier of 20
check(st.skills.bluntweapon.modifier == 20, "the engine rolls the blunt weapon at the lower of the two",
      st.skills.bluntweapon.modifier)
play("weapononehand", "chop small follow start")
check(st.skills.bluntweapon.modifier == 0, "and it is put back after", st.skills.bluntweapon.modifier)

-- Experience: blunt weapon is neither of its skills, so it keeps nothing, and the two get their shares.
st.skillUses = {}
local hit = { useType = 0, skillGain = 1.0 }
for i = #stubs.skillUsedHandlers, 1, -1 do stubs.skillUsedHandlers[i]("bluntweapon", hit) end
check(hit.skillGain == 0, "the weapon's own skill keeps nothing", hit.skillGain)
local credited = {}
for _, use in ipairs(st.skillUses) do credited[use.skill] = use.options.scale end
check(credited.handtohand == 0.7 and credited.destruction == 0.5, "hand-to-hand gets 70%, destruction 50%")

-- No draw sound is silenced unless the definition says so.
st.stoppedSounds = {}
play("bluntonehand", "equip start")
onUpdate(0.016)
check(#st.stoppedSounds == 0, "its draw keeps its sound", #st.stoppedSounds)

-- Its left hand is its own: a shield stays in it.
local playerSelf = require('openmw.self')
local shield = stubs.object({ recordId = "iron_shield", isItem = true, parentContainer = playerSelf.object, count = 1 })
st.inventories[playerSelf] = { shield }
st.left = shield
onUpdate(0.016)
check(st.left == shield, "a hybrid that is not two-handed leaves the shield in the left hand")

-- Two-handed: the shield comes off while it is out, and no copy goes in its place unless asked for.
st.equipped = { recordId = "fist_mace" }
for _ = 1, 4 do onUpdate(0.016) end
check(st.left == nil, "a two-handed one takes the shield off")
check(st.vfxById["H2HWeapons_OffHand"] == nil, "and with no offHandCopy, shows no copy")
st.equipped = { recordId = "copy_only" }
onUpdate(0.016)
check(st.vfxById["H2HWeapons_OffHand"] and st.vfxById["H2HWeapons_OffHand"].model == "meshes/w/copy_only.nif",
      "offHandCopy shows the copy, whatever the moveset")

-- A spear, as good as the better of its skills, swung by its two-handed group.
st.equipped = { recordId = "spear_of_will" }
onUpdate(0.016)
play("weapontwowide", "thrust start")
-- conjuration 60, spear 25: 60, a modifier of 35
check(st.skills.spear.modifier == 35, "the engine rolls the spear at the higher of the two", st.skills.spear.modifier)
play("weapontwowide", "thrust large follow start")
check(st.skills.spear.modifier == 0, "and puts it back")
st.skillUses = {}
hit = { useType = 0, skillGain = 1.0 }
for i = #stubs.skillUsedHandlers, 1, -1 do stubs.skillUsedHandlers[i]("spear", hit) end
check(math.abs(hit.skillGain - 0.4) < 1e-9, "spear, its own secondary skill, keeps its 40%", hit.skillGain)
check(#st.skillUses == 1 and st.skillUses[1].skill == "conjuration" and st.skillUses[1].options.scale == 0.6,
      "and conjuration gets its 60%")

--- asking for their skill (hybrid:getEffectiveSkill) -------------------------------------------------
check(mace:getEffectiveSkill(playerSelf) == 30, "another mod reads the mace's skill: the lower of the two",
      mace:getEffectiveSkill(playerSelf))
check(spear:getEffectiveSkill() == 60, "and with no actor, this script's own: the higher of the spear's")
-- hand-to-hand 50, plus 15% of short blade 40
st.skills.shortblade = { base = 40, modifier = 0, damage = 0 }
local fistBlade = player.interface.getHybridDefForRecordId("fist_blade") -- as another mod gets it
check(fistBlade:getEffectiveSkill(playerSelf) == 56, "a minor secondary bonus", fistBlade:getEffectiveSkill(playerSelf))
st.equipped = { recordId = "fist_blade" }
onUpdate(0.016)
play("weapononehand", "chop start")
check(st.skills.shortblade.modifier == 16, "the swing puts 56 into short blade", st.skills.shortblade.modifier)
check(fistBlade:getEffectiveSkill(playerSelf) == 56, "and mid-swing, its skill does not count that in",
      fistBlade:getEffectiveSkill(playerSelf))
play("weapononehand", "chop small follow start")
check(st.skills.shortblade.modifier == 0 and fistBlade:getEffectiveSkill(playerSelf) == 56, "nor after it")
-- A creature has one number for every skill of a specialization: hand-to-hand is stealth, destruction magic,
-- conjuration magic, spear combat.
local dremora = stubs.object({ creature = { isBiped = true, canUseWeapons = true,
                                            combatSkill = 70, magicSkill = 20, stealthSkill = 40 } })
check(mace:getEffectiveSkill(dremora) == 20, "a creature's: the lower of its stealth and magic",
      mace:getEffectiveSkill(dremora))
check(spear:getEffectiveSkill(dremora) == 70, "the higher of its magic and combat", spear:getEffectiveSkill(dremora))

--- their tooltips --------------------------------------------------------------------------------------
local function fakeTooltip(typeText)
    local inner = stubs.content({
        { name = "type", props = { text = typeText } },
        { name = "thrust", props = { text = "Thrust: 6 - 11" } },
    }, true)
    return { content = stubs.content {
        { name = "padding", content = stubs.content { { name = "tooltip", content = inner } } },
    } }, inner
end
local modifier = stubs.tooltipModifiers["H2HWeapons"]
local layout, inner = fakeTooltip("Type: Blunt Weapon, One Handed")
modifier({ recordId = "mace_of_fire" }, layout)
check(inner.type.props.text == "Type: Hand-to-hand (Destruction), One Handed",
      "the type line names its two skills", inner.type.props.text)
check(inner.h2hFatigue == nil, "no fatigue line for a weapon that deals none")
local note = inner.h2hExplanation and inner.h2hExplanation.props.text or ""
check(note:find("lower of the two (30)", 1, true) and note:find("Destruction", 1, true),
      "with no tooltip of its own, the lowest skill's footnote, its number filled in", note)

layout, inner = fakeTooltip("Type: Blunt Weapon, One Handed")
modifier({ recordId = "fist_mace" }, layout)
check(inner.type.props.text == "Type: Hand-to-hand (Blunt Weapon), Two Handed",
      "a one-handed weapon made two-handed says so", inner.type.props.text)

layout, inner = fakeTooltip("Type: Spear, Two Handed")
modifier({ recordId = "spear_of_will" }, layout)
note = inner.h2hExplanation and inner.h2hExplanation.props.text or ""
check(note == "Conjured edge: Conjuration 60, Spear 25, best 60, 60%", "its own tooltip, every placeholder filled", note)
check(inner.type.props.text == "Type: Conjuration (Spear), Two Handed", "and its type line", inner.type.props.text)

--- swing sounds (Combat Sounds Overhaul Overhauled) --------------------------------------------------
local swings, playHandlers, groupHandlers = {}, {}, {}
stubs.I.CombatSoundsOO = {
    WEAPON = { HandToHand = "handToHand", ShortBlade = "shortBlade", Blunt = "blunt" },
    SWING_GROUPS = { sharpMetal = "sharpMetal", plain = "plain" },
    playSwing = function(weapon, volume, attackType)
        swings[#swings + 1] = { weapon = weapon, volume = volume, attackType = attackType }
    end,
    addOnPlayHandler = function(f) playHandlers[#playHandlers + 1] = f end,
    addSwingGroupsHandler = function(f) groupHandlers[#groupHandlers + 1] = f end,
}
-- A fist's whoosh is the engine's own swish, which CSO keeps: nothing here plays it again
local fistSwishes = {}
require("openmw.core").sound.playSound3d = function(id, object, options)
    fistSwishes[#fistSwishes + 1] = { id = id, volume = options.volume, pitch = options.pitch }
end
require("scripts.MaxYari.H2HWeapons.actor")
local onPlay, groupsOf = playHandlers[1], groupHandlers[1]
check(onPlay ~= nil and groupsOf ~= nil, "a play handler and a swing groups handler are added")

local info = { kind = "swing", weaponId = "katar_steel", volume = 0.8, pitch = 1.05, attackType = 2 }
local stopped = onPlay(info) == false
local groups, keepsSwish = groupsOf("katar_steel")
check(groups and #groups == 1 and groups[1] == "sharpMetal" and keepsSwish == true,
      "a katar keeps the engine's swish, a fist's, with sharp metal whooshes over it")
check(#fistSwishes == 0 and #swings == 0, "nothing plays the swish again, nor CSO's hand-to-hand swing")
check(not stopped and math.abs(info.volume - 0.68) < 1e-9, "and its own at 85%", info.volume)

groups, keepsSwish = groupsOf("knuckle_iron")
check(type(groups) == "table" and #groups == 0, "knuckledusters keep the engine's swish alone, as a bare fist does")

info = { kind = "swing", weaponId = "fist_blade", volume = 1, attackType = 1 }
groups, keepsSwish = groupsOf("fist_blade")
check(groups == nil and keepsSwish == true, "with another kind added and none of its own, the swish is kept")
check(onPlay(info) == false and #swings == 1 and swings[1].weapon == "shortBlade" and swings[1].volume == 0.5
      and #fistSwishes == 0, "the kind plays over it, and the swing CSO made for it is stopped")
swings = {}

fistSwishes = {}
info = { kind = "swing", weaponId = "mace_of_fire", volume = 1 }
check(onPlay(info) == nil and #swings == 0 and #fistSwishes == 0 and info.volume == 1,
      "a hybrid with no swing sounds swings as its type")
check(groupsOf("mace_of_fire") == nil, "with its type's groups")

printed = {}
print = function(line) printed[#printed + 1] = line end
info = { kind = "swing", weaponId = "odd_whoosh", volume = 1 }
local result = onPlay(info)
print = realPrint
check(#swings == 0 and result == nil and info.volume == 1, "a whoosh CSO does not have is left out")
check(printed[1] and printed[1]:find("Kazoo", 1, true), "and said once", printed[1])
info = { kind = "hit", weaponId = "knuckle_iron", volume = 1 }
check(onPlay(info) == nil, "hits are none of its business")

print(string.format("\n%d checks, %d failures", checks, fails))
os.exit(fails == 0 and 0 or 1)

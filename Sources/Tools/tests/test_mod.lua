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

st.weaponRecords["katar_steel"] = { type = 0, model = "meshes/steel_katar.nif" }
st.weaponRecords["knuckle_iron"] = { type = 3, model = "meshes/iron_knuckle.nif" }
st.weaponRecords["steel dagger"] = { type = 0, model = "meshes/w/w_dagger.nif" }
st.weaponRecords["katar axe"] = { type = 8, model = "meshes/w/axe.nif" }  -- named like one, is not one
st.bones = { ["Weapon Bone"] = true, ["Weapon Bone.L"] = true }
-- Mage Fury ships a charge effect beside its mesh; the steel katar does not.
st.files = { ["meshes/mage_fury_charged.nif"] = true }
st.weaponRecords["knuckle_mage_fury"] = { type = 3, model = "meshes/mage_fury.nif", enchant = "h2h_magefury_en" }
st.weaponRecords["katar_ebony_rose"] = { type = 0, model = "meshes/ebony_rose.nif", enchant = "h2h_ebonyrose_en" }
-- The copy of Ebony Rose made for a burst: a generated record, found by its enchantment alone.
st.weaponRecords["generated:0x99"] = { type = 0, model = "meshes/ebony_rose.nif", enchant = "h2h_ebonyrose_burst_en" }
st.groups = { weapononehand = true, katar = true, kataralt = true, idlekatar = true }
st.skills = {
    handtohand = { base = 50, modifier = 0, damage = 0 },
    shortblade = { base = 30, modifier = 0, damage = 0 },
    bluntweapon = { base = 60, modifier = 0, damage = 0 },
}

--- weapons.lua ---------------------------------------------------------------------------------------
local weapons = require("scripts.MaxYari.H2HWeapons.scripts.weapons")
check(weapons.kindOfId("katar_steel") == "katar", "steel katar is a katar")
check(weapons.kindOfId("KATAR_STEEL") == "katar", "record ids are matched case-insensitively")
check(weapons.kindOfId("knuckle_iron") == "knuckle", "iron knuckles are knuckles")
check(weapons.kindOfId("steel dagger") == false, "a dagger is not one")
check(weapons.kindOfId("katar axe") == false, "a two-handed axe called a katar is not one")
check(weapons.kindOfId(nil) == false, "nil is not one")
check(weapons.modelOfId("katar_steel") == "meshes/steel_katar.nif", "model is cached", weapons.modelOfId("katar_steel"))
check(weapons.FATIGUE_FACTOR.katar == 0.50, "katar fatigue factor")
check(weapons.FATIGUE_FACTOR.knuckle == 0.75, "knuckle fatigue factor")
check(weapons.WEAPON_SKILL.katar == "shortblade", "katars use short blade")
check(weapons.WEAPON_SKILL.knuckle == "bluntweapon", "knuckles use blunt weapon")
check(weapons.specialOfId("katar_ebony_rose") == "venom", "Ebony Rose poisons", weapons.specialOfId("katar_ebony_rose"))
check(weapons.specialOfId("knuckle_mage_fury") == "magefury", "Mage Fury channels spells")
check(weapons.specialOfId("katar_steel") == false, "an ordinary katar has no trick")
check(weapons.kindOfId("Generated:0x99") == "katar", "the burst copy is a katar though its id says nothing")
check(weapons.specialOfId("Generated:0x99") == "burst", "and it is the one that bursts")
check(weapons.modelOfId("Generated:0x99") == "meshes/ebony_rose.nif", "with Ebony Rose's mesh")
-- A katar someone had enchanted is a new, generated record, and its id says nothing; its mesh does.
st.weaponRecords["generated:0x31"] = { type = 0, model = "Meshes\\steel_katar.nif", enchant = "some_fire_en" }
check(weapons.kindOfId("Generated:0x31") == "katar", "an enchanter's copy of a katar is still a katar")
st.weaponRecords["generated:0x32"] = { type = 3, model = "meshes/iron_knuckle.nif" }
check(weapons.kindOfId("Generated:0x32") == "knuckle", "and of knuckledusters, knuckledusters")
st.weaponRecords["generated:0x33"] = { type = 0, model = "meshes/w/w_dagger_iron.nif" }
check(weapons.kindOfId("Generated:0x33") == false, "an enchanted dagger is still a dagger")

--- formulas.lua --------------------------------------------------------------------------------------
local formulas = require("scripts.MaxYari.H2HWeapons.scripts.formulas")
local actor = {}
-- getHandToHandDamage: skill * (fMin + (fMax - fMin) * strength)
check(math.abs(formulas.handToHandFatigue(actor, 0, 0) - 50 * 0.1) < 1e-6, "bare fist at strength 0")
check(math.abs(formulas.handToHandFatigue(actor, 1, 0) - 50 * 0.5) < 1e-6, "bare fist at full strength")
check(math.abs(formulas.handToHandFatigue(actor, 0.5, 0) - 50 * 0.3) < 1e-6, "bare fist halfway")
st.attributes.strength = { base = 80, modifier = 0 }
check(math.abs(formulas.handToHandFatigue(actor, 1, 1) - 50 * 0.5 * 2) < 1e-6,
      "strength 80 doubles it when the setting is on", formulas.handToHandFatigue(actor, 1, 1))
check(math.abs(formulas.handToHandFatigue(actor, 1, 0) - 50 * 0.5) < 1e-6, "and does nothing when it is off")
st.attributes.strength = { base = 40, modifier = 0 }

-- skillBonus: a share of the weapon skill, full within the grace, tapering to a floor past it
local BONUS = { skillBonusMax = 0.15, skillBonusMin = 0.05, skillBonusGrace = 10, skillBonusFalloff = 20 }
local function bonus(h, w) return formulas.skillBonus(h, w, BONUS) end
check(bonus(50, 50) == 7, "parity pays 15% of the weapon skill, rounded down", bonus(50, 50))
check(bonus(50, 90) == 13, "a higher weapon skill pays 15% of the bigger number", bonus(50, 90))
check(bonus(50, 40) == 6, "ten points behind is still the full share", bonus(50, 40))
check(bonus(50, 30) == 3, "halfway through the taper is halfway to the floor", bonus(50, 30))
check(bonus(50, 20) == 1, "past the taper it is the floor rate", bonus(50, 20))
check(bonus(50, 5) == 0, "which a low enough weapon skill still rounds away", bonus(50, 5))
check(bonus(50, 50) % 1 == 0, "the bonus is always a whole number of skill points")
check(formulas.effectiveSkill(50, 50, BONUS) == 57, "the bonus is added to hand-to-hand")
-- the taper is monotonic: letting the weapon skill slide can never help
local previous = math.huge
for w = 100, 0, -1 do
    local b = bonus(50, w)
    if b > previous + 1e-9 then check(false, "bonus is monotonic in the weapon skill", w); break end
    previous = b
end
check(true, "bonus never goes up as the weapon skill drops")

--- the player script ----------------------------------------------------------------------------------
local api = require("scripts.MaxYari.ReAnimation_v3.ReAnimationAPI")
stubs.I.ReAnimation = api.interface

st.stance = 1 -- weapon drawn
st.equipped = { recordId = "katar_steel" }
stubs.enableInventoryExtender()
local player = require("scripts.MaxYari.H2HWeapons.player")
local onUpdate = player.engineHandlers.onUpdate
-- The first update, like a view switch, waits a couple of frames for the model before attaching.
local function settle() for _ = 1, 3 do onUpdate(0.016) end end

onUpdate(0.016)
check(st.vfx == nil, "nothing is attached before the model has settled")
settle()
check(st.vfx ~= nil, "the off-hand weapon is attached")
check(st.vfx and st.vfx.model == "meshes/steel_katar.nif", "with the weapon's own mesh", st.vfx and st.vfx.model)
check(st.vfx and st.vfx.opts.boneName == "Weapon Bone.L", "on the off-hand bone")
check(st.vfx and st.vfx.opts.loop == true, "and it loops, so it stays")

-- The off hand goes and comes with the weapon in the right hand, which the engine hides and shows on
-- the weapon group's detach and attach keys, partway through the animation.
st.stance = 0 -- sheathing
onUpdate(0.016)
check(st.vfx ~= nil, "the off hand stays while the sheathe is on its way")
stubs.textKey("weapononehand", "unequip detach")
onUpdate(0.016)
check(st.vfx == nil, "and goes when the right hand's weapon does")
st.stance = 1 -- drawing
onUpdate(0.016)
check(st.vfx == nil, "drawing does not show it before the right hand's")
stubs.textKey("weapononehand", "equip attach")
onUpdate(0.016)
check(st.vfx ~= nil, "but together with it")
-- A stance changed with no animation - a script, a load - is taken as it is after a moment.
st.stance = 0
onUpdate(0.016)
st.time = st.time + 2
onUpdate(0.016)
check(st.vfx == nil, "a sheathe with no detach key still takes it away, a moment later")
st.stance = 1
onUpdate(0.016)
st.time = st.time + 2
onUpdate(0.016)
check(st.vfx ~= nil, "and a draw with no attach key brings it back")
-- Resting takes every effect off (Actors::rest); closing the rest screen puts the off hand back.
st.vfxById, st.vfx = {}, nil
player.eventHandlers.UiModeChanged({ oldMode = "Rest", newMode = nil })
onUpdate(0.016)
check(st.vfxById["H2HWeapons_OffHand"] ~= nil, "after resting the off hand is put back")
st.vfxById, st.vfx = {}, nil
player.eventHandlers.UiModeChanged({ oldMode = "Inventory", newMode = nil })
onUpdate(0.016)
check(st.vfxById["H2HWeapons_OffHand"] == nil, "a screen that passes no time is left alone")
player.eventHandlers.UiModeChanged({ oldMode = "Rest", newMode = nil })
onUpdate(0.016)

-- skill swap over a swing
local function playWeapon(startKey)
    stubs.I.AnimationController.playBlendedAnimation("weapononehand",
        { startKey = startKey, startkey = startKey, stopKey = "x", stopkey = "x", speed = 2, priority = 7, blendMask = 15 })
end

check(st.skills.shortblade.modifier == 0, "short blade starts unmodified")
playWeapon("slash start")
-- hand-to-hand 50, short blade 30: 20 behind, halfway through the taper, so 10% of 30 on top.
-- The engine should roll against 53, which from a base of 30 is a modifier of 23.
check(st.skills.shortblade.modifier == 23,
      "the wind up puts hand-to-hand into the short blade skill", st.skills.shortblade.modifier)
playWeapon("slash large follow start")
check(st.skills.shortblade.modifier == 0, "the follow-through puts it back", st.skills.shortblade.modifier)

-- with both skills up, the full share applies: 50 + floor(15% of 50) = 57, a modifier of 7
st.skills.shortblade.base = 50
playWeapon("chop start")
check(st.skills.shortblade.modifier == 7,
      "parity earns the full share of the weapon skill", st.skills.shortblade.modifier)
playWeapon("chop small follow start")
check(st.skills.shortblade.modifier == 0, "and it is taken back off")
st.skills.shortblade.base = 30

-- an interrupted swing must not leave the modifier on
playWeapon("thrust start")
check(st.skills.shortblade.modifier ~= 0, "mid-swing")
st.stance = 0
onUpdate(0.016)
check(st.skills.shortblade.modifier == 0, "sheathing mid-swing puts the skill back", st.skills.shortblade.modifier)
st.stance = 1
onUpdate(0.016)

-- a plain weapon is left alone entirely
st.equipped = { recordId = "steel dagger" }
onUpdate(0.016)
check(st.vfx == nil, "a dagger gets no off-hand weapon")
playWeapon("slash start")
check(st.skills.shortblade.modifier == 0, "and no skill swap", st.skills.shortblade.modifier)
st.equipped = { recordId = "katar_steel" }
onUpdate(0.016)

-- the draw sound is silenced
st.stoppedSounds = {}
stubs.I.AnimationController.playBlendedAnimation("weapononehand",
    { startKey = "equip start", startkey = "equip start", speed = 1, priority = 7, blendMask = 15 })
onUpdate(0.016)
check(#st.stoppedSounds == 2, "drawing stops both short blade sounds", #st.stoppedSounds)
check(st.stoppedSounds[1] == "Item Weapon Shortblade Up", "the right one", st.stoppedSounds[1])

-- experience split
st.skillUses = {}
local options = { useType = 0, skillGain = 1.0 }
for i = #stubs.skillUsedHandlers, 1, -1 do stubs.skillUsedHandlers[i]("shortblade", options) end
check(math.abs(options.skillGain - 0.3) < 1e-6, "the weapon skill keeps 30%", options.skillGain)
check(#st.skillUses == 1 and st.skillUses[1].skill == "handtohand", "hand-to-hand is credited", #st.skillUses)
check(st.skillUses[1].options.scale == 0.7, "with 70%", st.skillUses[1] and st.skillUses[1].options.scale)

-- an actual punch is left alone, and cannot recurse
st.skillUses = {}
local punch = { useType = 0, skillGain = 1.0 }
for i = #stubs.skillUsedHandlers, 1, -1 do stubs.skillUsedHandlers[i]("handtohand", punch) end
check(punch.skillGain == 1.0, "a hand-to-hand use is untouched", punch.skillGain)
check(#st.skillUses == 0, "and starts nothing else", #st.skillUses)

--- the charge effect ------------------------------------------------------------------------------
-- A weapon lights up when a "<mesh>_charged.nif" sits beside its mesh, on both weapon bones - here
-- forced on, the way I.H2HWeapons.setCharged lets one look at it without casting.
st.equipped = { recordId = "knuckle_mage_fury" }
st.vfxById = {}
onUpdate(0.016)
check(st.vfxById["H2HWeapons_Charge_R"] == nil, "an uncharged Mage Fury stays dark")
player.interface.setCharged(true)
onUpdate(0.016)
local right, left = st.vfxById["H2HWeapons_Charge_R"], st.vfxById["H2HWeapons_Charge_L"]
check(right ~= nil and left ~= nil, "the mage knuckle lights up in both hands")
check(right and right.model == "meshes/mage_fury_charged.nif", "with the charge effect beside its mesh",
      right and right.model)
check(right and right.opts.boneName == "Weapon Bone", "main hand on the weapon bone")
check(left and left.opts.boneName == "Weapon Bone.L", "off hand on the mirrored one")
check(right and right.opts.loop == true, "and it loops")

st.stance = 0
stubs.textKey("weapononehand", "unequip detach")
onUpdate(0.016)
check(st.vfxById["H2HWeapons_Charge_R"] == nil, "sheathing puts it out")
st.stance = 1
stubs.textKey("weapononehand", "equip attach")
onUpdate(0.016)
check(st.vfxById["H2HWeapons_Charge_R"] ~= nil, "drawing lights it again")

player.interface.setCharged(false)
onUpdate(0.016)
check(st.vfxById["H2HWeapons_Charge_R"] == nil, "and setCharged(false) puts it out")
player.interface.setCharged(true)
onUpdate(0.016)

-- A weapon with no charge effect beside it gets none.
st.equipped = { recordId = "katar_steel" }
onUpdate(0.016)
check(st.vfxById["H2HWeapons_Charge_R"] == nil, "a weapon without one stays dark")
st.equipped = { recordId = "knuckle_mage_fury" }
onUpdate(0.016)

--- switching view ----------------------------------------------------------------------------------
-- A first/third person switch swaps the model, and every attached effect goes with it. Everything has
-- to come back once the new model is there - including the glow, which it used not to.
local function engineRebuildsModel() st.vfxById = {}; st.vfx = nil end
check(st.vfxById["H2HWeapons_OffHand"] and st.vfxById["H2HWeapons_Charge_R"]
      and st.vfxById["H2HWeapons_Charge_L"], "before the switch: weapon and both glows")
st.cameraMode = 1
engineRebuildsModel()
onUpdate(0.016)
onUpdate(0.016)
check(st.vfxById["H2HWeapons_OffHand"] == nil, "the new model gets a moment before anything is attached")
onUpdate(0.016)
check(st.vfxById["H2HWeapons_OffHand"] ~= nil, "then the off-hand weapon is back in third person")
check(st.vfxById["H2HWeapons_Charge_R"] ~= nil and st.vfxById["H2HWeapons_Charge_L"] ~= nil,
      "and so is the glow, in both hands")
st.cameraMode = 0
engineRebuildsModel()
settle()
check(st.vfxById["H2HWeapons_OffHand"] ~= nil and st.vfxById["H2HWeapons_Charge_R"] ~= nil,
      "and again back in first person")
-- A view that is still third person (vanity, preview) is the same model: nothing is redone.
st.cameraMode = 2
local before = st.vfxById["H2HWeapons_OffHand"]
onUpdate(0.016)
st.cameraMode = 1
onUpdate(0.016)
check(st.vfxById["H2HWeapons_OffHand"] == nil, "leaving first person starts over")
settle()
st.cameraMode = 2
onUpdate(0.016)
check(st.vfxById["H2HWeapons_OffHand"] ~= nil, "but third person to vanity does not")
st.cameraMode = 0
settle()
-- A teleport starts over too.
player.engineHandlers.onTeleported()
engineRebuildsModel()
settle()
check(st.vfxById["H2HWeapons_OffHand"] ~= nil and st.vfxById["H2HWeapons_Charge_R"] ~= nil,
      "a teleport re-attaches everything")

-- No off-hand weapon, no off-hand glow.
-- The same module instance the scripts use: they require it by its slash path.
local cfg = require("scripts/MaxYari/H2HWeapons/scripts/settings").values
cfg.showOffHandWeapon = false
onUpdate(0.016)
check(st.vfxById["H2HWeapons_OffHand"] == nil and st.vfxById["H2HWeapons_Charge_L"] == nil,
      "with the off-hand weapon off, the left hand is empty")
check(st.vfxById["H2HWeapons_Charge_R"] ~= nil, "and the right still glows")
cfg.showOffHandWeapon = true
onUpdate(0.016)

-- Someone else's skeleton, without the off-hand bone: the right hand still works, nothing throws.
st.bones["Weapon Bone.L"] = nil
st.cameraMode = 1
engineRebuildsModel()
settle()
check(st.vfxById["H2HWeapons_Charge_R"] ~= nil, "a skeleton without the left bone still lights the right")
check(st.vfxById["H2HWeapons_OffHand"] == nil and st.vfxById["H2HWeapons_Charge_L"] == nil,
      "and puts nothing on a bone it does not have")
st.bones["Weapon Bone.L"] = true
st.cameraMode = 0
engineRebuildsModel()
settle()
player.interface.setCharged(nil)
onUpdate(0.016)
check(st.vfxById["H2HWeapons_Charge_R"] == nil, "setCharged(nil) goes back to following the charge")

--- tooltips --------------------------------------------------------------------------------------------
-- A stand-in for the layout Inventory Extender builds for a weapon: the shape the modifier walks,
-- with the named lines it puts in for a melee weapon.
local function fakeTooltip()
    local inner = stubs.content {
        { name = "name", props = { text = "Steel Katar" } },
        { name = "type", props = { text = "Type: Short Blade, One Handed" } },
        { name = "chop", props = { text = "Chop: 5 - 11" } },
        { name = "slash", props = { text = "Slash: 5 - 11" } },
        { name = "thrust", props = { text = "Thrust: 6 - 11" } },
        { name = "range", props = { text = "Range: 4.6 Feet" } },
        { name = "speed", props = { text = "Speed: 200%" } },
    }
    return { content = stubs.content {
        { name = "padding", content = stubs.content {
            { name = "tooltip", content = inner },
        } },
    } }, inner
end

local modifier = stubs.tooltipModifiers["H2HWeapons"]
check(modifier ~= nil, "the tooltip modifier is registered")

local layout, inner = fakeTooltip()
modifier({ recordId = "katar_steel" }, layout)
check(inner.type.props.text == "Type: Hand-to-hand (Short Blade), One Handed",
      "the type line names hand-to-hand with the engine skill as a subtype", inner.type.props.text)
check(inner.h2hFatigue ~= nil, "a fatigue damage line is added")
check(inner.h2hFatigue and inner.h2hFatigue.props.text == "Fatigue Damage: 3 - 13",
      "with the katar's half of a bare fist, in whole numbers", inner.h2hFatigue and inner.h2hFatigue.props.text)
check(inner:indexOf("h2hFatigue") == inner:indexOf("thrust") + 1,
      "right under the damage lines", inner:indexOf("h2hFatigue"))
check(inner.h2hExplanation ~= nil, "an explanation is added")
check(inner:indexOf("h2hExplanation") == #inner, "at the very bottom", inner:indexOf("h2hExplanation"))
local explanation = inner.h2hExplanation and inner.h2hExplanation.props.text
check(explanation and explanation:find("Short Blade", 1, true) ~= nil,
      "naming the skill that gives the minor bonus", explanation)
-- hand-to-hand 50, short blade 30: 20 behind, halfway through the taper, so 10% of 30
check(explanation and explanation:find("(50)", 1, true) ~= nil,
      "showing the current hand-to-hand value", explanation)
check(explanation and explanation:find("(+3)", 1, true) ~= nil,
      "and the bonus that weapon skill is worth right now", explanation)
check(explanation and explanation:find("%.%d") == nil, "as whole skill points", explanation)
check(explanation and explanation:find("%%{") == nil, "with every placeholder filled in", explanation)

-- the numbers are read when the tooltip is built, not when the modifier was registered
st.skills.shortblade.base = 50
local levelled, levelledInner = fakeTooltip()
modifier({ recordId = "katar_steel" }, levelled)
check(levelledInner.h2hExplanation.props.text:find("(+7)", 1, true) ~= nil,
      "a levelled weapon skill shows a bigger bonus", levelledInner.h2hExplanation.props.text)
st.skills.shortblade.base = 30

local knuckleLayout, knuckleInner = fakeTooltip()
knuckleInner.type.props.text = "Type: Blunt Weapon, One Handed"
modifier({ recordId = "knuckle_iron" }, knuckleLayout)
check(knuckleInner.type.props.text == "Type: Hand-to-hand (Blunt Weapon), One Handed",
      "knuckledusters name blunt weapon instead", knuckleInner.type.props.text)
check(knuckleInner.h2hExplanation.props.text:find("Blunt Weapon", 1, true) ~= nil,
      "in the explanation too", knuckleInner.h2hExplanation.props.text)

local plainLayout, plainInner = fakeTooltip()
modifier({ recordId = "steel dagger" }, plainLayout)
check(plainInner.type.props.text == "Type: Short Blade, One Handed", "an ordinary weapon is untouched")
check(plainInner.h2hFatigue == nil, "and gets no extra lines")

--- the actor script ------------------------------------------------------------------------------------
local actorScript = require("scripts.MaxYari.H2HWeapons.actor")
local onHit = stubs.onHitHandlers[#stubs.onHitHandlers]

local attack = { successful = true, sourceType = "melee", attacker = {}, strength = 1,
                 weapon = { recordId = "katar_steel" }, damage = { health = 20 } }
onHit(attack)
-- bare fist at full strength is 50 * 0.5 = 25; a katar does half of that
check(math.abs(attack.damage.fatigue - 12.5) < 1e-6, "a katar bruises for 50% of a fist", attack.damage.fatigue)
check(attack.damage.health == 20, "and leaves the weapon's own damage alone")

attack = { successful = true, sourceType = "melee", attacker = {}, strength = 1,
           weapon = { recordId = "knuckle_iron" }, damage = { health = 5 } }
onHit(attack)
check(math.abs(attack.damage.fatigue - 18.75) < 1e-6, "knuckledusters for 75%", attack.damage.fatigue)
-- the damage itself stays fractional; only the tooltip rounds it
check(attack.damage.fatigue % 1 ~= 0, "the applied damage is not rounded", attack.damage.fatigue)

-- On someone who is down, the bruising lands on health instead, at a tenth - as a fist's does - and,
-- knocked down, half again on top, as every hit on a knocked-down target is.
local function knuckleHit()
    local a = { successful = true, sourceType = "melee", attacker = {}, strength = 1,
                weapon = { recordId = "knuckle_iron" }, damage = { health = 5 } }
    onHit(a)
    return a.damage
end
st.fatigue.current = -3
local down = knuckleHit()
check(down.fatigue == nil, "a knocked-out target takes no fatigue from it", down.fatigue)
check(math.abs(down.health - (5 + 2.8125)) < 1e-6, "but a tenth of it, half again, to health, on top of the weapon's", down.health)
st.fatigue.current = 40
st.playing = { knockdown = true }
check(math.abs(knuckleHit().health - 7.8125) < 1e-6, "the same while knocked down")
st.playing = {}
st.effects.paralyze = 1
check(math.abs(knuckleHit().health - 6.875) < 1e-6, "paralysed, only the tenth: paralysis is not knocked down")
st.effects.paralyze = nil
local up = knuckleHit()
check(up.health == 5 and math.abs(up.fatigue - 18.75) < 1e-6, "and back to fatigue once they are up")

attack = { successful = true, sourceType = "melee", attacker = {}, strength = 1,
           weapon = { recordId = "steel dagger" }, damage = { health = 5 } }
onHit(attack)
check(attack.damage.fatigue == nil, "an ordinary weapon adds none", attack.damage.fatigue)

attack = { successful = false, sourceType = "melee", attacker = {}, strength = 1,
           weapon = { recordId = "katar_steel" }, damage = {} }
onHit(attack)
check(attack.damage.fatigue == nil, "a miss adds none")

attack = { successful = true, sourceType = "magic", attacker = {}, strength = 1,
           weapon = { recordId = "katar_steel" }, damage = {} }
onHit(attack)
check(attack.damage.fatigue == nil, "a spell adds none")

local function near(a, b) return a ~= nil and math.abs(a - b) < 1e-6 end

-- Blocked, or dealt to a god: the engine has zeroed the weapon's damage, and would a fist's.
attack = { successful = true, sourceType = "melee", attacker = {}, strength = 1,
           weapon = { recordId = "katar_steel" }, damage = { health = 0 } }
onHit(attack)
check(attack.damage.fatigue == nil, "a blocked hit bruises nobody", attack.damage.fatigue)

-- A critical strike: the weapon's own damage came out at four times its roll, so the bruising is too.
-- The roll at full swing is 10, times condition 100/100, times Strength 40's 0.5 + 40 * 0.1 * 0.1.
st.weaponRecords["katar_test"] = { type = 0, model = "meshes/steel_katar.nif", health = 100,
    chopMinDamage = 5, chopMaxDamage = 10, slashMinDamage = 5, slashMaxDamage = 10,
    thrustMinDamage = 5, thrustMaxDamage = 10 }
local function testHit(health, attacker)
    local a = { successful = true, sourceType = "melee", attacker = attacker or {}, strength = 1, type = 1,
                weapon = { recordId = "katar_test", data = { condition = 100 } }, damage = { health = health } }
    onHit(a)
    return a.damage
end
check(near(testHit(9).fatigue, 12.5), "a plain hit bruises plainly", testHit(9).fatigue)
check(near(testHit(36).fatigue, 50), "a critical one four times over", testHit(36).fatigue)
check(near(testHit(14).fatigue, 12.5), "a hit merely a bit harder than its roll is not critical")
check(near(testHit(36, { notPlayer = true }).fatigue, 12.5), "only the player strikes critically")
st.playing = { knockdown = true }
check(near(testHit(13.5).health, 13.5 + 12.5 * 0.1 * 1.5), "knocked down, the 1.5 is not mistaken for one")
check(near(testHit(54).health, 54 + 12.5 * 4 * 0.1 * 1.5), "but a critical on the knocked down still is")
st.playing = {}

--- the mirror of the launcher's strength option ---------------------------------------------------
local settings = require("scripts/MaxYari/H2HWeapons/scripts/settings")
check(settings.values.strengthFactor == 0, "off by default, as the launcher is")
local section = stubs.section(settings.GLOBAL_GROUP)
st.attributes.strength = { base = 80, modifier = 0 }
section:set("strengthInfluencesHandToHand", "onExceptWerewolves")
check(settings.values.strengthFactor == 2, "the launcher's third option is its 2")
check(near(testHit(9).fatigue, 12.5 * 2), "and the bruising scales with Strength 80 / 40")
section:set("strengthInfluencesHandToHand", "off")
check(near(testHit(9).fatigue, 12.5), "and stops when it is set back off")
st.attributes.strength = { base = 40, modifier = 0 }

print(string.format("\n%d checks, %d failures", checks, fails))
os.exit(fails == 0 and 0 or 1)

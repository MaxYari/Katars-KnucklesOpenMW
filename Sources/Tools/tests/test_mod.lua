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
-- The mage knuckle ships a charge effect beside its mesh; the steel katar does not.
st.files = { ["meshes/mage_knuckle_charged.nif"] = true }
st.weaponRecords["knuckle_mage"] = { type = 3, model = "meshes/mage_knuckle.nif" }
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

onUpdate(0.016)
check(st.vfx ~= nil, "the off-hand weapon is attached")
check(st.vfx and st.vfx.model == "meshes/steel_katar.nif", "with the weapon's own mesh", st.vfx and st.vfx.model)
check(st.vfx and st.vfx.opts.boneName == "Weapon Bone.L", "on the off-hand bone")
check(st.vfx and st.vfx.opts.loop == true, "and it loops, so it stays")

st.stance = 0 -- sheathed
onUpdate(0.016)
check(st.vfx == nil, "sheathing takes it away")
st.stance = 1
onUpdate(0.016)
check(st.vfx ~= nil, "drawing brings it back")

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
-- A weapon lights up when a "<mesh>_charged.nif" sits beside its mesh, on both weapon bones.
st.equipped = { recordId = "knuckle_mage" }
st.vfxById = {}
onUpdate(0.016)
local right, left = st.vfxById["H2HWeapons_Charge_R"], st.vfxById["H2HWeapons_Charge_L"]
check(right ~= nil and left ~= nil, "the mage knuckle lights up in both hands")
check(right and right.model == "meshes/mage_knuckle_charged.nif", "with the charge effect beside its mesh",
      right and right.model)
check(right and right.opts.boneName == "Weapon Bone", "main hand on the weapon bone")
check(left and left.opts.boneName == "Weapon Bone.L", "off hand on the mirrored one")
check(right and right.opts.loop == true, "and it loops")

st.stance = 0
onUpdate(0.016)
check(st.vfxById["H2HWeapons_Charge_R"] == nil, "sheathing puts it out")
st.stance = 1
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
st.equipped = { recordId = "knuckle_mage" }
onUpdate(0.016)

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

print(string.format("\n%d checks, %d failures", checks, fails))
os.exit(fails == 0 and 0 or 1)

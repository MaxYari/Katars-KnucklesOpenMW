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
st.bones = { ["Weapon Bone.L"] = true }
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
check(weapons.FATIGUE_FACTOR.katar == 0.10, "katar fatigue factor")
check(weapons.FATIGUE_FACTOR.knuckle == 0.50, "knuckle fatigue factor")
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

-- effectiveSkill: full bonus at or above parity, gone 10 points below
check(math.abs(formulas.effectiveSkill(50, 50, 0.1, 10) - 55) < 1e-6, "parity gives the full bonus")
check(math.abs(formulas.effectiveSkill(50, 90, 0.1, 10) - 55) < 1e-6, "a higher weapon skill gives no more")
check(math.abs(formulas.effectiveSkill(50, 45, 0.1, 10) - 52.5) < 1e-6, "halfway down gives half", formulas.effectiveSkill(50, 45, 0.1, 10))
check(math.abs(formulas.effectiveSkill(50, 40, 0.1, 10) - 50) < 1e-6, "ten points below gives none")
check(math.abs(formulas.effectiveSkill(50, 10, 0.1, 10) - 50) < 1e-6, "further below gives none, never less")

--- the player script ----------------------------------------------------------------------------------
local api = require("scripts.MaxYari.ReAnimation_v3.ReAnimationAPI")
stubs.I.ReAnimation = api.interface

st.stance = 1 -- weapon drawn
st.equipped = { recordId = "katar_steel" }
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
-- hand-to-hand 50, short blade 30 -> 20 behind, so no bonus: the engine should roll against 50
check(math.abs(st.skills.shortblade.modifier - 20) < 1e-6,
      "the wind up puts hand-to-hand into the short blade skill", st.skills.shortblade.modifier)
playWeapon("slash large follow start")
check(st.skills.shortblade.modifier == 0, "the follow-through puts it back", st.skills.shortblade.modifier)

-- with both skills up, the bonus applies
st.skills.shortblade.base = 50
playWeapon("chop start")
check(math.abs(st.skills.shortblade.modifier - 5) < 1e-6,
      "parity earns the 10% bonus", st.skills.shortblade.modifier)
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

--- the actor script ------------------------------------------------------------------------------------
local actorScript = require("scripts.MaxYari.H2HWeapons.actor")
local onHit = stubs.onHitHandlers[#stubs.onHitHandlers]

local attack = { successful = true, sourceType = "melee", attacker = {}, strength = 1,
                 weapon = { recordId = "katar_steel" }, damage = { health = 20 } }
onHit(attack)
-- bare fist at full strength is 50 * 0.5 = 25; a katar does a tenth of that
check(math.abs(attack.damage.fatigue - 2.5) < 1e-6, "a katar bruises for 10% of a fist", attack.damage.fatigue)
check(attack.damage.health == 20, "and leaves the weapon's own damage alone")

attack = { successful = true, sourceType = "melee", attacker = {}, strength = 1,
           weapon = { recordId = "knuckle_iron" }, damage = { health = 5 } }
onHit(attack)
check(math.abs(attack.damage.fatigue - 12.5) < 1e-6, "knuckledusters for 50%", attack.damage.fatigue)

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

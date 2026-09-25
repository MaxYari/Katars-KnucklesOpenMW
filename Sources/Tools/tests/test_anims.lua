package.path = arg[0]:gsub("[^/]*$", "") .. "?.lua;" .. package.path
local stubs = require("stubs")
local K, R = stubs.findMods()
stubs.addRoot(R); stubs.addRoot(K)

local st = stubs.state
local fails, checks = 0, 0
local function check(ok, msg, extra)
    checks = checks + 1
    if not ok then fails = fails + 1; print("FAIL: " .. msg .. (extra and ("  ["..tostring(extra).."]") or "")) end
end

st.weaponRecords["katar_steel"] = { type = 0, model = "meshes/steel_katar.nif" }
st.weaponRecords["steel dagger"] = { type = 0, model = "meshes/w/w_dagger.nif" }
st.groups = { weapononehand = true, weapononehand1 = true, katar = true, kataralt = true, idlekatar = true,
              idle1s = true, idlekatarsneak = true, walkforward1s = true, walkforwardkatar = true,
              jump1s = true, jumpkatar = true }
st.stance = 1

local function key(k, t) st.textKeys[string.lower(k)] = t end
for _, g in ipairs({ "weapononehand", "katar", "kataralt" }) do
    local base = g == "weapononehand" and 50 or 0
    for _, attack in ipairs({ "slash", "chop", "thrust" }) do
        key(g .. ": " .. attack .. " start", base + 0)
        key(g .. ": " .. attack .. " max attack", base + 0.4667)
        key(g .. ": " .. attack .. " hit", base + (g == "weapononehand" and 0.8 or 0.6))
    end
end
-- The equip section: the fist's is half a second, the one-handed weapon's twice that.
key("katar: equip start", 0); key("katar: equip stop", 0.5)
key("weapononehand: equip start", 60); key("weapononehand: equip stop", 61)

local api = require("scripts.MaxYari.ReAnimation_v3.ReAnimationAPI")
stubs.I.ReAnimation = api.interface

-- ReAnimation's own one-handed set, registered the way AnimationOverrides.lua does, and before this
-- mod's, since ReAnimation loads first
api.interface.addAltAttackAnimations({
    parentAttackGroupname = "weapononehand",
    altAttackGroupname = "weapononehand1",
    armatureType = 1,
})

-- the mod's own animation registrations must load without error
local overrides = require("scripts.MaxYari.H2HWeapons.animations")
check(true, "animations.lua loaded")

local function swing(attackType)
    attackType = attackType or "slash"
    st.played = {}
    local startKey, stopKey = attackType .. " start", attackType .. " max attack"
    local o = { startKey = startKey, startkey = startKey, stopKey = stopKey, stopkey = stopKey,
                speed = 2, priority = 7, blendMask = 15 }
    stubs.I.AnimationController.playBlendedAnimation("weapononehand", o)
    local groups = {}
    for _, p in ipairs(st.played) do groups[p.group] = true end
    return groups, o
end

st.equipped = { recordId = "katar_steel" }
local groups, opts = swing()
check(groups["katar"] == true, "a katar swings with the katar animation")
check(groups["weapononehand1"] ~= true, "and ReAnimation's own alternate is stood down")
check(math.abs(opts.speed - 2.0) < 1e-3, "and the parent is re-timed to it", opts.speed)

-- chop and thrust are the fist's too, with the parent hidden underneath
local follow = function(attack)
    local k = attack .. " large follow start"
    stubs.I.AnimationController.playBlendedAnimation("weapononehand", { startKey = k, startkey = k,
        stopKey = attack .. " large follow stop", stopkey = attack .. " large follow stop",
        speed = 2, priority = 7, blendMask = 15 })
end
follow("slash")
groups, opts = swing("chop")
check(groups["katar"] or groups["kataralt"], "a katar chops with the fist's chop")
check(groups["weapononehand1"] ~= true, "not ReAnimation's one-handed alternate")
check(opts.blendMask == 0, "and the parent is hidden under it", opts.blendMask)
follow("chop")
groups = swing("thrust")
check(groups["katar"] or groups["kataralt"], "and thrusts with the fist's thrust")
follow("thrust")

-- the variants alternate as they do for bare fists
local seen = {}
for _ = 1, 2 do
    local g = swing("slash")
    if g["katar"] then seen.katar = true end
    if g["kataralt"] then seen.kataralt = true end
    follow("slash")
end
check(seen.katar and seen.kataralt, "one swing, then its mirror")

-- The equip plays the fist's section over the parent's length: the weapon still appears at the
-- parent's attach key.
st.played = {}
local equip = { startKey = "equip start", startkey = "equip start", stopKey = "equip stop",
                stopkey = "equip stop", speed = 1, priority = 7, blendMask = 15 }
stubs.I.AnimationController.playBlendedAnimation("weapononehand", equip)
local fistEquip
for _, p in ipairs(st.played) do if p.group == "katar" then fistEquip = p.options end end
check(fistEquip ~= nil, "drawing plays the fist's equip")
check(fistEquip and math.abs(fistEquip.speed - 0.5) < 1e-6, "at half speed, so its half second fills the parent's second",
      fistEquip and fistEquip.speed)
check(equip.blendMask == 0, "over a hidden parent", equip.blendMask)

-- locomotion and the jump
st.played = {}
stubs.I.AnimationController.playBlendedAnimation("walkforward1s", { speed = 1, priority = 5, blendMask = 15, loops = 999 })
local walked = false
for _, p in ipairs(st.played) do if p.group == "walkforwardkatar" then walked = true end end
check(walked, "walking plays the fist's walk")
st.played = {}
stubs.I.AnimationController.playBlendedAnimation("jump1s", { startKey = "start", startkey = "start", speed = 1, priority = 5, blendMask = 15 })
local jumped = false
for _, p in ipairs(st.played) do if p.group == "jumpkatar" then jumped = true end end
check(jumped, "and jumping its jump")

-- A generated record - a Bound Fist scaled to its caster, Ebony Rose's burst copy, a katar someone
-- enchanted - is one too, though ReAnimation hands out its id lowercased and the engine only knows it
-- as "Generated:0x...".
st.weaponRecords["generated:0x77"] = { type = 0, model = "meshes/daedric_katar.nif" }
st.equipped = { recordId = "Generated:0x77" }
follow("thrust")
groups = swing()
check(groups["katar"] or groups["kataralt"], "a generated katar swings as a katar")
follow("slash")

st.equipped = { recordId = "steel dagger" }
groups = swing()
check(groups["katar"] ~= true, "a dagger does not swing with the katar animation")
-- the alternation opens on the parent itself, so the second swing is ReAnimation's alternate. It only
-- counts a swing as the one before once its follow-through has played.
follow("slash")
groups = swing()
check(groups["weapononehand1"] == true, "and ReAnimation's own set takes the dagger's swings again")

print(string.format("\n%d checks, %d failures", checks, fails))
os.exit(fails == 0 and 0 or 1)

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
st.weaponRecords["knuckle_iron"] = { type = 3, model = "meshes/iron_knuckle.nif" }
-- The swings and the equip are the knuckledusters' for both sets; the idles, moves and jump each set's own.
st.groups = { weapononehand = true, weapononehand1 = true, knuckle = true, knucklealt = true,
              idle1s = true, walkforward1s = true, jump1s = true,
              idlekatar = true, idlekatarsneak = true, walkforwardkatar = true, jumpkatar = true,
              idleknuckle = true, idleknucklesneak = true, walkforwardknuckle = true, jumpknuckle = true }
st.stance = 1

local function key(k, t) st.textKeys[string.lower(k)] = t end
for _, g in ipairs({ "weapononehand", "knuckle", "knucklealt" }) do
    local base = g == "weapononehand" and 50 or 0
    for _, attack in ipairs({ "slash", "chop", "thrust" }) do
        key(g .. ": " .. attack .. " start", base + 0)
        key(g .. ": " .. attack .. " max attack", base + 0.4667)
        key(g .. ": " .. attack .. " hit", base + (g == "weapononehand" and 0.8 or 0.6))
    end
end
-- The equip section: the fist's is half a second, the one-handed weapon's twice that.
key("knuckle: equip start", 0); key("knuckle: equip stop", 0.5)
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

-- A ReAnimation from before 3.3 has the interface but not all of it: nothing is registered, and the
-- player is told to update it.
stubs.I.ReAnimation = { version = 2.9 }
st.messages = {}
local loadedOld, returned = pcall(require, "scripts.MaxYari.H2HWeapons.animations")
check(loadedOld and returned == true, "with ReAnimation 2.9 animations.lua stops before registering anything",
      tostring(returned))
check(st.messages[1] and st.messages[1]:find("update", 1, true), "and the player is told to update it",
      st.messages[1])
package.loaded["scripts.MaxYari.H2HWeapons.animations"] = nil
stubs.I.ReAnimation = api.interface

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
check(groups["knuckle"] == true, "a katar swings with the knuckledusters' animation")
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
check(groups["knuckle"] or groups["knucklealt"], "a katar chops with the fist's chop")
check(groups["weapononehand1"] ~= true, "not ReAnimation's one-handed alternate")
check(opts.blendMask == 0, "and the parent is hidden under it", opts.blendMask)
follow("chop")
groups = swing("thrust")
check(groups["knuckle"] or groups["knucklealt"], "and thrusts with the fist's thrust")
follow("thrust")

-- the variants alternate as they do for bare fists
local seen = {}
for _ = 1, 2 do
    local g = swing("slash")
    if g["knuckle"] then seen.knuckle = true end
    if g["knucklealt"] then seen.knucklealt = true end
    follow("slash")
end
check(seen.knuckle and seen.knucklealt, "one swing, then its mirror")

-- The equip plays the fist's section over the parent's length: the weapon still appears at the
-- parent's attach key.
st.played = {}
local equip = { startKey = "equip start", startkey = "equip start", stopKey = "equip stop",
                stopkey = "equip stop", speed = 1, priority = 7, blendMask = 15 }
stubs.I.AnimationController.playBlendedAnimation("weapononehand", equip)
local fistEquip
for _, p in ipairs(st.played) do if p.group == "knuckle" then fistEquip = p.options end end
check(fistEquip ~= nil, "drawing plays the fist's equip")
check(fistEquip and math.abs(fistEquip.speed - 0.5) < 1e-6, "at half speed, so its half second fills the parent's second",
      fistEquip and fistEquip.speed)
check(equip.blendMask == 0, "over a hidden parent", equip.blendMask)

-- Sneaking in first person: ReAnimation's own sneak idle plays over the same parent too, one above it
-- everywhere and unranked, and wins a tie. Ours goes above it on every bone group.
local selfControls = require("openmw.self").controls
selfControls.sneak = true
st.played = {}
stubs.I.AnimationController.playBlendedAnimation("idle1s",
    { startKey = "start", startkey = "start", speed = 1, priority = 0, blendMask = 15, loops = 999 })
api.engineHandlers.onUpdate(0.016)
local sneakPriority
for _, p in ipairs(st.played) do if p.group == "idlekatarsneak" then sneakPriority = p.options.priority end end
local above = sneakPriority ~= nil
for _, group in pairs(require("openmw.animation").BONE_GROUP) do
    above = above and sneakPriority[group] > 1
end
check(above, "sneaking in first person, the katar's sneak idle is above ReAnimation's on every bone group")
selfControls.sneak = false

-- locomotion and the jump
st.played = {}
stubs.I.AnimationController.playBlendedAnimation("walkforward1s", { speed = 1, priority = 5, blendMask = 15, loops = 999 })
local walked = false
for _, p in ipairs(st.played) do if p.group == "walkforwardkatar" then walked = true end end
check(walked, "walking plays the fist's walk")
-- A loop of the same steps but another length keeps up by playing at the ratio of the two lengths:
-- ours here is 1.2 times the parent's, so it starts at 1.2 times the parent's speed and is held there.
key("walkforward1s: start", 5.6); key("walkforward1s: stop", 6.6)
key("walkforwardkatar: start", 12.2); key("walkforwardkatar: stop", 13.4)
local function walkSpeed()
    st.played = {}
    stubs.I.AnimationController.playBlendedAnimation("walkforward1s", { startKey = "start", startkey = "start",
        stopKey = "stop", stopkey = "stop", speed = 1, priority = 5, blendMask = 15, loops = 999 })
    local started
    for _, p in ipairs(st.played) do if p.group == "walkforwardkatar" then started = p.options.speed end end
    st.speeds = {}
    api.engineHandlers.onUpdate(0.016)
    return started, st.speeds.walkforwardkatar
end
local started, held = walkSpeed()
check(started and math.abs(started - 1.2) < 1e-6, "a longer loop of the same steps starts at the ratio of the lengths", started)
check(held and math.abs(held - 1.2) < 1e-6, "and is held there", held)
-- Twice the length is not the same steps, and is left to the phase nudge alone, as before.
key("walkforwardkatar: stop", 14.2)
started, held = walkSpeed()
check(started and math.abs(started - 1) < 1e-6 and held and math.abs(held - 1) < 1e-6,
      "a loop of other steps plays at the parent's speed", tostring(started) .. " " .. tostring(held))
-- Over the one-handed walk - knuckledusters', having no blunt walk - first person has the fist's laid
-- out as that walk is, three step cycles to its loop, and plays that one instead.
st.groups.walkforward1h = true
st.groups.walkforwardkatar1h = true
local function walk1h()
    st.played = {}
    stubs.I.AnimationController.playBlendedAnimation("walkforward1h", { speed = 1, priority = 5, blendMask = 15, loops = 999 })
    local groups = {}
    for _, p in ipairs(st.played) do groups[p.group] = true end
    return groups
end
local over1h = walk1h()
check(over1h["walkforwardkatar1h"] and not over1h["walkforwardkatar"],
      "over the one-handed walk, first person plays the walk laid out the one-handed way")
local function walkMask()
    for _, p in ipairs(st.played) do
        if p.group == "walkforwardkatar1h" or p.group == "walkforwardkatar" then
            return p.options.blendMask or p.options.blendmask
        end
    end
end
check(walkMask() == 15, "first person plays the whole of the walk", walkMask())
st.groups.sneakforward1h = true
st.groups.sneakforwardkatar1h = true
st.played = {}
stubs.I.AnimationController.playBlendedAnimation("sneakforward1h", { speed = 1, priority = 5, blendMask = 15, loops = 999 })
local sneak1h = {}
for _, p in ipairs(st.played) do sneak1h[p.group] = true end
check(sneak1h["sneakforwardkatar1h"] and not sneak1h["sneakforwardkatar"],
      "and over the one-handed sneak, the sneak laid out the one-handed way")
st.played = {}
stubs.I.AnimationController.playBlendedAnimation("jump1s", { startKey = "start", startkey = "start", speed = 1, priority = 5, blendMask = 15 })
local jumped = false
for _, p in ipairs(st.played) do if p.group == "jumpkatar" then jumped = true end end
check(jumped, "and jumping its jump")

-- Knuckledusters hold the fist's own guard: the knuckle set's idle, walk and jump, not the katar's.
local function played(group, options)
    st.played = {}
    stubs.I.AnimationController.playBlendedAnimation(group, options)
    local out = {}
    for _, p in ipairs(st.played) do out[p.group] = true end
    return out
end
st.equipped = { recordId = "knuckle_iron" }
local idleOpts = { startKey = "start", startkey = "start", speed = 1, priority = 0, blendMask = 15, loops = 3 }
local seenKnuckle = played("idle1s", idleOpts)
check(seenKnuckle["idleknuckle"] and not seenKnuckle["idlekatar"], "knuckledusters stand in the knuckle idle")
seenKnuckle = played("walkforward1s", { speed = 1, priority = 5, blendMask = 15, loops = 999 })
check(seenKnuckle["walkforwardknuckle"] and not seenKnuckle["walkforwardkatar"], "walk with the knuckle walk")
seenKnuckle = played("jump1s", { startKey = "start", startkey = "start", speed = 1, priority = 5, blendMask = 15 })
check(seenKnuckle["jumpknuckle"] and not seenKnuckle["jumpkatar"], "and jump with the knuckle jump")
seenKnuckle = played("weapononehand", { startKey = "slash start", startkey = "slash start", stopKey = "slash max attack",
                                        stopkey = "slash max attack", speed = 2, priority = 7, blendMask = 15 })
check(seenKnuckle["knuckle"] or seenKnuckle["knucklealt"], "swinging the knuckle set's attacks, as katars do")
follow("slash")
st.equipped = { recordId = "katar_steel" }
local seenKatar = played("idle1s", idleOpts)
check(seenKatar["idlekatar"] and not seenKatar["idleknuckle"], "katars stand in their own, wider idle")

-- A generated record - a Bound Fist scaled to its caster, Ebony Rose's burst copy, a katar someone
-- enchanted - is one too, though ReAnimation hands out its id lowercased and the engine only knows it
-- as "Generated:0x...".
st.weaponRecords["katar_daedric"] = { type = 0, model = "meshes/daedric_katar.nif" }
st.weaponRecords["generated:0x77"] = { type = 0, model = "meshes/daedric_katar.nif" }
st.equipped = { recordId = "Generated:0x77" }
follow("thrust")
groups = swing()
check(groups["knuckle"] or groups["knucklealt"], "a generated katar swings as a katar")
follow("slash")

st.equipped = { recordId = "steel dagger" }
groups = swing()
check(groups["knuckle"] ~= true, "a dagger does not swing with the hand-to-hand animation")
-- the alternation opens on the parent itself, so the second swing is ReAnimation's alternate. It only
-- counts a swing as the one before once its follow-through has played.
follow("slash")
groups = swing()
check(groups["weapononehand1"] == true, "and ReAnimation's own set takes the dagger's swings again")
follow("slash")

-- Third person - an NPC, or the player with the camera pulled back - plays the same set: the same
-- names, loaded from the third-person skeleton's folder instead.
st.cameraMode = 1
api.engineHandlers.onUpdate(0.016) -- ReAnimation looks at the view once a frame
st.equipped = { recordId = "katar_steel" }
groups = swing()
check(groups["knuckle"] or groups["knucklealt"], "in third person a katar swings with the knuckledusters' animation too")
check(groups["weapononehand1"] ~= true, "where ReAnimation has no set of its own")
follow("slash")
-- Standing still, the swing's own legs show: its lower body goes over the katar idle's, which outranks
-- the engine's idle by two there. The engine hands an attack its priorities bone group by bone group.
local function swingLegs()
    st.played = {}
    local LB = require("openmw.animation").BONE_GROUP
    local o = { startKey = "slash start", startkey = "slash start", stopKey = "slash max attack",
                stopkey = "slash max attack", speed = 2, blendMask = 15,
                priority = { [LB.LowerBody] = 1, [LB.Torso] = 7, [LB.LeftArm] = 7, [LB.RightArm] = 7 } }
    stubs.I.AnimationController.playBlendedAnimation("weapononehand", o)
    local lower
    for _, p in ipairs(st.played) do
        if p.group == "knuckle" or p.group == "knucklealt" then lower = p.options.priority[LB.LowerBody] end
    end
    follow("slash")
    return lower, o.priority[LB.LowerBody]
end
local legs, parentLegs = swingLegs()
check(legs == 3, "in third person a katar swing's legs go over the katar idle's", legs)
check(parentLegs ~= 3, "the hidden parent's are left as they were", parentLegs)
st.cameraMode = 0
api.engineHandlers.onUpdate(0.016)
legs = swingLegs()
check(legs == 1, "in first person the swing's lower body is left at the engine's", legs)
st.cameraMode = 1
api.engineHandlers.onUpdate(0.016)
over1h = walk1h()
check(over1h["walkforwardkatar"] and not over1h["walkforwardkatar1h"],
      "third person has no one-handed layout of the walk, and plays the plain one")
check(walkMask() == 15, "and the whole of it: it is made on the one-handed walk's own legs", walkMask())

-- Third person has a sneaking idle of its own, played whatever is in hand; with a katar, ours goes over it.
st.groups.idlesneak = true
st.played = {}
stubs.I.AnimationController.playBlendedAnimation("idlesneak",
    { startKey = "start", startkey = "start", speed = 1, priority = 2, blendMask = 15, loops = 999 })
local sneakIdle = false
for _, p in ipairs(st.played) do if p.group == "idlekatarsneak" then sneakIdle = true end end
check(sneakIdle, "sneaking in third person plays the katar's sneaking idle")
st.equipped = { recordId = "steel dagger" }
st.played = {}
stubs.I.AnimationController.playBlendedAnimation("idlesneak",
    { startKey = "start", startkey = "start", speed = 1, priority = 2, blendMask = 15, loops = 999 })
sneakIdle = false
for _, p in ipairs(st.played) do if p.group == "idlekatarsneak" then sneakIdle = true end end
check(not sneakIdle, "and a dagger's is left alone")

-- Under Full Body Awareness first person has a sneaking idle too, which the engine plays on while the
-- player sneaks about, two up on the legs (SneakIdleLowerBody). Ours has to stay under the sneak walk
-- there, or it wins the legs and the player cannot move; and it stops once the weapon is sheathed, as
-- that idle plays on whatever is in hand.
local animationApi = require("openmw.animation")
local LBG = animationApi.BONE_GROUP
st.cameraMode = 0
api.engineHandlers.onUpdate(0.016)
st.equipped = { recordId = "katar_steel" }
st.played = {}
stubs.I.AnimationController.playBlendedAnimation("idlesneak", { startKey = "start", startkey = "start", speed = 1,
    blendMask = 15, loops = 999,
    priority = { [LBG.LowerBody] = animationApi.PRIORITY.SneakIdleLowerBody, [LBG.Torso] = 0, [LBG.LeftArm] = 0,
                 [LBG.RightArm] = 0 } })
local fbaSneak
for _, p in ipairs(st.played) do if p.group == "idlekatarsneak" then fbaSneak = p.options end end
check(fbaSneak and fbaSneak.priority[LBG.LowerBody] < animationApi.PRIORITY.Movement,
      "under FBA, the katar's sneaking idle stays under the sneak walk on the legs",
      fbaSneak and fbaSneak.priority[LBG.LowerBody])
-- Sheathed, sneaking on: only the sneaking idles play now (the stubs take every known group to be
-- playing, which would start the walks too).
st.cancelled = {}
st.stance = 0
local allGroups = st.groups
st.groups = { idlesneak = true, idlekatarsneak = true }
api.engineHandlers.onUpdate(0.016)
st.groups = allGroups
local sheathedStop = false
for _, g in ipairs(st.cancelled) do if g == "idlekatarsneak" then sheathedStop = true end end
check(sheathedStop, "and stops when the katars are sheathed, though the sneaking idle plays on")
st.stance = 1
st.cameraMode = 1
api.engineHandlers.onUpdate(0.016)

-- Turning on the spot in third person: with a katar, ours goes over the turn as a walk does - the katar
-- idle's upper body made on the one-handed turn's legs.
st.groups.turnleft1h = true
st.groups.turnright1s = true
st.groups.turnleftkatar = true
st.groups.turnrightkatar = true
local function turned(group)
    st.played = {}
    local o = { startKey = "start", startkey = "start", speed = 1, priority = 5, blendMask = 15, loops = 999 }
    stubs.I.AnimationController.playBlendedAnimation(group, o)
    local ours
    for _, p in ipairs(st.played) do if p.group:find("katar", 1, true) then ours = p end end
    return ours, o
end
st.equipped = { recordId = "katar_steel" }
local turn, parent = turned("turnleft1h")
check(turn and turn.group == "turnleftkatar", "turning in third person with a katar plays the katar turn", turn and turn.group)
check(turn and (turn.options.blendMask or turn.options.blendmask) == 15, "whole",
      turn and (turn.options.blendMask or turn.options.blendmask))
check(parent.blendMask == 15, "over the engine's turn, left as it is", parent.blendMask)
turn = turned("turnright1s")
check(turn and turn.group == "turnrightkatar", "either way, over the short blade's turn too", turn and turn.group)
st.equipped = { recordId = "steel dagger" }
check(turned("turnleft1h") == nil, "a dagger's turn is left alone")
st.equipped = { recordId = "katar_steel" }
st.cameraMode = 0
api.engineHandlers.onUpdate(0.016)
check(turned("turnleft1h") == nil, "and first person keeps the engine's turn")

--- the idle -------------------------------------------------------------------------------------------
-- The engine plays a weapon idle for one to four loops and then plays it again. Ours loops on its own -
-- copying the count, it ran out first and stood frozen - and when the parent comes round again,
-- carries on from where it is.
local animationStub = require("openmw.animation")
local function idleStart()
    st.played = {}
    stubs.I.AnimationController.playBlendedAnimation("idle1s", { startKey = "start", startkey = "start",
        stopKey = "stop", stopkey = "stop", speed = 1, priority = 0, blendMask = 15, loops = 3, startPoint = 0.9 })
    for _, p in ipairs(st.played) do if p.group == "idlekatar" then return p.options end end
end
local idle = idleStart()
check(idle and idle.loops == 4294967295, "the katar's idle loops until it is stopped, not for the parent's count",
      idle and idle.loops)
check(idle and idle.startPoint == 0, "from its own beginning, not from where the parent is", idle and idle.startPoint)
local realCompletion = animationStub.getCompletion
animationStub.getCompletion = function(actor, group)
    if group == "idlekatar" then return 0.4 end
    return realCompletion(actor, group)
end
idle = idleStart()
check(idle and idle.startPoint == 0.4, "the parent coming round again leaves ours where it was", idle and idle.startPoint)
animationStub.getCompletion = realCompletion

-- Loaded with one out, or come into the world with it: the engine started the idle before Lua could
-- see it, so no override had its options. ReAnimation (3.3) looks once, on its first update after, and
-- takes the idle to have been played as the engine plays one; ours then starts over it.
for _, parent in ipairs({ "idle1s", "idle1b" }) do
    for _, anim in ipairs(api.interface.animations[parent]) do anim.parentOptions = nil; anim.running = false end
end
st.played = {}
api.engineHandlers.onActive()
api.engineHandlers.onUpdate(0.016)
local loadedIdle
for _, p in ipairs(st.played) do if p.group == "idlekatar" then loadedIdle = p.options end end
local BG = animationStub.BONE_GROUP
check(loadedIdle ~= nil, "loaded with a katar out, its idle starts on the first update")
check(loadedIdle and type(loadedIdle.priority) == "table" and loadedIdle.priority[BG.RightArm] == 1
      and loadedIdle.priority[BG.LowerBody] == 2, "above the idle the engine started unseen")
check(loadedIdle and loadedIdle.loops == 4294967295, "and loops until it is stopped", loadedIdle and loadedIdle.loops)
check(api.interface.animations["idle1b"][1].parentOptions == nil, "a parent that is not playing is left unknown")
st.played = {}
api.engineHandlers.onUpdate(0.016)
local again = false
for _, p in ipairs(st.played) do if p.group == "idlekatar" then again = true end end
check(not again, "and the look is once: the idle is not started over on the next update")

print(string.format("\n%d checks, %d failures", checks, fails))
os.exit(fails == 0 and 0 or 1)

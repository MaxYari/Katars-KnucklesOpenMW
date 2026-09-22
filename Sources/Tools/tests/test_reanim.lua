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

--- world setup -------------------------------------------------------------------------------------
local function key(k, t) st.textKeys[string.lower(k)] = t end
-- vanilla weapononehand (xbase_anim.1st.kf), shifted so the numbers are readable
key("weapononehand: slash start", 51.3333)
key("weapononehand: slash min attack", 51.6667)
key("weapononehand: slash max attack", 51.8000)
key("weapononehand: slash min hit", 51.9333)
key("weapononehand: slash hit", 52.1333)
key("weapononehand: slash large follow start", 52.2000)
key("weapononehand: slash large follow stop", 52.4667)
-- the katar set, cut from the hand-to-hand animations and never re-timed
key("katar: slash start", 0.0)
key("katar: slash min attack", 0.2333)
key("katar: slash max attack", 0.4667)
key("katar: slash min hit", 0.5333)
key("katar: slash hit", 0.6)
key("katar: slash large follow start", 0.6)
key("katar: slash large follow stop", 1.1333)
st.groups = { weapononehand = true, katar = true, kataralt = true, idlekatar = true, idle1s = true }
st.bones = { ["Weapon Bone.L"] = true }
st.weaponRecords["katar_steel"] = { type = 0, model = "meshes/steel_katar.nif" }
st.weaponRecords["knuckle_iron"] = { type = 3, model = "meshes/iron_knuckle.nif" }
st.weaponRecords["steel dagger"] = { type = 0, model = "meshes/w/w_dagger.nif" }

--- load the API -------------------------------------------------------------------------------------
local api = require("scripts.MaxYari.ReAnimation_v3.ReAnimationAPI")
stubs.I.ReAnimation = api.interface
check(api.interface.version == 3.2, "API version bumped", api.interface.version)
check(api.interface.TIMING_MATCHING ~= nil, "TIMING_MATCHING exported")
check(api.interface.TIMING_MATCHING.ToOverride == "toOverride", "ToOverride value")
check(api.interface.TIMING_MATCHING.None == "None", "None value")
check(type(api.interface.addOverrideCondition) == "function", "addOverrideCondition exported")

--- timing matching ------------------------------------------------------------------------------------
local katarRuns = 0
api.interface.addAttackVariants({
    id = "TestKatar",
    parentAttackGroupname = "weapononehand",
    armatureType = 1,
    timingMatching = api.interface.TIMING_MATCHING.ToOverride,
    condition = function() katarRuns = katarRuns + 1; return true end,
    attacks = { slash = { { "katar" } } },
})

local function playParent(startKey, stopKey, speed)
    st.played = {}
    local options = {
        startKey = startKey, stopKey = stopKey, startkey = startKey, stopkey = stopKey,
        speed = speed, priority = 7, blendMask = 15, autoDisable = false, loops = 0,
    }
    stubs.I.AnimationController.playBlendedAnimation("weapononehand", options)
    return options
end

local WEAPON_SPEED = 2.0
local parentOpts = playParent("slash start", "slash max attack", WEAPON_SPEED)
local override = st.played[1]
check(override and override.group == "katar", "wind up plays the katar group", override and override.group)
check(override and math.abs(override.options.speed - WEAPON_SPEED) < 1e-6,
      "override keeps the engine's speed", override and override.options.speed)
check(math.abs(parentOpts.speed - WEAPON_SPEED * (0.4667 / 0.4667)) < 1e-3,
      "wind up: same length, so the parent keeps its speed", parentOpts.speed)
check(parentOpts.blendMask == 0, "parent is hidden")

parentOpts = playParent("slash max attack", "slash hit", WEAPON_SPEED)
check(math.abs(parentOpts.speed - WEAPON_SPEED * (0.3333 / 0.1333)) < 1e-2,
      "release: parent sped up to the katar's shorter section", parentOpts.speed)
-- what the test is really asserting: both sections take the same wall time
local parentWall = 0.3333 / parentOpts.speed
local overrideWall = 0.1333 / WEAPON_SPEED
check(math.abs(parentWall - overrideWall) < 1e-4, "release wall times agree", parentWall .. " vs " .. overrideWall)

parentOpts = playParent("slash large follow start", "slash large follow stop", WEAPON_SPEED)
check(math.abs(parentOpts.speed - WEAPON_SPEED * (0.2667 / 0.5333)) < 1e-2,
      "follow through: parent slowed to the katar's longer section", parentOpts.speed)
parentWall = 0.2667 / parentOpts.speed
overrideWall = 0.5333 / WEAPON_SPEED
check(math.abs(parentWall - overrideWall) < 1e-4, "follow wall times agree", parentWall .. " vs " .. overrideWall)

--- timingMatching = None leaves the parent alone -------------------------------------------------------
api.interface.addAttackVariants({
    id = "TestPlain",
    parentAttackGroupname = "weapontwohand",
    armatureType = 1,
    attacks = { slash = { { "katar" } } },
})
st.groups.weapontwohand = true
key("weapontwohand: slash start", 10)
key("weapontwohand: slash max attack", 11)
st.played = {}
local plainOpts = {
    startKey = "slash start", stopKey = "slash max attack", startkey = "slash start",
    stopkey = "slash max attack", speed = 3, priority = 7, blendMask = 15,
}
stubs.I.AnimationController.playBlendedAnimation("weapontwohand", plainOpts)
check(plainOpts.speed == 3, "default timing matching does not touch the parent's speed", plainOpts.speed)

--- extra conditions ---------------------------------------------------------------------------------
local allow = true
api.interface.addOverrideCondition("TestKatar", function() return allow end)
allow = false
katarRuns = 0
st.played = {}
playParent("slash start", "slash max attack", WEAPON_SPEED)
-- the stub logs the parent's own play too, so one entry means only the parent ran
check(#st.played == 1, "a vetoed set plays nothing of its own", #st.played)
check(st.played[1].group == "weapononehand", "only the parent was played", st.played[1].group)
check(katarRuns == 0, "a vetoed set never reaches its own condition", katarRuns)

allow = true
st.played = {}
playParent("slash start", "slash max attack", WEAPON_SPEED)
check(#st.played == 2 and st.played[1].group == "katar", "the veto lifts again", #st.played)

check(api.interface.removeOverrideCondition("TestKatar", function() end) == false,
      "removing a condition that was never added returns false")

print(string.format("\n%d checks, %d failures", checks, fails))
os.exit(fails == 0 and 0 or 1)

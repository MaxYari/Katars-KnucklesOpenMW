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

--- override ranking ---------------------------------------------------------------------------------
-- The general set is registered first, the way ReAnimation's own loads before a weapon mod's.
st.groups.rankgeneral = true
st.groups.rankspecial = true
st.groups.ranklayer = true
local specialWanted = true
local generalAsked = 0
api.interface.addAttackVariants({
    id = "RankGeneral",
    parentAttackGroupname = "rankparent",
    armatureType = 1,
    condition = function() generalAsked = generalAsked + 1; return true end,
    attacks = { slash = { { "rankgeneral" } }, chop = { { "rankgeneral" } } },
})
api.interface.addAttackVariants({
    id = "RankSpecial",
    parentAttackGroupname = "rankparent",
    armatureType = 1,
    overridePriority = 1,
    condition = function() return specialWanted end,
    attacks = { slash = { { "rankspecial" } } },
})
-- An unranked override on the same parent, which the ranking must leave alone.
api.interface.addAnimationOverride({
    id = "RankLayer",
    parent = "rankparent",
    groupname = "ranklayer",
    armatureType = 1,
    condition = function() return true end,
    options = function() return {} end,
    startOnAnimEvent = true,
})

local ranked = api.interface.animations.rankparent
check(ranked[1].id == "RankSpecial" and ranked[2].id == "RankGeneral" and ranked[3].id == "RankLayer",
      "a higher rank is asked first, whatever the registration order")
local general = ranked[2]

local function playRanked(attackType)
    st.played = {}
    local startKey, stopKey = attackType .. " start", attackType .. " max attack"
    stubs.I.AnimationController.playBlendedAnimation("rankparent", {
        startKey = startKey, stopKey = stopKey, startkey = startKey, stopkey = stopKey,
        speed = 1, priority = 7, blendMask = 15,
    })
    local groups = {}
    for _, p in ipairs(st.played) do groups[p.group] = true end
    return groups
end

local g = playRanked("slash")
check(g.rankspecial and not g.rankgeneral, "the higher set takes an attack it lists, the lower stands down")
check(generalAsked == 0, "and the lower set is not even asked", generalAsked)
check(g.ranklayer, "an unranked override on the same parent still plays")
check(general.enabled == false, "an outranked set does not claim the parent is hidden")

g = playRanked("chop")
check(g.rankgeneral and not g.rankspecial, "an attack type the higher set does not list goes to the lower one")

specialWanted = false
g = playRanked("slash")
check(g.rankgeneral and not g.rankspecial, "the lower set plays again once the higher's condition fails")
check(general.running == true, "and is left running")

specialWanted = true
st.cancelled = {}
g = playRanked("slash")
check(g.rankspecial and not g.rankgeneral, "the higher set takes over again")
local handlerCancelledGeneral = false
for _, group in ipairs(st.cancelled) do handlerCancelledGeneral = handlerCancelledGeneral or group == "rankgeneral" end
check(general.running == true and not handlerCancelledGeneral,
      "the handler leaves the running lower set alone", table.concat(st.cancelled, ","))

-- The parent is still playing, so what stops the lower set here is the ranking alone.
st.groups.rankparent = true
st.cancelled = {}
api.engineHandlers.onUpdate(0.016)
check(general.running == false and #st.cancelled == 1 and st.cancelled[1] == "rankgeneral",
      "onUpdate stops the outranked set that was still running", table.concat(st.cancelled, ","))
check(ranked[1].running == true, "and leaves the higher one running")

--- ranking on the poll path ----------------------------------------------------------------------------
-- Three polled overrides on one parent, registered out of rank order.
local want, asked = {}, {}
local function pollOverride(id, rank)
    st.groups[id] = true
    asked[id] = 0
    api.interface.addAnimationOverride({
        id = id,
        parent = "pollparent",
        groupname = id,
        armatureType = 1,
        stance = api.interface.STANCE.Any,
        overridePriority = rank,
        condition = function() asked[id] = asked[id] + 1; return want[id] == true end,
        stopCondition = function(self) return not self:condition() end,
        options = function() return {} end,
        startOnUpdate = true,
    })
end
pollOverride("polllow", 0)
pollOverride("pollhigh", 2)
pollOverride("pollmid", 1)
st.groups.pollparent = true

local function tick() api.engineHandlers.onUpdate(0.016) end
local function runningIds()
    local out = {}
    for _, a in ipairs(api.interface.animations.pollparent) do
        if a.running then out[#out + 1] = a.id end
    end
    return table.concat(out, ",")
end

-- New registrations are polled once the tracked list is rebuilt, which a stance change does. The
-- parent's play also hands them their parentOptions.
st.stance = 0
tick()
stubs.I.AnimationController.playBlendedAnimation("pollparent", { priority = 5 })
st.stance = 1

want.polllow = true
tick()
check(runningIds() == "polllow", "the only one wanting starts", runningIds())

want.pollhigh, want.pollmid = true, true
tick()
check(runningIds() == "pollhigh", "the highest one wanting takes over in one frame, the others stop", runningIds())

asked.polllow, asked.pollmid = 0, 0
tick(); tick()
check(asked.polllow == 0 and asked.pollmid == 0, "lower ones are not asked while a higher one runs",
      asked.polllow .. "," .. asked.pollmid)

want.pollhigh = false
tick()
check(runningIds() == "pollmid", "when it stops, the next one down starts in the same frame", runningIds())

want.pollmid = false
tick()
check(runningIds() == "polllow", "and the one below that", runningIds())

print(string.format("\n%d checks, %d failures", checks, fails))
os.exit(fails == 0 and 0 or 1)

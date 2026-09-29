-- Creatures: ReAnimation's API, animations.lua and npc.lua on a creature - nothing at all on one that
-- cannot hold these weapons, not even a handler, and everything an NPC gets on one that can - and a
-- creature's fists, its Combat, in the fatigue damage a katar adds.
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
local function near(a, b) return a ~= nil and math.abs(a - b) < 1e-6 end

local API = "scripts.MaxYari.ReAnimation_v3.ReAnimationAPI"
local ANIMATIONS = "scripts.MaxYari.H2HWeapons.animations"
local NPC = "scripts.MaxYari.H2HWeapons.npc"

local function load(name)
    package.loaded[name] = nil
    return require(name)
end

local function count(t)
    local n = 0
    for _ in pairs(t) do n = n + 1 end
    return n
end

-- These run on a creature.
local selfHandle = require('openmw.self')
selfHandle.notPlayer = true
selfHandle.object.notPlayer = true
local function become(record)
    selfHandle.creature, selfHandle.object.creature = record, record
end

-- A creature that cannot hold them: nothing is loaded past the first lines, and nothing is left
-- behind to run - no play or text key handler, no interface, no engine handler.
for _, case in ipairs({
    { "a rat", { isBiped = false, canUseWeapons = false, combatSkill = 10 } },
    { "a two-legged creature with no weapons (Vivec)", { isBiped = true, canUseWeapons = false, combatSkill = 100 } },
    { "a creature with weapons but no legs to stand on", { isBiped = false, canUseWeapons = true, combatSkill = 30 } },
}) do
    local name, record = case[1], case[2]
    become(record)
    local plays, keys = #stubs.playHandlers, #stubs.textKeyHandlers + count(stubs.textKeyHandlersByGroup)
    check(load(API) == true, name .. ": ReAnimation's API returns nothing")
    check(load(ANIMATIONS) == true, name .. ": animations.lua returns nothing")
    check(load(NPC) == true, name .. ": npc.lua returns nothing")
    check(#stubs.playHandlers == plays and #stubs.textKeyHandlers + count(stubs.textKeyHandlersByGroup) == keys,
          name .. ": and no handler is left registered")
end
check(stubs.I.ReAnimation == nil, "and no ReAnimation interface is ever put up for one")

-- A skeleton, or a dremora: all of it, as an NPC gets it.
become({ isBiped = true, canUseWeapons = true, combatSkill = 40 })
local plays = #stubs.playHandlers
local api = load(API)
check(type(api) == "table" and api.interface ~= nil, "a skeleton gets ReAnimation's API")
check(api.engineHandlers and api.engineHandlers.onUpdate ~= nil, "with its update, as an NPC's")
-- Two: the override handler, and anim_manager's mirror of what is playing, loaded here for the first time.
check(#stubs.playHandlers == plays + 2, "and its play handlers", #stubs.playHandlers - plays)
stubs.I.ReAnimation = api.interface
load(ANIMATIONS)
check(api.interface.animations["idle1s"] ~= nil and api.interface.animations["weapononehand"] ~= nil,
      "the katar's idle and attacks register on it")
local npc = load(NPC)
check(type(npc) == "table" and npc.eventHandlers.H2HWeapons_Reattach ~= nil and npc.engineHandlers.onActive ~= nil,
      "and npc.lua looks after its off hand")
check(npc.engineHandlers.onUpdate == nil and (npc.engineHandlers.onFrame == nil),
      "without a per-frame handler, as on an NPC")

-- A creature's katar bruises as its fists would: its Combat stands for every combat skill.
local formulas = require("scripts.MaxYari.H2HWeapons.scripts.formulas")
local dremora = stubs.object({ name = "dremora", creature = { isBiped = true, canUseWeapons = true, combatSkill = 50 } })
check(near(formulas.handToHandFatigue(dremora, 1, 0), 50 * st.gmst.fMaxHandToHandMult),
      "a creature's full swing: Combat x fMaxHandToHandMult", formulas.handToHandFatigue(dremora, 1, 0))
check(near(formulas.handToHandFatigue(dremora, 0, 0), 50 * st.gmst.fMinHandToHandMult),
      "and a tap: Combat x fMinHandToHandMult", formulas.handToHandFatigue(dremora, 0, 0))
local weakling = stubs.object({ name = "weakling", creature = { isBiped = true, canUseWeapons = true, combatSkill = 0 } })
check(formulas.handToHandFatigue(weakling, 1, 0) == 0, "no Combat, no bruising")

print(string.format("\n%d checks, %d failures", checks, fails))
os.exit(fails == 0 and 0 or 1)

-- NPCs: the off-hand weapon, Ebony Rose's burst and the draw sound on an NPC (npc.lua), and the Rose's
-- owner being handed it (global.lua).
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

local U = require("scripts/MaxYari/H2HWeapons/scripts/uniques")

st.weaponRecords["katar_steel"] = { type = 0, model = "meshes/steel_katar.nif" }
st.weaponRecords["steel dagger"] = { type = 0, model = "meshes/w/w_dagger.nif" }
st.weaponRecords["katar_ebony_rose"] = { type = 0, model = "meshes/ebony_rose.nif", enchant = "h2h_ebonyrose_en" }
st.weaponRecords["generated:0x99"] = { type = 0, model = "meshes/ebony_rose.nif", enchant = "h2h_ebonyrose_burst_en" }
st.bones = { ["Weapon Bone"] = true, ["Weapon Bone.L"] = true }

-- This script runs on an NPC.
local selfHandle = require('openmw.self')
selfHandle.notPlayer = true
selfHandle.object.notPlayer = true
local me = selfHandle.object

local function item(recordId)
    return stubs.object({ recordId = recordId, isItem = true, parentContainer = me })
end
local katar, dagger, rose = item("katar_steel"), item("steel dagger"), item("katar_ebony_rose")

local npc = require("scripts.MaxYari.H2HWeapons.npc")
local E = npc.engineHandlers
local fire = function(name, data) npc.eventHandlers[name](data) end
local function offHand() return st.vfxById["H2HWeapons_OffHand"] end
local function key(k) stubs.textKey("weapononehand", k) end
local function play(startKey)
    stubs.I.AnimationController.playBlendedAnimation("weapononehand",
        { startKey = startKey, startkey = startKey, stopKey = "x", stopkey = "x", speed = 1, priority = 7, blendMask = 15 })
end
local function lastGlobal(name)
    for i = #st.globalEvents, 1, -1 do
        if st.globalEvents[i].name == name then return st.globalEvents[i].data end
    end
end

check(npc.engineHandlers.onUpdate == nil, "no per-frame handler: this runs on every NPC")

--- The off hand ------------------------------------------------------------------------------------
st.equipped = katar
st.stance = 0
E.onActive()
stubs.advance(0.2)
check(offHand() == nil, "a katar at the belt shows nothing in the off hand")

st.stance = 1
key("equip attach")
check(offHand() and offHand().model == "meshes/steel_katar.nif", "drawn, the off hand shows a copy of it",
      offHand() and offHand().model)
check(offHand() and offHand().opts.boneName == "Weapon Bone.L" and offHand().opts.loop == true,
      "hung on the left weapon bone, for as long as it is out")

st.stance = 0
stubs.advance(0.6)
check(offHand() ~= nil, "a sheathe that has begun still shows it, the right hand does too")
key("unequip detach")
check(offHand() == nil, "until the hand puts the weapon away")
stubs.advance(5)
check(#st.timers == 0, "and with nothing out, nothing is looked at", #st.timers)

-- A swap to another short blade plays no animation, and neither does a weapon taken off a corpse.
st.stance = 1
key("equip attach")
st.equipped = dagger
stubs.advance(0.6)
check(offHand() == nil, "a swap to a dagger takes it away within half a second")
st.equipped = katar
stubs.advance(0.6)
check(offHand() ~= nil, "and a swap back brings it back")
st.equipped = nil
stubs.advance(0.6)
check(offHand() == nil, "an empty hand shows nothing")
st.equipped = katar
stubs.advance(0.6)

-- A stance a script changed, with no animation and so no key.
st.stance = 0
stubs.advance(1.0)
check(offHand() ~= nil, "a stance left without a key is given a moment")
stubs.advance(1.5)
check(offHand() == nil, "then taken as it is")

-- Coming into the world with the weapon out: no key comes, the stance says it.
st.stance = 1
st.vfxById = {}
E.onInactive()
E.onActive()
stubs.advance(0.2)
check(offHand() ~= nil, "an NPC coming into the world with a katar out shows the off hand")

-- The player rested nearby: everything on the bones is gone and goes back on.
st.vfxById = {}
fire("H2HWeapons_Reattach", {})
check(offHand() ~= nil, "after the player rests nearby it goes back on")

local section = stubs.section("SettingsGlobalH2HWeapons")
section:set("showOffHandWeapon", false)
stubs.advance(0.6)
check(offHand() == nil, "the setting to show it is followed")
section:set("showOffHandWeapon", true)
stubs.advance(0.6)
check(offHand() ~= nil, "both ways")

-- Out of the world, nothing is touched.
E.onInactive()
st.vfxById = {}
stubs.advance(2)
check(offHand() == nil and #st.timers == 0, "an NPC out of the world is left alone, and stops looking")
E.onActive()
stubs.advance(0.2)

--- Draw and sheathe sound --------------------------------------------------------------------------
st.stoppedSounds = {}
play("equip start")
stubs.advance(0.2)
check(st.stoppedSounds[1] == "Item Weapon Shortblade Up", "a katar's draw sound is stopped", st.stoppedSounds[1])
st.stoppedSounds = {}
st.equipped = dagger
play("unequip start")
stubs.advance(0.2)
check(#st.stoppedSounds == 0, "a dagger's is not")
st.equipped = katar

--- Ebony Rose -------------------------------------------------------------------------------------
st.equipped = rose
stubs.advance(0.6)
local enemy = stubs.object({ name = "enemy" })
st.effects[U.VENOM_EFFECT] = 3
fire("H2HWeapons_VenomStrike", { victim = enemy })
stubs.advance(1)
fire("H2HWeapons_VenomStrike", { victim = enemy })
st.globalEvents = {}
play("slash start")
local staged = lastGlobal("H2HWeapons_StageBurst")
check(staged and staged.item == rose and staged.actor == me, "an NPC's third strike on the poisoned asks for the burst")
local copy = stubs.object({ recordId = "Generated:0x99", isItem = true, parentContainer = me })
fire("H2HWeapons_BurstStaged", { original = rose, copy = copy })
check(st.equipped == copy, "and swings with the copy")
check(offHand() and offHand().model == "meshes/ebony_rose.nif", "the off hand showing the Rose all the while")
play("slash large follow start")
check(st.equipped == rose, "the follow-through puts the Rose back")
check(lastGlobal("H2HWeapons_BurstDone") and lastGlobal("H2HWeapons_BurstDone").copy == copy,
      "and hands the copy back")
fire("H2HWeapons_VenomStrike", { burst = true })

-- Sheathed mid-swing, with nothing else to end it.
for _ = 1, 2 do
    stubs.advance(1)
    fire("H2HWeapons_VenomStrike", { victim = enemy })
end
play("chop start")
fire("H2HWeapons_BurstStaged", { original = rose, copy = copy })
check(st.equipped == copy, "copy in hand")
st.stance = 0
stubs.advance(0.6)
check(st.equipped == rose, "an NPC who sheathes mid-swing gets the Rose back")
st.stance = 1
key("equip attach")

-- A save taken with the copy in hand.
for _ = 1, 2 do
    stubs.advance(1)
    fire("H2HWeapons_VenomStrike", { victim = enemy })
end
play("thrust start")
fire("H2HWeapons_BurstStaged", { original = rose, copy = copy })
local saved = E.onSave()
check(saved and saved.burstSwap and saved.burstSwap.copy == copy, "a save mid-swing remembers the copy")
st.equipped = copy
E.onLoad(saved)
stubs.advance(0.2)
check(st.equipped == rose, "and the load puts the Rose back")
check(E.onSave() == nil, "an NPC with nothing going on saves nothing")

-- An ordinary katar never asks.
st.equipped = katar
st.globalEvents = {}
play("slash start")
play("slash large follow start")
check(lastGlobal("H2HWeapons_StageBurst") == nil, "an ordinary katar's swing is an ordinary swing")

--- Handed a weapon --------------------------------------------------------------------------------
fire("H2HWeapons_Wield", { item = rose })
check(st.equipped == rose, "a weapon handed over goes in the hand")
local elsewhere = stubs.object({ recordId = "katar_steel", isItem = true, parentContainer = stubs.object({}) })
fire("H2HWeapons_Wield", { item = elsewhere })
check(st.equipped == rose, "one that is not in the inventory does not")

--- Ebony Rose's owner (global.lua) ----------------------------------------------------------------
local global = require("scripts.MaxYari.H2HWeapons.global")
local onActorActive = global.engineHandlers.onActorActive
local dandras = stubs.object({ recordId = "Dandras Vules" })
local jinkblade = stubs.object({ recordId = "adamantium_shortsword_db", isItem = true, data = { enchantmentCharge = 90 } })
st.inventories[dandras] = { jinkblade }
st.events = {}
onActorActive(stubs.object({ recordId = "fargoth" }))
check(#st.events == 0, "nobody else is handed anything")
onActorActive(dandras)
local given
for _, i in ipairs(st.inventories[dandras]) do if i.recordId == U.EBONY_ROSE then given = i end end
check(given ~= nil, "Dandras Vules is handed the Rose")
local wield = stubs.eventsNamed("H2HWeapons_Wield")[1]
check(wield and wield.target == dandras and wield.data.item == given, "and told to take it in hand")
check(jinkblade.data.enchantmentCharge == 0, "his Jinkblade is left without charge, so the AI fights with the Rose")

jinkblade.data.enchantmentCharge = 30
st.events = {}
onActorActive(dandras)
local roses = 0
for _, i in ipairs(st.inventories[dandras]) do if i.recordId == U.EBONY_ROSE then roses = roses + 1 end end
check(roses == 1 and #st.events == 0, "only once")
check(jinkblade.data.enchantmentCharge == 0, "but the Jinkblade is emptied each time he comes back")

-- A copy, as the engine's save would be.
local data = {}
for k, v in pairs(global.engineHandlers.onSave()) do data[k] = v end
check(data.roseGiven == true, "the gift is kept in the save")
global.engineHandlers.onLoad({ roseGiven = false })
global.engineHandlers.onLoad(data)
onActorActive(dandras)
roses = 0
for _, i in ipairs(st.inventories[dandras]) do if i.recordId == U.EBONY_ROSE then roses = roses + 1 end end
check(roses == 1, "and a load does not give it again")

given.isValid = function() return false end -- taken off him
jinkblade.data.enchantmentCharge = 30
onActorActive(dandras)
check(jinkblade.data.enchantmentCharge == 30, "without the Rose he keeps his Jinkblade's charge")
given.isValid = function() return true end
dandras.dead = true
onActorActive(dandras)
check(jinkblade.data.enchantmentCharge == 30, "and a dead man's is left alone")

-- Met dead the first time: the Rose is on his body, and he is told nothing.
global.engineHandlers.onLoad({ roseGiven = false })
local corpse = stubs.object({ recordId = "dandras vules", dead = true })
st.events = {}
onActorActive(corpse)
check(st.inventories[corpse] and st.inventories[corpse][1].recordId == U.EBONY_ROSE and #st.events == 0,
      "one met dead has it on the body")

-- Without Katar.omwaddon's records, nothing.
global.engineHandlers.onLoad({ roseGiven = false })
local record = st.weaponRecords["katar_ebony_rose"]
st.weaponRecords["katar_ebony_rose"] = nil
local another = stubs.object({ recordId = "dandras vules" })
onActorActive(another)
check(st.inventories[another] == nil, "with the plugin off, nobody is handed a weapon that does not exist")
st.weaponRecords["katar_ebony_rose"] = record

print(string.format("\n%d checks, %d failures", checks, fails))
os.exit(fails == 0 and 0 or 1)

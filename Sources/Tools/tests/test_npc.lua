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

-- Out of the world, nothing is touched.
E.onInactive()
st.vfxById = {}
stubs.advance(2)
check(offHand() == nil and #st.timers == 0, "an NPC out of the world is left alone, and stops looking")
E.onActive()
stubs.advance(0.2)

--- The left hand -----------------------------------------------------------------------------------
-- A katar takes both hands, as bare fists do: a shield or torch comes off while it is out, and goes
-- back once it is put away.
local torch, shield, spare = item("torch_01"), item("iron_shield"), item("torch_01")
torch.count, shield.count, spare.count = 1, 1, 3
st.inventories[selfHandle] = { torch, shield, spare }

st.left = shield
stubs.advance(0.6)
check(st.left == nil, "a shield comes off while a katar is out")
st.left = torch -- the engine, somewhere dark, putting a light back in the hand
stubs.advance(0.6)
check(st.left == nil, "and whatever the engine puts back comes off within half a second")
st.stance = 0
stubs.advance(0.3)
check(st.left == nil, "still off while the sheathe is on its way")
key("unequip detach")
stubs.advance(0.01)
check(st.left == torch, "put away, the last one taken off goes back", st.left and st.left.recordId)
stubs.advance(1)
check(#st.timers == 0, "and with the katar away, nothing is looked at", #st.timers)
stubs.advance(2)
check(st.left == torch, "a torch beside a katar at the belt stays in hand")

st.stance = 1
play("equip start")
check(st.left == nil, "drawing takes it off at once")
key("equip attach")
st.equipped = dagger
stubs.advance(0.6)
check(st.left == torch, "a swap to a dagger gives the left hand back")
st.equipped = katar
stubs.advance(0.6)
check(st.left == nil, "and a swap back, with no animation, takes it off within half a second")

-- Equipping a two-handed weapon takes the shield or torch off, so a swap to one gives nothing back.
st.weaponRecords["steel claymore"] = { type = 2, model = "meshes/w/w_claymore.nif" }
st.equipped = item("steel claymore")
stubs.advance(0.6)
check(st.left == nil, "a swap to a two-handed weapon leaves the left hand empty, as equipping one does")
st.left = torch
st.equipped = katar
stubs.advance(0.6)
check(st.left == nil, "and a torch put in beside it comes off again with the katar back")

-- Taking a torch off can stack it back in with the others of its kind, and that object is gone.
torch.isValid = function() return false end
st.stance = 0
key("unequip detach")
stubs.advance(0.01)
check(st.left == spare, "one stacked back in with the rest: another of them goes back")
torch.isValid = function() return true end

st.stance = 1
play("equip start")
key("equip attach")
spare.parentContainer = stubs.object({})
st.stance = 0
key("unequip detach")
stubs.advance(0.01)
check(st.left == nil, "one dropped meanwhile is gone, as it would be from the hand")
spare.parentContainer = me

st.left = shield
st.stance = 1
play("equip start")
key("equip attach")
selfHandle.dead = true
stubs.advance(0.01)
st.stance = 0
key("unequip detach")
stubs.advance(0.6)
check(st.left == nil, "one who dies with it out keeps what came off in the inventory")
check(#st.timers == 0, "and is not looked at any longer", #st.timers)
selfHandle.dead = nil

st.left = shield
st.stance = 1
play("equip start")
key("equip attach")
local savedLeft = E.onSave()
check(savedLeft and savedLeft.leftHand and savedLeft.leftHand.item == shield,
      "a save with it out remembers what came off")
E.onInactive()
st.stance = 0
stubs.advance(0.1)
E.onLoad(savedLeft)
E.onActive()
stubs.advance(0.2)
check(st.left == shield, "and one loaded with the katar away puts it back")

st.left = nil
st.stance = 1
key("equip attach")
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
local staged = lastGlobal("H2HWeapons_StageCopy")
check(staged and staged.item == rose and staged.actor == me and staged.enchant == "h2h_ebonyrose_burst_en",
      "an NPC's third strike on the poisoned asks for the burst")
local copy = stubs.object({ recordId = "Generated:0x99", isItem = true, parentContainer = me })
fire("H2HWeapons_CopyStaged", { original = rose, copy = copy })
check(st.equipped == copy, "and swings with the copy")
check(offHand() and offHand().model == "meshes/ebony_rose.nif", "the off hand showing the Rose all the while")
play("slash large follow start")
check(st.equipped == rose, "the follow-through puts the Rose back")
check(lastGlobal("H2HWeapons_CopyDone") and lastGlobal("H2HWeapons_CopyDone").copy == copy,
      "and hands the copy back")
fire("H2HWeapons_VenomStrike", { burst = true })

-- Sheathed mid-swing, with nothing else to end it.
for _ = 1, 2 do
    stubs.advance(1)
    fire("H2HWeapons_VenomStrike", { victim = enemy })
end
play("chop start")
fire("H2HWeapons_CopyStaged", { original = rose, copy = copy })
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
fire("H2HWeapons_CopyStaged", { original = rose, copy = copy })
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
check(lastGlobal("H2HWeapons_StageCopy") == nil, "an ordinary katar's swing is an ordinary swing")

--- Ebony Rose's owner (global.lua) ----------------------------------------------------------------
local global = require("scripts.MaxYari.H2HWeapons.global")
local onActorActive = global.engineHandlers.onActorActive
st.weaponRecords["adamantium_shortsword_db"] = { type = 0, model = "meshes/w/w_adamantium_shortsword.nif",
                                                  enchant = "db_poison" }
st.enchantRecords["db_poison"] = { cost = 45, charge = 90 }
local dandras = stubs.object({ recordId = "Dandras Vules" })
local jinkblade = stubs.object({ recordId = "adamantium_shortsword_db", isItem = true, data = { enchantmentCharge = 0 } })
st.inventories[dandras] = { jinkblade }
-- The Rose placed in his room, and one the player left there.
local function lying(fields)
    fields.recordId, fields.isItem, fields.count = "katar_ebony_rose", true, 1
    fields.remove = function(self) self.count = 0; self.removed = true end
    return stubs.object(fields)
end
local placed, dropped = lying({ contentFile = U.ROOM_ROSE_CONTENT }), lying({})
st.cells[U.ROOM_ROSE_CELL] = { getAll = function() return { placed, dropped } end }
local function roses()
    local n = 0
    for _, i in ipairs(st.inventories[dandras]) do if i.recordId == U.EBONY_ROSE then n = n + 1 end end
    return n
end

st.missingContent[U.MERCY_CONTENT] = true
st.events = {}
onActorActive(dandras)
check(roses() == 0, "without Mercy he is not handed the Rose")
check(not placed.removed, "and the one in his room stays where it is")
check(jinkblade.data.enchantmentCharge == 0, "and his Jinkblade is left alone")
st.missingContent[U.MERCY_CONTENT] = nil

onActorActive(stubs.object({ recordId = "fargoth" }))
check(not placed.removed and #st.events == 0, "nobody else is handed anything")
onActorActive(dandras)
check(roses() == 1, "with Mercy, Dandras Vules is handed the Rose")
check(#st.events == 0, "and not told to take it in hand: he opens with the Jinkblade (roseowner.lua)")
check(placed.removed, "the one in his room goes")
check(not dropped.removed, "but not one that came to lie there from elsewhere")
check(jinkblade.data.enchantmentCharge == 90, "and the charge an older save drained is put back")

jinkblade.data.enchantmentCharge = 30
onActorActive(dandras)
check(roses() == 1, "only once")
check(jinkblade.data.enchantmentCharge == 30, "and the charge only once")

-- A copy, as the engine's save would be.
local data = {}
for k, v in pairs(global.engineHandlers.onSave()) do data[k] = v end
check(data.roseGiven == true and data.jinkbladeRecharged == true, "both are kept in the save")
global.engineHandlers.onLoad({ roseGiven = false })
global.engineHandlers.onLoad(data)
onActorActive(dandras)
check(roses() == 1 and jinkblade.data.enchantmentCharge == 30, "and a load does neither again")

global.engineHandlers.onLoad({})
local body = stubs.object({ recordId = "dandras vules", dead = true })
st.inventories[body] = {}
onActorActive(body)
local onBody = false
for _, i in ipairs(st.inventories[body]) do if i.recordId == U.EBONY_ROSE then onBody = true end end
check(onBody, "dead by the time he comes into the world, it is on his body")

print(string.format("\n%d checks, %d failures", checks, fails))
os.exit(fails == 0 and 0 or 1)

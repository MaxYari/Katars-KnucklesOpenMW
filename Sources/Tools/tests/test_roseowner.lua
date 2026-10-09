-- Ebony Rose's owner fighting with both his blades under Mercy (roseowner.lua, through npc.lua).
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
local owner = require("scripts/MaxYari/H2HWeapons/scripts/roseowner")

--- The choice itself -------------------------------------------------------------------------------
local J, RO = owner.JINKBLADE, owner.ROSE
local function choose(t)
    local s = { holding = nil, fresh = false, now = 100, roseSince = nil, swings = 0, charged = true,
                paralyzed = false, hasRose = true, hasJinkblade = true }
    for k, v in pairs(t) do s[k] = v end
    return owner.choose(s)
end
check(choose({ fresh = true }) == J, "a fight opens with the Jinkblade")
check(choose({ fresh = true, holding = RO, roseSince = 99 }) == J, "even with the Rose in hand")
check(choose({ fresh = true, charged = false }) == RO, "but with the Rose if the Jinkblade has no strike's charge")
check(choose({ holding = J, swings = 7 }) == nil, "the Jinkblade is kept for seven swings")
check(choose({ holding = J, swings = U.ROSE_OWNER_SWINGS }) == RO, "and given up after eight")
check(choose({ holding = J, paralyzed = true }) == RO, "or as soon as the enemy is paralysed")
check(choose({ holding = J, charged = false }) == RO, "or its charge is too low for one more")
check(choose({ holding = J, charged = false, hasRose = false }) == nil, "unless there is no Rose to turn to")
check(choose({ holding = RO, roseSince = 95 }) == nil, "the Rose is held at least ten seconds")
check(choose({ holding = RO, roseSince = 90 }) == J, "and then the Jinkblade comes back")
check(choose({ holding = RO, roseSince = 80, paralyzed = true }) == nil, "not while the enemy is paralysed")
check(choose({ holding = RO, roseSince = 80, charged = false }) == nil, "nor once its charge has run out")

--- As a step of Mercy's melee fight ---------------------------------------------------------------
st.weaponRecords["katar_ebony_rose"] = { type = 0, model = "meshes/ebony_rose.nif", enchant = "h2h_ebonyrose_en" }
st.weaponRecords["generated:0x99"] = { type = 0, model = "meshes/ebony_rose.nif", enchant = "h2h_ebonyrose_burst_en" }
st.weaponRecords["adamantium_shortsword_db"] = { type = 0, model = "meshes/w/w_adamantium_shortsword.nif",
                                                  enchant = "db_poison" }
st.enchantRecords["db_poison"] = { cost = 45, charge = 90 }
st.skills.enchant = { base = 60, modifier = 0, damage = 0 } -- a cast costs him 45 - 22.5: 22

local registered = {}
stubs.I.MercyCAO = { addExtension = function(tree, combatState, stance, extension)
    table.insert(registered, { point = tree .. ":" .. combatState .. "_" .. stance, extension = extension })
end }

local selfHandle = require('openmw.self')
selfHandle.notPlayer = true
selfHandle.object.notPlayer = true
selfHandle.recordId = "Dandras Vules"
local me = selfHandle.object
local function item(recordId, data)
    return stubs.object({ recordId = recordId, isItem = true, parentContainer = me, data = data })
end
local jinkblade = item("adamantium_shortsword_db", { enchantmentCharge = 90 })
local rose = item("katar_ebony_rose")
local burstCopy = item("Generated:0x99")
st.inventories[selfHandle] = { jinkblade, rose }

require("scripts.MaxYari.H2HWeapons.npc")
check(#registered == 1 and registered[1].point == "Combat:FIGHT_Melee",
      "the step goes into Mercy's melee fight", registered[1] and registered[1].point)

local enemy = stubs.object({ recordId = "player" })
local finished
local function step()
    finished = nil
    registered[1].extension.run({
        success = function() finished = "success" end,
        fail = function() finished = "fail" end,
        running = function() finished = "running" end,
    }, { enemyActor = enemy })
end
local function play(startKey)
    stubs.I.AnimationController.playBlendedAnimation("weapononehand",
        { startKey = startKey, startkey = startKey, stopKey = "x", stopkey = "x", speed = 1, priority = 7, blendMask = 15 })
end

st.stance = 1
st.equipped = rose
step()
check(st.equipped == jinkblade, "he opens the fight with the Jinkblade, whatever was in hand")
check(finished == "success", "and Mercy goes on to the attack at once")

for _ = 1, 7 do play("chop start") end
stubs.advance(5)
step()
check(st.equipped == jinkblade, "seven swings without paralysis keep the Jinkblade")
play("chop start")
step()
check(st.equipped == rose, "the eighth turns him to the Rose")

stubs.advance(9)
step()
check(st.equipped == rose, "he keeps it for ten seconds")
stubs.advance(1.5)
step()
check(st.equipped == jinkblade, "and then goes back to the Jinkblade")

st.effects.paralyze = 1
step()
check(st.equipped == rose, "a paralysed enemy turns him to the Rose")
stubs.advance(20)
step()
check(st.equipped == rose, "and keeps him on it while the paralysis lasts")
st.effects.paralyze = 0
step()
check(st.equipped == jinkblade, "back to the Jinkblade when it wears off")

jinkblade.data.enchantmentCharge = 21
step()
check(st.equipped == rose, "too little charge for another strike's paralysis: the Rose")
stubs.advance(15)
step()
check(st.equipped == rose, "and the Rose stays, now that the charge has run out")

st.equipped = burstCopy
jinkblade.data.enchantmentCharge = 22
stubs.advance(15)
step()
check(st.equipped == jinkblade, "a swing made with the bursting copy counts as the Rose")

-- Mercy left a stretch of the fight to the engine, which swapped weapons by itself.
st.equipped = rose
step()
check(st.equipped == rose, "a Rose the engine put in his hand is held its ten seconds too")
stubs.advance(11)
step()
check(st.equipped == jinkblade, "and then given up")

play("unequip start")
st.equipped = rose
step()
check(st.equipped == jinkblade, "a fight after he put his weapon away opens with the Jinkblade again")

st.inventories[selfHandle] = { jinkblade }
jinkblade.data.enchantmentCharge = 0
play("chop start")
step()
check(st.equipped == jinkblade, "without the Rose he keeps the Jinkblade, charged or not")

print(string.format("\n%d checks, %d failures", checks, fails))
os.exit(fails == 0 and 0 or 1)

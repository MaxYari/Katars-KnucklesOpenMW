-- Fatigue damage from hand-to-hand weapons, applied on whoever is hit.
--
-- The engine hands the whole attack to the victim (LuaManager::onHit -> the "Hit" event ->
-- I.Combat.onHit), and a handler may add to attack.damage before the built-in one applies it. That
-- is the only place an extra damage type can be attached to an ordinary weapon hit, so this script
-- rides on every actor rather than only on the player - an NPC swinging a katar has to bruise too.
--
-- Nothing here runs outside a hit: no update handler, no polling.
local mp = "scripts/MaxYari/H2HWeapons/"

local I = require('openmw.interfaces')

local formulas = require(mp .. "scripts/formulas")
local settings = require(mp .. "scripts/settings")
local weapons = require(mp .. "scripts/weapons")

local MELEE = I.Combat.ATTACK_SOURCE_TYPES.Melee

I.Combat.addOnHitHandler(function(attack)
    -- A miss deals nothing, and attack.damage is ignored for one anyway.
    if not attack.successful then return end
    if attack.sourceType ~= MELEE then return end

    local attacker = attack.attacker
    if attacker == nil then return end

    local kind = weapons.kindOfItem(attack.weapon)
    if not kind then return end

    local fatigue = formulas.handToHandFatigue(attacker, attack.strength or 0, settings.values.strengthFactor)
                  * weapons.FATIGUE_FACTOR[kind]
    if fatigue <= 0 then return end

    local damage = attack.damage
    damage.fatigue = (damage.fatigue or 0) + fatigue
end)

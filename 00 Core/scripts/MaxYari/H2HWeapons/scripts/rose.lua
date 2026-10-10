-- Ebony Rose's burst, on the wielder's side - the player's (player.lua) or an NPC's (npc.lua): which
-- swing bursts.
--
-- Whoever it strikes reports the strike (actor.lua). Strikes on one enemy run on while each lands
-- within BURST_CHAIN seconds of the one before - every strike renews the countdown - and the swing
-- that would be the third in a run bursts, if that enemy is poisoned when it winds up, by the venom
-- or by any other poison. Whether it is to burst has to be settled on the wind-up, before the blow
-- lands, so the one it lands on is taken to be the one the run was on.
--
-- The burst is a second enchantment, so that swing is made with a copy of the katar carrying it
-- (swingcopy.lua).
local mp = "scripts/MaxYari/H2HWeapons/"

local core = require('openmw.core')
local types = require('openmw.types')

local U = require(mp .. "scripts/uniques")
local weapons = require(mp .. "scripts/weapons")

local POISONS = { core.magic.EFFECT_TYPE.Poison or "poison", U.VENOM_EFFECT }

local M = {}

local function isPoisoned(actor)
    local effects = types.Actor.activeEffects(actor)
    for i = 1, #POISONS do
        if weapons.effectExists(POISONS[i]) then
            local effect = effects:getEffect(POISONS[i])
            if effect and effect.magnitude > 0 then return true end
        end
    end
    return false
end

-- One per wielder.
function M.new()
    local state = {
        target = nil,        -- the enemy the run of strikes is on
        strikes = 0,         -- how many in the run
        lastStrike = -math.huge,
    }
    local rose = {}

    -- A strike landed, reported by whoever it landed on; or a burst went off.
    function rose.onVenomStrike(e)
        if e.burst or e.victim == nil then
            state.target = nil
            state.strikes = 0
            return
        end
        local now = core.getSimulationTime()
        if e.victim ~= state.target or now - state.lastStrike > U.BURST_CHAIN then
            state.target = e.victim
            state.strikes = 0
        end
        state.strikes = state.strikes + 1
        state.lastStrike = now
    end

    -- Whether the swing winding up now is the one that bursts.
    function rose.burstDue()
        local target = state.target
        if target == nil or state.strikes < U.BURST_STRIKES - 1 then return false end
        if core.getSimulationTime() - state.lastStrike > U.BURST_CHAIN then return false end
        return target:isValid() and isPoisoned(target)
    end

    -- The enchantment a swing winding up with `item` strikes with instead of the Rose's own: the
    -- burst, when it is due; nil for any other.
    function rose.enchantFor(item)
        if weapons.specialOfItem(item) ~= weapons.SPECIAL.Venom or not rose.burstDue() then return nil end
        return U.BURST_ENCHANT
    end

    return rose
end

return M

-- Ebony Rose's burst, on the wielder's side - the player's (player.lua) or an NPC's (npc.lua): which
-- swing bursts, and the copy of the katar that swing is made with.
--
-- Whoever it strikes reports the strike (actor.lua). Strikes on one enemy run on while each lands
-- within BURST_CHAIN seconds of the one before - every strike renews the countdown - and the swing
-- that would be the third in a run bursts, if that enemy is poisoned when it winds up, by the venom
-- or by any other poison. Whether it is to burst has to be settled on the wind-up, before the blow
-- lands, so the one it lands on is taken to be the one the run was on.
--
-- The burst is a second enchantment, and an item cannot change its enchantment, so that swing is made
-- with a copy of the katar that carries it: global.lua makes one when the swing winds up, it goes in
-- the hand for the swing, and at the follow-through the original goes back and the copy is folded
-- into it. The two are the same weapon type, so the engine neither interrupts the swing nor plays a
-- draw (CharacterController only re-draws for a change of type), and the original never leaves the
-- inventory, so hotkeys never notice. The combat AI does not notice either: it only picks a weapon
-- again between swings (CharacterController::readyToPrepareAttack), by which time the original is back.
local mp = "scripts/MaxYari/H2HWeapons/"

local core = require('openmw.core')
local types = require('openmw.types')

local U = require(mp .. "scripts/uniques")
local weapons = require(mp .. "scripts/weapons")

local CARRIED_RIGHT = types.Actor.EQUIPMENT_SLOT.CarriedRight
local WEAPON_STANCE = types.Actor.STANCE.Weapon
local POISONS = { core.magic.EFFECT_TYPE.Poison or "poison", U.VENOM_EFFECT }
-- No swing lasts this long. A stagger that eats the follow-through would otherwise leave the copy in
-- hand for good.
local SWAP_TIMEOUT = 30

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

-- One per wielder. `actor` is the wielder's openmw.self.
function M.new(actor)
    local state = {
        target = nil,        -- the enemy the run of strikes is on
        strikes = 0,         -- how many in the run
        lastStrike = -math.huge,
        swinging = false,    -- between the wind-up and the follow-through
        staging = false,     -- a copy has been asked for and has not come
        swap = nil,          -- { original, copy, at } while the copy is in hand
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

    local function returnCopy(original, copy)
        core.sendGlobalEvent("H2HWeapons_BurstDone", { original = original, copy = copy })
    end

    local function endSwap()
        local swap = state.swap
        if swap == nil then return end
        state.swap = nil
        -- The original goes back - unless the wielder has changed weapons mid-swing, which stands.
        local equipment = types.Actor.getEquipment(actor)
        if equipment[CARRIED_RIGHT] == swap.copy then
            equipment[CARRIED_RIGHT] = swap.original
            types.Actor.setEquipment(actor, equipment)
        end
        returnCopy(swap.original, swap.copy)
    end

    -- A swing winds up with `item` in the hand.
    function rose.windUp(item)
        state.swinging = true
        if state.swap or state.staging or item == nil then return end
        if weapons.specialOfItem(item) ~= weapons.SPECIAL.Venom or not rose.burstDue() then return end
        state.staging = true
        core.sendGlobalEvent("H2HWeapons_StageBurst", { actor = actor.object, item = item })
    end

    -- The follow-through: the hit has been rolled and dealt.
    function rose.followStart()
        state.swinging = false
        endSwap()
    end

    function rose.onBurstStaged(e)
        state.staging = false
        if e.copy == nil then return end
        -- Too late for this swing, or the weapon has changed hands meanwhile: next swing, then.
        if not state.swinging or types.Actor.getStance(actor) ~= WEAPON_STANCE
            or types.Actor.getEquipment(actor, CARRIED_RIGHT) ~= e.original then
            returnCopy(e.original, e.copy)
            return
        end
        local equipment = types.Actor.getEquipment(actor)
        equipment[CARRIED_RIGHT] = e.copy
        types.Actor.setEquipment(actor, equipment)
        state.swap = { original = e.original, copy = e.copy, at = core.getSimulationTime() }
    end

    -- Sheathing or swapping mid-swing ends the swing, and puts the original back; so does a swing that
    -- never reached its follow-through.
    function rose.check(stance)
        if stance ~= WEAPON_STANCE then state.swinging = false end
        if state.swap and (stance ~= WEAPON_STANCE
            or core.getSimulationTime() - state.swap.at > SWAP_TIMEOUT) then
            endSwap()
        end
    end

    function rose.isSwapped() return state.swap ~= nil end

    -- A save taken mid-swing has the copy in hand.
    function rose.save()
        local swap = state.swap
        return swap and { original = swap.original, copy = swap.copy } or nil
    end

    -- Put things back after such a load, as the follow-through would have.
    function rose.restore(saved)
        if saved == nil then return end
        state.swap = { original = saved.original, copy = saved.copy, at = 0 }
        endSwap()
    end

    return rose
end

return M

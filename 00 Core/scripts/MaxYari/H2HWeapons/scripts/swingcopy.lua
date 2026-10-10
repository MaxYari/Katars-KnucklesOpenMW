-- For one swing, a copy of the weapon in hand that carries another enchantment: Ebony Rose's burst,
-- Mage Fury's channelled spell. Shared by the player's script and every NPC's.
--
-- An item cannot change its enchantment, so the swing that is to strike with another one is made with
-- a copy of the weapon carrying it: global.lua makes one when the swing winds up, it goes in the hand
-- for the swing, and at the follow-through the original goes back and the copy is folded into it,
-- charge and wear. The engine then strikes with that enchantment as with any weapon's - its cost, its
-- effects, their sounds and looks, reflection, absorption, resistances - and nothing of it is
-- imitated here. The two are the same weapon type and mesh, so the engine neither interrupts the
-- swing nor plays a draw (CharacterController only re-draws for a change of type), and the original
-- never leaves the inventory, so hotkeys never notice. The combat AI does not notice either: it only
-- picks a weapon again between swings (CharacterController::readyToPrepareAttack), by which time the
-- original is back.
--
-- A copy has to arrive before the blow lands. One that comes too late - a swing released the moment
-- it wound up - goes straight back, and that swing strikes with the original.
local core = require('openmw.core')
local types = require('openmw.types')

local CARRIED_RIGHT = types.Actor.EQUIPMENT_SLOT.CarriedRight
local WEAPON_STANCE = types.Actor.STANCE.Weapon
-- No swing lasts this long. A stagger that eats the follow-through would otherwise leave the copy in
-- hand for good.
local SWAP_TIMEOUT = 30

local M = {}

-- One per wielder. `actor` is the wielder's openmw.self.
function M.new(actor)
    local state = {
        swinging = false,    -- between the wind-up and the follow-through
        staging = false,     -- a copy has been asked for and has not come
        swap = nil,          -- { original, copy, at } while the copy is in hand
    }
    local copy = {}

    local function returnCopy(original, made)
        core.sendGlobalEvent("H2HWeapons_CopyDone", { original = original, copy = made })
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

    -- A swing winds up with `item` in the hand; `enchant` is the enchantment it is to strike with
    -- instead of the item's own, or nil for the item as it is.
    function copy.windUp(item, enchant)
        state.swinging = true
        if state.swap or state.staging or item == nil or enchant == nil then return end
        state.staging = true
        core.sendGlobalEvent("H2HWeapons_StageCopy", { actor = actor.object, item = item, enchant = enchant })
    end

    -- The follow-through: the hit has been rolled and dealt.
    function copy.followStart()
        state.swinging = false
        endSwap()
    end

    function copy.onStaged(e)
        state.staging = false
        if e.copy == nil then return end
        -- Too late for this swing, or the weapon has changed hands meanwhile.
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
    function copy.check(stance)
        if stance ~= WEAPON_STANCE then state.swinging = false end
        if state.swap and (stance ~= WEAPON_STANCE
            or core.getSimulationTime() - state.swap.at > SWAP_TIMEOUT) then
            endSwap()
        end
    end

    function copy.isSwapped() return state.swap ~= nil end

    -- The copy in the hand for this swing, and the original it stands in for; nil while there is none.
    function copy.inHand()
        local swap = state.swap
        if swap == nil then return nil end
        return swap.copy, swap.original
    end

    -- A save taken mid-swing has the copy in hand.
    function copy.save()
        local swap = state.swap
        return swap and { original = swap.original, copy = swap.copy } or nil
    end

    -- Put things back after such a load, as the follow-through would have.
    function copy.restore(saved)
        if saved == nil then return end
        state.swap = { original = saved.original, copy = saved.copy, at = 0 }
        endSwap()
    end

    return copy
end

return M

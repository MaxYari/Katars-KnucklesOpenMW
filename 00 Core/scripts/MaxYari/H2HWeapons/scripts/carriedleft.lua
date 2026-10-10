-- The left hand while a katar or knuckledusters are out: nothing in it, as with bare fists. Shared by
-- the player's script and every NPC's, which each say when one is out.
--
-- The engine counts hand-to-hand, like any two-handed weapon, as taking both hands: while it is out,
-- a shield or torch stays equipped but is not shown, not held up, does not burn and cannot block, and
-- once it is put away the shield or torch is back (NpcAnimation::updateCarriedLeftVisible, from the
-- weapon type's TwoHanded flag; character.cpp:1334, :2918; actors.cpp:1087). A katar is a one-handed
-- short blade to it, so a torch stays up beside one and a shield blocks.
--
-- A script cannot hide what is in the left hand, so it is taken off instead, and put back once the
-- weapon is away. Whatever goes in while one is out - from the inventory, a hotkey, or the engine,
-- which puts a light or a shield back in an NPC's hand once a second somewhere dark
-- (Actors::updateEquippedLight) - comes off the same way, and it is the last one taken off that goes
-- back, as it would be the last one equipped in the engine's case. The one difference: a shield taken
-- off gives no armour while the weapon is out, where the engine's hidden one still would.
local types = require('openmw.types')

local CARRIED_LEFT = types.Actor.EQUIPMENT_SLOT.CarriedLeft
local CARRIED_RIGHT = types.Actor.EQUIPMENT_SLOT.CarriedRight

-- The weapons the engine counts as taking both hands (weapontype.cpp, TwoHanded). Equipping one
-- takes the shield or torch off (MWClass::Weapon::canBeEquipped, ActionEquip), so with one in the
-- right hand nothing goes back in the left.
local T = types.Weapon.TYPE
local TWO_HANDED = {
    [T.LongBladeTwoHand] = true, [T.AxeTwoHand] = true, [T.BluntTwoClose] = true, [T.BluntTwoWide] = true,
    [T.SpearTwoWide] = true, [T.MarksmanBow] = true, [T.MarksmanCrossbow] = true,
}

local function holdsTwoHanded(actor)
    local weapon = types.Actor.getEquipment(actor, CARRIED_RIGHT)
    if weapon == nil or not types.Weapon.objectIsInstance(weapon) then return false end
    local record = types.Weapon.record(weapon)
    return record ~= nil and TWO_HANDED[record.type] == true
end

local M = {}

local function setLeft(actor, item)
    local equipment = types.Actor.getEquipment(actor)
    equipment[CARRIED_LEFT] = item
    types.Actor.setEquipment(actor, equipment)
end

-- One per actor. `actor` is its openmw.self.
function M.new(actor)
    local taken = nil     -- what came off the left hand, to go back on
    local takenId = nil   -- its record id: taking a torch off can stack it back in with the rest
    local left = {}

    local function putBack()
        local item, id = taken, takenId
        taken, takenId = nil, nil
        -- Something went in with another weapon meanwhile: that stays.
        if types.Actor.getEquipment(actor, CARRIED_LEFT) ~= nil then return end
        -- Swapped for a two-handed weapon: there is no hand for it, as there would not have been in
        -- the engine's case. It stays in the inventory.
        if holdsTwoHanded(actor) then return end
        if item and item:isValid() and item.count > 0 then
            -- Dropped, sold or put away somewhere, it is gone, as it would be from the hand.
            if item.parentContainer == actor.object then setLeft(actor, item) end
            return
        end
        -- Stacked back in with the rest of its kind: one of them goes back, found by its id.
        if types.Actor.inventory(actor):find(id) then setLeft(actor, id) end
    end

    -- `out`: whether a katar or knuckledusters are out. Costs one equipment lookup while they are,
    -- nothing while they are not and nothing is waiting to go back.
    function left.update(out)
        if out then
            local held = types.Actor.getEquipment(actor, CARRIED_LEFT)
            if held == nil then return end
            taken, takenId = held, held.recordId
            setLeft(actor, nil)
        elseif takenId then
            putBack()
        end
    end

    -- Died with one out: what came off stays in the inventory.
    function left.forget()
        taken, takenId = nil, nil
    end

    function left.save()
        return takenId and { item = taken, recordId = takenId } or nil
    end

    -- Put back by the next update that finds the weapon away.
    function left.load(saved)
        if saved == nil then return end
        taken, takenId = saved.item, saved.recordId
    end

    return left
end

return M

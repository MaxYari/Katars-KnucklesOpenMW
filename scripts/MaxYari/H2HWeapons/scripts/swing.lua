-- Where a one-handed weapon's animation is, read from the keys the engine plays it by. Shared by the
-- player's script and every NPC's, which both hang their work off these.
local M = {}

-- The engine's own long animation group for these weapon types, plus weapononehand, which is what
-- both fall back to when the specific group has no animation - which, in vanilla, is always
-- (character.cpp:575-600). Used to skip every other playBlended cheaply.
M.WEAPON_GROUPS = {
    weapononehand = true,
    shortbladeonehand = true,
    bluntonehand = true,
}
-- The same, as a list, for registering text key handlers.
M.WEAPON_GROUP_LIST = { "weapononehand", "shortbladeonehand", "bluntonehand" }

-- The keys the engine shows and hides the weapon on (CharacterController::handleTextKey), partway
-- through drawing and sheathing.
M.SHOW_KEY = "equip attach"
M.HIDE_KEY = "unequip detach"

local ATTACK_TYPES = { "chop ", "slash ", "thrust " }
local FOLLOW_START = "follow start"
local FOLLOW_START_OFFSET = -#FOLLOW_START

-- Whether a section starting at this key is a swing winding up: "slash start" is, "slash large
-- follow start" is not.
function M.isWindUpStart(key)
    if string.sub(key, -6) ~= " start" then return false end
    for i = 1, #ATTACK_TYPES do
        if string.find(key, ATTACK_TYPES[i], 1, true) == 1 then
            return string.find(key, FOLLOW_START, FOLLOW_START_OFFSET, true) == nil
        end
    end
    return false
end

-- Whether it is a follow-through: the hit has been rolled and dealt by then.
function M.isFollowStart(key)
    return string.find(key, FOLLOW_START, FOLLOW_START_OFFSET, true) ~= nil
end

return M

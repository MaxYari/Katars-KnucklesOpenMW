-- What counts as a hand-to-hand weapon, and what that means.
--
-- The engine has no hand-to-hand weapon type, so these are ordinary weapons as far as it is
-- concerned: katars are short blades, knuckledusters are blunt. Everything that makes them
-- hand-to-hand weapons is done by this mod's scripts, and all of it starts here.
--
-- Answers are worked out once per record id and cached, because the hot paths - the per-frame
-- off-hand mesh check, the per-hit fatigue damage - must not be asking the engine for records.
local types = require('openmw.types')

local M = {}

M.KIND = {
    Katar = "katar",
    Knuckle = "knuckle",
}

-- Fatigue damage these deal, as a fraction of what a bare-fisted hand-to-hand hit would do. Both
-- trade health damage for it against the shortsword they are cut from - a katar hits for 80% of
-- one, knuckledusters for 50% - and knuckledusters, which are made for bruising, trade the most.
M.FATIGUE_FACTOR = {
    [M.KIND.Katar] = 0.50,
    [M.KIND.Knuckle] = 0.75,
}

-- The skill the engine itself uses for each kind - the one the scripts have to work around.
M.WEAPON_SKILL = {
    [M.KIND.Katar] = "shortblade",
    [M.KIND.Knuckle] = "bluntweapon",
}

-- Matched against the record id, so another mod's katars and knuckledusters are picked up too
-- without needing to know about this one. The weapon type has to agree as well, so a two-handed
-- "Katar Axe" from somewhere is left alone.
local RULES = {
    { term = "katar", kind = M.KIND.Katar, type = types.Weapon.TYPE.ShortBladeOneHand },
    { term = "knuckle", kind = M.KIND.Knuckle, type = types.Weapon.TYPE.BluntOneHand },
}

-- [lowercased record id] = kind, or false. One small entry per weapon ever looked at.
local kindById = {}
-- [lowercased record id] = model path. Kept separately because .model is a property backed by a
-- C++ call, and the off-hand mesh check would otherwise make one every frame.
local modelById = {}

local function classify(recordId)
    local record = types.Weapon.record(recordId)
    if record == nil then return false end

    local id = string.lower(recordId)
    for i = 1, #RULES do
        local rule = RULES[i]
        if record.type == rule.type and string.find(id, rule.term, 1, true) then
            modelById[id] = record.model
            return rule.kind
        end
    end
    return false
end

-- The kind of hand-to-hand weapon this record id is, or false.
function M.kindOfId(recordId)
    if recordId == nil then return false end
    local id = string.lower(recordId)
    local kind = kindById[id]
    if kind == nil then
        kind = classify(recordId)
        kindById[id] = kind
    end
    return kind
end

-- The same, for an item object. Anything that is not a weapon is false without a record lookup.
function M.kindOfItem(item)
    if item == nil then return false end
    if not types.Weapon.objectIsInstance(item) then return false end
    return M.kindOfId(item.recordId)
end

-- Mesh of a weapon this module has already classified as hand-to-hand. nil for anything else.
function M.modelOfId(recordId)
    if recordId == nil then return nil end
    local id = string.lower(recordId)
    if kindById[id] == nil then M.kindOfId(recordId) end
    return modelById[id]
end

return M

-- What counts as a hand-to-hand weapon, and what that means.
--
-- The engine has no hand-to-hand weapon type, so these are ordinary weapons as far as it is
-- concerned: katars are short blades, knuckledusters are blunt. Everything that makes them
-- hand-to-hand weapons is done by this mod's scripts, and all of it starts here.
--
-- Answers are worked out once per record id and cached, because the hot paths - the per-frame
-- off-hand mesh check, the per-hit fatigue damage - must not be asking the engine for records.
local mp = "scripts/MaxYari/H2HWeapons/"

local core = require('openmw.core')
local types = require('openmw.types')
local vfs = require('openmw.vfs')

local U = require(mp .. "scripts/uniques")

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
-- without needing to know about this one - and against the mesh's file name, which is all a
-- generated record keeps to say what it is: one an enchanter made from a katar, or a Bound Fist
-- scaled to its caster, has an id like "Generated:0x1a2". The weapon type has to agree as well, so a
-- two-handed "Katar Axe" from somewhere is left alone.
local RULES = {
    { term = "katar", kind = M.KIND.Katar, type = types.Weapon.TYPE.ShortBladeOneHand },
    { term = "knuckle", kind = M.KIND.Knuckle, type = types.Weapon.TYPE.BluntOneHand },
}

-- What the uniques' enchantments do - and, through them, what a weapon is when its id says nothing:
-- the copy of Ebony Rose held for the one swing that bursts is a generated record with a generated
-- id, and it has to stay a katar to the animations, the skill swap and the off hand.
M.SPECIAL = {
    Venom = "venom",        -- Ebony Rose: every strike poisons
    Burst = "burst",        -- the swing that sets the venom off around its target
    MageFury = "magefury",  -- Mage Fury: strikes deliver the spell it was charged with
}
local ENCHANTMENTS = {
    [string.lower(U.VENOM_ENCHANT)] = { kind = M.KIND.Katar, special = M.SPECIAL.Venom },
    [string.lower(U.BURST_ENCHANT)] = { kind = M.KIND.Katar, special = M.SPECIAL.Burst },
    [string.lower(U.MAGE_FURY_ENCHANT)] = { kind = M.KIND.Knuckle, special = M.SPECIAL.MageFury },
}

local function modelFile(record)
    return record.model and string.match(string.lower(record.model), "([^/\\]+)$") or ""
end

-- [lowercased record id] = kind, or false. One small entry per weapon ever looked at.
local kindById = {}
-- [lowercased record id] = model path. Kept separately because .model is a property backed by a
-- C++ call, and the off-hand mesh check would otherwise make one every frame.
local modelById = {}
-- [lowercased record id] = charge effect model, or false. A weapon has one if a "<mesh>_charged.nif"
-- sits beside its mesh: a particle system authored in the weapon's own local space, so hanging it
-- on the weapon bone drops it inside the weapon with no offsets. Looked up once per weapon.
local chargeModelById = {}
-- [lowercased record id] = one of M.SPECIAL, or false.
local specialById = {}

local function classify(recordId)
    local record = types.Weapon.record(recordId)
    if record == nil then return false end

    local id = string.lower(recordId)
    local enchantment = record.enchant and ENCHANTMENTS[string.lower(record.enchant)]
    specialById[id] = enchantment and enchantment.special or false

    local file = modelFile(record)
    for i = 1, #RULES do
        local rule = RULES[i]
        if record.type == rule.type
            and (string.find(id, rule.term, 1, true) or string.find(file, rule.term, 1, true)) then
            modelById[id] = record.model
            return rule.kind
        end
    end
    local kind = enchantment and enchantment.kind
    if kind then
        modelById[id] = record.model
        return kind
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

-- Which of the uniques' tricks a weapon carries (one of M.SPECIAL), or false.
function M.specialOfId(recordId)
    if recordId == nil then return false end
    local id = string.lower(recordId)
    if kindById[id] == nil then M.kindOfId(recordId) end
    return specialById[id] or false
end

-- The same, for an item object.
function M.specialOfItem(item)
    if item == nil then return false end
    if not types.Weapon.objectIsInstance(item) then return false end
    return M.specialOfId(item.recordId)
end

-- Whether a magic effect exists. This mod's own are made at load (content.lua); should that fail, the
-- engine throws on every read of one, so whatever reads them asks this first. Once per id.
local effectKnown = {}
function M.effectExists(id)
    local known = effectKnown[id]
    if known == nil then
        known = core.magic.effects.records[id] ~= nil
        effectKnown[id] = known
    end
    return known
end

-- The charge effect that goes with a weapon's mesh, or nil if it has none.
function M.chargeModelOfId(recordId)
    local model = M.modelOfId(recordId)
    if model == nil then return nil end
    local id = string.lower(recordId)

    local charge = chargeModelById[id]
    if charge == nil then
        charge = string.gsub(model, "%.nif$", "_charged.nif")
        if charge == model or not vfs.fileExists(charge) then charge = false end
        chargeModelById[id] = charge
    end
    return charge or nil
end

return M

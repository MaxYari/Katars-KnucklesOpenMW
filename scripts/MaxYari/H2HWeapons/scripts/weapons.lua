-- What counts as a hybrid weapon, and what that means.
--
-- The engine knows one skill per weapon, from its type: a katar is a short blade to it, knuckledusters
-- a blunt weapon. A hybrid is swung with two skills instead, and everything that makes it one is done
-- by this mod's scripts, starting here. Which weapons are hybrids, and with which skills, is not
-- decided here but in the definition files any mod can ship (definitions.lua); this puts a file
-- together with the weapon record it is for.
--
-- Answers are worked out once per record id and cached, because the hot paths - the per-frame
-- off-hand mesh check, the per-hit fatigue damage - must not be asking the engine for records.
local mp = "scripts/MaxYari/H2HWeapons/"

local core = require('openmw.core')
local types = require('openmw.types')
local vfs = require('openmw.vfs')

local definitions = require(mp .. "scripts/definitions")
local U = require(mp .. "scripts/uniques")

local M = {}

M.MOVESET = definitions.MOVESET
M.SCALING = definitions.SCALING

-- Who can hold these at all: the player and NPCs, and of creatures only a two-legged one that fights
-- with weapons - dremora, golden saints, liches, skeletons - which is what gives a creature an
-- inventory to hold them from (MWClass::Creature::hasInventoryStore) and the NPC animations and
-- bones to swing them with (CreatureAnimation, Animation::setObjectRoot). animations.lua and npc.lua
-- open with the same test, written out there so a creature that fails it loads nothing else.
function M.canWield(actor)
    if not types.Creature.objectIsInstance(actor) then return true end
    local record = types.Creature.record(actor)
    return record.isBiped and record.canUseWeapons
end

-- What the engine makes of each melee weapon type (weapontype.cpp): the skill it trains and rolls the
-- hit against, and the sound it draws and sheathes with (+ " Up" / " Down", character.cpp:1417,
-- :1477). Hybrids are melee only: a type not here cannot be one.
local T = types.Weapon.TYPE
local MELEE = {
    [T.ShortBladeOneHand] = { skill = "shortblade", sound = "Item Weapon Shortblade", oneHanded = true },
    [T.LongBladeOneHand] = { skill = "longblade", sound = "Item Weapon Longblade", oneHanded = true },
    [T.BluntOneHand] = { skill = "bluntweapon", sound = "Item Weapon Blunt", oneHanded = true },
    [T.AxeOneHand] = { skill = "axe", sound = "Item Weapon Blunt", oneHanded = true },
    [T.LongBladeTwoHand] = { skill = "longblade", sound = "Item Weapon Longblade" },
    [T.BluntTwoClose] = { skill = "bluntweapon", sound = "Item Weapon Blunt" },
    [T.BluntTwoWide] = { skill = "bluntweapon", sound = "Item Weapon Blunt" },
    [T.SpearTwoWide] = { skill = "spear", sound = "Item Weapon Spear" },
    [T.AxeTwoHand] = { skill = "axe", sound = "Item Weapon Blunt" },
}
-- What the uniques' enchantments do. The copy of Ebony Rose held for the one swing that bursts is a
-- generated record, and is known for the Rose by its mesh (below) and for the burst by this.
M.SPECIAL = {
    Venom = "venom",        -- Ebony Rose: every strike poisons
    Burst = "burst",        -- the swing that sets the venom off around its target
    MageFury = "magefury",  -- Mage Fury: strikes deliver the spell it was charged with
}
local ENCHANTMENTS = {
    [string.lower(U.VENOM_ENCHANT)] = M.SPECIAL.Venom,
    [string.lower(U.BURST_ENCHANT)] = M.SPECIAL.Burst,
    [string.lower(U.MAGE_FURY_ENCHANT)] = M.SPECIAL.MageFury,
}

--- Generated records ------------------------------------------------------------------------------
-- A weapon an enchanter made, a Bound Fist scaled to its caster, the Rose's burst copy: each is a new
-- record with an id like "Generated:0x1a2", which no file can be named after. All it keeps of the
-- weapon it was made from is everything else - the mesh among it - so it is the hybrid that a
-- defined weapon of the same mesh and type is. Several defined weapons may share one (a katar and
-- its shop-enchanted versions): the first by id is taken.
local function modelKey(record)
    local model = string.gsub(string.lower(record.model or ""), "\\", "/")
    return model .. "|" .. tostring(record.type)
end

local definedByModel = nil -- [modelKey] = lowercased id of a defined weapon; built on first need

local function definedLike(record)
    if definedByModel == nil then
        definedByModel = {}
        local ids = {}
        for id in pairs(definitions.paths()) do ids[#ids + 1] = id end
        table.sort(ids)
        for i = #ids, 1, -1 do
            local defined = types.Weapon.record(ids[i])
            if defined then definedByModel[modelKey(defined)] = ids[i] end
        end
    end
    return definedByModel[modelKey(record)]
end

--- Hybrids -------------------------------------------------------------------------------------------
-- [lowercased record id] = the hybrid, or false. One small entry per weapon ever looked at.
local hybridById = {}
-- [lowercased record id] = one of M.SPECIAL, or false.
local specialById = {}
-- [lowercased record id] = charge effect model, or false. A weapon has one if a "<mesh>_charged.nif"
-- sits beside its mesh: a particle system authored in the weapon's own local space, so hanging it
-- on the weapon bone drops it inside the weapon with no offsets. Looked up once per weapon.
local chargeModelById = {}

-- The hybrid a weapon record is - its definition, put together with what its record says - or false,
-- and what stops a definition from making it one.
local function resolve(recordId, record)
    local id = string.lower(recordId)
    local def, problems, path = definitions.load(id)
    if def == nil and path == nil and string.find(id, "^generated:") then
        local like = definedLike(record)
        if like then def, problems, path = definitions.load(like) end
    end
    if def == nil then return false, problems, path end
    -- The file's own list is shared by every weapon it is for; this weapon's problems go on a copy.
    local own = {}
    for i = 1, #problems do own[i] = problems[i] end
    problems = own

    local melee = MELEE[record.type]
    if melee == nil then
        problems[#problems + 1] = "the weapon is not a melee weapon, and only melee weapons can be hybrids"
        return false, problems, path
    end

    local hybrid = {}
    for key, value in pairs(def) do hybrid[key] = value end
    hybrid.weaponSkill = melee.skill
    hybrid.drawSounds = { melee.sound .. " Up", melee.sound .. " Down" }
    hybrid.model = record.model
    if hybrid.moveset == M.MOVESET.HandToHand and not melee.oneHanded then
        problems[#problems + 1] = "the handToHand moveset needs a one-handed weapon; it uses the default one"
        hybrid.moveset = M.MOVESET.Default
    end
    hybrid.handToHand = hybrid.moveset == M.MOVESET.HandToHand
    return hybrid, problems, path
end

local function classify(recordId)
    local id = string.lower(recordId)
    local record = types.Weapon.record(recordId)
    if record == nil then
        specialById[id] = false
        return false
    end
    specialById[id] = record.enchant and ENCHANTMENTS[string.lower(record.enchant)] or false
    return (resolve(recordId, record))
end

--- The hybrid this record id is, or false. A table of its definition's fields (definitions.parse)
-- and what the weapon's record adds: weaponSkill (the skill the engine swings it with), handToHand
-- (whether it swings with this mod's moveset), drawSounds (the engine's, for silentDraw), model.
-- Shared: never change it.
function M.hybridOfId(recordId)
    if recordId == nil then return false end
    local id = string.lower(recordId)
    local hybrid = hybridById[id]
    if hybrid == nil then
        hybrid = classify(recordId)
        hybridById[id] = hybrid
    end
    return hybrid
end

--- The same, for an item object. Anything that is not a weapon is false without a record lookup.
function M.hybridOfItem(item)
    if item == nil then return false end
    if not types.Weapon.objectIsInstance(item) then return false end
    return M.hybridOfId(item.recordId)
end

-- Mesh of a weapon this module has already classified as a hybrid. nil for anything else.
function M.modelOfId(recordId)
    local hybrid = M.hybridOfId(recordId)
    return hybrid and hybrid.model or nil
end

-- Which of the uniques' tricks a weapon carries (one of M.SPECIAL), or false.
function M.specialOfId(recordId)
    if recordId == nil then return false end
    local id = string.lower(recordId)
    if hybridById[id] == nil then M.hybridOfId(recordId) end
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

--- Every definition file there is, checked against the records loaded: what is wrong with each, in
-- the log. For the global script, once a game is started or loaded - every actor's scripts read the
-- same files, and say nothing.
function M.report()
    local ids = {}
    for id in pairs(definitions.paths()) do ids[#ids + 1] = id end
    table.sort(ids)
    local hybrids, unused = 0, {}
    for _, id in ipairs(ids) do
        local record = types.Weapon.record(id)
        if record == nil then
            unused[#unused + 1] = id
        else
            local hybrid, problems, path = resolve(id, record)
            if hybrid then hybrids = hybrids + 1 end
            for i = 1, #(problems or {}) do
                print("[H2HWeapons] " .. path .. ": " .. problems[i]
                    .. (hybrid and "" or " - not a hybrid weapon"))
            end
        end
    end
    print("[H2HWeapons] " .. hybrids .. " hybrid weapons defined in " .. definitions.FOLDER)
    if #unused > 0 then
        print("[H2HWeapons] definitions for weapons no loaded content file has (left unused): "
            .. table.concat(unused, ", "))
    end
end

return M

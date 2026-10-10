-- Hybrid weapon definitions: the files that say a weapon is a hybrid, and how.
--
-- One file per weapon record, in a HybridWeaponDefinitions folder in any data folder (or any folder
-- under it), named after the record id: HybridWeaponDefinitions/katar_steel.yaml. YAML or JSON -
-- .yaml, .yml or .json; openmw.markup reads JSON as the YAML it also is. A file at the same path in a
-- later data folder replaces the earlier one, as any other file does, so a patch can change this
-- mod's own weapons. The fields, with what each defaults to, are in README.md ("Hybrid weapons for
-- modders"); parse() below is the authority.
--
-- The folder is listed once per script instance, on first use, and a file is only read when its
-- weapon is first looked at - every actor carries scripts that ask, and most never meet a hybrid.
-- Nothing here prints: every actor's scripts parse the same files, so the global script alone says
-- what is wrong with them (weapons.report).
local mp = "scripts/MaxYari/H2HWeapons/"

local core = require('openmw.core')
local markup = require('openmw.markup')
local vfs = require('openmw.vfs')

local formulas = require(mp .. "scripts/formulas")

local M = {}

-- As the VFS has it: paths are lowercased (VFS::Path::Normalized).
M.FOLDER = "hybridweapondefinitions/"

M.MOVESET = {
    -- This mod's: ReAnimation's hand-to-hand set over the weapon's own animations (animations.lua),
    -- a copy of the weapon in the off hand, and nothing else in that hand.
    HandToHand = "handToHand",
    -- The weapon's own animations, as the engine plays them.
    Default = "default",
}
M.SCALING = formulas.SCALING

local EXTENSIONS = { yaml = true, yml = true, json = true }

-- What a field's value is compared as: "Hand to Hand", "hand-to-hand" and "HandToHand" are all
-- "handtohand", which is also how the engine spells the skill's id.
local function token(value)
    if type(value) ~= "string" then return nil end
    return (string.gsub(string.lower(value), "[^%w]", ""))
end

local SCALINGS = {
    minorsecondarybonus = M.SCALING.MinorSecondaryBonus,
    lowestskill = M.SCALING.LowestSkill,
    lowest = M.SCALING.LowestSkill,
    highestskill = M.SCALING.HighestSkill,
    highest = M.SCALING.HighestSkill,
}
local MOVESETS = {
    handtohand = M.MOVESET.HandToHand,
    default = M.MOVESET.Default,
}

-- A share of experience: 0.7, or "70%".
local function share(value)
    if type(value) == "number" then return value end
    if type(value) ~= "string" then return nil end
    local percent = string.match(value, "^%s*([%d%.]+)%s*%%%s*$")
    if percent then
        local number = tonumber(percent)
        return number and number / 100
    end
    return tonumber(value)
end

local function skill(value)
    local id = token(value)
    if id and core.stats.Skill.records[id] then return id end
    return nil
end

--- A definition from a file's contents: the fields checked and filled in with their defaults.
-- @return the definition, or nil when it cannot be used; and a list of what is wrong with it, which
-- is empty for a good one. A problem with an optional field leaves that field at its default.
function M.parse(raw)
    local problems = {}
    if type(raw) ~= "table" then return nil, { "the file is not a set of fields" } end

    local primary, secondary = skill(raw.primarySkill), skill(raw.secondarySkill)
    if not primary then
        problems[#problems + 1] = "primarySkill '" .. tostring(raw.primarySkill) .. "' is not a skill"
    end
    if not secondary then
        problems[#problems + 1] = "secondarySkill '" .. tostring(raw.secondarySkill) .. "' is not a skill"
    end
    if primary and primary == secondary then
        problems[#problems + 1] = "primarySkill and secondarySkill are the same skill"
    end
    if #problems > 0 then return nil, problems end

    local def = {
        primarySkill = primary,
        secondarySkill = secondary,
        primaryExperience = 0.7,
        secondaryExperience = 0.3,
        scaling = M.SCALING.MinorSecondaryBonus,
        moveset = M.MOVESET.Default,
        fatigueDamage = 0,
        tooltip = nil,
        silentDraw = false,
        swingSounds = nil, -- nil: the weapon swings as its type does
    }

    local function number(field, check)
        local value = raw[field]
        if value == nil then return end
        local parsed = share(value)
        if parsed == nil or not check(parsed) then
            problems[#problems + 1] = field .. " '" .. tostring(value) .. "' is not a usable number"
            return
        end
        def[field] = parsed
    end
    local function notNegative(x) return x >= 0 end
    number("primaryExperience", notNegative)
    number("secondaryExperience", notNegative)
    number("fatigueDamage", notNegative)

    if raw.scaling ~= nil then
        local scaling = SCALINGS[token(raw.scaling) or ""]
        if scaling then
            def.scaling = scaling
        else
            problems[#problems + 1] = "scaling '" .. tostring(raw.scaling) .. "' is not one of minorSecondaryBonus, "
                .. "lowestSkill, highestSkill"
        end
    end

    if raw.moveset ~= nil then
        local moveset = MOVESETS[token(raw.moveset) or ""]
        if moveset then
            def.moveset = moveset
        else
            problems[#problems + 1] = "moveset '" .. tostring(raw.moveset) .. "' is not one of handToHand, default"
        end
    end

    if raw.tooltip ~= nil then
        if type(raw.tooltip) == "string" then
            def.tooltip = raw.tooltip
        else
            problems[#problems + 1] = "tooltip is not text"
        end
    end

    if raw.silentDraw ~= nil then
        if type(raw.silentDraw) == "boolean" then
            def.silentDraw = raw.silentDraw
        else
            problems[#problems + 1] = "silentDraw is not true or false"
        end
    end

    if raw.swingSounds ~= nil then
        def.swingSounds = M.parseSwingSounds(raw.swingSounds, problems)
    end

    return def, problems
end

--- swingSounds: the whooshes a swing makes with Combat Sounds Overhaul Overhauled, each one sound
-- played on every swing - { sound = , volume = , groups = }. `sound` is "own", the weapon's own swing
-- (drawn from CSO's swing `groups` when given, otherwise from what its type uses), or the name of one
-- of CSO's WEAPON kinds, whose swing is played as well. Without an "own" one the weapon's own swing is
-- silent. Becomes { own = { volume, groups } or nil, extra = { { sound, volume }, ... } }; the CSO
-- names are only checked where CSO is (actor.lua).
function M.parseSwingSounds(raw, problems)
    if type(raw) ~= "table" then
        problems[#problems + 1] = "swingSounds is not a list"
        return nil
    end
    local sounds = { own = nil, extra = {} }
    for i, entry in ipairs(raw) do
        if type(entry) ~= "table" or type(entry.sound) ~= "string" then
            problems[#problems + 1] = "swingSounds entry " .. i .. " has no sound"
        else
            local volume = 1
            if entry.volume ~= nil then
                local given = share(entry.volume)
                if given ~= nil and given >= 0 then
                    volume = given
                else
                    problems[#problems + 1] = "swingSounds entry " .. i .. ": volume '" .. tostring(entry.volume)
                        .. "' is not a usable number"
                end
            end
            if token(entry.sound) == "own" then
                local groups = entry.groups
                if type(groups) == "string" then groups = { groups } end
                if groups ~= nil and type(groups) ~= "table" then
                    problems[#problems + 1] = "swingSounds entry " .. i .. ": groups is not a list"
                    groups = nil
                end
                sounds.own = { volume = volume, groups = groups }
            else
                sounds.extra[#sounds.extra + 1] = { sound = entry.sound, volume = volume }
            end
        end
    end
    return sounds
end

--- The files ------------------------------------------------------------------------------------------
local pathById = nil -- [lowercased record id] = path

--- [lowercased record id] = path of its definition file, for every file there is.
function M.paths()
    if pathById then return pathById end
    pathById = {}
    for path in vfs.pathsWithPrefix(M.FOLDER) do
        local id, extension = string.match(path, "([^/]+)%.(%w+)$")
        if id and EXTENSIONS[extension] then pathById[id] = path end
    end
    return pathById
end

local loaded = {} -- [lowercased record id] = { def = , problems = } or false

--- What the file for this record id says: the definition (or nil) and its problems - or nothing at
-- all when there is no file. Read once.
function M.load(id)
    local entry = loaded[id]
    if entry == nil then
        local path = M.paths()[id]
        if path == nil then
            entry = false
        else
            local ok, raw = pcall(markup.loadYaml, path)
            if ok then
                local def, problems = M.parse(raw)
                entry = { def = def, problems = problems, path = path }
            else
                entry = { problems = { "could not be read: " .. tostring(raw) }, path = path }
            end
        end
        loaded[id] = entry
    end
    if not entry then return nil end
    return entry.def, entry.problems, entry.path
end

return M

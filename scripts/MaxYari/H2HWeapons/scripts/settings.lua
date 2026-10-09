-- Settings, read once and kept in plain Lua variables.
--
-- The hot paths read these on every hit and every frame, and storage:get() is an engine call that
-- builds a value each time, so nothing here is fetched on demand: the section is read at load and
-- again only when something actually changes.
local async = require('openmw.async')
local storage = require('openmw.storage')

local GLOBAL_GROUP = "SettingsGlobalH2HWeapons"

local M = {}

M.GLOBAL_GROUP = GLOBAL_GROUP

-- A mirror of the launcher's "Factor Strength into Hand-to-Hand Combat" (Settings -> Gameplay), which
-- no Lua API exposes - only difficulty is (corebindings.cpp) - so the player sets this to match it. The
-- setting is stored as a string, because the "select" renderer takes the value itself as the label's
-- l10n key; these are the engine's own 0/1/2 behind it, in the launcher's order.
local STRENGTH_VALUES = { off = 0, on = 1, onExceptWerewolves = 2 }

-- Defaults, also used as the registered defaults in global.lua. Keep the two in step.
M.DEFAULTS = {
    strengthInfluencesHandToHand = "off",
    showOffHandWeapon = true,
    silenceDrawSound = true,
}

M.values = {}
for key, value in pairs(M.DEFAULTS) do M.values[key] = value end

local section = storage.globalSection(GLOBAL_GROUP)

local function refresh()
    local stored = section:asTable()
    for key, default in pairs(M.DEFAULTS) do
        local value = stored[key]
        if value == nil then value = default end
        M.values[key] = value
    end
    -- Resolved here so the hot paths get a number, not a string compare.
    M.values.strengthFactor = STRENGTH_VALUES[M.values.strengthInfluencesHandToHand] or 0
end

refresh()
section:subscribe(async:callback(refresh))

return M

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

-- A mirror of the launcher's "strength influences hand to hand" (Advanced -> Combat), which no Lua
-- API exposes - only difficulty is (corebindings.cpp) - so the player sets this to match it. The
-- setting is stored as a string, because the "select" renderer takes the value itself as the label's
-- l10n key; these are the engine's own 0/1/2 behind it, in the launcher's order.
local STRENGTH_VALUES = { off = 0, on = 1, onExceptWerewolves = 2 }

-- Defaults, also used as the registered defaults in global.lua. Keep the two in step.
M.DEFAULTS = {
    strengthInfluencesHandToHand = "off",
    -- Of the experience a successful hit would have given, this much goes to hand-to-hand and the
    -- rest to the weapon skill the engine thinks was used.
    handToHandShare = 0.7,
    -- What the weapon skill adds to the effective hand-to-hand value, as a share of the weapon
    -- skill itself: the full share while it is within skillBonusGrace points of hand-to-hand,
    -- tapering over the next skillBonusFalloff points to skillBonusMin, which is a floor.
    skillBonusMax = 0.15,
    skillBonusMin = 0.05,
    skillBonusGrace = 10,
    skillBonusFalloff = 20,
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

-- Teaches this mod's spells to the merchants who should sell them (list.lua), as they come into the
-- world. A spell merchant sells what they know (MWGui::SpellBuyingWindow reads the NPC's own spell
-- list), and that list is theirs in the save, so a spell taught once stays taught.
--
-- Done from a script rather than from Katar.omwaddon because a plugin can only give an NPC a spell by
-- replacing that NPC's whole record, which fights every other mod that touches them; this changes
-- nothing but the spell list. It is its own content file so it can be left out: without it, nobody
-- sells these spells, and nothing else changes.
local core = require('openmw.core')
local types = require('openmw.types')

local list = require("scripts/MaxYari/H2HWeapons/traders/list")

-- The list turned inside out: [lowercased NPC record id] = { spell id, ... }. One lookup per actor
-- that comes into the world is all this costs.
local spellsOf = {}
for spellId, traders in pairs(list) do
    for _, traderId in ipairs(traders) do
        local key = string.lower(traderId)
        spellsOf[key] = spellsOf[key] or {}
        table.insert(spellsOf[key], spellId)
    end
end

local function teach(actor)
    local spells = spellsOf[string.lower(actor.recordId)]
    if spells == nil then return end
    local known = types.Actor.spells(actor)
    for _, spellId in ipairs(spells) do
        -- Only a spell that exists: the main mod may be turned off while this is on. Adding one they
        -- know already does nothing.
        if core.magic.spells.records[spellId] ~= nil then known:add(spellId) end
    end
end

return {
    engineHandlers = {
        onActorActive = teach,
    },
}

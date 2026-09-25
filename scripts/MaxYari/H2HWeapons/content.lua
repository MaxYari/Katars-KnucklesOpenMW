-- The records the two uniques' magic is made of, created once at game start (a LOAD script).
--
-- openmw.content edits the data "as if a content file had done so", and it can do what an ESM file
-- cannot: make magic effects of this mod's own. Those are what give the venom its purple visuals
-- and both weapons' magic a name and a description in the game's own tooltips.
--
-- A custom effect gets everything the engine does from a record - duration, the looping cloud on
-- the victim, the area burst, the hostile reaction and the crime - but nothing it does from a
-- hard-coded effect id, which includes all damage and all resistances. The venom's damage is
-- therefore dealt by actor.lua; everything else here is left to the engine.
--
-- Katar.omwaddon ships vanilla stand-ins under the same enchantment ids, so the plugin is whole on
-- its own; the ones made here replace them.
local mp = "scripts/MaxYari/H2HWeapons/"

local content = require('openmw.content')

local U = require(mp .. "scripts/uniques")

local okUtil, util = pcall(require, 'openmw.util')

local function colour(r, g, b)
    if okUtil and util and util.color then return util.color.rgb(r, g, b) end
    return nil
end

-- An effect is only a label if nothing else can use it: no spellmaking, no enchanting.
local function private(record)
    record.allowsSpellmaking = false
    record.allowsEnchanting = false
    return record
end

-- Each part is made on its own: one that fails - a record the engine rejects - says so in the log
-- and leaves the plugin's stand-ins for that part, rather than taking the others down with it.
local function section(name, make)
    local ok, err = pcall(make)
    if not ok then
        print("[H2HWeapons] ERROR: could not make the records for " .. name .. ": " .. tostring(err))
    end
end

local function define()
    local effects = content.magicEffects.records
    local TOUCH, SELF = content.RANGE.Touch, content.RANGE.Self
    local STRIKES = content.enchantments.TYPE.CastOnStrike

    -- What the display-only effects show and sound: nothing. A static has to have a model, so it
    -- is one with nothing in it; the sound is the Destruction hit at no volume.
    local silence = nil
    section("the silent effects", function()
        content.statics.records[U.NO_VFX_STATIC] = { model = "meshes/katars/vfx_none.nif" }
        local from = content.sounds.records["destruction hit"]
        if from ~= nil then
            content.sounds.records[U.SILENT_SOUND] = { template = from, volume = 0 }
            silence = U.SILENT_SOUND
        end
    end)

    --- Ebony Rose --------------------------------------------------------------------------------
    section("Ebony Rose", function()
        -- Vanilla poison's own meshes, retextured purple (Sources/Tools/venom_fx.py). The particle
        -- texture is purple too: the engine lays it over the first texture of whichever mesh plays.
        content.statics.records.h2h_vfx_venomhit = { model = "meshes/katars/vfx_venom_hit.nif" }
        content.statics.records.h2h_vfx_venomarea = { model = "meshes/katars/vfx_venom_area.nif" }

        -- Its sounds (uniques.lua): each a copy of the vanilla record the school would have played,
        -- only with this mod's file in it. One whose vanilla record is missing is left out, and the
        -- effect keeps what Poison plays.
        local venomSounds = {}
        for id, spec in pairs(U.VENOM_SOUNDS) do
            local from = content.sounds.records[spec.from]
            if from ~= nil then
                content.sounds.records[id] = { template = from, fileName = spec.file }
                venomSounds[id] = id
            end
        end

        effects[U.VENOM_EFFECT] = private {
            template = effects.poison,
            name = "Poison",
            description = "A violet venom that eats at the victim's health. Resist and Weakness to Poison "
                .. "work on it; Cure Poison does not.",
            icon = "katars\\tx_s_venom.dds",
            particle = "katars_vfx\\vfx_venom.dds",
            hitStatic = "h2h_vfx_venomhit",
            areaStatic = "h2h_vfx_venomarea",
            hitSound = venomSounds[U.VENOM_HIT_SOUND],
            areaSound = venomSounds[U.VENOM_AREA_SOUND],
            -- Applied whole when it lands rather than bit by bit over its duration, as Poison is.
            -- The engine deals nothing for it either way (actor.lua does), but a bit-by-bit effect
            -- struck again while it lasts loses its looping cloud: the new strike's first
            -- application is worth nothing (magnitude times a zero step, applyMagicEffect), so when
            -- the old strike's spell is taken off the effect's total reads nothing, the cloud is
            -- removed (onMagicEffectRemoved), and the new one, marked as already applied, never
            -- plays it again.
            isAppliedOnce = true,
            -- A reflected venom would land on the wielder, whose script is not watching for it.
            unreflectable = true,
            -- Also the glow of the enchanted blade.
            color = colour(0.62, 0.22, 0.85),
        }

        -- The burst's line in the Rose's tooltip. The tooltip can only list an enchantment's
        -- effects, and the burst is not one of them - it comes with a second enchantment, for one
        -- swing (global.lua) - so this effect says what it does, and does nothing: no area, so no
        -- explosion (explodeSpell), an empty model (vfx_none.nif, a node and nothing else) and a
        -- silent sound. The engine prints its magnitude and duration after the name.
        local ordinals = { "1st", "2nd", "3rd" }
        effects[U.BURST_NOTE_EFFECT] = private {
            template = effects.poison,
            name = "Volatile Venom (" .. (ordinals[U.BURST_STRIKES] or (U.BURST_STRIKES .. "th"))
                .. " strike on the poisoned, " .. U.BURST.area .. " ft)",
            description = "Every " .. (ordinals[U.BURST_STRIKES] or (U.BURST_STRIKES .. "th")) .. " strike "
                .. "in a row on a poisoned enemy - each within " .. U.BURST_CHAIN .. " seconds of the last - "
                .. "bursts, poisoning everyone within " .. U.BURST.area .. " feet of them.",
            icon = "katars\\tx_s_venom.dds",
            castStatic = U.NO_VFX_STATIC,
            hitStatic = U.NO_VFX_STATIC,
            areaStatic = U.NO_VFX_STATIC,
            castSound = silence,
            hitSound = silence,
            areaSound = silence,
            harmful = false,
            continuousVfx = false,
            isAppliedOnce = true,
            unreflectable = true,
            color = colour(0.62, 0.22, 0.85),
        }

        local venom = {
            id = U.VENOM_EFFECT, range = TOUCH, area = 0,
            duration = U.VENOM.duration, magnitudeMin = U.VENOM.magnitude, magnitudeMax = U.VENOM.magnitude,
        }
        local roseCharge = U.VENOM_COST * U.STRIKES_PER_CHARGE
        content.enchantments.records[U.VENOM_ENCHANT] = {
            type = STRIKES, cost = U.VENOM_COST, charge = roseCharge, isAutocalc = false,
            effects = {
                venom,
                {
                    id = U.BURST_NOTE_EFFECT, range = TOUCH, area = 0,
                    duration = U.BURST.duration, magnitudeMin = U.BURST.magnitude, magnitudeMax = U.BURST.magnitude,
                },
            },
        }
        -- The swing that bursts: the ordinary venom on whoever it hits, and the burst around them.
        -- An area effect on a touch enchantment is applied to the target directly and exploded
        -- around it for everyone else (CastSpell::inflict, explodeSpell), and never to the caster.
        content.enchantments.records[U.BURST_ENCHANT] = {
            type = STRIKES, cost = U.BURST_COST, charge = roseCharge, isAutocalc = false,
            effects = {
                venom,
                {
                    id = U.VENOM_EFFECT, range = TOUCH, area = U.BURST.area,
                    duration = U.BURST.duration, magnitudeMin = U.BURST.magnitude, magnitudeMax = U.BURST.magnitude,
                },
            },
        }

        -- Damage Health, which the engine does count as a kill for whoever cast it (Actors::
        -- adjustMagicEffects). actor.lua leaves a dying victim a sliver of health and hands it
        -- this, so the kill - and the murder, if it is one - is the engine's call, by the engine's
        -- rules.
        content.spells.records[U.FINISHER_SPELL] = {
            name = "Volatile Venom", type = content.spells.TYPE.Spell, cost = 0, isAutocalc = false,
            effects = {
                {
                    id = "damagehealth", range = TOUCH, area = 0, duration = 1,
                    magnitudeMin = U.FINISHER_MAGNITUDE, magnitudeMax = U.FINISHER_MAGNITUDE,
                },
            },
        }
    end)

    --- Mage Fury ----------------------------------------------------------------------------------
    section("Mage Fury", function()
        -- The enchantment's one effect, which only says what the knuckles do - the tooltip lists an
        -- enchantment's effects and nothing else - and does nothing, as the Rose's burst line does.
        -- It is cast on strike rather than constant so that the knuckles hold a charge, which the
        -- strikes that carry a spell spend (player.lua).
        effects[U.MAGE_FURY_EFFECT] = private {
            template = effects.spellabsorption,
            name = "Spell Channeling: " .. U.MAGE_FURY_STRIKES .. " strikes after a cast deal damage "
                .. "in proportion to the spell",
            description = "Cast a harmful spell with these on, and the next " .. U.MAGE_FURY_STRIKES
                .. " strikes deal damage in proportion to it, each spending charge.",
            icon = "s\\tx_s_spll_absb.tga",
            castStatic = U.NO_VFX_STATIC,
            hitStatic = U.NO_VFX_STATIC,
            areaStatic = U.NO_VFX_STATIC,
            castSound = silence,
            hitSound = silence,
            areaSound = silence,
            hasMagnitude = false,
            hasDuration = false,
            harmful = false,
            isAppliedOnce = true,
            unreflectable = true,
            onSelf = false,
            onTouch = true,
            onTarget = false,
            color = colour(0.45, 0.70, 1.0),
        }
        effects[U.MAGE_FURY_CHARGE_EFFECT] = private {
            template = effects.reflect,
            name = "Channeled Spell",
            description = "The knuckles hold a spell. Each strike spends one charge, carrying a third of "
                .. "the spell's harmful effects into the target. The magnitude is the strikes left.",
            icon = "s\\tx_s_reflect.tga",
            hasMagnitude = true,
            hasDuration = true,
            harmful = false,
            onSelf = true,
            onTouch = false,
            onTarget = false,
            color = colour(0.45, 0.70, 1.0),
        }

        -- At a channelled strike's full price, so the engine charges every strike as it would any
        -- enchanted weapon's - Enchant skill and all - and refuses, saying so, when there is too
        -- little left. player.lua hands the price back to a strike that carried no spell.
        content.enchantments.records[U.MAGE_FURY_ENCHANT] = {
            type = STRIKES, cost = U.MAGE_FURY_COST, charge = U.MAGE_FURY_COST * U.STRIKES_PER_CHARGE, isAutocalc = false,
            effects = { { id = U.MAGE_FURY_EFFECT, range = TOUCH, area = 0, duration = 0 } },
        }
    end)

    --- Bound Fist ---------------------------------------------------------------------------------
    section("Bound Fist", function()
        -- Bound Dagger's effect in every way the engine takes from a record - school, cost, cast
        -- and hit visuals, the rule that it cannot be cast again while it lasts - except the one
        -- thing it keys to the effect's id: which item it binds. actor.lua does that part.
        effects[U.BOUND_FIST_EFFECT] = private {
            template = effects.bounddagger,
            name = "Bound Fist",
            description = "This effect binds a daedric hand-to-hand weapon to the caster's fists for the "
                .. "duration of the spell. A novice conjurer gets daedric knuckledusters, an adept spiked "
                .. "ones, a master a daedric katar. When the effect ends, the weapon returns to Oblivion "
                .. "and whatever the caster held before is back in hand.",
            hasMagnitude = false,
            hasDuration = true,
            harmful = false,
            nonRecastable = true,
            onSelf = true,
            onTouch = false,
            onTarget = false,
        }
        content.spells.records[U.BOUND_FIST_SPELL] = {
            name = "Bound Fist", type = content.spells.TYPE.Spell, cost = U.BOUND_FIST.cost, isAutocalc = false,
            effects = {
                {
                    id = U.BOUND_FIST_EFFECT, range = SELF, area = 0, duration = U.BOUND_FIST.duration,
                    -- The effect has no magnitude to show or use, but the active effect's magnitude
                    -- is rolled from these (spelleffects.cpp, roll), and actor.lua tells whether it
                    -- is still on by reading it, so it has to be above nothing.
                    magnitudeMin = 1, magnitudeMax = 1,
                },
            },
        }

        for strikes = 1, U.MAGE_FURY_STRIKES do
            content.spells.records[U.MAGE_FURY_CHARGE_SPELLS[strikes]] = {
                name = "Mage Fury", type = content.spells.TYPE.Spell, cost = 0, isAutocalc = false,
                effects = {
                    {
                        id = U.MAGE_FURY_CHARGE_EFFECT, range = SELF, area = 0,
                        duration = U.MAGE_FURY_FADE, magnitudeMin = strikes, magnitudeMax = strikes,
                    },
                },
            }
        end
    end)
end

return {
    engineHandlers = {
        onContentFilesLoaded = define,
    },
}

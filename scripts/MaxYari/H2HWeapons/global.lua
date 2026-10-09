-- The mod's settings, and the two things only a global script can do for the uniques: make records
-- at run time, and move items in and out of an inventory.
local mp = "scripts/MaxYari/H2HWeapons/"

local core = require('openmw.core')
local I = require('openmw.interfaces')
local types = require('openmw.types')
local world = require('openmw.world')

local formulas = require(mp .. "scripts/formulas")
local settings = require(mp .. "scripts/settings")
local U = require(mp .. "scripts/uniques")
local weapons = require(mp .. "scripts/weapons")

-- What the hybrid weapon definitions say, and what is wrong with them, in the log: once, here, rather
-- than from every actor's scripts, which read the same files.
weapons.report()

-- A global group rather than a player one: the fatigue damage is worked out on the victim, which
-- for an NPC is an NPC script, and only a global section is readable from there.
I.Settings.registerGroup {
    key = settings.GLOBAL_GROUP,
    page = "H2HWeapons",
    l10n = "H2HWeapons",
    name = "settings_group",
    description = "settings_group_description",
    permanentStorage = false,
    order = 0,
    settings = {
        {
            key = "strengthInfluencesHandToHand",
            name = "strength_influences",
            description = "strength_influences_description",
            default = settings.DEFAULTS.strengthInfluencesHandToHand,
            -- The "select" renderer labels each item with the l10n key of its own value, so the
            -- values are the strings below and settings.lua maps them back to the engine's 0/1/2.
            renderer = "select",
            argument = {
                l10n = "H2HWeapons",
                items = { "off", "on", "onExceptWerewolves" },
            },
        },
        {
            key = "showOffHandWeapon",
            name = "show_off_hand_weapon",
            description = "show_off_hand_weapon_description",
            default = settings.DEFAULTS.showOffHandWeapon,
            renderer = "checkbox",
        },
        {
            key = "silenceDrawSound",
            name = "silence_draw_sound",
            description = "silence_draw_sound_description",
            default = settings.DEFAULTS.silenceDrawSound,
            renderer = "checkbox",
        },
    },
}

--- Records made at run time -----------------------------------------------------------------------
-- Both kinds are made once and kept: world.createRecord records live in the save, and the ids that
-- point at them are saved here, so nothing is made twice.
local made = {
    -- ["<lowercased weapon id>|<lowercased enchantment id>"] = id of a copy of that weapon carrying
    -- that enchantment, for one swing (swingcopy.lua)
    copyWeapons = {},
    -- [lowercased spell id] = id of the enchantment that carries Mage Fury's share of it
    furyEnchants = {},
    -- ["<tier>:<Conjuration step>:<settings>"] = id of that tier's bound fist, scaled
    boundWeapons = {},
    -- The player's last report of how bound items scale (see player.lua): Unofficial TR Spells'
    -- settings, or its defaults. Kept in the save so an NPC who casts before the report arrives
    -- still gets the right one.
    boundScaling = { enabled = true, values = U.BOUND_SCALING_DEFAULTS },
    -- Whether Ebony Rose's owner has been handed it, and his Jinkblade's charge put back (below).
    roseGiven = false,
    jinkbladeRecharged = false,
}

--- A swing's copy of the weapon ------------------------------------------------------------------------
-- An item cannot change its enchantment, so the swing that strikes with another one - Ebony Rose's
-- burst, Mage Fury's channelled spell - is made with a copy of the weapon that carries it: made here,
-- handed over, and folded back into the original - charge and wear - the moment the swing is over
-- (swingcopy.lua). The original never leaves the inventory, so hotkeys and the inventory screen never
-- see a different weapon.
local function copyWeaponFor(original, enchant)
    local key = string.lower(original.recordId) .. "|" .. string.lower(enchant)
    local id = made.copyWeapons[key]
    if id and types.Weapon.record(id) then return id end

    local base = types.Weapon.record(original.recordId)
    if base == nil then return nil end
    id = world.createRecord(types.Weapon.createRecordDraft({
        template = base,
        enchant = enchant,
    })).id
    made.copyWeapons[key] = id
    return id
end

-- Charge and wear go wherever the weapon goes, so the copy starts where the original is and hands it
-- back when it is done.
local function copyItemData(from, to)
    local source, target = types.Item.itemData(from), types.Item.itemData(to)
    target.condition = source.condition
    target.enchantmentCharge = source.enchantmentCharge
end

local function stageCopy(e)
    local actor, original = e.actor, e.item
    if actor == nil or original == nil or not original:isValid() or e.enchant == nil then return end

    local id = copyWeaponFor(original, e.enchant)
    if id == nil then
        actor:sendEvent("H2HWeapons_CopyStaged", {})
        return
    end
    local copy = world.createObject(id, 1)
    copyItemData(original, copy)
    copy:moveInto(types.Actor.inventory(actor))
    actor:sendEvent("H2HWeapons_CopyStaged", { original = original, copy = copy })
end

local function copyDone(e)
    local copy, original = e.copy, e.original
    if copy == nil or not copy:isValid() then return end
    if original ~= nil and original:isValid() then copyItemData(copy, original) end
    copy:remove()
end

--- Mage Fury's share of a spell ---------------------------------------------------------------------
-- What a channelled strike carries: the spell's harmful effects that reach past the caster, at a
-- third of their magnitude (a third of their duration, for one that has none), delivered by touch -
-- as a cast-on-strike enchantment, which the knuckles' copy for that swing carries, so the engine
-- strikes with it as with any enchanted weapon. A spell with nothing like that - a heal, a feather -
-- does not charge the knuckles at all.
--
-- The knuckles' own effect goes first, doing nothing as it does on them: an enchanted weapon's
-- shimmer takes the colour of its enchantment's first effect (Class::getEnchantmentColor), so the
-- knuckles look the same through the swing.
local function share(value)
    return math.max(1, math.floor(value * U.MAGE_FURY_SHARE + 0.5))
end

local function furyEnchantFor(spellId)
    local key = string.lower(spellId)
    local id = made.furyEnchants[key]
    if id and core.magic.enchantments.records[id] then return id end

    local spell = core.magic.spells.records[spellId]
    if spell == nil then return nil end

    local SELF, TOUCH = core.magic.RANGE.Self, core.magic.RANGE.Touch
    local effects = {}
    for i = 1, #spell.effects do
        local params = spell.effects[i]
        local mgef = params.effect
        if mgef and mgef.harmful and params.range ~= SELF then
            local low, high, duration = params.magnitudeMin, params.magnitudeMax, params.duration
            if mgef.hasMagnitude then
                low = share(low)
                high = math.max(low, share(high))
            elseif mgef.hasDuration then
                duration = share(duration)
            end
            effects[#effects + 1] = {
                id = params.id,
                affectedSkill = params.affectedSkill,
                affectedAttribute = params.affectedAttribute,
                range = TOUCH,
                area = 0,
                duration = duration,
                magnitudeMin = low,
                magnitudeMax = high,
            }
        end
    end
    if #effects == 0 then return nil end
    if core.magic.effects.records[U.MAGE_FURY_EFFECT] then
        table.insert(effects, 1, { id = U.MAGE_FURY_EFFECT, range = TOUCH, area = 0, duration = 0 })
    end

    id = world.createRecord(core.magic.enchantments.createRecordDraft({
        type = core.magic.ENCHANTMENT_TYPE.CastOnStrike,
        cost = U.MAGE_FURY_COST,
        charge = U.MAGE_FURY_COST * U.STRIKES_PER_CHARGE,
        isAutocalc = false,
        effects = effects,
    })).id
    made.furyEnchants[key] = id
    return id
end

local function chargeMageFury(e)
    if e.actor == nil or e.spell == nil then return end
    local id = furyEnchantFor(e.spell)
    if id == nil then return end
    local spell = core.magic.spells.records[e.spell]
    e.actor:sendEvent("H2HWeapons_MageFuryCharged", { enchant = id, name = spell and spell.name or "" })
end

-- Charge taken from, or given back to, an enchanted item - which only a global script may change on
-- someone else's behalf. Never past what the enchantment holds, never below nothing.
local function chargeUse(e)
    local item = e.item
    if item == nil or not item:isValid() or not types.Weapon.objectIsInstance(item) then return end
    local data = types.Item.itemData(item)
    local current = data.enchantmentCharge
    if current == nil then return end
    local record = types.Weapon.record(item)
    local enchantment = record and record.enchant and core.magic.enchantments.records[record.enchant]
    local most = enchantment and enchantment.charge or current
    data.enchantmentCharge = math.max(0, math.min(most, current + (e.delta or 0)))
end

--- Bound Fist -------------------------------------------------------------------------------------
-- The weapon a caster gets: their tier's record as it is, or - with bound item scaling on - a copy of
-- it with the damage, weight and enchantment scaled to their Conjuration, the way Unofficial TR
-- Spells scales its own (boundRecords.lua). The copy keeps the tier's mesh, which is what tells the
-- tiers apart. Copies are made once per tier, Conjuration step and set of numbers, and kept.
local function settingsKey(values)
    return string.format("%g/%g/%g/%g/%g/%g", values.BOUND_DAMAGE_BASE, values.BOUND_DAMAGE_BONUS_PER_LEVEL,
        values.BOUND_WEIGHT_BASE, values.BOUND_WEIGHT_REDUCTION_PER_LEVEL,
        values.BOUND_ENCHANT_BASE or 100, values.BOUND_ENCHANT_BONUS_PER_LEVEL or 0)
end

-- The tier's constant effect - Fortify Hand-to-hand, as a vanilla bound weapon fortifies its own
-- skill - at a scaled magnitude, never below 1: boundRecords.lua's buildScaledEnchantment.
local function scaledEnchantment(enchantId, mult)
    local source = core.magic.enchantments.records[enchantId]
    if source == nil then return enchantId end
    local effects = {}
    for i, effect in ipairs(source.effects) do
        effects[i] = {
            id = effect.id,
            range = effect.range,
            area = effect.area,
            duration = effect.duration,
            magnitudeMin = math.max(1, math.floor((effect.magnitudeMin or 0) * mult + 0.5)),
            magnitudeMax = math.max(1, math.floor((effect.magnitudeMax or 0) * mult + 0.5)),
            affectedSkill = effect.affectedSkill,
            affectedAttribute = effect.affectedAttribute,
        }
    end
    return world.createRecord(core.magic.enchantments.createRecordDraft({
        type = source.type,
        charge = source.charge,
        cost = source.cost,
        isAutocalc = source.isAutocalc,
        effects = effects,
    })).id
end

local function boundWeaponFor(tierIndex, conjuration)
    local tier = U.BOUND_FIST_TIERS[tierIndex]
    if tier == nil then return nil end
    local base = types.Weapon.record(tier.weapon)
    if base == nil then return nil end
    local scaling = made.boundScaling
    if not scaling.enabled then return tier.weapon end

    local values = scaling.values
    local step = formulas.boundStep(conjuration, U.BOUND_SCALING_STEP)
    local key = tierIndex .. ":" .. step .. ":" .. settingsKey(values)
    local id = made.boundWeapons[key]
    if id and types.Weapon.record(id) then return id end

    local mult = formulas.boundDamageMult(step, values)
    local function scaled(damage) return math.floor(damage * mult + 0.5) end
    local draft = {
        template = base,
        chopMinDamage = scaled(base.chopMinDamage),
        chopMaxDamage = scaled(base.chopMaxDamage),
        slashMinDamage = scaled(base.slashMinDamage),
        slashMaxDamage = scaled(base.slashMaxDamage),
        thrustMinDamage = scaled(base.thrustMinDamage),
        thrustMaxDamage = scaled(base.thrustMaxDamage),
        weight = formulas.boundWeight(tier.baseWeight, step, values),
    }
    if base.enchant and base.enchant ~= "" and values.BOUND_ENCHANT_BASE then
        local enchantMult = formulas.boundEnchantMult(step, values)
        if enchantMult ~= 1 then draft.enchant = scaledEnchantment(base.enchant, enchantMult) end
    end
    id = world.createRecord(types.Weapon.createRecordDraft(draft)).id
    made.boundWeapons[key] = id
    return id
end

local function summonFist(e)
    local actor = e.actor
    if actor == nil or not actor:isValid() then return end
    local id = boundWeaponFor(e.tier, e.conjuration or 0)
    if id == nil then return end
    local item = world.createObject(id, 1)
    item:moveInto(types.Actor.inventory(actor))
    actor:sendEvent("H2HWeapons_FistSummoned", { item = item })
end

-- Back to Oblivion. One left lying in the world goes with the puff a vanilla bound item would.
local function dismissFist(e)
    local item = e.item
    if item == nil or not item:isValid() or item.count <= 0 then return end
    if item.parentContainer == nil and item.cell ~= nil then
        core.sound.playSound3d("conjuration hit", item)
        world.vfx.spawn("meshes/e/magic_summon.nif", item.position, { scale = 0.3 })
    end
    item:remove()
end

--- Ebony Rose's owner -----------------------------------------------------------------------------
-- The Dark Brotherhood's master in Mournhold (Tribunal) fights with the Rose and his own Jinkblade,
-- turn about (roseowner.lua) - but only when Mercy: Combat AI Overhaul runs his fights. Mercy switches
-- the engine's combat AI off while it fights, and with it the engine's choice of weapon before every
-- swing, so the choice has to be a step of Mercy's own. Without Mercy he is not handed the Rose: the
-- one placed in his room (KatarWorldPlacements.omwaddon) is the one there is. With Mercy he is handed
-- one the first time he comes into the world - on his body, if he is dead by then - and the one in his
-- room goes, as long as it is still lying there: there is only ever one Rose to find.
--
-- Older saves kept his Jinkblade drained, so that the engine's AI would fight with the Rose; its
-- charge is put back once.
local function removeRoomRose()
    local cell = world.getCellByName(U.ROOM_ROSE_CELL)
    if cell == nil then return end
    for _, item in ipairs(cell:getAll(types.Weapon)) do
        if item.contentFile == U.ROOM_ROSE_CONTENT and string.lower(item.recordId) == U.EBONY_ROSE
            and item.count > 0 then
            item:remove()
        end
    end
end

local function onActorActive(actor)
    if string.lower(actor.recordId) ~= U.ROSE_OWNER then return end
    if types.Weapon.records[U.EBONY_ROSE] == nil then return end
    if not core.contentFiles.has(U.MERCY_CONTENT) then return end
    local inventory = types.Actor.inventory(actor)
    if not made.roseGiven then
        made.roseGiven = true
        world.createObject(U.EBONY_ROSE, 1):moveInto(inventory)
    end
    removeRoomRose()
    if not made.jinkbladeRecharged then
        made.jinkbladeRecharged = true
        local jinkblade = inventory:find(U.ROSE_OWNER_WEAPON)
        local record = jinkblade and types.Weapon.record(jinkblade)
        local enchantment = record and record.enchant and core.magic.enchantments.records[record.enchant]
        if enchantment then types.Item.itemData(jinkblade).enchantmentCharge = enchantment.charge end
    end
end

return {
    eventHandlers = {
        H2HWeapons_StageCopy = stageCopy,
        H2HWeapons_CopyDone = copyDone,
        H2HWeapons_ChargeMageFury = chargeMageFury,
        H2HWeapons_ChargeUse = chargeUse,
        H2HWeapons_SummonFist = summonFist,
        H2HWeapons_DismissFist = dismissFist,
        H2HWeapons_BoundScaling = function(e)
            made.boundScaling = { enabled = e.enabled and true or false, values = e.values or U.BOUND_SCALING_DEFAULTS }
        end,
    },
    engineHandlers = {
        onActorActive = onActorActive,
        onSave = function() return made end,
        onLoad = function(data)
            if not data then return end
            made.copyWeapons = data.copyWeapons or {}
            -- Saves from before the copies were shared: the burst's were keyed by weapon alone.
            for weapon, id in pairs(data.burstWeapons or {}) do
                made.copyWeapons[weapon .. "|" .. string.lower(U.BURST_ENCHANT)] = id
            end
            made.furyEnchants = data.furyEnchants or {}
            made.boundWeapons = data.boundWeapons or {}
            made.boundScaling = data.boundScaling or made.boundScaling
            made.roseGiven = data.roseGiven or false
            made.jinkbladeRecharged = data.jinkbladeRecharged or false
        end,
    },
}

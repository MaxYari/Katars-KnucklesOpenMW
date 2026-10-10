-- Everything that makes a hybrid weapon - a katar, knuckledusters, or any weapon a definition file
-- names (definitions.lua) - behave like one on the player: the skill the engine rolls against, where
-- the experience goes, what the tooltip says and the draw sound it should not make; for one swung
-- with the hand-to-hand moveset, the second weapon in the off hand and the shield or torch it leaves
-- no room for - and the wielder's half of the two uniques' magic: Ebony Rose's burst and Mage Fury's
-- stored spell.
--
-- The engine knows one skill per weapon, from its type: a katar is a short blade to it, knuckledusters
-- a blunt weapon. Each piece below puts one of its assumptions back.
--
-- Per frame this costs: one getStance, one camera.getMode, one equipment lookup that Max Yari's
-- Script Services answers from its own cache ten times a second, and a handful of compares - and,
-- while one is out, a look at the left hand.
-- Everything else hangs off animation events and hits, so it runs once per swing or once per draw.
local mp = "scripts/MaxYari/H2HWeapons/"

local animation = require('openmw.animation')
local async = require('openmw.async')
local camera = require('openmw.camera')
local core = require('openmw.core')
local debug = require('openmw.debug')
local I = require('openmw.interfaces')
local omwself = require('openmw.self')
local storage = require('openmw.storage')
local types = require('openmw.types')
local nearby = require('openmw.nearby')
local ui = require('openmw.ui')
local util = require('openmw.util')

local carriedLeft = require(mp .. "scripts/carriedleft")
local formulas = require(mp .. "scripts/formulas")
local hands = require(mp .. "scripts/hands")
local roseState = require(mp .. "scripts/rose")
local swingCopy = require(mp .. "scripts/swingcopy")
local settings = require(mp .. "scripts/settings")
local swing = require(mp .. "scripts/swing")
local U = require(mp .. "scripts/uniques")
local weapons = require(mp .. "scripts/weapons")

local cfg = settings.values

-- MSS answers the equipment lookup this script makes every frame. ReAnimation requires it too, so
-- it should always be there; if it is not, say so once rather than failing with a stack trace.
if not core.contentFiles.has("MaxYariScriptServices.omwscripts") then
    print("[H2HWeapons] ERROR: Max Yari's Script Services (MSS) is missing. It is required.")
    ui.showMessage("Katars & Knuckles: Max Yari's Script Services (MSS) is missing, please install it.")
    return {}
end

local CARRIED_RIGHT = types.Actor.EQUIPMENT_SLOT.CarriedRight
local WEAPON_STANCE = types.Actor.STANCE.Weapon
local FIRST_PERSON = camera.MODE.FirstPerson
local SKILLS = types.NPC.stats.skills
local WEAPON_SUCCESSFUL_HIT = I.SkillProgression.SKILL_USE_TYPES.Weapon_SuccessfulHit
local SPELLCAST_SUCCESS = I.SkillProgression.SKILL_USE_TYPES.Spellcast_Success
local SPECIAL = weapons.SPECIAL

local l10n = core.l10n("H2HWeapons")

-- Fills the %{name} placeholders this mod's strings use. A function replacement, so a value with a
-- % in it (a spell name, say) goes in as written.
local function fill(text, values)
    return (text:gsub("%%{(%w+)}", function(key)
        local value = values[key]
        if value == nil then return nil end
        return tostring(value)
    end))
end

--- Settings page ----------------------------------------------------------------------------------
-- The settings themselves are global (see global.lua): the fatigue damage is worked out on whoever
-- is hit, and only a global section can be read from an NPC's script.
I.Settings.registerPage {
    key = "H2HWeapons",
    l10n = "H2HWeapons",
    name = "page_name",
    description = "page_description",
}

-- The banner, its renderer in menu.lua. A group with no name and nothing to store, ahead of the rest.
I.Settings.registerGroup {
    key = "SettingsPlayerH2HWeaponsBanner",
    page = "H2HWeapons",
    l10n = "H2HWeapons",
    name = "banner",
    permanentStorage = false,
    order = -1,
    settings = {
        { key = "banner", name = "banner", renderer = "H2HWeapons_banner" },
    },
}

--- Bound Fist's scaling ---------------------------------------------------------------------------
-- A bound fist scales with Conjuration exactly as Unofficial TR Spells scales its bound weapons, from
-- that mod's own settings; there are none here. Only a player script can read a player settings
-- section, so they are read here and handed to the global script, which makes the weapons, and what
-- was found is shown on this mod's settings page. Without that mod: its defaults, and scaling on.
local STATUS_GROUP = "SettingsPlayerH2HWeaponsStatus"
I.Settings.registerGroup {
    key = STATUS_GROUP,
    page = "H2HWeapons",
    l10n = "H2HWeapons",
    name = "status_group",
    description = "status_group_description",
    permanentStorage = false,
    order = 1,
    settings = {
        {
            key = "boundScaling",
            name = "bound_scaling",
            description = "bound_scaling_description",
            renderer = "textLine",
            default = "",
            argument = { disabled = true },
        },
    },
}


local function readBoundScaling()
    if not core.contentFiles.has(U.TR_SPELLS_SCRIPTS) then
        return { enabled = true, values = U.BOUND_SCALING_DEFAULTS, status = "bound_scaling_default" }
    end
    local section = storage.playerSection(U.TR_BOUND_SECTION)
    local values = {}
    for key, default in pairs(U.BOUND_SCALING_DEFAULTS) do
        local value = section:get(key)
        values[key] = type(value) == "number" and value or default
    end
    -- Off unless switched on, as it is there.
    local enabled = section:get(U.TR_BOUND_ENABLED) == true
    return {
        enabled = enabled,
        values = values,
        status = enabled and "bound_scaling_tr_on" or "bound_scaling_tr_off",
    }
end

local function reportBoundScaling()
    local found = readBoundScaling()
    core.sendGlobalEvent("H2HWeapons_BoundScaling", { enabled = found.enabled, values = found.values })
    storage.playerSection(STATUS_GROUP):set("boundScaling", l10n(found.status))
end

-- Changed in that mod's settings, changed here.
if core.contentFiles.has(U.TR_SPELLS_SCRIPTS) then
    storage.playerSection(U.TR_BOUND_SECTION):subscribe(async:callback(reportBoundScaling))
end
local scalingReported = false

--- What is in the hand ----------------------------------------------------------------------------
-- MSS hands back the same table until the item actually changes, so the common case is one pointer
-- compare. Everything derived from the item is worked out on that change, never per frame.
local EQUIPMENT_CACHE_TIME = 0.1

local equippedInfo = nil
local equippedHybrid = false     -- weapons.hybridOfId's answer
local equippedHandToHand = false -- and whether it swings with the hand-to-hand moveset
local equippedSpecial = false
local equippedModel = nil
local equippedChargeModel = nil

local function refreshEquipped()
    local info = I.MSS.getEquipmentInfo(CARRIED_RIGHT, EQUIPMENT_CACHE_TIME)
    if info == equippedInfo then return false end
    equippedInfo = info
    local hybrid = info and weapons.hybridOfId(info.recordId) or false
    local changed = hybrid ~= equippedHybrid
    equippedHybrid = hybrid
    equippedHandToHand = hybrid and hybrid.handToHand or false
    equippedSpecial = hybrid and weapons.specialOfId(info.recordId) or false
    equippedModel = hybrid and hybrid.model or nil
    equippedChargeModel = hybrid and weapons.chargeModelOfId(info.recordId) or nil
    return changed
end

--- Hit chance -------------------------------------------------------------------------------------
-- Npc::evaluateHit rolls against getSkill(attacker, the weapon's equipment skill) - Short Blade for
-- a katar, Blunt Weapon for knuckledusters - and there is no hook for that number. So for the length
-- of a swing the weapon skill *is* the hybrid's effective skill (formulas.effectiveSkill, from its
-- two skills by its scaling): the modifier is nudged by the difference and put back afterwards.
-- Skill modifiers are only ever added to and subtracted from (fortify and drain effects do the same,
-- spelleffects.cpp:131), so this composes with them rather than fighting them.
--
-- Applied on the wind-up, because prepareHit() - which is where the roll happens - runs when the
-- attack is released, before the release section plays (character.cpp:1754).
local swappedSkill = nil
local swappedDelta = 0
local swappedAt = 0
-- No swing lasts this long. A stagger or a reload that eats the follow-through would otherwise
-- leave the modifier on for good.
local SWAP_TIMEOUT = 30

local function revertSkillSwap()
    if not swappedSkill then return end
    local stat = SKILLS[swappedSkill](omwself)
    stat.modifier = stat.modifier - swappedDelta
    swappedSkill = nil
    swappedDelta = 0
end

-- The player's current values for a hybrid's two skills, and the one it swings with.
local function hybridSkills(hybrid)
    local primary = SKILLS[hybrid.primarySkill](omwself).modified
    local secondary = SKILLS[hybrid.secondarySkill](omwself).modified
    return primary, secondary, formulas.effectiveSkill(hybrid.scaling, primary, secondary)
end

local function applySkillSwap(hybrid)
    revertSkillSwap() -- an interrupted previous swing may still be holding one

    local skillName = hybrid.weaponSkill
    local weaponStat = SKILLS[skillName](omwself)
    local _, _, effective = hybridSkills(hybrid)
    local delta = effective - weaponStat.modified
    -- getHitChance truncates the skill to an int, so anything under a point changes nothing.
    if delta > -0.5 and delta < 0.5 then return end

    weaponStat.modifier = weaponStat.modifier + delta
    swappedSkill = skillName
    swappedDelta = delta
    swappedAt = core.getSimulationTime()
end

--- Experience -------------------------------------------------------------------------------------
-- Npc::hit credits the weapon's own skill on a successful hit and there is no way to redirect it at
-- the source, so it is split here instead, by the hybrid's shares: a primary or secondary skill that
-- is the weapon's own keeps its share of the engine's credit, and the others are credited
-- separately, each as one use of its own (a magic school's first kind of use is a successful cast)
-- at its share. A weapon skill that is neither keeps nothing. The nested skillUsed calls never name
-- the weapon's own skill, which is the only one this handler acts on, so they cannot recurse.
local function creditShare(skillid, share)
    if share <= 0 then return end
    I.SkillProgression.skillUsed(skillid, { useType = WEAPON_SUCCESSFUL_HIT, scale = share })
end

I.SkillProgression.addSkillUsedHandler(function(skillid, options)
    if options.useType ~= WEAPON_SUCCESSFUL_HIT then return end
    local hybrid = equippedHybrid
    if not hybrid or skillid ~= hybrid.weaponSkill then return end

    local kept = 0
    if skillid == hybrid.primarySkill then
        kept = hybrid.primaryExperience
    else
        creditShare(hybrid.primarySkill, hybrid.primaryExperience)
    end
    if skillid == hybrid.secondarySkill then
        kept = hybrid.secondaryExperience
    else
        creditShare(hybrid.secondarySkill, hybrid.secondaryExperience)
    end
    -- Zeroed rather than stopped, so the handlers after this one still hear of the hit.
    if options.skillGain then options.skillGain = options.skillGain * kept end
end)

--- Mage Fury's charge ---------------------------------------------------------------------------
-- A spell cast successfully with the knuckles equipped charges them: each of the next strikes carries
-- a share of that spell. The share is an enchantment (global.lua makes it), and each of those swings
-- is made with a copy of the knuckles that carries it (swingcopy.lua), so the engine strikes with it
-- as with any enchanted weapon - its sounds and looks, reflection, absorption, resistances. The charge
-- is kept here, because it is the wielder's: the crystal glows while it lasts (below), and it is
-- shown in the active effects as a "Channeled Spell" whose magnitude is the strikes left.
local SCHOOLS = {
    alteration = true, conjuration = true, destruction = true,
    illusion = true, mysticism = true, restoration = true,
}

local fury = {
    enchant = nil, -- the enchantment carrying the share of the spell a strike carries
    name = "",
    strikes = 0,
    fadesAt = 0,
    shown = nil,   -- record id of the active spell showing the charge
    -- The knuckles in hand when the swing wound up, and their charge then, before the strike took any.
    windUpItem = nil,
    chargeAtWindUp = nil,
}

local function showFury()
    local spells = types.Actor.activeSpells(omwself)
    if fury.shown then
        local stale = {}
        for _, params in pairs(spells) do
            if string.lower(params.id) == fury.shown then stale[#stale + 1] = params.activeSpellId end
        end
        for i = 1, #stale do spells:remove(stale[i]) end
        fury.shown = nil
    end
    if fury.strikes <= 0 then return end

    local id = U.MAGE_FURY_CHARGE_SPELLS[fury.strikes]
    if core.magic.spells.records[id] == nil then return end
    spells:add({ id = id, effects = { 0 }, name = fill(l10n("fury_active"), { spell = fury.name }) })
    fury.shown = string.lower(id)
end

local function clearFury()
    fury.strikes = 0
    fury.enchant = nil
    showFury()
end

-- The enchantment a swing winding up now strikes with instead of the knuckles' own, or nil.
local function furyEnchant()
    if fury.strikes <= 0 or core.getSimulationTime() >= fury.fadesAt then return nil end
    return fury.enchant
end

-- Two things report a successful cast. The engine reports its own as a skill use - a failed one is
-- not (CastSpell::cast) - and the spell is the selected one. Spell Framework Plus, which Oblivion-
-- Style Spell Casting casts through, reports its casts as MagExp_CastResult, naming the spell; that
-- mod may report a skill use for the same cast too, and its spell is not necessarily the selected
-- one. So within CAST_REPORT_WINDOW of each other, whichever order they come in, MagExp's word wins.
-- Casting may be done with the weapon put away, so this asks what is equipped, not what is drawn.
-- Whether the spell has anything to hand on is global.lua's call.
local CAST_REPORT_WINDOW = 1.0
local lastCastReport = -math.huge
local lastSkillCharge = -math.huge

local function chargeMageFury(spellId)
    core.sendGlobalEvent("H2HWeapons_ChargeMageFury", { actor = omwself.object, spell = spellId })
end

I.SkillProgression.addSkillUsedHandler(function(skillid, options)
    if not SCHOOLS[skillid] or options.useType ~= SPELLCAST_SUCCESS then return end
    if equippedSpecial ~= SPECIAL.MageFury then return end
    local now = core.getSimulationTime()
    if now - lastCastReport < CAST_REPORT_WINDOW then return end -- charged from the report already
    local spell = types.Actor.getSelectedSpell(omwself)
    if spell == nil then return end
    lastSkillCharge = now
    chargeMageFury(spell.id)
end)

local function onCastReport(e)
    if e == nil or not e.success or e.spellId == nil then return end
    local now = core.getSimulationTime()
    lastCastReport = now
    if equippedSpecial ~= SPECIAL.MageFury then return end
    -- An enchanted item's cast is reported too, under the enchantment's id; only spells charge.
    if core.magic.spells.records[e.spellId] == nil then return end
    -- A charge taken from the selected spell a moment ago was this same cast: undo it, and charge
    -- from the spell that was actually cast - or from nothing, if it has nothing to hand on.
    if now - lastSkillCharge < CAST_REPORT_WINDOW then
        lastSkillCharge = -math.huge
        clearFury()
    end
    chargeMageFury(e.spellId)
end

local function onMageFuryCharged(e)
    fury.enchant = e.enchant
    fury.name = e.name or ""
    fury.strikes = U.MAGE_FURY_STRIKES
    fury.fadesAt = core.getSimulationTime() + U.MAGE_FURY_FADE
    showFury()
end

-- A strike with the knuckles landed (actor.lua). The engine has charged it by now, as it would any
-- enchanted weapon's - the Enchant skill's share off - or refused, and said so, with too little left;
-- what it took is read off the charge, which the swing's wind-up saw before. A strike made with the
-- swing's copy carried the spell, and spends a strike of the charge - unless the engine refused it,
-- which carried nothing. One made with the knuckles themselves - uncharged, or a swing let go before
-- the copy came - carried nothing either, and gets back what their own enchantment took, which is a
-- channelled strike's price (content.lua). In god mode the engine casts without charging anything
-- (CastSpell::cast).
local function onMageFuryStrike(e)
    if e.victim == nil or e.item == nil then return end
    local before, knuckles = fury.chargeAtWindUp, fury.windUpItem
    fury.chargeAtWindUp, fury.windUpItem = nil, nil
    local channelled = knuckles ~= nil and e.item ~= knuckles
    -- The copy may be folded back into the knuckles by now, its charge with it.
    local struck = e.item:isValid() and e.item or knuckles
    local after = struck and struck:isValid() and types.Item.itemData(struck).enchantmentCharge
    local paid = (before and after) and before - after or 0
    local free = debug.isGodMode()

    local now = core.getSimulationTime()
    if fury.strikes > 0 and now >= fury.fadesAt then clearFury() end
    if not channelled then
        if paid > 0 then core.sendGlobalEvent("H2HWeapons_ChargeUse", { item = e.item, delta = paid }) end
        return
    end
    if (paid <= 0 and not free) or fury.strikes <= 0 then return end
    fury.strikes = fury.strikes - 1
    fury.fadesAt = now + U.MAGE_FURY_FADE
    if fury.strikes <= 0 then fury.enchant = nil end
    showFury()
end

--- Hung on the hands ------------------------------------------------------------------------------
-- Two things hang off bones (hands.lua): the off-hand copy of the weapon, on "Weapon Bone.L", and a
-- charged weapon's glow, on both weapon bones. The glow is a "<mesh>_charged.nif" beside the weapon's
-- mesh (weapons.chargeModelOfId): a particle system authored in the weapon's own local space, so
-- hanging it on the bone drops it inside the weapon.
--
-- Switching between first and third person swaps the whole model, skeleton and all, and everything
-- attached to it goes too. So the view is watched - first person or not, which is what picks the
-- model - and a couple of frames after it changes, once the new model exists, everything is attached
-- again from scratch. A teleport or a load starts over the same way. So does passing time - resting,
-- waiting, jail, travel, training - which strips every actor nearby of its effects (Actors::rest,
-- removeEffects) and puts back only magic effects' own; the NPCs around are told to do the same.
--
-- The off hand shows while the right hand does. The engine shows and hides the weapon on the weapon
-- group's "equip attach" and "unequip detach" keys (CharacterController::handleTextKey), partway
-- through drawing and sheathing, so those are followed here too: the stance changes the moment a
-- sheathe starts, the weapon only when the hand gets to it. A stance changed with no such animation
-- - a load, a script - is taken as it is once no key has come for a moment.
local OFF_HAND, GLOW_RIGHT, GLOW_LEFT = 1, 2, 3
local onBones = hands.new(omwself, {
    [OFF_HAND] = { vfxId = "H2HWeapons_OffHand", bone = "Weapon Bone.L" },
    [GLOW_RIGHT] = { vfxId = "H2HWeapons_Charge_R", bone = "Weapon Bone" },
    [GLOW_LEFT] = { vfxId = "H2HWeapons_Charge_L", bone = "Weapon Bone.L" },
})
local REATTACH_DELAY = 2

local firstPerson = nil   -- nil: start over on the next update
local reattachIn = 0

local WEAPON_KEY_WAIT = 1.5
-- Screens that pass time, after which everything attached has been taken off (see above).
local TIME_PASSING_MODES = { Rest = true, Jail = true, Travel = true, Training = true }

local weaponShown = nil   -- whether the right hand shows the weapon; nil: take the stance's word
local lastStance = nil
local stanceChangedAt = 0

for _, group in ipairs(swing.WEAPON_GROUP_LIST) do
    I.AnimationController.addTextKeyHandler(group, function(_, key)
        if key == swing.SHOW_KEY then
            weaponShown = true
        elseif key == swing.HIDE_KEY then
            weaponShown = false
        end
    end)
end

local function followWeaponShown(stance)
    local inStance = stance == WEAPON_STANCE
    local now = core.getSimulationTime()
    if weaponShown == nil then weaponShown = inStance end
    if stance ~= lastStance then
        lastStance = stance
        stanceChangedAt = now
    end
    if weaponShown ~= inStance and now - stanceChangedAt > WEAPON_KEY_WAIT then weaponShown = inStance end
end

local function updateAttachments(stance)
    followWeaponShown(stance)
    local isFirstPerson = camera.getMode() == FIRST_PERSON
    if isFirstPerson ~= firstPerson then
        firstPerson = isFirstPerson
        onBones.detachAll()
        reattachIn = REATTACH_DELAY
    end
    if reattachIn > 0 then
        reattachIn = reattachIn - 1
        return
    end

    local drawn = equippedHandToHand and weaponShown
    local offHand = (drawn and equippedModel) or nil
    local glow = (drawn and fury.strikes > 0 and equippedChargeModel) or nil
    onBones.attach(OFF_HAND, offHand)
    onBones.attach(GLOW_RIGHT, glow)
    -- Only a hand holding something can glow.
    onBones.attach(GLOW_LEFT, (offHand and glow) or nil)
end

-- Time passed: everything on everyone's bones nearby is gone. NPCs, and creatures that can hold these,
-- keep their own (npc.lua).
local function afterTimePassed()
    onBones.forget()
    local me = omwself.object
    for _, actor in ipairs(nearby.actors) do
        if actor ~= me and weapons.canWield(actor) then actor:sendEvent("H2HWeapons_Reattach", {}) end
    end
end

--- The left hand --------------------------------------------------------------------------------
-- Nothing in it while one swung with the hand-to-hand moveset is out (carriedleft.lua): out from the
-- moment the stance says so, to the moment the hand has put it away, which is when the engine hides
-- and shows a shield or torch with bare fists. Something equipped with the game paused, in the
-- inventory, comes off when it resumes.
local left = carriedLeft.new(omwself)

--- The uniques' swings ------------------------------------------------------------------------------
-- Ebony Rose's burst is counted by rose.lua, shared with the NPCs who carry it. The swing that bursts,
-- and each that carries Mage Fury's spell, is made with a copy of the weapon carrying that enchantment
-- (swingcopy.lua); this tells it when a swing winds up and follows through (below).
local rose = roseState.new()
local copy = swingCopy.new(omwself)

--- Draw and sheathe sound -------------------------------------------------------------------------
-- The engine plays a weapon's draw and sheathe sound for anything that is not hand-to-hand
-- (character.cpp:1417, :1477), and hybrids officially are not. Bare hands are silent, and so is a
-- hybrid whose definition says silentDraw - katars and knuckledusters. There is no hook for a sound
-- about to play, so it is stopped instead: the engine plays it after the animation it belongs to,
-- which is the event we see, so the stop lands on the next update - well under a frame of audio.
local SILENCE_UPDATES = 8

local silenceSounds = nil
local silenceLeft = 0

local function silenceDrawSounds()
    if silenceLeft <= 0 then return end
    silenceLeft = silenceLeft - 1
    core.sound.stopSound3d(silenceSounds[1], omwself)
    core.sound.stopSound3d(silenceSounds[2], omwself)
end

--- Animation events -------------------------------------------------------------------------------
-- One handler for the whole script, so the attack and equip sections are read once. It runs for
-- every playBlended on the player, including other mods', so anything that is not one of the weapon
-- groups leaves on the first table lookup.
I.AnimationController.addPlayBlendedAnimationHandler(function(groupname, options)
    if not swing.WEAPON_GROUPS[groupname] then return end

    local startKey = options.startKey or options.startkey
    if startKey == nil then return end

    if startKey == "equip start" or startKey == "unequip start" then
        -- The sheathe plays while the weapon is still in hand, and a swap plays the incoming
        -- weapon's group, so the current item is the right one to ask either way.
        refreshEquipped()
        if equippedHybrid and equippedHybrid.silentDraw then
            silenceSounds = equippedHybrid.drawSounds
            silenceLeft = SILENCE_UPDATES
        end
        return
    end

    if not equippedHybrid then return end

    if swing.isWindUpStart(startKey) then
        applySkillSwap(equippedHybrid)
        -- Read from the hand rather than the cached equipment: a swing's copy may have gone back only
        -- a moment ago, and the cache still have it.
        local item = types.Actor.getEquipment(omwself, CARRIED_RIGHT)
        local enchant = rose.enchantFor(item)
        if item and weapons.specialOfItem(item) == SPECIAL.MageFury then
            fury.windUpItem = item
            fury.chargeAtWindUp = types.Item.itemData(item).enchantmentCharge
            enchant = furyEnchant()
        end
        copy.windUp(item, enchant)
    elseif swing.isFollowStart(startKey) then
        -- The hit has been rolled and dealt by now.
        revertSkillSwap()
        copy.followStart()
    end
end)

--- Tooltips ---------------------------------------------------------------------------------------
-- Two tooltip mods are dressed up, both optional: Inventory Extender's, in the inventory, and the
-- Shared Tooltip QuickLoot shows for what is under the crosshair. Their interfaces may not exist yet
-- when this script loads, so they are picked up on the first update instead. Both get the type line
-- naming the hybrid's two skills, and a fatigue damage line under the damage ones for one that deals
-- it; Inventory Extender's, which has the room for it, the definition's footnote on how the weapon
-- runs on its skills as well.
local tooltipsTried = false

local function fatigueRange(hybrid)
    local factor = hybrid.fatigueDamage
    local strengthFactor = cfg.strengthFactor
    -- The plain GameObject, not the self handle: formulas does a types.NPC.objectIsInstance on it.
    local player = omwself.object
    return formulas.handToHandFatigue(player, 0, strengthFactor) * factor,
           formulas.handToHandFatigue(player, 1, strengthFactor) * factor
end

-- Whole numbers, like the chop/slash/thrust lines they go under.
local function fatigueNumbers(hybrid)
    local low, high = fatigueRange(hybrid)
    return math.floor(low + 0.5), math.floor(high + 0.5)
end

local function skillName(skillid)
    local record = core.stats.Skill.records[skillid]
    return record and record.name or skillid
end

-- What a hybrid's tooltip text can say, as %{name} (README.md lists them): its skills' names, and the
-- player's numbers - read here rather than once, so the tooltip is right after a level up, a fortify
-- effect or a change to the settings.
local function tooltipValues(hybrid)
    local primary, secondary, effective = hybridSkills(hybrid)
    local function whole(value) return string.format("%d", math.floor(value + 0.5)) end
    return {
        primarySkill = skillName(hybrid.primarySkill),
        secondarySkill = skillName(hybrid.secondarySkill),
        weaponSkill = skillName(hybrid.weaponSkill),
        primary = whole(primary),
        secondary = whole(secondary),
        effective = whole(effective),
        bonus = string.format("%+d", math.floor(effective - primary + 0.5)),
        lowest = whole(math.min(primary, secondary)),
        highest = whole(math.max(primary, secondary)),
        primaryExperience = whole(hybrid.primaryExperience * 100) .. "%",
        secondaryExperience = whole(hybrid.secondaryExperience * 100) .. "%",
    }
end

-- The definition's footnote, or the one for its scaling.
local DEFAULT_TOOLTIPS = {
    [weapons.SCALING.MinorSecondaryBonus] = "tooltip_minor_secondary_bonus",
    [weapons.SCALING.LowestSkill] = "tooltip_lowest_skill",
    [weapons.SCALING.HighestSkill] = "tooltip_highest_skill",
}
local function footnote(hybrid, values)
    return fill(hybrid.tooltip or l10n(DEFAULT_TOOLTIPS[hybrid.scaling]), values)
end

-- The type line reads "Type: Short Blade, One Handed". Only the weapon's skill name is replaced -
-- "Hand-to-hand (Short Blade)" - so the label, the separator and the handedness all stay in the
-- player's own language.
local function hybridType(text, values)
    local pattern = values.weaponSkill:gsub("(%W)", "%%%1")
    local label = fill(l10n("tooltip_type"), values):gsub("%%", "%%%%")
    return (text:gsub(pattern, label, 1))
end

-- A line put in at a place in a ui content list. Not content:insert, which in 0.51 files the lines
-- it moves down under the lines themselves rather than their names (components/lua_ui/content.lua),
-- so a lookup by name below it - ours, Inventory Extender's own, another mod's - finds the wrong
-- line. Taking the tail off and putting it back goes through removal and add, which both keep the
-- names right, and the list stays the same object for whoever else holds it.
local function insertLine(content, index, line)
    local tail = {}
    while #content >= index do
        tail[#tail + 1] = content[#content]
        content[#content] = nil
    end
    content:add(line)
    for i = #tail, 1, -1 do content:add(tail[i]) end
end

local function registerInventoryExtender()
    if not I.InventoryExtender then return end

    -- Inventory Extender's own text templates, so the added lines match the rest of the tooltip
    -- (its font size setting included). MWUI's are the same thing without that, as a fallback.
    local ok, base = pcall(require, "scripts.InventoryExtender.ui.templates.base")
    base = ok and base or nil
    local textNormal = (base and base.textNormal) or I.MWUI.templates.textNormal
    -- The footnote wraps, so it needs a paragraph template and a width to wrap at. This is how
    -- Inventory Extender builds the lore text it shows at the bottom of a tooltip.
    local textParagraph = (base and base.textParagraph) or I.MWUI.templates.textParagraph
    local okConst, constants = pcall(require, "scripts.InventoryExtender.util.constants")
    local DIMMED = (okConst and constants and constants.Colors and constants.Colors.DISABLED)
        or util.color.rgb(0.6, 0.6, 0.6)
    local FOOTNOTE_WIDTH = 320

    I.InventoryExtender.registerTooltipModifier("H2HWeapons", function(item, layout)
        local hybrid = weapons.hybridOfItem(item)
        if not hybrid then return end

        local found, inner = pcall(function() return layout.content.padding.content.tooltip.content end)
        if not found or not inner then return end

        local values = tooltipValues(hybrid)
        local typeEntry = inner:indexOf("type") and inner.type
        if typeEntry then
            typeEntry.props.text = hybridType(typeEntry.props.text, values)
        end

        if hybrid.fatigueDamage > 0 then
            local low, high = fatigueNumbers(hybrid)
            local line = {
                name = "h2hFatigue",
                template = textNormal,
                props = { text = string.format("%s: %d - %d", l10n("tooltip_fatigue"), low, high) },
            }
            local after = inner:indexOf("thrust") or inner:indexOf("attack") or inner:indexOf("type")
            if after then
                insertLine(inner, after + 1, line)
            else
                inner:add(line)
            end
        end

        -- And a footnote at the bottom saying how this weapon actually runs on its skills, since
        -- "Hand-to-hand (Short Blade)" on the type line does not say what the short blade is for.
        inner:add({
            name = "h2hExplanation",
            template = textParagraph,
            props = {
                text = footnote(hybrid, values),
                textColor = DIMMED,
                autoSize = true,
                size = util.vector2(FOOTNOTE_WIDTH, 0),
            },
        })
    end)
end

-- QuickLoot's tooltips come from Shared Tooltip, a library other mods bundle too, so this covers any
-- of them that use it. A modifier is handed the built layout and the library's own helpers: its
-- textElement makes a line in the tooltip's style, colours, size and alignment, and puts it in place.
-- No footnote here: these show at a glance while looting, and stay short.
local function registerSharedTooltip()
    local shared = I.SharedTooltip
    if not (shared and shared.registerModifier) then return end

    shared.registerModifier({
        id = "H2HWeapons",
        func = function(ctx)
            if ctx.itemType ~= types.Weapon then return end
            -- A tooltip for a record rather than an object has no item.
            local hybrid = (ctx.item and weapons.hybridOfItem(ctx.item))
                or (not ctx.item and ctx.rawRecord and weapons.hybridOfId(ctx.rawRecord.id))
            if not hybrid then return end

            local content = ctx.flex.content
            local typeIndex = content:indexOf("weaponType")
            if typeIndex then
                local typeLine = content[typeIndex]
                typeLine.props.text = hybridType(typeLine.props.text, tooltipValues(hybrid))
            end
            if hybrid.fatigueDamage <= 0 then return end

            -- Written as its own damage lines are: label and value in the tooltip's two colours,
            -- tight or spaced as its short text setting has them.
            local low, high = fatigueNumbers(hybrid)
            local separator = (ctx.style and ctx.style.shortText) and "-" or " - "
            local text = (ctx.labelTag or "") .. l10n("tooltip_fatigue") .. ": "
                .. (ctx.valueTag or "") .. low .. separator .. high
            local after = content:indexOf("thrust") or content:indexOf("attack") or typeIndex
            ctx.textElement(text, nil, "h2hFatigue", after and after + 1 or nil)
        end,
    })
end

local function registerTooltipModifiers()
    pcall(registerInventoryExtender)
    pcall(registerSharedTooltip)
end

--- Bound Fist, however it was cast -------------------------------------------------------------------
-- actor.lua notices the engine's casts and Spell Framework Plus' as they happen. This catches the
-- rest - a casting mod that reports neither, a console cast - by watching for the effect itself,
-- twice a second through MSS, and telling actor.lua when it appears.
local FIST_WATCH_INTERVAL = 0.5
local nextFistWatch = 0
local fistWasOn = false

local function watchForFist()
    if not weapons.effectExists(U.BOUND_FIST_EFFECT) then return end
    local now = core.getSimulationTime()
    if now < nextFistWatch then return end
    nextFistWatch = now + FIST_WATCH_INTERVAL
    local on = (I.MSS.getActiveEffect(U.BOUND_FIST_EFFECT, FIST_WATCH_INTERVAL) or 0) > 0
    if on and not fistWasOn then omwself:sendEvent("H2HWeapons_FistSeen", {}) end
    fistWasOn = on
end

--- Per frame --------------------------------------------------------------------------------------
local pendingCopyReturn = nil

local function onUpdate(dt)
    if dt <= 0 then return end

    if not tooltipsTried then
        tooltipsTried = true
        registerTooltipModifiers()
    end
    if not scalingReported then
        scalingReported = true
        reportBoundScaling()
    end

    local stance = types.Actor.getStance(omwself)
    local changed = refreshEquipped()

    -- Sheathing or swapping mid-swing has to put the skill back, and so does a swing that never
    -- reached its follow-through - but not the swing's own copy coming into the hand, which is the
    -- same weapon to everything here. The same goes for that copy.
    if swappedSkill and ((changed and not copy.isSwapped()) or stance ~= WEAPON_STANCE
        or core.getSimulationTime() - swappedAt > SWAP_TIMEOUT) then
        revertSkillSwap()
    end
    copy.check(stance)
    if pendingCopyReturn then
        -- Saved mid-swing: the copy was in hand.
        copy.restore(pendingCopyReturn)
        pendingCopyReturn = nil
    end

    if fury.strikes > 0 and core.getSimulationTime() >= fury.fadesAt then clearFury() end
    watchForFist()

    updateAttachments(stance)
    left.update(equippedHandToHand and (stance == WEAPON_STANCE or weaponShown) or false)
    silenceDrawSounds()
end

return {
    interfaceName = "H2HWeapons",
    interface = {
        version = 1,
        --- The hybrid weapon a record id is, or false: its definition's fields (primarySkill,
        --- secondarySkill, primaryExperience, secondaryExperience, scaling, moveset, fatigueDamage,
        --- tooltip, silentDraw, swingSounds) and what its record adds (weaponSkill, handToHand,
        --- drawSounds, model).
        --- Shared - read it, never change it.
        hybridOfId = weapons.hybridOfId,
        --- The same for an item object.
        hybridOfItem = weapons.hybridOfItem,
        --- The hybrid in the player's right hand, or false.
        equippedHybrid = function() return equippedHybrid end,
    },
    eventHandlers = {
        H2HWeapons_VenomStrike = rose.onVenomStrike,
        H2HWeapons_CopyStaged = copy.onStaged,
        H2HWeapons_MageFuryCharged = onMageFuryCharged,
        H2HWeapons_MageFuryStrike = onMageFuryStrike,
        -- Passing time took off everything attached; forget it, and it goes back on.
        UiModeChanged = function(e)
            if e and TIME_PASSING_MODES[e.oldMode] then afterTimePassed() end
        end,
        -- Spell Framework Plus' report of a cast it made. Listened to, never consumed.
        MagExp_CastResult = onCastReport,
    },
    engineHandlers = {
        onUpdate = onUpdate,
        onTeleported = function() firstPerson = nil end,
        onSave = function()
            -- A save taken mid-swing has the nudged modifier baked into it; remember it so the load
            -- can take it back out. Likewise a swing's copy of the weapon, if it was in hand.
            return {
                swappedSkill = swappedSkill,
                swappedDelta = swappedDelta,
                burstSwap = copy.save(),
                leftHand = left.save(),
                fury = { enchant = fury.enchant, name = fury.name, strikes = fury.strikes,
                         fadesAt = fury.fadesAt, shown = fury.shown },
            }
        end,
        onLoad = function(data)
            -- The model is new; whatever was attached went with the old one.
            onBones.forget()
            firstPerson = nil
            weaponShown = nil
            lastStance = nil
            scalingReported = false
            fistWasOn = false
            if not data then return end
            if data.swappedSkill then
                swappedSkill = data.swappedSkill
                swappedDelta = data.swappedDelta or 0
                swappedAt = 0
                revertSkillSwap()
            end
            if data.burstSwap then
                pendingCopyReturn = data.burstSwap
            end
            left.load(data.leftHand)
            if data.fury and (data.fury.strikes or 0) > 0 and data.fury.enchant then
                fury.enchant = data.fury.enchant
                fury.name = data.fury.name or ""
                fury.strikes = data.fury.strikes
                fury.fadesAt = data.fury.fadesAt or 0
                fury.shown = data.fury.shown
            end
        end,
    },
}

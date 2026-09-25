-- Everything that makes a katar or a knuckleduster behave like a hand-to-hand weapon on the player:
-- the skill the engine rolls against, where the experience goes, the second weapon in the off hand,
-- the draw sound it should not make, and what the tooltip says - and the wielder's half of the two
-- uniques' magic: Ebony Rose's burst and Mage Fury's stored spell.
--
-- The engine has no hand-to-hand weapon type, so these are a short blade and a blunt weapon as far
-- as it is concerned. Each piece below puts one of its assumptions back.
--
-- Per frame this costs: one getStance, one camera.getMode, one equipment lookup that Max Yari's
-- Script Services answers from its own cache ten times a second, and a handful of compares.
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
local ui = require('openmw.ui')
local util = require('openmw.util')

local formulas = require(mp .. "scripts/formulas")
local settings = require(mp .. "scripts/settings")
local U = require(mp .. "scripts/uniques")
local weapons = require(mp .. "scripts/weapons")

local cfg = settings.values

-- MSS answers the equipment lookup this script makes every frame. ReAnimation requires it too, so
-- it should always be there; if it is not, say so once rather than failing with a stack trace.
if not core.contentFiles.has("MaxYariScriptServices.omwscripts") then
    print("[H2HWeapons] ERROR: Max Yari's Script Services (MSS) is missing. It is required.")
    ui.showMessage("Katars and Knuckledusters: Max Yari's Script Services (MSS) is missing, please install it.")
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

-- The engine's own long animation group for each of these weapon types, plus weapononehand, which
-- is what both fall back to when the specific group has no animation - which, in vanilla, is always
-- (character.cpp:575-600). Used only to skip other mods' playBlended calls cheaply.
local WEAPON_GROUPS = {
    weapononehand = true,
    shortbladeonehand = true,
    bluntonehand = true,
}

--- Settings page ----------------------------------------------------------------------------------
-- The settings themselves are global (see global.lua): the fatigue damage is worked out on whoever
-- is hit, and only a global section can be read from an NPC's script.
I.Settings.registerPage {
    key = "H2HWeapons",
    l10n = "H2HWeapons",
    name = "page_name",
    description = "page_description",
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
local equippedKind = false
local equippedSpecial = false
local equippedModel = nil
local equippedChargeModel = nil

local function refreshEquipped()
    local info = I.MSS.getEquipmentInfo(CARRIED_RIGHT, EQUIPMENT_CACHE_TIME)
    if info == equippedInfo then return false end
    equippedInfo = info
    local kind = info and weapons.kindOfId(info.recordId) or false
    local changed = kind ~= equippedKind
    equippedKind = kind
    equippedSpecial = kind and weapons.specialOfId(info.recordId) or false
    equippedModel = kind and weapons.modelOfId(info.recordId) or nil
    equippedChargeModel = kind and weapons.chargeModelOfId(info.recordId) or nil
    return changed
end

--- Hit chance -------------------------------------------------------------------------------------
-- Npc::evaluateHit rolls against getSkill(attacker, the weapon's equipment skill) - Short Blade for
-- a katar, Blunt Weapon for knuckledusters - and there is no hook for that number. So for the length
-- of a swing the weapon skill *is* the hand-to-hand value: the modifier is nudged by the difference
-- and put back afterwards. Skill modifiers are only ever added to and subtracted from (fortify and
-- drain effects do the same, spelleffects.cpp:131), so this composes with them rather than fighting
-- them.
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

local function applySkillSwap(kind)
    revertSkillSwap() -- an interrupted previous swing may still be holding one

    local skillName = weapons.WEAPON_SKILL[kind]
    local weaponStat = SKILLS[skillName](omwself)
    local weaponSkill = weaponStat.modified
    local handToHand = SKILLS.handtohand(omwself).modified

    local effective = formulas.effectiveSkill(handToHand, weaponSkill, cfg)
    local delta = effective - weaponSkill
    -- getHitChance truncates the skill to an int, so anything under a point changes nothing.
    if delta > -0.5 and delta < 0.5 then return end

    weaponStat.modifier = weaponStat.modifier + delta
    swappedSkill = skillName
    swappedDelta = delta
    swappedAt = core.getSimulationTime()
end

--- Experience -------------------------------------------------------------------------------------
-- Npc::hit credits the weapon's own skill on a successful hit and there is no way to redirect it at
-- the source, so it is split here instead: the weapon skill keeps its share and hand-to-hand is
-- credited separately. The nested skillUsed re-enters this handler with skillid "handtohand", which
-- the first line drops, so it cannot recurse.
I.SkillProgression.addSkillUsedHandler(function(skillid, options)
    if skillid == "handtohand" then return end
    if options.useType ~= WEAPON_SUCCESSFUL_HIT then return end
    if not equippedKind then return end
    if skillid ~= weapons.WEAPON_SKILL[equippedKind] then return end

    local share = cfg.handToHandShare
    if options.skillGain then options.skillGain = options.skillGain * (1 - share) end

    I.SkillProgression.skillUsed("handtohand", {
        useType = WEAPON_SUCCESSFUL_HIT,
        scale = share,
    })
end)

--- Mage Fury's charge ---------------------------------------------------------------------------
-- A spell cast successfully with the knuckles equipped charges them; each of the next strikes hands
-- the one struck a share of that spell (global.lua makes it, actor.lua applies it). The charge is
-- kept here, because it is the wielder's: the crystal glows while it lasts (below), and it is shown
-- in the active effects as a "Channeled Spell" whose magnitude is the strikes left.
local SCHOOLS = {
    alteration = true, conjuration = true, destruction = true,
    illusion = true, mysticism = true, restoration = true,
}

local fury = {
    spell = nil,   -- the share of the spell a strike carries
    name = "",
    strikes = 0,
    fadesAt = 0,
    shown = nil,   -- record id of the active spell showing the charge
    chargeAtWindUp = nil, -- the knuckles' charge when the swing wound up, before the strike took any
}
-- I.H2HWeapons.setCharged: light the glow without casting anything, to look at it. nil: follow the
-- charge.
local forcedCharge = nil

local function isCharged()
    if forcedCharge ~= nil then return forcedCharge end
    return fury.strikes > 0
end

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
    fury.spell = nil
    showFury()
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
    fury.spell = e.spell
    fury.name = e.name or ""
    fury.strikes = U.MAGE_FURY_STRIKES
    fury.fadesAt = core.getSimulationTime() + U.MAGE_FURY_FADE
    showFury()
end

-- The knuckles' enchantment is cast on strike at a channelled strike's full price (content.lua), so by
-- the time a strike is reported the engine has charged it as it would any enchanted weapon's - the
-- Enchant skill's share off - or refused, and said so, with too little left. What it took is read off
-- the charge: the swing's wind-up saw it before. A strike that carried the spell keeps it paid; any
-- other gets it back. One the engine refused carries nothing, and there is nothing to give back.
-- In god mode the engine casts it without charging anything (CastSpell::cast), so nothing is read.
local function onMageFuryStrike(e)
    if e.victim == nil or e.item == nil then return end
    local before = fury.chargeAtWindUp
    fury.chargeAtWindUp = nil
    local paid = before and (before - (types.Item.itemData(e.item).enchantmentCharge or before)) or 0
    local free = debug.isGodMode()
    if paid <= 0 and not free then return end

    local now = core.getSimulationTime()
    if fury.strikes > 0 and now >= fury.fadesAt then clearFury() end
    if fury.strikes <= 0 then
        if paid > 0 then core.sendGlobalEvent("H2HWeapons_ChargeUse", { item = e.item, delta = paid }) end
        return
    end
    e.victim:sendEvent("H2HWeapons_MageFuryDischarge", {
        spell = fury.spell, caster = omwself.object, name = fury.name,
    })
    fury.strikes = fury.strikes - 1
    fury.fadesAt = now + U.MAGE_FURY_FADE
    if fury.strikes <= 0 then fury.spell = nil end
    showFury()
end

--- Hung on the hands ------------------------------------------------------------------------------
-- Two things hang off bones as looping VFX, which is the only way a script can put a model on one:
-- the off-hand copy of the weapon, on "Weapon Bone.L" - the mirror of the engine's own weapon bone
-- that this mod's skeleton meshes add - and a charged weapon's glow, on both weapon bones. The glow
-- is a "<mesh>_charged.nif" beside the weapon's mesh (weapons.chargeModelOfId): a particle system
-- authored in the weapon's own local space, so hanging it on the bone drops it inside the weapon.
--
-- Switching between first and third person swaps the whole model, skeleton and all, and everything
-- attached to it goes too. So the view is watched - first person or not, which is what picks the
-- model - and a couple of frames after it changes, once the new model exists, everything is attached
-- again from scratch. A teleport or a load starts over the same way. Otherwise something is
-- attached or taken off only when what should be there changes.
local ATTACHMENTS = {
    { vfxId = "H2HWeapons_OffHand", bone = "Weapon Bone.L" },
    { vfxId = "H2HWeapons_Charge_R", bone = "Weapon Bone" },
    { vfxId = "H2HWeapons_Charge_L", bone = "Weapon Bone.L" },
}
local OFF_HAND, GLOW_RIGHT, GLOW_LEFT = 1, 2, 3
local REATTACH_DELAY = 2

local attached = {}       -- [attachment] = the model on it, as far as this script knows
local firstPerson = nil   -- nil: start over on the next update
local reattachIn = 0
local boneWarned = {}

local function warnMissingBone(bone)
    if boneWarned[bone] then return end
    boneWarned[bone] = true
    -- The bone is grafted onto whichever skeleton the engine loads, from
    -- animations/<that skeleton>/h2h_weapon_bone_l.nif (Animation::injectCustomBones) - which only
    -- happens with "use additional animation sources" on.
    print("[H2HWeapons] this actor's skeleton has no '" .. bone .. "' bone, so nothing can be shown " ..
        "on it. It is added from Animations/<skeleton>/h2h_weapon_bone_l.nif, and only with 'Use " ..
        "additional animation sources' on (launcher: Settings -> Visuals -> Animations). A skeleton " ..
        "this mod has no folder for will not get it: re-run Sources/Tools/patch_skeleton.py " ..
        "--bones-out on it.")
end

local function attach(index, model)
    if attached[index] == model then return end
    local slot = ATTACHMENTS[index]
    if attached[index] then animation.removeVfx(omwself, slot.vfxId) end
    attached[index] = model
    if model == nil then return end
    -- The engine throws for a bone that is not there. A missing one is still recorded as attached,
    -- so it is asked about once per change rather than every frame.
    if not animation.hasBone(omwself, slot.bone) then
        warnMissingBone(slot.bone)
        return
    end
    animation.addVfx(omwself, model, {
        vfxId = slot.vfxId,
        boneName = slot.bone,
        loop = true,
        useAmbientLight = false,
    })
end

local function detachAll()
    for i = 1, #ATTACHMENTS do
        -- Harmless when the model they were on is already gone.
        if attached[i] then animation.removeVfx(omwself, ATTACHMENTS[i].vfxId) end
        attached[i] = nil
    end
end

local function updateAttachments(stance)
    local isFirstPerson = camera.getMode() == FIRST_PERSON
    if isFirstPerson ~= firstPerson then
        firstPerson = isFirstPerson
        detachAll()
        reattachIn = REATTACH_DELAY
    end
    if reattachIn > 0 then
        reattachIn = reattachIn - 1
        return
    end

    local drawn = equippedKind and stance == WEAPON_STANCE
    local offHand = (drawn and cfg.showOffHandWeapon and equippedModel) or nil
    local glow = (drawn and isCharged() and equippedChargeModel) or nil
    attach(OFF_HAND, offHand)
    attach(GLOW_RIGHT, glow)
    -- Only a hand holding something can glow.
    attach(GLOW_LEFT, (offHand and glow) or nil)
end

--- Ebony Rose ------------------------------------------------------------------------------------
-- Whoever it strikes reports the strike (actor.lua). Strikes on one enemy run on while each lands
-- within BURST_CHAIN seconds of the one before - every strike renews the countdown - and the swing
-- that would be the third in a run bursts, if that enemy is poisoned when it winds up, by the venom
-- or by any other poison. Whether it is to burst has to be settled on the wind-up, before the blow
-- lands, so the one it lands on is taken to be the one the run was on.
--
-- The burst is a second enchantment, and an item cannot change its enchantment, so that swing is made
-- with a copy of the katar that carries it: global.lua makes one when the swing winds up, it goes in
-- the hand for the swing, and at the follow-through the original goes back and the copy is folded
-- into it. The two are the same weapon type, so the engine neither interrupts the swing nor plays a
-- draw (CharacterController only re-draws for a change of type), and the original never leaves the
-- inventory, so hotkeys never notice.
local rose = {
    target = nil,        -- the enemy the run of strikes is on
    strikes = 0,         -- how many in the run
    lastStrike = -math.huge,
    swinging = false,    -- between the wind-up and the follow-through
    staging = false,     -- a copy has been asked for and has not come
    swap = nil,          -- { original, copy, at } while the copy is in hand
}
local POISONS = { core.magic.EFFECT_TYPE.Poison or "poison", U.VENOM_EFFECT }

local function onVenomStrike(e)
    if e.burst or e.victim == nil then
        rose.target = nil
        rose.strikes = 0
        return
    end
    local now = core.getSimulationTime()
    if e.victim ~= rose.target or now - rose.lastStrike > U.BURST_CHAIN then
        rose.target = e.victim
        rose.strikes = 0
    end
    rose.strikes = rose.strikes + 1
    rose.lastStrike = now
end

local function isPoisoned(actor)
    local effects = types.Actor.activeEffects(actor)
    for i = 1, #POISONS do
        if weapons.effectExists(POISONS[i]) then
            local effect = effects:getEffect(POISONS[i])
            if effect and effect.magnitude > 0 then return true end
        end
    end
    return false
end

-- Whether the swing winding up now is the one that bursts.
local function burstDue()
    local target = rose.target
    if target == nil or rose.strikes < U.BURST_STRIKES - 1 then return false end
    if core.getSimulationTime() - rose.lastStrike > U.BURST_CHAIN then return false end
    return target:isValid() and isPoisoned(target)
end

local function stageBurst()
    if rose.swap or rose.staging or equippedInfo == nil then return end
    if not burstDue() then return end
    rose.staging = true
    core.sendGlobalEvent("H2HWeapons_StageBurst", { actor = omwself.object, item = equippedInfo.item })
end

local function returnCopy(original, copy)
    core.sendGlobalEvent("H2HWeapons_BurstDone", { original = original, copy = copy })
end

local function onBurstStaged(e)
    rose.staging = false
    if e.copy == nil then return end
    -- Too late for this swing, or the weapon has changed hands meanwhile: next swing, then.
    if not rose.swinging or types.Actor.getStance(omwself) ~= WEAPON_STANCE
        or types.Actor.getEquipment(omwself, CARRIED_RIGHT) ~= e.original then
        returnCopy(e.original, e.copy)
        return
    end
    local equipment = types.Actor.getEquipment(omwself)
    equipment[CARRIED_RIGHT] = e.copy
    types.Actor.setEquipment(omwself, equipment)
    rose.swap = { original = e.original, copy = e.copy, at = core.getSimulationTime() }
end

local function endBurstSwap()
    local swap = rose.swap
    if swap == nil then return end
    rose.swap = nil
    -- The original goes back - unless the player has changed weapons mid-swing, which stands.
    local equipment = types.Actor.getEquipment(omwself)
    if equipment[CARRIED_RIGHT] == swap.copy then
        equipment[CARRIED_RIGHT] = swap.original
        types.Actor.setEquipment(omwself, equipment)
    end
    returnCopy(swap.original, swap.copy)
end

--- Draw and sheathe sound -------------------------------------------------------------------------
-- The engine plays a weapon's draw and sheathe sound for anything that is not hand-to-hand
-- (character.cpp:1417, :1477), and these officially are not. Bare hands are silent, so these are
-- silenced too. There is no hook for a sound about to play, so it is stopped instead: the engine
-- plays it after the animation it belongs to, which is the event we see, so the stop lands on the
-- next update - well under a frame of audio.
local DRAW_SOUNDS = {
    [weapons.KIND.Katar] = { "Item Weapon Shortblade Up", "Item Weapon Shortblade Down" },
    [weapons.KIND.Knuckle] = { "Item Weapon Blunt Up", "Item Weapon Blunt Down" },
}
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
local ATTACK_TYPES = { "chop ", "slash ", "thrust " }
local FOLLOW_START = "follow start"
local FOLLOW_START_OFFSET = -#FOLLOW_START

local function isWindUpStart(key)
    if string.sub(key, -6) ~= " start" then return false end
    for i = 1, #ATTACK_TYPES do
        if string.find(key, ATTACK_TYPES[i], 1, true) == 1 then
            -- "slash start" is the wind up; "slash large follow start" is not.
            return string.find(key, FOLLOW_START, FOLLOW_START_OFFSET, true) == nil
        end
    end
    return false
end

I.AnimationController.addPlayBlendedAnimationHandler(function(groupname, options)
    if not WEAPON_GROUPS[groupname] then return end

    local startKey = options.startKey or options.startkey
    if startKey == nil then return end

    if startKey == "equip start" or startKey == "unequip start" then
        -- The sheathe plays while the weapon is still in hand, and a swap plays the incoming
        -- weapon's group, so the current item is the right one to ask either way.
        refreshEquipped()
        if cfg.silenceDrawSound and equippedKind then
            silenceSounds = DRAW_SOUNDS[equippedKind]
            silenceLeft = SILENCE_UPDATES
        end
        return
    end

    if not equippedKind then return end

    if isWindUpStart(startKey) then
        applySkillSwap(equippedKind)
        rose.swinging = true
        if equippedSpecial == SPECIAL.Venom then stageBurst() end
        if equippedSpecial == SPECIAL.MageFury and equippedInfo then
            fury.chargeAtWindUp = types.Item.itemData(equippedInfo.item).enchantmentCharge
        end
    elseif string.find(startKey, FOLLOW_START, FOLLOW_START_OFFSET, true) then
        -- The hit has been rolled and dealt by now.
        rose.swinging = false
        revertSkillSwap()
        endBurstSwap()
    end
end)

--- Tooltips ---------------------------------------------------------------------------------------
-- Inventory Extender is optional, and its interface may not exist yet when this script loads, so it
-- is picked up on the first update instead.
local tooltipsTried = false

local function fatigueRange(kind)
    local factor = weapons.FATIGUE_FACTOR[kind]
    local strengthFactor = cfg.strengthFactor
    -- The plain GameObject, not the self handle: formulas does a types.NPC.objectIsInstance on it.
    local player = omwself.object
    return formulas.handToHandFatigue(player, 0, strengthFactor) * factor,
           formulas.handToHandFatigue(player, 1, strengthFactor) * factor
end

local function registerTooltipModifier()
    if not I.InventoryExtender then return end

    local l10n = core.l10n("H2HWeapons")
    local handToHandName = core.getGMST("sSkillHandtohand")
    local skillNames = {
        [weapons.KIND.Katar] = core.getGMST("sSkillShortblade"),
        [weapons.KIND.Knuckle] = core.getGMST("sSkillBluntweapon"),
    }

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
        local kind = weapons.kindOfItem(item)
        if not kind then return end

        local found, inner = pcall(function() return layout.content.padding.content.tooltip.content end)
        if not found or not inner then return end

        -- The type line reads "Type: Short Blade, One Handed". Only the skill name is replaced, so
        -- the label, the separator and the handedness all stay in the player's own language.
        local typeEntry = inner.type
        local skillName = skillNames[kind]
        if typeEntry and skillName then
            local pattern = skillName:gsub("(%W)", "%%%1")
            typeEntry.props.text = typeEntry.props.text:gsub(
                pattern, handToHandName .. " (" .. skillName .. ")", 1)
        end

        local low, high = fatigueRange(kind)
        local line = {
            name = "h2hFatigue",
            template = textNormal,
            -- Whole numbers, like the chop/slash/thrust lines above it.
            props = { text = string.format("%s: %d - %d", l10n("tooltip_fatigue"),
                math.floor(low + 0.5), math.floor(high + 0.5)) },
        }
        local after = inner:indexOf("thrust") or inner:indexOf("attack") or inner:indexOf("type")
        if after then
            inner:insert(after + 1, line)
        else
            inner:add(line)
        end

        -- And a footnote at the bottom saying which skills this weapon actually runs on, since
        -- "Hand to Hand (Short Blade)" on the type line does not say what the short blade is for.
        -- The numbers are read here rather than at registration, so the tooltip is right after a
        -- level up, a fortify effect or a change to the settings.
        if skillName then
            local handToHand = SKILLS.handtohand(omwself).modified
            local weaponSkill = SKILLS[weapons.WEAPON_SKILL[kind]](omwself).modified
            local bonus = formulas.skillBonus(handToHand, weaponSkill, cfg)
            local text = l10n("tooltip_explanation")
                :gsub("%%{skill}", skillName)
                :gsub("%%{handToHand}", string.format("%d", math.floor(handToHand + 0.5)))
                :gsub("%%{bonus}", string.format("%+d", bonus))
            inner:add({
                name = "h2hExplanation",
                template = textParagraph,
                props = {
                    text = text,
                    textColor = DIMMED,
                    autoSize = true,
                    size = util.vector2(FOOTNOTE_WIDTH, 0),
                },
            })
        end

    end)
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
local pendingBurstReturn = nil

local function onUpdate(dt)
    if dt <= 0 then return end

    if not tooltipsTried then
        tooltipsTried = true
        pcall(registerTooltipModifier)
    end
    if not scalingReported then
        scalingReported = true
        reportBoundScaling()
    end

    local stance = types.Actor.getStance(omwself)
    local changed = refreshEquipped()

    -- Sheathing or swapping mid-swing has to put the skill back, and so does a swing that never
    -- reached its follow-through. The same goes for the copy of Ebony Rose held for a burst.
    if stance ~= WEAPON_STANCE then rose.swinging = false end
    if swappedSkill and (changed or stance ~= WEAPON_STANCE
        or core.getSimulationTime() - swappedAt > SWAP_TIMEOUT) then
        revertSkillSwap()
    end
    if rose.swap and (stance ~= WEAPON_STANCE
        or core.getSimulationTime() - rose.swap.at > SWAP_TIMEOUT) then
        endBurstSwap()
    end
    if pendingBurstReturn then
        -- Saved mid-swing: the copy was in hand. Put things back as the follow-through would have.
        rose.swap = pendingBurstReturn
        pendingBurstReturn = nil
        endBurstSwap()
    end

    if fury.strikes > 0 and core.getSimulationTime() >= fury.fadesAt then clearFury() end
    watchForFist()

    updateAttachments(stance)
    silenceDrawSounds()
end

return {
    interfaceName = "H2HWeapons",
    interface = {
        version = 1.1,
        --- What kind of hand-to-hand weapon a record id is: "katar", "knuckle", or false.
        kindOfId = weapons.kindOfId,
        --- The same for an item object.
        kindOfItem = weapons.kindOfItem,
        --- Which of the uniques' tricks a record id carries: "venom", "burst", "magefury", or false.
        specialOfId = weapons.specialOfId,
        --- Fatigue each kind deals, as a fraction of a bare-fisted hit. [kind] = number.
        FATIGUE_FACTOR = weapons.FATIGUE_FACTOR,
        --- The skill the engine believes each kind uses. [kind] = skill id.
        WEAPON_SKILL = weapons.WEAPON_SKILL,
        --- The kind in the player's right hand, or false.
        equippedKind = function() return equippedKind end,
        --- Force the charge glow on (true) or off (false) regardless of any charge; nil to follow it
        --- again. For looking at the effect.
        setCharged = function(value) forcedCharge = value end,
        isCharged = function() return isCharged() end,
        --- Strikes left on Mage Fury's charge.
        mageFuryStrikes = function() return fury.strikes end,
        --- Whether Ebony Rose's next swing bursts.
        isBurstArmed = function() return burstDue() end,
    },
    eventHandlers = {
        H2HWeapons_VenomStrike = onVenomStrike,
        H2HWeapons_BurstStaged = onBurstStaged,
        H2HWeapons_MageFuryCharged = onMageFuryCharged,
        H2HWeapons_MageFuryStrike = onMageFuryStrike,
        -- Spell Framework Plus' report of a cast it made. Listened to, never consumed.
        MagExp_CastResult = onCastReport,
    },
    engineHandlers = {
        onUpdate = onUpdate,
        onTeleported = function() firstPerson = nil end,
        onSave = function()
            -- A save taken mid-swing has the nudged modifier baked into it; remember it so the load
            -- can take it back out. Likewise the copy of Ebony Rose, if it was in hand.
            return {
                swappedSkill = swappedSkill,
                swappedDelta = swappedDelta,
                burstSwap = rose.swap and { original = rose.swap.original, copy = rose.swap.copy } or nil,
                fury = { spell = fury.spell, name = fury.name, strikes = fury.strikes,
                         fadesAt = fury.fadesAt, shown = fury.shown },
            }
        end,
        onLoad = function(data)
            -- The model is new; whatever was attached went with the old one.
            attached = {}
            firstPerson = nil
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
                pendingBurstReturn = { original = data.burstSwap.original, copy = data.burstSwap.copy, at = 0 }
            end
            if data.fury and (data.fury.strikes or 0) > 0 then
                fury.spell = data.fury.spell
                fury.name = data.fury.name or ""
                fury.strikes = data.fury.strikes
                fury.fadesAt = data.fury.fadesAt or 0
                fury.shown = data.fury.shown
            end
        end,
    },
}

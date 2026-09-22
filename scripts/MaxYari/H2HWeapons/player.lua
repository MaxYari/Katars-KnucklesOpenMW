-- Everything that makes a katar or a knuckleduster behave like a hand-to-hand weapon on the player:
-- the skill the engine rolls against, where the experience goes, the second weapon in the off hand,
-- the draw sound it should not make, and what the tooltip says.
--
-- The engine has no hand-to-hand weapon type, so these are a short blade and a blunt weapon as far
-- as it is concerned. Each piece below puts one of its assumptions back.
--
-- Per frame this costs: one getStance, one camera.getMode, one equipment lookup that Max Yari's
-- Script Services answers from its own cache ten times a second, and a handful of integer compares.
-- Everything else hangs off animation events, so it runs once per swing or once per draw.
local mp = "scripts/MaxYari/H2HWeapons/"

local animation = require('openmw.animation')
local camera = require('openmw.camera')
local core = require('openmw.core')
local I = require('openmw.interfaces')
local omwself = require('openmw.self')
local types = require('openmw.types')
local util = require('openmw.util')

local formulas = require(mp .. "scripts/formulas")
local settings = require(mp .. "scripts/settings")
local weapons = require(mp .. "scripts/weapons")

local cfg = settings.values

-- MSS answers the equipment lookup this script makes every frame. ReAnimation requires it too, so
-- it should always be there; if it is not, say so once rather than failing with a stack trace.
if not core.contentFiles.has("MaxYariScriptServices.omwscripts") then
    print("[H2HWeapons] ERROR: Max Yari's Script Services (MSS) is missing. It is required.")
    require('openmw.ui').showMessage("Katars and Knuckledusters: Max Yari's Script Services (MSS) is missing, please install it.")
    return {}
end

local CARRIED_RIGHT = types.Actor.EQUIPMENT_SLOT.CarriedRight
local WEAPON_STANCE = types.Actor.STANCE.Weapon
local SKILLS = types.NPC.stats.skills
local WEAPON_SUCCESSFUL_HIT = I.SkillProgression.SKILL_USE_TYPES.Weapon_SuccessfulHit

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

--- What is in the hand ----------------------------------------------------------------------------
-- MSS hands back the same table until the item actually changes, so the common case is one pointer
-- compare. Everything derived from the item is worked out on that change, never per frame.
local EQUIPMENT_CACHE_TIME = 0.1

local equippedInfo = nil
local equippedKind = false
local equippedModel = nil

local function refreshEquipped()
    local info = I.MSS.getEquipmentInfo(CARRIED_RIGHT, EQUIPMENT_CACHE_TIME)
    if info == equippedInfo then return false end
    equippedInfo = info
    local kind = info and weapons.kindOfId(info.recordId) or false
    local changed = kind ~= equippedKind
    equippedKind = kind
    equippedModel = kind and weapons.modelOfId(info.recordId) or nil
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

--- The off-hand weapon ----------------------------------------------------------------------------
-- A second copy of the weapon, hung off "Weapon Bone.L" - the mirror of the engine's own weapon bone
-- that this mod's skeleton meshes add. A looping VFX is the only way a script can put a model on a
-- bone, and the engine throws if the bone is not there, so it is checked first: with someone else's
-- skeleton installed the off hand is simply empty.
--
-- A first/third person switch rebuilds the model and takes every attached effect with it, so the
-- camera mode is watched and the weapon re-attached a couple of frames after it changes - long
-- enough for the new model to exist.
local OFF_HAND_BONE = "Weapon Bone.L"
local OFF_HAND_VFX = "H2HWeapons_OffHand"
local REATTACH_DELAY = 2

local attachedModel = nil
local lastCameraMode = nil
local reattachIn = 0
local boneWarned = false

local function updateOffHandWeapon(stance)
    local mode = camera.getMode()
    if mode ~= lastCameraMode then
        lastCameraMode = mode
        if attachedModel then
            attachedModel = nil
            reattachIn = REATTACH_DELAY
        end
    end

    local wanted = nil
    if cfg.showOffHandWeapon and equippedKind and stance == WEAPON_STANCE then
        wanted = equippedModel
    end

    if wanted == attachedModel then return end

    if reattachIn > 0 then
        reattachIn = reattachIn - 1
        return
    end

    animation.removeVfx(omwself, OFF_HAND_VFX)
    attachedModel = nil

    if not wanted then return end
    if not animation.hasBone(omwself, OFF_HAND_BONE) then
        if not boneWarned then
            boneWarned = true
            print("[H2HWeapons] the skeleton has no '" .. OFF_HAND_BONE .. "' bone, so the off-hand " ..
                "weapon cannot be shown. Another mod is probably replacing meshes/base_anim*.nif - " ..
                "re-run Sources/Tools/patch_skeleton.py on its skeletons, or turn the off-hand " ..
                "weapon off in the settings.")
        end
        return
    end

    animation.addVfx(omwself, wanted, {
        vfxId = OFF_HAND_VFX,
        boneName = OFF_HAND_BONE,
        loop = true,
        useAmbientLight = false,
    })
    attachedModel = wanted
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
    core.sound.stopSound(silenceSounds[1], omwself)
    core.sound.stopSound(silenceSounds[2], omwself)
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
    elseif string.find(startKey, FOLLOW_START, FOLLOW_START_OFFSET, true) then
        -- The hit has been rolled and dealt by now.
        revertSkillSwap()
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

--- Per frame --------------------------------------------------------------------------------------
local function onUpdate(dt)
    if dt <= 0 then return end

    if not tooltipsTried then
        tooltipsTried = true
        pcall(registerTooltipModifier)
    end

    local stance = types.Actor.getStance(omwself)
    local changed = refreshEquipped()

    -- Sheathing or swapping mid-swing has to put the skill back, and so does a swing that never
    -- reached its follow-through.
    if swappedSkill and (changed or stance ~= WEAPON_STANCE
        or core.getSimulationTime() - swappedAt > SWAP_TIMEOUT) then
        revertSkillSwap()
    end

    updateOffHandWeapon(stance)
    silenceDrawSounds()
end

return {
    interfaceName = "H2HWeapons",
    interface = {
        version = 1.0,
        --- What kind of hand-to-hand weapon a record id is: "katar", "knuckle", or false.
        kindOfId = weapons.kindOfId,
        --- The same for an item object.
        kindOfItem = weapons.kindOfItem,
        --- Fatigue each kind deals, as a fraction of a bare-fisted hit. [kind] = number.
        FATIGUE_FACTOR = weapons.FATIGUE_FACTOR,
        --- The skill the engine believes each kind uses. [kind] = skill id.
        WEAPON_SKILL = weapons.WEAPON_SKILL,
        --- The kind in the player's right hand, or false.
        equippedKind = function() return equippedKind end,
    },
    engineHandlers = {
        onUpdate = onUpdate,
        onSave = function()
            -- A save taken mid-swing has the nudged modifier baked into it; remember it so the load
            -- can take it back out.
            return { swappedSkill = swappedSkill, swappedDelta = swappedDelta }
        end,
        onLoad = function(data)
            attachedModel = nil
            lastCameraMode = nil
            if data and data.swappedSkill then
                swappedSkill = data.swappedSkill
                swappedDelta = data.swappedDelta or 0
                swappedAt = 0
                revertSkillSwap()
            end
        end,
    },
}

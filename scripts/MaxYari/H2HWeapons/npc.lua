-- A weapon swung with the hand-to-hand moveset - a katar, knuckledusters - in an NPC's hands: the
-- second one in the off hand, and the shield or torch they leave no room for; the draw sound of any
-- hybrid whose definition silences it; and Ebony Rose's burst.
--
-- An NPC needs far less than the player (player.lua). They pick up hybrid weapons and fight with them
-- by the skill the engine gives them - Short Blade, Blunt Weapon: weaponpriority.cpp rates a weapon by
-- getEquipmentSkill - so there is no skill to swap and no experience to split. They never channel a
-- spell into Mage Fury (actor.lua gives back what their strikes cost). Their animations are
-- animations.lua's, which runs on NPCs as on the player, and whoever they hit is actor.lua's.
--
-- This runs on every NPC, and on every creature that can hold these (weapons.canWield) - a dremora
-- or a skeleton is looked after exactly as an NPC is. So it has no per-frame handler. It hangs off the NPC's own animation events,
-- and only while a one-handed weapon is out does it look again, twice a second, for what comes with no
-- animation: a swap to another weapon of the same type, one taken off a corpse, a stance a script set.
local mp = "scripts/MaxYari/H2HWeapons/"

local async = require('openmw.async')
local core = require('openmw.core')
local I = require('openmw.interfaces')
local omwself = require('openmw.self')
local types = require('openmw.types')

-- A creature that cannot hold these gets nothing at all: this returns before loading anything, with
-- no handlers, so it costs a rat nothing per frame. The test is weapons.canWield's, written out here
-- so that it comes first.
if types.Creature.objectIsInstance(omwself) then
    local record = types.Creature.record(omwself)
    if not (record.isBiped and record.canUseWeapons) then return end
end

local carriedLeft = require(mp .. "scripts/carriedleft")
local hands = require(mp .. "scripts/hands")
local roseState = require(mp .. "scripts/rose")
local settings = require(mp .. "scripts/settings")
local swing = require(mp .. "scripts/swing")
local U = require(mp .. "scripts/uniques")
local weapons = require(mp .. "scripts/weapons")

local cfg = settings.values
local CARRIED_RIGHT = types.Actor.EQUIPMENT_SLOT.CarriedRight
local WEAPON_STANCE = types.Actor.STANCE.Weapon

local function weapon()
    return types.Actor.getEquipment(omwself, CARRIED_RIGHT)
end

-- The hybrid an item is, if it swings with the hand-to-hand moveset; nil for anything else.
local function handToHand(item)
    local hybrid = weapons.hybridOfItem(item)
    return hybrid and hybrid.handToHand and hybrid or nil
end

--- The off hand -------------------------------------------------------------------------------------
-- Shows while the right hand shows its weapon: from the engine's "equip attach" key to its "unequip
-- detach" (see player.lua). An NPC coming into the world, or back after the player rested near them,
-- has everything on its bones gone (hands.lua), and is looked at afresh.
local OFF_HAND = 1
local onBones = hands.new(omwself, { [OFF_HAND] = { vfxId = "H2HWeapons_OffHand", bone = "Weapon Bone.L" } })
local LOOK_INTERVAL = 0.5
-- A stance left with no "unequip detach" for this long - a script, a death - is taken as it is.
local KEY_WAIT = 1.5
-- How long after coming into the world the model is looked at: it has to exist first.
local SETTLE_DELAY = 0.1

local active = false
local shown = false        -- whether the right hand shows its weapon
local looking = false      -- a look is scheduled
local stanceLeftAt = nil
local checkLeftHand        -- the left hand's (below)

local rose = roseState.new(omwself)
-- Ebony Rose's owner fights with both his blades, when Mercy runs his fights (roseowner.lua).
local owner = string.lower(omwself.recordId) == U.ROSE_OWNER
    and require(mp .. "scripts/roseowner").attach(omwself) or nil

local function refresh()
    if not active then return end
    local item = shown and cfg.showOffHandWeapon and weapon() or nil
    local hybrid = item and handToHand(item)
    local model = hybrid and hybrid.model or nil
    onBones.attach(OFF_HAND, model)
end

local look

local function keepLooking()
    if looking or not active then return end
    looking = true
    async:newUnsavableSimulationTimer(LOOK_INTERVAL, look)
end

look = function()
    looking = false
    if not active then return end
    local stance = types.Actor.getStance(omwself)
    rose.check(stance)
    if shown and stance ~= WEAPON_STANCE then
        local now = core.getSimulationTime()
        stanceLeftAt = stanceLeftAt or now
        if now - stanceLeftAt >= KEY_WAIT then shown = false end
    else
        stanceLeftAt = nil
    end
    refresh()
    checkLeftHand()
    if shown or rose.isSwapped() then keepLooking() end
end

for _, group in ipairs(swing.WEAPON_GROUP_LIST) do
    I.AnimationController.addTextKeyHandler(group, function(_, key)
        if key == swing.SHOW_KEY then
            shown = true
            stanceLeftAt = nil
            refresh()
            keepLooking()
            checkLeftHand()
        elseif key == swing.HIDE_KEY then
            shown = false
            refresh()
            checkLeftHand()
        end
    end)
end

-- Coming into the world, or loaded: the model is new, and no key will say what the hand shows.
local function settle()
    onBones.forget()
    async:newUnsavableSimulationTimer(SETTLE_DELAY, function()
        if not active then return end
        shown = types.Actor.getStance(omwself) == WEAPON_STANCE
        refresh()
        if shown then keepLooking() end
        -- Also puts back what came off, if the weapon went away meanwhile.
        checkLeftHand()
    end)
end

--- The left hand ----------------------------------------------------------------------------------
-- Nothing in it while a weapon swung with the hand-to-hand moveset is out (carriedleft.lua): from the
-- draw's start to the hand putting it away. Looked at on those, and with everything else twice a
-- second while a weapon is out - so a shield or torch the engine puts back in an NPC's hand somewhere dark, once a second
-- (Actors::updateEquippedLight), can be seen there for up to half a second.
local left = carriedLeft.new(omwself)

local function isOut()
    if not shown and types.Actor.getStance(omwself) ~= WEAPON_STANCE then return false end
    return handToHand(weapon()) ~= nil
end

checkLeftHand = function()
    if not active then return end
    -- Died with one out: what came off stays in the inventory.
    if types.Actor.isDead(omwself) then
        left.forget()
        return
    end
    left.update(isOut())
end

--- Draw and sheathe sound ---------------------------------------------------------------------------
-- Stopped as player.lua stops the player's, only by timer: the engine plays it with the animation this
-- sees start, so the first stop lands a frame later, and a few more follow in case it came late.
local SILENCE_AT = { 0.01, 0.03, 0.06, 0.1, 0.15 }

local function silence(hybrid)
    if not (hybrid and hybrid.silentDraw and cfg.silenceDrawSound) then return end
    local sounds = hybrid.drawSounds
    local function stop()
        core.sound.stopSound3d(sounds[1], omwself)
        core.sound.stopSound3d(sounds[2], omwself)
    end
    for i = 1, #SILENCE_AT do async:newUnsavableSimulationTimer(SILENCE_AT[i], stop) end
end

--- Animation events ---------------------------------------------------------------------------------
-- Runs for every playBlended on this NPC; anything that is not a melee weapon group leaves on the first
-- table lookup.
I.AnimationController.addPlayBlendedAnimationHandler(function(groupname, options)
    if not swing.WEAPON_GROUPS[groupname] then return end
    local startKey = options.startKey or options.startkey
    if startKey == nil then return end

    if startKey == "equip start" or startKey == "unequip start" then
        -- Sheathing plays with the weapon still in hand, and a swap plays the incoming one's group, so
        -- the hand holds the one to ask about either way.
        silence(weapons.hybridOfItem(weapon()))
        if startKey == "equip start" then checkLeftHand() end
        if startKey == "unequip start" and owner then owner.sheathe() end
    elseif swing.isWindUpStart(startKey) then
        local item = weapon()
        if weapons.specialOfItem(item) == weapons.SPECIAL.Venom then rose.windUp(item) end
        if owner then owner.windUp(item) end
    elseif swing.isFollowStart(startKey) then
        rose.followStart()
    end
end)

return {
    eventHandlers = {
        H2HWeapons_VenomStrike = rose.onVenomStrike,
        H2HWeapons_BurstStaged = function(e)
            rose.onBurstStaged(e)
            if rose.isSwapped() then keepLooking() end
        end,
        -- The player passed time nearby, which took off everything on this NPC's bones.
        H2HWeapons_Reattach = function()
            onBones.forget()
            refresh()
        end,
    },
    engineHandlers = {
        onActive = function()
            active = true
            settle()
        end,
        onInactive = function()
            active = false
        end,
        onSave = function()
            local swap = rose.save()
            local taken = left.save()
            if swap or taken then return { burstSwap = swap, leftHand = taken } end
        end,
        onLoad = function(data)
            if data then left.load(data.leftHand) end
            -- Saved mid-swing, with the copy of Ebony Rose in hand: put things back once the NPC is
            -- in the world again.
            if data and data.burstSwap then
                async:newUnsavableSimulationTimer(SETTLE_DELAY, function() rose.restore(data.burstSwap) end)
            end
        end,
    },
}

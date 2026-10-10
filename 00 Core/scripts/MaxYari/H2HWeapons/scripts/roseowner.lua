-- Ebony Rose's owner, Dandras Vules, fighting with both his blades, as a step of Mercy: Combat AI
-- Overhaul's melee fight. Only with Mercy, which runs his fights; global.lua hands him the Rose only
-- then.
--
-- His Jinkblade paralyses on a strike; the Rose poisons, and bursts on a run of strikes. He opens with
-- the Jinkblade and turns to the Rose when the enemy is paralysed, when the Jinkblade has too little
-- charge left for another strike's paralysis, or after ROSE_OWNER_SWINGS swings with it. He keeps the
-- Rose at least ROSE_OWNER_ROSE_MIN seconds, and goes back to the Jinkblade once that is up if it has
-- the charge and the enemy is not paralysed - back and forth, until the Jinkblade's charge runs out.
--
-- Mercy switches the engine's combat AI off while it fights, and with it the engine's own choice of
-- weapon before every swing, so the choice is made here. The step is the first in Mercy's melee
-- sequence (extension point FIGHT_Melee of its Combat tree), which moves on to the attack whatever the
-- step returns; it only runs between attacks, as the sequence starts over. The two are the same weapon
-- type, so the swap is instant: the engine plays no draw for it (CharacterController only re-draws for
-- a change of type).
local mp = "scripts/MaxYari/H2HWeapons/"

local core = require('openmw.core')
local I = require('openmw.interfaces')
local types = require('openmw.types')

local formulas = require(mp .. "scripts/formulas")
local U = require(mp .. "scripts/uniques")
local weapons = require(mp .. "scripts/weapons")

local CARRIED_RIGHT = types.Actor.EQUIPMENT_SLOT.CarriedRight
local PARALYZE = core.magic.EFFECT_TYPE.Paralyze or "paralyze"
local JINKBLADE, ROSE = "jinkblade", "rose"
-- A fight with no step for this long is over, whether or not he put his weapon away.
local FIGHT_GAP = 60

local M = {}

--- Which of the two to hold now, or nil to keep what is in hand. Pure, for the tests.
-- s: holding (JINKBLADE, ROSE or nil), fresh (the fight's first look), now, roseSince, swings,
-- charged (the Jinkblade has a strike's charge), paralyzed (the enemy), hasRose, hasJinkblade
function M.choose(s)
    local jinkbladeFits = s.hasJinkblade and s.charged and not s.paralyzed
    if s.holding == JINKBLADE then
        if s.hasRose and (not jinkbladeFits or s.swings >= U.ROSE_OWNER_SWINGS) then return ROSE end
        return nil
    elseif s.holding == ROSE then
        local held = s.roseSince and s.now - s.roseSince or math.huge
        if jinkbladeFits and (s.fresh or held >= U.ROSE_OWNER_ROSE_MIN) then return JINKBLADE end
        return nil
    end
    if jinkbladeFits then return JINKBLADE end
    if s.hasRose then return ROSE end
    return nil
end

M.JINKBLADE, M.ROSE = JINKBLADE, ROSE

--- Registers the step with Mercy for this actor (openmw.self). Returns the hooks npc.lua calls, or nil
-- without Mercy.
function M.attach(actor)
    local mercy = I.MercyCAO
    if not (mercy and mercy.addExtension) then return nil end

    local fight = nil -- { holding, roseSince, swings, last } for the fight under way

    local function kind(item)
        if item == nil then return nil end
        if string.lower(item.recordId) == U.ROSE_OWNER_WEAPON then return JINKBLADE end
        -- The Rose, or the copy of it a bursting swing is made with (rose.lua).
        local special = weapons.specialOfItem(item)
        if special == weapons.SPECIAL.Venom or special == weapons.SPECIAL.Burst then return ROSE end
        return nil
    end

    local function charged(jinkblade)
        local record = types.Weapon.record(jinkblade)
        local enchantment = record and record.enchant and core.magic.enchantments.records[record.enchant]
        if enchantment == nil then return false end
        local skill = types.NPC.stats.skills.enchant(actor).modified
        local charge = types.Item.itemData(jinkblade).enchantmentCharge
        return charge ~= nil and charge >= formulas.effectiveCastCost(enchantment.cost, skill)
    end

    local function paralyzed(enemy)
        if enemy == nil or not enemy:isValid() then return false end
        local effect = types.Actor.activeEffects(enemy):getEffect(PARALYZE)
        return effect ~= nil and effect.magnitude > 0
    end

    local function wield(item)
        local equipment = types.Actor.getEquipment(actor)
        equipment[CARRIED_RIGHT] = item
        types.Actor.setEquipment(actor, equipment)
    end

    -- The hand changed - by this, or by the engine while Mercy left a stretch of the fight to it.
    local function took(holding, now)
        fight.holding = holding
        if holding == JINKBLADE then fight.swings = 0 end
        if holding == ROSE then fight.roseSince = now end
    end

    local function step(state)
        local now = core.getSimulationTime()
        local fresh = fight == nil or now - fight.last > FIGHT_GAP
        if fresh then fight = { holding = nil, roseSince = nil, swings = 0 } end
        fight.last = now

        local holding = kind(types.Actor.getEquipment(actor, CARRIED_RIGHT))
        if not fresh and holding ~= fight.holding then took(holding, now) end
        fight.holding = holding

        local inventory = types.Actor.inventory(actor)
        local jinkblade = inventory:find(U.ROSE_OWNER_WEAPON)
        local theRose = inventory:find(U.EBONY_ROSE)
        local want = M.choose({
            holding = holding, fresh = fresh, now = now, roseSince = fight.roseSince, swings = fight.swings,
            charged = jinkblade ~= nil and charged(jinkblade), paralyzed = paralyzed(state and state.enemyActor),
            hasRose = theRose ~= nil, hasJinkblade = jinkblade ~= nil,
        })
        if want == JINKBLADE then
            wield(jinkblade)
            took(JINKBLADE, now)
        elseif want == ROSE then
            wield(theRose)
            took(ROSE, now)
        end
    end

    mercy.addExtension("Combat", "FIGHT", "Melee", {
        name = "H2HWeapons_RoseOwner",
        run = function(task, state)
            step(state)
            task:success()
        end,
    })

    local hooks = {}
    -- A swing winds up with `item` in the hand.
    function hooks.windUp(item)
        if fight == nil or kind(item) ~= JINKBLADE then return end
        if fight.holding ~= JINKBLADE then took(JINKBLADE, core.getSimulationTime()) end
        fight.swings = fight.swings + 1
    end
    -- The weapon being put away: the fight is over, and the next one opens afresh.
    function hooks.sheathe()
        fight = nil
    end
    return hooks
end

return M

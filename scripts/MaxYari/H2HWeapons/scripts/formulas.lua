-- The engine's own hand-to-hand numbers, so these weapons agree with a bare fist rather than
-- inventing their own scale.
local core = require('openmw.core')
local types = require('openmw.types')

-- Constant for the run: GMSTs do not change in game.
local fMinHandToHandMult = core.getGMST("fMinHandToHandMult")
local fMaxHandToHandMult = core.getGMST("fMaxHandToHandMult")
local HAND_TO_HAND_STRENGTH_DIVISOR = 40.0 -- MCP's formula, as the engine uses it

local M = {}

--- Fatigue a bare-fisted hand-to-hand hit from this actor would do.
--
-- MWMechanics::getHandToHandDamage, apps/openmw/mwmechanics/combat.cpp:
--
--     damage = handToHand * (fMinHandToHandMult + (fMaxHandToHandMult - fMinHandToHandMult) * strength)
--     if "strength influences hand to hand" is on: damage *= Strength / 40
--
-- `strengthInfluences` mirrors that launcher setting (Advanced -> Combat), which no Lua API can
-- read - hence this mod's own copy of it. The engine's values are 0 (off), 1 (on) and 2 (on,
-- werewolves excluded); an actor holding a weapon is never a werewolf, so 1 and 2 behave alike here.
--
-- Against a paralysed or knocked-down target the engine turns hand-to-hand damage into health
-- damage instead (* fHandtoHandHealthPer). These weapons already deal their own health damage
-- through the normal weapon path, so the fatigue part is simply always applied.
--
-- @param actor #GameObject the attacker
-- @param attackStrength #number 0..1, how far the swing was charged
-- @param strengthInfluences #number 0, 1 or 2
-- @return #number fatigue damage, or 0 if the actor has no hand-to-hand skill
function M.handToHandFatigue(actor, attackStrength, strengthInfluences)
    local skill
    if types.NPC.objectIsInstance(actor) then
        skill = types.NPC.stats.skills.handtohand(actor).modified
    elseif types.Creature.objectIsInstance(actor) then
        -- A creature has one Combat value that stands for every combat skill, Hand-to-hand among them
        -- (MWClass::Creature::getSkill).
        skill = types.Creature.record(actor).combatSkill
    else
        return 0
    end
    if not skill or skill <= 0 then return 0 end

    local damage = skill * (fMinHandToHandMult + (fMaxHandToHandMult - fMinHandToHandMult) * attackStrength)

    if strengthInfluences and strengthInfluences ~= 0 then
        local strength = types.Actor.stats.attributes.strength(actor).modified
        damage = damage * strength / HAND_TO_HAND_STRENGTH_DIVISOR
    end

    return damage
end

--- How a hybrid weapon's two skills make the one it is swung with (definitions.lua, `scaling`).
M.SCALING = {
    -- The primary skill, plus a share of the secondary (skillBonus).
    MinorSecondaryBonus = "minorSecondaryBonus",
    -- The lower of the two.
    LowestSkill = "lowestSkill",
    -- The higher of the two.
    HighestSkill = "highestSkill",
}

-- The minorSecondaryBonus curve (skillBonus, below).
local BONUS_MAX, BONUS_MIN = 0.15, 0.05
local BONUS_GRACE, BONUS_FALLOFF = 10, 20

--- What keeping the secondary skill up is worth, in whole skill points.
--
-- The bonus is a share of the secondary skill itself, not of the primary, so letting it rot costs
-- you twice over: a smaller share of a smaller number. The share is the full BONUS_MAX while the
-- secondary is within BONUS_GRACE points of the primary (or ahead of it), and from there tapers over
-- BONUS_FALLOFF points down to BONUS_MIN - a floor, not a cutoff, so a neglected secondary skill is
-- still worth something.
--
-- Rounded down, and rounded here rather than at the point of use, so the number the tooltip shows
-- is exactly the number the swing applies.
--
-- @param primary #number the actor's primary skill - Hand to Hand, for this mod's weapons
-- @param secondary #number the actor's secondary skill - Short Blade or Blunt Weapon, for this mod's
function M.skillBonus(primary, secondary)
    local behind = primary - secondary
    local rate = BONUS_MAX
    if behind > BONUS_GRACE then
        local taper = math.min(1, (behind - BONUS_GRACE) / BONUS_FALLOFF)
        rate = BONUS_MAX + (BONUS_MIN - BONUS_MAX) * taper
    end
    return math.floor(secondary * rate)
end

--- The skill value the engine should roll the hit chance against.
--
-- That is the weapon's own skill to the engine, so player.lua writes this into it for the length of
-- a swing.
function M.effectiveSkill(scaling, primary, secondary)
    if scaling == M.SCALING.LowestSkill then return math.min(primary, secondary) end
    if scaling == M.SCALING.HighestSkill then return math.max(primary, secondary) end
    return primary + M.skillBonus(primary, secondary)
end

--- Bound Fist ------------------------------------------------------------------------------------
-- Which tier a caster's Conjuration earns: the first whose `below` it is under, or the last.
function M.boundTier(conjuration, tiers)
    for i = 1, #tiers do
        local below = tiers[i].below
        if below == nil or conjuration < below then return i end
    end
    return #tiers
end

-- Unofficial TR Spells' bound item scaling (boundRecords.lua), so the two agree to the point:
-- Conjuration in steps, damage as a share that grows with it, weight as a share that shrinks.
function M.boundStep(conjuration, step)
    return math.floor(math.floor(conjuration) / step) * step
end

function M.boundDamageMult(step, values)
    return values.BOUND_DAMAGE_BASE / 100 + values.BOUND_DAMAGE_BONUS_PER_LEVEL * step / 100
end

function M.boundEnchantMult(step, values)
    return values.BOUND_ENCHANT_BASE / 100 + values.BOUND_ENCHANT_BONUS_PER_LEVEL * step / 100
end

function M.boundWeight(baseWeight, step, values)
    local reduction = values.BOUND_WEIGHT_REDUCTION_PER_LEVEL * step / 100
    return math.max(0, baseWeight * values.BOUND_WEIGHT_BASE / 100 * (1 - reduction))
end

--- What one cast of an enchantment costs this wielder: each point of Enchant above 10 takes 1% off,
-- each point below adds 1%, and it never comes under 1 (getEffectiveEnchantmentCastCost,
-- spellutil.cpp). A weapon casts on a strike only with at least this much charge left.
function M.effectiveCastCost(cost, enchantSkill)
    local result = cost - (cost / 100) * (enchantSkill - 10)
    if result < 1 then return 1 end
    return math.floor(result)
end

return M

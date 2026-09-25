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
-- @return #number fatigue damage, or 0 if the actor has no hand-to-hand skill (a creature)
function M.handToHandFatigue(actor, attackStrength, strengthInfluences)
    if not types.NPC.objectIsInstance(actor) then return 0 end

    local skill = types.NPC.stats.skills.handtohand(actor).modified
    if not skill or skill <= 0 then return 0 end

    local damage = skill * (fMinHandToHandMult + (fMaxHandToHandMult - fMinHandToHandMult) * attackStrength)

    if strengthInfluences and strengthInfluences ~= 0 then
        local strength = types.Actor.stats.attributes.strength(actor).modified
        damage = damage * strength / HAND_TO_HAND_STRENGTH_DIVISOR
    end

    return damage
end

--- What keeping the weapon skill up is worth, in whole skill points.
--
-- The bonus is a share of the weapon skill itself, not of hand-to-hand, so letting Short Blade or
-- Blunt Weapon rot costs you twice over: a smaller share of a smaller number. The share is the full
-- `skillBonusMax` while the weapon skill is within `skillBonusGrace` points of hand-to-hand (or
-- ahead of it), and from there tapers over `skillBonusFalloff` points down to `skillBonusMin` - a
-- floor, not a cutoff, so a neglected weapon skill is still worth something.
--
-- Rounded down, and rounded here rather than at the point of use, so the number the tooltip shows
-- is exactly the number the swing applies.
--
-- @param handToHand #number the actor's hand-to-hand skill
-- @param weaponSkill #number the actor's skill in the weapon the engine thinks it is
-- @param cfg #table settings.values
function M.skillBonus(handToHand, weaponSkill, cfg)
    local behind = handToHand - weaponSkill
    local rate
    if behind <= cfg.skillBonusGrace then
        rate = cfg.skillBonusMax
    elseif cfg.skillBonusFalloff <= 0 then
        rate = cfg.skillBonusMin
    else
        local taper = math.min(1, (behind - cfg.skillBonusGrace) / cfg.skillBonusFalloff)
        rate = cfg.skillBonusMax + (cfg.skillBonusMin - cfg.skillBonusMax) * taper
    end
    return math.floor(weaponSkill * rate)
end

--- The skill value the engine should roll the hit chance against.
--
-- Hand-to-hand is what these weapons are really swung with, so that is the number the engine gets
-- (see player.lua, which writes it into the weapon skill for the duration of a swing), plus
-- whatever the weapon skill is worth on top.
function M.effectiveSkill(handToHand, weaponSkill, cfg)
    return handToHand + M.skillBonus(handToHand, weaponSkill, cfg)
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

return M

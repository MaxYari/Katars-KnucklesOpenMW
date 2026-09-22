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

--- The skill value the engine should roll the hit chance against.
--
-- Hand-to-hand is what these weapons are really swung with, so that is the number the engine gets
-- (see player.lua, which writes it into the weapon skill for the duration of a swing). Keeping the
-- weapon skill up alongside it pays a bonus: the full `bonusMax` while the weapon skill is at or
-- above hand-to-hand, tapering to nothing once it is `bonusFalloff` points below.
--
-- @param handToHand #number the actor's hand-to-hand skill
-- @param weaponSkill #number the actor's skill in the weapon the engine thinks it is
-- @param bonusMax #number fraction added at full bonus, e.g. 0.10
-- @param bonusFalloff #number skill points below hand-to-hand at which the bonus reaches zero
function M.effectiveSkill(handToHand, weaponSkill, bonusMax, bonusFalloff)
    local bonus = 0
    local difference = weaponSkill - handToHand
    if difference >= 0 then
        bonus = bonusMax
    elseif bonusFalloff > 0 and difference > -bonusFalloff then
        bonus = bonusMax * (1 + difference / bonusFalloff)
    end
    return handToHand * (1 + bonus)
end

return M

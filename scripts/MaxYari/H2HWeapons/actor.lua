-- What a hand-to-hand weapon does to whoever it hits, run on the one hit: fatigue damage, Ebony
-- Rose's venom, and Mage Fury's stored spell.
--
-- The engine hands the whole attack to the victim (LuaManager::onHit -> the "Hit" event ->
-- I.Combat.onHit), and a handler may add to attack.damage before the built-in one applies it. That
-- is the only place an extra damage type can be attached to an ordinary weapon hit, so this script
-- rides on every actor rather than only on the player - an NPC swinging a katar has to bruise too.
--
-- Nothing here runs outside a hit - no per-frame handler at all - except while this actor carries
-- Ebony Rose's venom or holds a Bound Fist: then it reads that effect a few times a second until it
-- is gone.
local mp = "scripts/MaxYari/H2HWeapons/"

local animation = require('openmw.animation')
local async = require('openmw.async')
local core = require('openmw.core')
local I = require('openmw.interfaces')
local nearby = require('openmw.nearby')
local omwself = require('openmw.self')
local types = require('openmw.types')

local formulas = require(mp .. "scripts/formulas")
local settings = require(mp .. "scripts/settings")
local U = require(mp .. "scripts/uniques")
local weapons = require(mp .. "scripts/weapons")

local MELEE = I.Combat.ATTACK_SOURCE_TYPES.Melee
local SPECIAL = weapons.SPECIAL

--- Reading this actor -------------------------------------------------------------------------------
-- maxAge as MSS takes it: nil or 0 reads at most once a frame; more lets a cached value that old do.
local function effectMagnitude(id, maxAge)
    if not weapons.effectExists(id) then return 0 end
    if I.MSS and I.MSS.getActiveEffect then
        return I.MSS.getActiveEffect(id, maxAge or 0) or 0
    end
    local effect = types.Actor.activeEffects(omwself):getEffect(id)
    return effect and effect.magnitude or 0
end

--- Fatigue ----------------------------------------------------------------------------------------
-- The bruising a fist would do (MWMechanics::getHandToHandDamage), at the weapon's share of it, put
-- through what Npc::hit puts a fist's through after that - the engine has done the same to the
-- weapon's own damage by the time this runs:
--   * a blocked hit does nothing: blockMeleeAttack zeroes the damage, so the weapon's comes here as
--     nothing. So does a hit on a player in god mode.
--   * a critical strike on an unaware target is fCombatCriticalStrikeMult (4) times it - see
--     wasCritical.
--   * on someone knocked down or paralysed it lands on health instead of fatigue, at
--     fHandtoHandHealthPer (0.1) of it, and on someone knocked down - not merely paralysed - at
--     fCombatKODamageMult (1.5) of that again.
-- The Morrowind combat script then takes armour and difficulty off the health damage, as it does off
-- a fist's.
--
-- The engine's "knocked down" is a flag no script can read, but it is set only while the knockdown or
-- knockout animation plays and cleared when it ends (CharacterController::refreshHitRecoilAnims) -
-- and a knockout is fatigue below nothing - so those are what is asked. Only on a hit.
local HEALTH_PER = core.getGMST("fHandtoHandHealthPer") or 0.1
local KNOCKED_DOWN_MULT = core.getGMST("fCombatKODamageMult") or 1.5
local CRITICAL_MULT = core.getGMST("fCombatCriticalStrikeMult") or 4
local STRENGTH_BASE = core.getGMST("fDamageStrengthBase") or 0.5
local STRENGTH_MULT = core.getGMST("fDamageStrengthMult") or 0.1
local DOWN_ANIMATIONS = { "knockdown", "knockout", "swimknockdown", "swimknockout" }
local PARALYZE = core.magic.EFFECT_TYPE.Paralyze or "paralyze"

local function isKnockedDown()
    if types.Actor.stats.dynamic.fatigue(omwself).current < 0 then return true end
    for i = 1, #DOWN_ANIMATIONS do
        if animation.isPlaying(omwself, DOWN_ANIMATIONS[i]) then return true end
    end
    return false
end

-- Whether the engine made this hit a critical strike. It only ever does for the player, on a target
-- not in combat that fails to notice them (Npc::hit) - an awareness roll no script can see - and says
-- so only in a message box. But it multiplies the weapon's own damage as well, and that one can be
-- worked out: the weapon's roll for this attack, scaled by its condition and the wielder's Strength
-- (adjustWeaponDamage). A hit that came out more than halfway from that to a critical one was one.
-- What the estimate leaves out moves it far less than that: Resist or Weakness to Normal Weapons
-- (which hinge on a launcher option too), a silver blade on a werewolf, this hit's own wear.
local ATTACK_DAMAGE = {
    [0] = { "chopMinDamage", "chopMaxDamage" },
    [1] = { "slashMinDamage", "slashMaxDamage" },
    [2] = { "thrustMinDamage", "thrustMaxDamage" },
}
local CRITICAL_THRESHOLD = (1 + CRITICAL_MULT) / 2

local function wasCritical(attack, knockedDown)
    if CRITICAL_MULT <= 1 or not types.Player.objectIsInstance(attack.attacker) then return false end
    local record = types.Weapon.record(attack.weapon)
    local keys = ATTACK_DAMAGE[attack.type]
    if record == nil or keys == nil then return false end
    local low, high = record[keys[1]], record[keys[2]]
    if low == nil or high == nil then return false end

    local expected = low + (high - low) * (attack.strength or 0)
    local maxCondition = record.health
    if maxCondition and maxCondition > 0 then
        local data = types.Item.itemData(attack.weapon)
        if data and data.condition then expected = expected * data.condition / maxCondition end
    end
    local strength = types.Actor.stats.attributes.strength(attack.attacker).modified
    expected = expected * (STRENGTH_BASE + strength * STRENGTH_MULT * 0.1)
    if knockedDown then expected = expected * KNOCKED_DOWN_MULT end
    return expected > 0 and attack.damage.health / expected >= CRITICAL_THRESHOLD
end

local function addFatigue(attack, kind)
    local damage = attack.damage
    if damage == nil then return end -- the engine always sends one; another mod's call might not
    if (damage.health or 0) <= 0 then return end -- blocked, or dealt to a god

    local fatigue = formulas.handToHandFatigue(attack.attacker, attack.strength or 0,
        settings.values.strengthFactor) * weapons.FATIGUE_FACTOR[kind]
    if fatigue <= 0 then return end

    local knockedDown = isKnockedDown()
    if wasCritical(attack, knockedDown) then fatigue = fatigue * CRITICAL_MULT end
    if knockedDown or effectMagnitude(PARALYZE) > 0 then
        local health = fatigue * HEALTH_PER
        if knockedDown then health = health * KNOCKED_DOWN_MULT end
        damage.health = (damage.health or 0) + health
    else
        damage.fatigue = (damage.fatigue or 0) + fatigue
    end
end

--- Ebony Rose's venom -----------------------------------------------------------------------------
-- The venom is this mod's own magic effect. The engine applies it, times it, shows it and bursts it,
-- but deals no damage for it - damage is keyed to the built-in effect ids (spelleffects.cpp) - so
-- whoever carries it deals the damage to themselves, the way the engine does for Poison: its
-- magnitude every second, less Resist Poison, more with Weakness to Poison.
--
-- There is no event for an effect landing, so this script is told instead: by its own hit handler
-- for a strike, and by whoever was struck for a burst that caught it. From then on it reads the
-- effect through MSS every TICK, and stops the first time it finds none - allowing GRACE for one
-- that has only just landed to show up.
local TICK = 0.1
-- A tick that comes this late has been held up by the actor going inactive; the venom was not
-- running meanwhile either, so no more than this is billed for it.
local MAX_TICK = 0.5
local GRACE = 0.5
-- Whoever was struck tells everyone this close; explodeSpell measures from where the blow landed,
-- which can be a body's height from where an actor stands.
local BURST_REACH = U.BURST.area * U.UNITS_PER_FOOT + 128

local EFFECT = core.magic.EFFECT_TYPE
local RESIST = EFFECT.ResistPoison or "resistpoison"
local WEAKNESS = EFFECT.WeaknessToPoison or "weaknesstopoison"

local healthStat = nil     -- this actor's health, taken on first use
local graceUntil = 0       -- read on until then even while nothing is found
local lastTick = nil       -- nil: not ticking
local source = nil         -- who poisoned this actor last - the kill is theirs
local finisherAt = -math.huge

local function health()
    healthStat = healthStat or types.Actor.stats.dynamic.health(omwself)
    return healthStat
end

-- The engine's figure for a poison (MWMechanics::getEffectResistance): 1 - (resist - weakness) / 100,
-- never below nothing. It also rolls a willpower save, worth under a point in a hundred for an
-- enchantment; that is left out.
-- Read at most once a second: they change far less often than the venom ticks.
local RESISTANCE_MAX_AGE = 1.0

local function venomMultiplier()
    local resistance = effectMagnitude(RESIST, RESISTANCE_MAX_AGE) - effectMagnitude(WEAKNESS, RESISTANCE_MAX_AGE)
    return math.max(0, 1 - math.min(resistance, 100) / 100)
end

local function validSource()
    return source ~= nil and source:isValid() and types.Actor.objectIsInstance(source)
end

-- Venom damage. A blow that would kill is not dealt here: the victim is left a sliver of health and
-- handed a Damage Health cast by whoever poisoned them, and dies of that inside the engine's own
-- spell update - where the engine credits the kill, and decides whether it was murder, by its own
-- rules (Actors::adjustMagicEffects -> MechanicsManager::actorKilled). Those rules look at who
-- attacked first, which no script can see.
local function hurt(amount, now)
    if amount <= 0 then return end
    local stat = health()
    local current = stat.current
    if current <= 0 then return end

    if current - amount > U.FINISHER_HEALTH or not validSource() then
        stat.current = current - amount
        return
    end

    if current > U.FINISHER_HEALTH then stat.current = U.FINISHER_HEALTH end
    if now - finisherAt < 1 then return end -- the last one is still running
    finisherAt = now
    types.Actor.activeSpells(omwself):add({
        id = U.FINISHER_SPELL,
        effects = { 0 },
        caster = source,
        ignoreResistances = true,
        ignoreReflect = true,
        ignoreSpellAbsorption = true,
        stackable = true,
    })
end

local tick

local function schedule()
    async:newUnsavableSimulationTimer(TICK, tick)
end

tick = function()
    local now = core.getSimulationTime()
    local dt = math.min(now - (lastTick or now), MAX_TICK)
    lastTick = now

    local magnitude = effectMagnitude(U.VENOM_EFFECT)
    if magnitude > 0 then
        hurt(magnitude * venomMultiplier() * dt, now)
    elseif now >= graceUntil then
        -- Gone, or it never landed (an empty enchantment, an absorbed one).
        lastTick = nil
        return
    end

    if health().current > 0 then
        schedule()
    else
        lastTick = nil
    end
end

-- Start (or keep) reading the venom. `since` backdates the first tick to when it landed.
local function watch(from, since)
    if from ~= nil then source = from end
    local now = core.getSimulationTime()
    graceUntil = math.max(graceUntil, now + GRACE)
    if lastTick == nil then
        lastTick = math.min(since or now, now)
        schedule()
    end
end

local function struckByVenom(attacker, burst)
    local now = core.getSimulationTime()
    watch(attacker, now)

    if burst then
        -- The burst went off around this actor. The engine tells nobody it caught, so they are told
        -- from here.
        local here = omwself.position
        local me = omwself.object
        local notice = { source = attacker, since = now }
        for _, actor in ipairs(nearby.actors) do
            if actor ~= me and actor ~= attacker and (actor.position - here):length() <= BURST_REACH then
                actor:sendEvent("H2HWeapons_WatchVenom", notice)
            end
        end
    end

    -- Only the player's script listens: the strikes towards a burst are theirs to count.
    attacker:sendEvent("H2HWeapons_VenomStrike", { victim = omwself.object, burst = burst })
end

--- Mage Fury ------------------------------------------------------------------------------------
-- The wielder decides whether a strike carries a spell - the charge is theirs - so this side only
-- reports the strike and, when told to, takes the spell. activeSpells:add applies it the engine's
-- way (resistances, reflection, the hostile reaction, the kill credit) but plays nothing, so the
-- hit effects are played here, as CastSpell::playEffects would.
local function playHitEffects(record)
    local played = {}
    for i = 1, #record.effects do
        local mgef = record.effects[i].effect
        if mgef and not played[mgef.id] then
            played[mgef.id] = true

            local hitStatic = mgef.hitStatic
            if hitStatic == nil or hitStatic == "" then hitStatic = "VFX_DefaultHit" end
            local static = types.Static.records[hitStatic]
            if static and static.model ~= "" then
                -- A looping effect named after its magic effect is taken off by the engine when that
                -- effect runs out (CharacterController::updateContinuousVfx), as its own are.
                animation.addVfx(omwself, static.model, {
                    loop = mgef.continuousVfx,
                    vfxId = mgef.continuousVfx and mgef.id or "",
                    particleTextureOverride = mgef.particle,
                })
            end

            if mgef.hitSound ~= nil and mgef.hitSound ~= "" then
                core.sound.playSound3d(mgef.hitSound, omwself)
            else
                local skill = core.stats.Skill.records[mgef.school]
                local school = skill and skill.school
                if school and school.hitSound and school.hitSound ~= "" then
                    core.sound.playSoundFile3d(school.hitSound, omwself)
                end
            end
        end
    end
end

local function takeStoredSpell(e)
    local record = core.magic.spells.records[e.spell]
    if record == nil then return end
    local indexes = {}
    for i = 1, #record.effects do indexes[i] = record.effects[i].index end
    if #indexes == 0 then return end

    types.Actor.activeSpells(omwself):add({
        id = e.spell,
        effects = indexes,
        caster = e.caster,
        name = e.name,
        -- Three strikes are three spells, as three casts would be.
        stackable = true,
    })
    playHitEffects(record)
end

--- Bound Fist -------------------------------------------------------------------------------------
-- The engine binds its own bound weapons itself (spelleffects.cpp, addBoundItem); this effect it only
-- times, so the binding is done here, on whoever casts it - the player, or an NPC who knows it (the
-- AI takes a harmless self effect it does not recognise for one worth casting). The steps are the
-- engine's: the weapon goes into the hand, the hand's previous weapon is remembered, and when the
-- effect ends the bound weapon goes and the previous one comes back.
local BOUND_TICK = 0.25
-- How long after the cast the effect has to show up before the cast is taken to have failed.
local BOUND_GRACE = 1.0
-- How long a summon may wait on the global script before it is given up on.
local SUMMON_TIMEOUT = 5
local CARRIED_RIGHT = types.Actor.EQUIPMENT_SLOT.CarriedRight
local WEAPON_STANCE = types.Actor.STANCE.Weapon

local isPlayer = types.Player.objectIsInstance(omwself)
-- Only NPCs, the player among them, have a Conjuration to pick the tier by.
local canConjure = types.NPC.objectIsInstance(omwself)

-- nil, or { phase = "waiting" | "summoning" | "held", ... }
local fist = nil
local fistTicking = false
local fistSpells = {} -- [spell id] = whether that spell carries the effect

local function carriesFist(spell)
    local known = fistSpells[spell.id]
    if known == nil then
        known = false
        for i = 1, #spell.effects do
            if string.lower(spell.effects[i].id) == U.BOUND_FIST_EFFECT then
                known = true
                break
            end
        end
        fistSpells[spell.id] = known
    end
    return known
end

local function carried(item)
    return item ~= nil and item:isValid() and item.parentContainer == omwself.object
end

-- The bound weapon goes back to Oblivion, and the hand gets back what it held - if the bound
-- weapon is still what it holds; a weapon changed to since stays.
local function endFist()
    local current = fist
    fist = nil
    if current == nil or current.item == nil then return end
    local equipment = types.Actor.getEquipment(omwself)
    if equipment[CARRIED_RIGHT] == current.item then
        equipment[CARRIED_RIGHT] = carried(current.previous) and current.previous or nil
        types.Actor.setEquipment(omwself, equipment)
    end
    core.sendGlobalEvent("H2HWeapons_DismissFist", { item = current.item })
end

-- The weapon was dropped, sold or taken - which a vanilla bound weapon cannot be, the engine knows its
-- own - so the spell ends with it rather than go on binding nothing.
local function endFistEffect()
    local spells = types.Actor.activeSpells(omwself)
    local ids = {}
    for _, spell in pairs(spells) do
        for _, effect in pairs(spell.effects) do
            if string.lower(effect.id) == U.BOUND_FIST_EFFECT then
                ids[#ids + 1] = spell.activeSpellId
                break
            end
        end
    end
    for i = 1, #ids do spells:remove(ids[i]) end
end

local fistTick

local function scheduleFist()
    async:newUnsavableSimulationTimer(BOUND_TICK, fistTick)
end

fistTick = function()
    local current = fist
    if current == nil then
        fistTicking = false
        return
    end
    local now = core.getSimulationTime()
    local on = effectMagnitude(U.BOUND_FIST_EFFECT) > 0

    if current.phase == "waiting" then
        if on then
            local conjuration = types.NPC.stats.skills.conjuration(omwself).modified
            current.phase = "summoning"
            current.giveUpAt = now + SUMMON_TIMEOUT
            current.previous = types.Actor.getEquipment(omwself, CARRIED_RIGHT)
            core.sendGlobalEvent("H2HWeapons_SummonFist", {
                actor = omwself.object,
                tier = formulas.boundTier(conjuration, U.BOUND_FIST_TIERS),
                conjuration = conjuration,
            })
        elseif now > current.giveUpAt then
            fist = nil -- the cast failed, or was absorbed or reflected
        end
    elseif current.phase == "summoning" then
        -- Over before the weapon came: it is sent straight back when it does.
        if not on then current.cancelled = true end
        if now > current.giveUpAt then fist = nil end
    elseif current.phase == "held" then
        if not on then
            endFist()
        elseif not carried(current.item) then
            endFistEffect()
            endFist()
        elseif current.drawPending and not animation.isPlaying(omwself, "spellcast") then
            -- The engine readies the player's own bound weapons as it hands them over; this waits
            -- for the cast to finish so the draw does not cut it short.
            current.drawPending = false
            if types.Actor.getStance(omwself) ~= WEAPON_STANCE then
                types.Actor.setStance(omwself, WEAPON_STANCE)
            end
        end
    end

    if fist ~= nil then
        scheduleFist()
    else
        fistTicking = false
    end
end

local function startFistTicking()
    if fistTicking then return end
    fistTicking = true
    scheduleFist()
end

local function castFist()
    -- One at a time; the engine will not recast it while it lasts anyway (nonRecastable).
    if fist ~= nil then return end
    fist = { phase = "waiting", giveUpAt = core.getSimulationTime() + BOUND_GRACE }
    startFistTicking()
end

local function onFistSummoned(e)
    local current = fist
    if current == nil or current.phase ~= "summoning" or current.cancelled then
        core.sendGlobalEvent("H2HWeapons_DismissFist", { item = e.item })
        if current ~= nil and current.phase == "summoning" then fist = nil end
        return
    end
    local equipment = types.Actor.getEquipment(omwself)
    equipment[CARRIED_RIGHT] = e.item
    types.Actor.setEquipment(omwself, equipment)
    current.phase = "held"
    current.item = e.item
    current.drawPending = isPlayer
end

-- How a cast is noticed. None of these has to say whether it worked: that shows when the effect
-- does, or does not, and castFist is a no-op while a fist is already on its way or in hand.
--   * The engine's own cast, for anyone: the release of its "spellcast" animation.
--   * A cast made by Spell Framework Plus - which is how Oblivion-Style Spell Casting casts, for the
--     player and for NPCs, without that animation - reported to the caster as MagExp_CastResult.
--   * For the player, anything else: player.lua watches for the effect itself (H2HWeapons_FistSeen).
local function castFistIfCarried(spell)
    if spell ~= nil and carriesFist(spell) then castFist() end
end

if canConjure then
    I.AnimationController.addTextKeyHandler("spellcast", function(_, key)
        if string.sub(key, -7) == "release" then castFistIfCarried(types.Actor.getSelectedSpell(omwself)) end
    end)
end

local function onCastReport(e)
    if not canConjure or e == nil or not e.success or e.spellId == nil then return end
    castFistIfCarried(core.magic.spells.records[e.spellId])
end

--- The hit ----------------------------------------------------------------------------------------
I.Combat.addOnHitHandler(function(attack)
    -- A miss deals nothing, and attack.damage is ignored for one anyway.
    if not attack.successful then return end
    if attack.sourceType ~= MELEE then return end

    local attacker = attack.attacker
    if attacker == nil then return end

    local kind = weapons.kindOfItem(attack.weapon)
    if not kind then return end

    addFatigue(attack, kind)

    local special = weapons.specialOfItem(attack.weapon)
    if special == SPECIAL.Venom or special == SPECIAL.Burst then
        struckByVenom(attacker, special == SPECIAL.Burst)
    elseif special == SPECIAL.MageFury then
        if types.Player.objectIsInstance(attacker) then
            -- The wielder decides what the strike cost: a spell carried, or nothing.
            attacker:sendEvent("H2HWeapons_MageFuryStrike", { victim = omwself.object, item = attack.weapon })
        else
            -- An NPC never channels, so its strikes cost nothing: what the engine took goes back.
            core.sendGlobalEvent("H2HWeapons_ChargeUse", { item = attack.weapon, delta = U.MAGE_FURY_COST })
        end
    end
end)

--- Combat Sounds Overhaul Overhauled -------------------------------------------------------------
-- With Combat Sounds Overhaul Overhauled, a hand-to-hand weapon swings with a fist's whoosh: a katar's
-- blade whoosh plays under it, softer, and a knuckle's own whoosh not at all. A script only sees
-- the interfaces of those attached before it, so this needs CSO's plugin above
-- H2HWeapons.omwscripts.
local cso = I.CombatSoundsOO
if cso and cso.addOnPlayHandler then
    cso.addOnPlayHandler(function(info)
        if info.kind ~= "swing" then return end
        local kind = weapons.kindOfId(info.weaponId)
        if not kind then return end
        -- playSwing has no weaponId, so this doesn't come back here
        cso.playSwing(cso.WEAPON.HandToHand, info.volume)
        if kind == weapons.KIND.Knuckle then return false end
        info.volume = info.volume * 0.66
    end)
end
-- A katar's own whoosh is only ever the sharp metal one: the dagger's ringing ones and plain ones
-- don't suit it
if cso and cso.addSwingGroupsHandler then
    cso.addSwingGroupsHandler(function(recordId)
        if weapons.kindOfId(recordId) == weapons.KIND.Katar then return { cso.SWING_GROUPS.sharpMetal } end
    end)
end

return {
    eventHandlers = {
        H2HWeapons_WatchVenom = function(e) watch(e.source, e.since) end,
        H2HWeapons_MageFuryDischarge = takeStoredSpell,
        H2HWeapons_FistSummoned = onFistSummoned,
        H2HWeapons_FistSeen = castFist,
        -- Spell Framework Plus' report of a cast it made. Listened to, never consumed.
        MagExp_CastResult = onCastReport,
    },
    engineHandlers = {
        onSave = function()
            -- Only an actor that is poisoned, or holds a bound fist, has anything worth keeping.
            local poisoned = lastTick ~= nil
            local held = fist ~= nil and fist.phase == "held"
            if not poisoned and not held then return nil end
            return {
                reading = poisoned, source = source,
                fist = held and { item = fist.item, previous = fist.previous } or nil,
            }
        end,
        onLoad = function(data)
            if not data then return end
            if data.reading then watch(data.source, core.getSimulationTime()) end
            if data.fist and data.fist.item then
                fist = { phase = "held", item = data.fist.item, previous = data.fist.previous }
                startFistTicking()
            end
        end,
    },
}

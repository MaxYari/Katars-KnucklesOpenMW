-- The katar moveset, registered with ReAnimation: ReAnimation's own hand-to-hand set, imported under
-- the katar's names by Sources/Tools/import_h2h_set.py (Weapon Bone seated for the katar grip and
-- mirrored onto Weapon Bone.L on the way), and played over the one-handed groups the engine uses for
-- these weapons - a katar is a short blade (1s), knuckledusters blunt (1b), and either falls back to
-- the generic one-handed animations (1h) when those have none (character.cpp:795). Everything here
-- lists all three rather than guessing.
--
-- Built the way ReAnimation builds its throwing-star set on top of the thrown one: idle and
-- locomotion outrank their parent, the jump and equip hide it, and the attacks are attack variants.
-- The animations keep the fist's timing. TIMING_MATCHING.ToOverride re-times the hidden parent to
-- each attack instead of the other way round, so the engine still lands its hit on the right frame;
-- the equip is fitted to its parent's length instead, since the parent's attach and detach keys are
-- what show and hide the weapon.
local mp = "scripts/MaxYari/H2HWeapons/"

local animation = require('openmw.animation')
local core = require('openmw.core')
local I = require('openmw.interfaces')
local omwself = require('openmw.self')
local ui = require('openmw.ui')

local weapons = require(mp .. "scripts/weapons")

if not core.contentFiles.has("ReAnimation_API.omwscripts") then
    print("[H2HWeapons] ERROR: ReAnimation is missing. It is a hard dependency - without it these " ..
        "weapons have no animations of their own.")
    ui.showMessage("Katars and Knuckledusters: ReAnimation is missing, please install it.")
    return
end

local RA = I.ReAnimation
local gutils = RA.gutils
local FIRST_PERSON = RA.ARMATURE_TYPE.FirstPerson
local BG = animation.BONE_GROUP
local controls = omwself.controls

--- Is a hand-to-hand weapon in hand? ---------------------------------------------------------------
-- ReAnimation already caches the equipped weapon's record id for everyone, at ten reads a second, so
-- the answer costs one table lookup. Conditions are polled every frame, which is why it matters.
--
-- The id only keys the cache. What the weapon is comes from the item: ReAnimation's id is lowercased,
-- and a generated record's - a Bound Fist scaled to its caster, Ebony Rose's burst copy, anything an
-- enchanter made - only resolves in its own case, "Generated:0x..." (ESM::RefId::deserializeText).
-- Looked up by the lowercased one, those were none of ours, and swung as plain one-handed weapons.
local kindById = {}

local function equippedKind()
    local id = RA.getEquippedWeaponId()
    if id == nil then return false end
    local kind = kindById[id]
    if kind == nil then
        kind = weapons.kindOfItem(RA.getEquippedWeapon())
        kindById[id] = kind
    end
    return kind
end

local function isHandToHandWeapon()
    return equippedKind() ~= false
end

-- The three groups a one-handed hand-to-hand weapon's `base` can play under.
local function oneHanded(base)
    return { base .. "1s", base .. "1h", base .. "1b" }
end

--- How an override sits over its parent -----------------------------------------------------------
-- Outranked: one above the parent everywhere, two on the lower body. An override that starts while its
-- parent is already playing has to outrank it, and a priority set exactly equal to one already
-- playing makes the engine destroy the other state (animation.cpp:905); the uneven lower body keeps
-- the set from ever matching a uniform engine one. Used for what has to be able to stop while its
-- parent plays on - swapping a katar for a dagger is a same-type swap that replays nothing, so a
-- hidden parent would stay hidden with nothing over it.
local function outrankParent(self, pOptions)
    local opts = gutils.cloneAnimOptions(pOptions or self.parentOptions)
    local priority = opts.priority
    local function at(group)
        if type(priority) == "number" then return priority end
        return priority[group]
    end
    opts.priority = {
        [BG.LeftArm] = at(BG.LeftArm) + 1,
        [BG.RightArm] = at(BG.RightArm) + 1,
        [BG.Torso] = at(BG.Torso) + 1,
        [BG.LowerBody] = at(BG.LowerBody) + 2,
    }
    return opts
end

-- Hidden: the parent plays on underneath with nothing showing (ReAnimation's own trick for attack
-- variants). For what only ever stops together with its parent - the jump, the equip.
local function hideParent(self, pOptions)
    local opts = gutils.cloneAnimOptions(pOptions)
    gutils.uniquifyPriority(pOptions)
    pOptions.blendMask = 0
    pOptions.blendmask = 0
    return opts
end

--- Idle ---------------------------------------------------------------------------------------------
-- Two ranked overrides on the same parents, only one of which ever plays: sneaking (2) over standing
-- (1), both over ReAnimation's own one-handed sneak idles (0). First person has no "idlesneak" of its
-- own - a sneaking weapon user is still playing idle1s - so controls.sneak is the only way to tell,
-- and startOnUpdate is what notices it change.
local function idleCondition(self)
    -- startOnUpdate reads parentOptions, which is only filled once the parent has been seen
    -- playing; a parent already running when the save loaded never passes through the handler.
    return self.parentOptions ~= nil and isHandToHandWeapon()
end

RA.addAnimationOverride({
    id = "H2HWeaponIdle",
    parent = oneHanded("idle"),
    groupname = "idlekatar",
    armatureType = FIRST_PERSON,
    overridePriority = 1,
    condition = idleCondition,
    stopCondition = function(self) return not isHandToHandWeapon() end,
    options = outrankParent,
    startOnAnimEvent = true,
    startOnUpdate = true,
})
RA.addAnimationOverride({
    id = "H2HWeaponIdleSneak",
    parent = oneHanded("idle"),
    groupname = "idlekatarsneak",
    armatureType = FIRST_PERSON,
    overridePriority = 2,
    condition = function(self) return idleCondition(self) and controls.sneak end,
    stopCondition = function(self) return not (isHandToHandWeapon() and controls.sneak) end,
    options = outrankParent,
    startOnAnimEvent = true,
    startOnUpdate = true,
})

--- Locomotion ---------------------------------------------------------------------------------------
-- Follows the one-handed cycle it replaces every frame, as ReAnimation's star locomotion does
-- (syncStarMove): the engine starts movement groups at speed 1 and re-scales them each frame to the
-- actor's current speed (character.cpp:2402), so a speed copied once goes stale. The speed is copied
-- every frame, nudged by the phase error so the two cycles stay aligned - an animation's time cannot
-- be set directly, and a cancel-and-replay would blend.
local PHASE_GAIN = 2          -- speed nudge per unit of phase error; halves a small error in ~0.4 s
local PHASE_MAX_NUDGE = 0.25  -- never more than 25% off the parent's speed
local PHASE_DEADZONE = 0.002  -- about 2 ms of a 1 s cycle; below it, plain parent speed

local function syncMove(self)
    local parentSpeed = animation.getSpeed(omwself, self.parent)
    if not parentSpeed then return end

    local speed = parentSpeed
    local parentDone = animation.getCompletion(omwself, self.parent)
    local done = animation.getCompletion(omwself, self.groupname)
    if parentDone and done then
        local err = parentDone - done
        err = err - math.floor(err + 0.5) -- wrap to [-0.5, 0.5): both cycles loop
        if math.abs(err) > PHASE_DEADZONE then
            local nudge = math.max(-PHASE_MAX_NUDGE, math.min(PHASE_MAX_NUDGE, err * PHASE_GAIN))
            speed = parentSpeed * (1 + nudge)
        end
    end

    if speed ~= self.syncedSpeed then
        animation.setSpeed(omwself, self.groupname, speed)
        self.syncedSpeed = speed
    end
end

local function moveOptions(self, pOptions)
    local opts = outrankParent(self, pOptions)
    self.syncedSpeed = nil
    if not pOptions then
        -- Started on update, with the parent already running: start from its live speed and phase.
        opts.speed = animation.getSpeed(omwself, self.parent) or opts.speed
        opts.startPoint = animation.getCompletion(omwself, self.parent) or opts.startPoint
    end
    return opts
end

for _, base in ipairs({ "walkforward", "walkback", "walkleft", "walkright",
                        "runforward", "runback", "runleft", "runright",
                        "sneakforward", "sneakback", "sneakleft", "sneakright" }) do
    RA.addAnimationOverride({
        id = "H2HWeaponMove_" .. base,
        parent = oneHanded(base),
        groupname = base .. "katar",
        armatureType = FIRST_PERSON,
        overridePriority = 1,
        condition = isHandToHandWeapon,
        stopCondition = function(self) return not isHandToHandWeapon() end,
        options = moveOptions,
        onUpdate = syncMove,
        startOnAnimEvent = true,
        startOnUpdate = true,
    })
end

--- Jump ---------------------------------------------------------------------------------------------
-- Plays twice per jump - from "start" in the air, then from "loop stop" for the landing - and the
-- engine replays it each time, so starting on the event covers both. It stops with its parent: the
-- one-handed jump underneath is hidden, so stopping this mid-air would leave nothing playing.
RA.addAnimationOverride({
    id = "H2HWeaponJump",
    parent = oneHanded("jump"),
    groupname = "jumpkatar",
    armatureType = FIRST_PERSON,
    overridePriority = 1,
    condition = isHandToHandWeapon,
    options = hideParent,
    startOnAnimEvent = true,
})

--- Equip and unequip ----------------------------------------------------------------------------------
-- Sections of the weapon's own group - "weapononehand: equip start/stop", "unequip start/stop"
-- (character.cpp:1405, :1463) - so they live in "katar" as the attacks do, in xKatarEqUneq.kf. The
-- hidden parent's "equip attach" / "unequip detach" keys are still what show and hide the weapon,
-- and the engine ends the section on the parent's timing (character.cpp:1834, :1860), so the fist's
-- section is played fitted to the parent's length: the weapon appears and leaves at the same
-- fraction of the motion it always did.
--
-- Registered before the attacks, which play "katar" on the same parent: the condition clears a
-- finished equip when an attack plays, and preOverride clears a swing still winding up when a
-- sheathe starts the unequip - both rely on this running first. Stance Any: a sheathe drops the
-- stance to Nothing before the unequip plays.
local EQUIP_SECTIONS = { ["equip start"] = "equip", ["unequip start"] = "unequip" }

local function sectionLength(group, section)
    local from = animation.getTextKeyTime(omwself, group .. ": " .. section .. " start")
    local to = animation.getTextKeyTime(omwself, group .. ": " .. section .. " stop")
    if from and to and to > from then return to - from end
    return nil
end

RA.addAnimationOverride({
    id = "H2HWeaponEquip",
    parent = "weapononehand",
    groupname = "katar",
    armatureType = FIRST_PERSON,
    stance = RA.STANCE.Any,
    overridePriority = 1,
    condition = function(self)
        local startKey = self.parentOptions.startkey or self.parentOptions.startKey
        if EQUIP_SECTIONS[startKey] then return isHandToHandWeapon() end
        if self.running then
            animation.cancel(omwself, self.groupname)
            self.running = false
        end
        return false
    end,
    preOverride = function(self)
        if not self.running and animation.isPlaying(omwself, self.groupname) then
            animation.cancel(omwself, self.groupname)
        end
    end,
    options = function(self, pOptions)
        local opts = hideParent(self, pOptions)
        local section = EQUIP_SECTIONS[opts.startkey or opts.startKey]
        local ours = section and sectionLength(self.groupname, section)
        local theirs = section and sectionLength(self.parent, section)
        if ours and theirs then
            opts.speed = (opts.speed or 1) * ours / theirs
        end
        return opts
    end,
    startOnAnimEvent = true,
})

--- Attacks -------------------------------------------------------------------------------------------
-- The fist's chop, slash and thrust, each with its mirrored variant, alternated as ReAnimation
-- alternates them for bare fists. ReAnimation's own one-handed set lives on "weapononehand" too, and
-- two sets active at once would hide the parent twice and uniquify its priority twice - the engine
-- would then erase one of the two. Ranked above it (ReAnimation's sets sit at 0), this one takes
-- every attack while a hand-to-hand weapon is in hand, and ReAnimation's stands down.
RA.addAttackVariants({
    id = "H2HWeaponAttacks",
    parentAttackGroupname = "weapononehand",
    armatureType = FIRST_PERSON,
    subAttackMode = RA.SUB_ATTACK_MODE.RoundRobin,
    timingMatching = RA.TIMING_MATCHING.ToOverride,
    overridePriority = 1,
    condition = isHandToHandWeapon,
    attacks = {
        chop = { { "katar" }, { "kataralt" } },
        slash = { { "katar" }, { "kataralt" } },
        thrust = { { "katar" }, { "kataralt" } },
    },
})

-- The katar moveset, registered with ReAnimation: ReAnimation's own hand-to-hand set, imported under
-- the katar's names by Sources/Tools/import_h2h_set.py (Weapon Bone seated for the katar grip and
-- mirrored onto Weapon Bone.L on the way), and played over the one-handed groups the engine uses for
-- these weapons - a katar is a short blade (1s), knuckledusters blunt (1b), and either falls back to
-- the generic one-handed animations (1h) when those have none (character.cpp:795). Everything here
-- lists all three rather than guessing.
--
-- In first person and in third, on the player and on every NPC: the third-person set is the same
-- animations under the same names, with vanilla's hand-to-hand legs merged in under them
-- (Animations/xbase_anim*, built by Sources/Tools/make_third_person_anims.py), so one set of
-- registrations serves both - whichever the engine has loaded for the view is what plays. ReAnimation
-- runs on NPCs too, and an NPC is always third person to it.
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
local types = require('openmw.types')

local weapons = require(mp .. "scripts/weapons")

if not core.contentFiles.has("ReAnimation_API.omwscripts") then
    -- Said once, by the player's copy; openmw.ui is not there for an NPC's anyway.
    if types.Player.objectIsInstance(omwself) then
        print("[H2HWeapons] ERROR: ReAnimation is missing. It is a hard dependency - without it these " ..
            "weapons have no animations of their own.")
        require('openmw.ui').showMessage("Katars and Knuckledusters: ReAnimation is missing, please install it.")
    end
    return
end

local RA = I.ReAnimation
if RA == nil then
    -- Installed, but loaded after this mod: its interface is not there yet when this script starts.
    if types.Player.objectIsInstance(omwself) then
        print("[H2HWeapons] ERROR: ReAnimation is loaded after H2HWeapons.omwscripts. Move it above " ..
            "this mod in the launcher's Content Files, or these weapons have no animations of their own.")
    end
    return
end
local gutils = RA.gutils
local ANY_VIEW = RA.ARMATURE_TYPE.Any
local BG = animation.BONE_GROUP
local BLEND_MASK = animation.BLEND_MASK
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
local function raiseOverParent(self, pOptions, upper, lower)
    local opts = gutils.cloneAnimOptions(pOptions or self.parentOptions)
    local priority = opts.priority
    local function at(group)
        if type(priority) == "number" then return priority end
        return priority[group]
    end
    opts.priority = {
        [BG.LeftArm] = at(BG.LeftArm) + upper,
        [BG.RightArm] = at(BG.RightArm) + upper,
        [BG.Torso] = at(BG.Torso) + upper,
        [BG.LowerBody] = at(BG.LowerBody) + lower,
    }
    return opts
end

local function outrankParent(self, pOptions)
    return raiseOverParent(self, pOptions, 1, 2)
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
-- (1). First person has no "idlesneak" of its own - a sneaking weapon user is still playing idle1s -
-- so controls.sneak is the only way to tell, and startOnUpdate is what notices it change. Third
-- person has one, and plays it for anyone sneaking, weapon or not (CharacterController::
-- refreshIdleAnims only adds the weapon's suffix to a plain idle), so there it is a parent of its own
-- and says so itself.
local SNEAK_IDLE = "idlesneak"

-- ReAnimation's own first-person sneak idles (idle1hsneak, idle1ssneak) play over these same parents
-- whenever the player sneaks, one above the parent everywhere and unranked, which ranking does not
-- stop. The engine shows the highest state on each bone group, and on a tie the one whose name sorts
-- first (animation.cpp, resetActiveGroups) - theirs, so theirs showed. In first person ours goes one
-- above them: two above the parent, three on the lower body, which there carries the spine the arms
-- and the camera hang from; still below the jump. Theirs never play in third person, where
-- "idlesneak" already has its lower body two up and raising it as far would tie it with walking.
local function sneakIdleOptions(self, pOptions)
    if gutils.getArmatureType() == RA.ARMATURE_TYPE.FirstPerson then
        return raiseOverParent(self, pOptions, 2, 3)
    end
    return outrankParent(self, pOptions)
end

local function sneaking(self)
    return self.parent == SNEAK_IDLE or controls.sneak
end

local function idleCondition(self)
    -- startOnUpdate reads parentOptions, which is only filled once the parent has been seen
    -- playing; a parent already running when the save loaded never passes through the handler.
    return self.parentOptions ~= nil and isHandToHandWeapon()
end

RA.addAnimationOverride({
    id = "H2HWeaponIdle",
    parent = oneHanded("idle"),
    groupname = "idlekatar",
    armatureType = ANY_VIEW,
    overridePriority = 1,
    condition = idleCondition,
    stopCondition = function(self) return not isHandToHandWeapon() end,
    options = outrankParent,
    startOnAnimEvent = true,
    startOnUpdate = true,
})
local sneakParents = oneHanded("idle")
sneakParents[#sneakParents + 1] = SNEAK_IDLE
RA.addAnimationOverride({
    id = "H2HWeaponIdleSneak",
    parent = sneakParents,
    groupname = "idlekatarsneak",
    armatureType = ANY_VIEW,
    overridePriority = 2,
    condition = function(self) return idleCondition(self) and sneaking(self) end,
    stopCondition = function(self) return not (isHandToHandWeapon() and sneaking(self)) end,
    options = sneakIdleOptions,
    startOnAnimEvent = true,
    startOnUpdate = true,
})

--- Locomotion ---------------------------------------------------------------------------------------
-- Follows the one-handed cycle it replaces every frame, as ReAnimation's star locomotion does
-- (syncStarMove): the engine starts movement groups at speed 1 and re-scales them each frame to the
-- actor's current speed (character.cpp:2402), so a speed copied once goes stale. The speed is copied
-- every frame, nudged by the phase error so the two cycles stay aligned - an animation's time cannot
-- be set directly, and a cancel-and-replay would blend.
--
-- The phase is how far through its track each one is, so a loop of the same steps but a different
-- length has to play at a different speed to keep up: ours is 21% longer than the third-person
-- one-handed walk, and a few percent off the short blade walk and the one-handed sneak. The speed is
-- scaled by the ratio of the two lengths; the nudge alone would get there, but only by trailing the
-- parent by half the difference, as a share of the loop. Past MAX_LENGTH_RATIO the two are not the
-- same steps (one cycle to a loop against two or three) and matching their lengths would only play
-- ours at the wrong pace; that is left to the nudge, as before.
local PHASE_GAIN = 2          -- speed nudge per unit of phase error; halves a small error in ~0.4 s
local PHASE_MAX_NUDGE = 0.25  -- never more than 25% off the parent's speed
local PHASE_DEADZONE = 0.002  -- about 2 ms of a 1 s cycle; below it, plain parent speed
local MAX_LENGTH_RATIO = 4 / 3

-- The length of a group's track from one key to another, in the file that plays it: getTextKeyTime
-- looks through the loaded files latest first, as play() does (animation.cpp:845).
local function trackLength(group, startKey, stopKey)
    local from = animation.getTextKeyTime(omwself, group .. ": " .. startKey)
    local to = animation.getTextKeyTime(omwself, group .. ": " .. stopKey)
    if from and to and to > from then return to - from end
    return nil
end

-- Our track's length against the parent's, over the part both play: from the keys the parent was
-- started with, which ours is started with too - "start" to "stop" for the engine's own movement
-- (character.cpp:759).
local function lengthRatio(self, opts)
    local startKey = opts.startkey or opts.startKey or "start"
    local stopKey = opts.stopkey or opts.stopKey or "stop"
    local ours = trackLength(self.groupname, startKey, stopKey)
    local theirs = trackLength(self.parent, startKey, stopKey)
    if not (ours and theirs) then return 1 end
    local ratio = ours / theirs
    if ratio > MAX_LENGTH_RATIO or ratio < 1 / MAX_LENGTH_RATIO then return 1 end
    return ratio
end

local function syncMove(self)
    local parentSpeed = animation.getSpeed(omwself, self.parent)
    if not parentSpeed then return end

    local speed = parentSpeed * (self.lengthRatio or 1)
    local parentDone = animation.getCompletion(omwself, self.parent)
    local done = animation.getCompletion(omwself, self.groupname)
    if parentDone and done then
        local err = parentDone - done
        err = err - math.floor(err + 0.5) -- wrap to [-0.5, 0.5): both cycles loop
        if math.abs(err) > PHASE_DEADZONE then
            local nudge = math.max(-PHASE_MAX_NUDGE, math.min(PHASE_MAX_NUDGE, err * PHASE_GAIN))
            speed = speed * (1 + nudge)
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
    -- Worked out on every start: the parent, and the file it plays from, change with the view.
    self.lengthRatio = lengthRatio(self, opts)
    opts.speed = (opts.speed or 1) * self.lengthRatio
    -- Third person plays only the upper body. The legs, hips and spine stay the one-handed walk's,
    -- and with them the footsteps and the pace: the engine moves an actor by the root of whatever
    -- plays its lower body, and ours, a loop of another length, walked it slower than the steps.
    -- Ours is keyed from the chest to sit on that spine (make_third_person_anims.py).
    if gutils.getArmatureType() == RA.ARMATURE_TYPE.ThirdPerson then
        local mask = opts.blendMask or opts.blendmask or BLEND_MASK.All
        mask = mask - mask % 2 -- the parent's, less the lower body (BLEND_MASK.LowerBody = 1)
        opts.blendMask, opts.blendmask = mask, mask
    end
    return opts
end

-- Started on update, the options come from the parent as it was last seen starting (moveOptions),
-- and one already walking when this script began - a save loaded mid-stride, an NPC walking into the
-- cell - never was; as the idle's condition, it waits for the next start.
local function moveCondition(self)
    return self.parentOptions ~= nil and isHandToHandWeapon()
end

for _, base in ipairs({ "walkforward", "walkback", "walkleft", "walkright",
                        "runforward", "runback", "runleft", "runright",
                        "sneakforward", "sneakback", "sneakleft", "sneakright" }) do
    RA.addAnimationOverride({
        id = "H2HWeaponMove_" .. base,
        parent = oneHanded(base),
        groupname = base .. "katar",
        armatureType = ANY_VIEW,
        overridePriority = 1,
        condition = moveCondition,
        stopCondition = function(self) return not isHandToHandWeapon() end,
        options = moveOptions,
        onUpdate = syncMove,
        startOnAnimEvent = true,
        startOnUpdate = true,
    })
end

-- The first-person one-handed walk, run and sneak are not laid out like the fist's: the walk and run
-- are an 8-frame lead-in and then three step cycles to the loop, the sneak two cycles, where the
-- fist's - and the short blade's a katar moves over - are one. Knuckledusters move over them (there is
-- no blunt set), and a one-cycle loop phase-matched to a longer one drifts off its footsteps. Over
-- those, the katar's cycles laid out the one-handed way (xKatar1hMovement.kf and
-- xKatar1hSneakMovement.kf, from Sources/Tools/make_katar_1h_movement.py), ranked above the plain
-- ones. First person only: third person has no such files, and there the plain ones play.
for _, base in ipairs({ "walkforward", "walkback", "walkleft", "walkright",
                        "runforward", "runback", "runleft", "runright",
                        "sneakforward", "sneakback", "sneakleft", "sneakright" }) do
    RA.addAnimationOverride({
        id = "H2HWeaponMove1h_" .. base,
        parent = base .. "1h",
        groupname = base .. "katar1h",
        armatureType = RA.ARMATURE_TYPE.FirstPerson,
        overridePriority = 2,
        condition = moveCondition,
        stopCondition = function(self) return not isHandToHandWeapon() end,
        options = moveOptions,
        onUpdate = syncMove,
        startOnAnimEvent = true,
        startOnUpdate = true,
    })
end

--- Turning --------------------------------------------------------------------------------------------
-- Turning on the spot plays the weapon's turn - turnleft1s, or the one-handed one it falls back to
-- (CharacterController::refreshMovementAnims) - on the whole body, over the idle, and so over ours.
-- The idle plays on underneath: the engine keeps a biped's idle going through its movement
-- (refreshIdleAnims). So in third person, with one of ours in hand, the turn keeps only the legs, hips
-- and spine, and the idle above them - the katar's, standing or sneaking - shows through. Not an
-- override: nothing of ours needs playing, only the turn narrowing.
local TURNS = {}
for _, base in ipairs({ "turnleft", "turnright" }) do
    for _, group in ipairs(oneHanded(base)) do TURNS[group] = true end
end

I.AnimationController.addPlayBlendedAnimationHandler(function(groupname, options)
    if TURNS[groupname] and isHandToHandWeapon()
            and gutils.getArmatureType() == RA.ARMATURE_TYPE.ThirdPerson then
        options.blendMask, options.blendmask = BLEND_MASK.LowerBody, BLEND_MASK.LowerBody
    end
end)

--- Jump ---------------------------------------------------------------------------------------------
-- Plays twice per jump - from "start" in the air, then from "loop stop" for the landing - and the
-- engine replays it each time, so starting on the event covers both. It stops with its parent: the
-- one-handed jump underneath is hidden, so stopping this mid-air would leave nothing playing.
RA.addAnimationOverride({
    id = "H2HWeaponJump",
    parent = oneHanded("jump"),
    groupname = "jumpkatar",
    armatureType = ANY_VIEW,
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
    armatureType = ANY_VIEW,
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
    armatureType = ANY_VIEW,
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

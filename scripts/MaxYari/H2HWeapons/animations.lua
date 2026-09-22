-- The katar moveset, registered with ReAnimation.
--
-- These animations were cut from the hand-to-hand set, so their key times are the fist's, not the
-- one-handed weapon's that the engine plays underneath. TIMING_MATCHING.ToOverride is what makes
-- that work: ReAnimation re-times the hidden parent to each section of the katar animation instead
-- of the other way round, so the animations can stay exactly as they were authored and the engine
-- still lands its hit on the right frame. See addAttackVariants in ReAnimationAPI.lua.
local mp = "scripts/MaxYari/H2HWeapons/"

local animation = require('openmw.animation')
local core = require('openmw.core')
local I = require('openmw.interfaces')
local ui = require('openmw.ui')

local weapons = require(mp .. "scripts/weapons")

if not core.contentFiles.has("ReAnimation_API.omwscripts") then
    print("[H2HWeapons] ERROR: ReAnimation is missing. It is a hard dependency - without it these " ..
        "weapons have no animations of their own.")
    ui.showMessage("Katars and Knuckledusters: ReAnimation is missing, please install it.")
    return
end

--- Is a hand-to-hand weapon in hand? ---------------------------------------------------------------
-- ReAnimation already caches the equipped weapon's record id for everyone, at ten reads a second, so
-- the answer costs one table lookup. Conditions are polled every frame, which is why it matters.
local kindById = {}

local function equippedKind()
    local id = I.ReAnimation.getEquippedWeaponId()
    if id == nil then return false end
    local kind = kindById[id]
    if kind == nil then
        kind = weapons.kindOfId(id)
        kindById[id] = kind
    end
    return kind
end

local function isHandToHandWeapon()
    return equippedKind() ~= false
end

--- Stand ReAnimation's own one-handed set down ------------------------------------------------------
-- Both sets live on "weapononehand". Two of them active at once would hide the parent twice and
-- uniquify its priority twice, and the engine would then erase one of the two - so they have to be
-- mutually exclusive. This is the half that belongs to this mod.
I.ReAnimation.addOverrideCondition("1hAttacks", function() return not isHandToHandWeapon() end)

--- Idle ---------------------------------------------------------------------------------------------
-- A katar is a short blade (idle1s) and knuckledusters are blunt (idle1b, which vanilla has no
-- animation for, so the engine falls back to idle1h - character.cpp:795). All three are listed
-- rather than guessed at.
--
-- The idle outranks its parent instead of hiding it: swapping a katar for a dagger is a same-type
-- swap that replays nothing, so a hidden parent would stay hidden with nothing over it.
local BG = animation.BONE_GROUP

local function outrankParent(self, pOptions)
    local opts = I.ReAnimation.gutils.cloneAnimOptions(pOptions or self.parentOptions)
    local priority = opts.priority
    local function at(group)
        if type(priority) == "number" then return priority end
        return priority[group]
    end
    -- One above the parent everywhere, two on the lower body: an override that starts while its
    -- parent is already playing has to outrank it, and a priority set exactly equal to one already
    -- playing makes the engine destroy the other state (animation.cpp:905). The uneven lower body
    -- keeps the set from ever matching a uniform engine one either.
    opts.priority = {
        [BG.LeftArm] = at(BG.LeftArm) + 1,
        [BG.RightArm] = at(BG.RightArm) + 1,
        [BG.Torso] = at(BG.Torso) + 1,
        [BG.LowerBody] = at(BG.LowerBody) + 2,
    }
    return opts
end

I.ReAnimation.addAnimationOverride({
    id = "H2HWeaponIdle",
    parent = { "idle1s", "idle1h", "idle1b" },
    groupname = "idlekatar",
    armatureType = I.ReAnimation.ARMATURE_TYPE.FirstPerson,
    condition = function(self)
        -- startOnUpdate reads parentOptions, which is only filled once the parent has been seen
        -- playing; a parent already running when the save loaded never passes through the handler.
        return self.parentOptions ~= nil and isHandToHandWeapon()
    end,
    stopCondition = function(self) return not isHandToHandWeapon() end,
    options = outrankParent,
    startOnAnimEvent = true,
    startOnUpdate = true,
})

--- Attacks -------------------------------------------------------------------------------------------
-- Only slash: the katar animations define "Katar: Slash ..." keys and nothing else, and a variant
-- whose start key is missing plays nothing at all while the parent stays hidden - an invisible
-- swing. Chop and thrust fall through to the engine's own one-handed animation.
I.ReAnimation.addAttackVariants({
    id = "H2HWeaponAttacks",
    parentAttackGroupname = "weapononehand",
    armatureType = I.ReAnimation.ARMATURE_TYPE.FirstPerson,
    timingMatching = I.ReAnimation.TIMING_MATCHING.ToOverride,
    condition = isHandToHandWeapon,
    attacks = {
        slash = { { "katar" }, { "kataralt" } },
    },
})

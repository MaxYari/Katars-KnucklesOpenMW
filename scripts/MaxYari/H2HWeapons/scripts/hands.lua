-- Models hung off an actor's bones as looping VFX, which is the only way a script can put a model on
-- one: the off-hand copy of the weapon on "Weapon Bone.L" - the mirror of the engine's own weapon bone,
-- which this mod grafts onto every vanilla skeleton (Animations/<skeleton>/h2h_weapon_bone_l.nif) -
-- and, on the player, a charged weapon's glow. Shared by the player's script and every NPC's.
--
-- Each slot is attached or taken off only when what should be on it changes. Whatever rebuilds the
-- actor's model - a first/third person switch, a load, the actor coming back into the world - takes
-- everything with it, and so does passing time (Actors::rest, removeEffects); forget() is for then,
-- so that everything goes back on.
local animation = require('openmw.animation')

local M = {}

local boneWarned = {}

local function warnMissingBone(bone)
    if boneWarned[bone] then return end
    boneWarned[bone] = true
    -- The bone is grafted onto whichever skeleton the engine loads, from
    -- animations/<that skeleton>/h2h_weapon_bone_l.nif (Animation::injectCustomBones) - which only
    -- happens with "use additional animation sources" on.
    print("[H2HWeapons] this actor's skeleton has no '" .. bone .. "' bone, so nothing can be shown " ..
        "on it. It is added from Animations/<skeleton>/h2h_weapon_bone_l.nif, and only with 'Use " ..
        "additional animation sources' on (launcher: Settings -> Visuals -> Animations). A skeleton " ..
        "this mod has no folder for will not get it; Sources/Tools/patch_skeleton.py in the mod's git " ..
        "repository makes one: https://github.com/MaxYari/Katars-KnucklesOpenMW")
end

-- slots: { { vfxId = , bone = }, ... }
function M.new(actor, slots)
    local attached = {} -- [slot index] = the model on it, as far as this knows
    local hands = {}

    function hands.attach(index, model)
        if attached[index] == model then return end
        local slot = slots[index]
        if attached[index] then animation.removeVfx(actor, slot.vfxId) end
        attached[index] = model
        if model == nil then return end
        -- The engine throws for a bone that is not there. A missing one is still recorded as attached,
        -- so it is asked about once per change rather than on every check.
        if not animation.hasBone(actor, slot.bone) then
            warnMissingBone(slot.bone)
            return
        end
        animation.addVfx(actor, model, {
            vfxId = slot.vfxId,
            boneName = slot.bone,
            loop = true,
            useAmbientLight = false,
        })
    end

    function hands.detachAll()
        for i = 1, #slots do
            -- Harmless when the model they were on is already gone.
            if attached[i] then animation.removeVfx(actor, slots[i].vfxId) end
            attached[i] = nil
        end
    end

    -- Everything was taken off with the model, or by passing time: forget it, and it goes back on
    -- with the next attach. An effect still there is not added twice (Animation::addEffect keeps a
    -- looping one to one per bone).
    function hands.forget()
        attached = {}
    end

    function hands.model(index) return attached[index] end

    return hands
end

return M

-- Minimal fakes for the openmw API, enough to load and drive the scripts under test.
local M = {}

local roots = {}          -- data folders, searched in order
function M.addRoot(path) roots[#roots+1] = path end

--- This mod's folder, and ReAnimation's next to it. Override either with H2H_MOD / H2H_REANIMATION.
function M.findMods()
    local here = arg[0]:gsub("[^/]*$", "")
    local mod = os.getenv("H2H_MOD") or (here .. "../../..")
    local reanimation = os.getenv("H2H_REANIMATION")
    if not reanimation then
        -- The Nexus download folder carries a version suffix, so it is matched rather than named.
        -- The Nexus download folder carries a version suffix, and other ReAnimation-something
        -- folders sit next to it, so the API script is what is actually looked for.
        local pipe = io.popen('for d in "' .. mod ..
            '"/../*/scripts/MaxYari/ReAnimation_v3/ReAnimationAPI.lua; do [ -f "$d" ] && ' ..
            'echo "${d%/scripts/MaxYari/ReAnimation_v3/ReAnimationAPI.lua}" && break; done 2>/dev/null')
        reanimation = pipe:read("l")
        pipe:close()
    end
    if not reanimation or reanimation == "" then
        error("ReAnimation not found next to this mod. Set H2H_REANIMATION to its folder.")
    end
    return mod, reanimation
end

-- OpenMW resolves require("scripts/Foo/bar") against the VFS; plain Lua wants dots.
table.insert(package.searchers or package.loaders, 1, function(name)
    if name:sub(1, 6) ~= "openmw" then
        local rel = name:gsub("%.", "/") .. ".lua"
        for _, root in ipairs(roots) do
            local f = io.open(root .. "/" .. rel, "r")
            if f then
                local src = f:read("a"); f:close()
                return assert(load(src, "@" .. root .. "/" .. rel))
            end
        end
    end
    return nil
end)

--- state the tests poke at -------------------------------------------------------------------------
M.state = {
    textKeys = {},        -- ["group: key"] = time
    groups = {},          -- [group] = true
    stance = 1,
    equipped = nil,       -- { recordId = ..., type = ... }
    skills = {},          -- [name] = { base, modifier, damage }
    attributes = { strength = { base = 40, modifier = 0 } },
    gmst = {
        fMinHandToHandMult = 0.1, fMaxHandToHandMult = 0.5,
        sSkillHandtohand = "Hand-to-hand", sSkillShortblade = "Short Blade",
        sSkillBluntweapon = "Blunt Weapon", fFightDispMult = 0.2,
    },
    weaponRecords = {},   -- [id] = { type = , model = }
    played = {},          -- log of playBlendedAnimation calls
    time = 0,
}
local st = M.state

local function statObject(tbl)
    return setmetatable({}, {
        __index = function(_, k)
            if k == "modified" then return (tbl.base or 0) + (tbl.modifier or 0) - (tbl.damage or 0) end
            return tbl[k]
        end,
        __newindex = function(_, k, v) tbl[k] = v end,
    })
end
M.statObject = statObject

--- packages -----------------------------------------------------------------------------------------
local packages = {}

--- A stand-in for openmw.ui's content lists: an array that can also be indexed by element name.
function M.content(items)
    local c = {}
    for _, item in ipairs(items or {}) do c[#c + 1] = item end
    return setmetatable(c, {
        __index = function(t, k)
            if k == "add" then return function(self, v) self[#self + 1] = v end end
            if k == "insert" then return function(self, i, v) table.insert(self, i, v) end end
            if k == "indexOf" then
                return function(self, name)
                    for i = 1, #self do if rawget(self, i).name == name then return i end end
                    return nil
                end
            end
            if type(k) == "string" then
                for i = 1, #t do if rawget(t, i).name == k then return rawget(t, i) end end
            end
            return nil
        end,
    })
end

packages['openmw.util'] = {
    vector2 = function(x, y) return { x = x, y = y } end,
    vector3 = function(x, y, z) return { x = x, y = y, z = z } end,
    clamp = function(v, a, b) return math.max(a, math.min(b, v)) end,
    round = function(v) return math.floor(v + 0.5) end,
    makeStrictReadOnly = function(t) return t end,
    color = { rgb = function(r, g, b) return { r = r, g = g, b = b } end },
}

packages['openmw.core'] = {
    getGMST = function(name) return st.gmst[name] end,
    getSimulationTime = function() return st.time end,
    getRealTime = function() return st.time end,
    contentFiles = { has = function(_, n) return true end },
    -- Reads the mod's own l10n file, so a test that checks a message really checks the message.
    -- Only the flat `key: "text"` entries; the settings descriptions are block scalars and no test
    -- looks at them, so those come back as their key.
    l10n = function(context)
        local strings = {}
        for _, root in ipairs(roots) do
            local f = io.open(root .. "/l10n/" .. context .. "/en.yaml", "r")
            if f then
                for line in f:lines() do
                    local k, v = line:match('^([%w_]+):%s*"(.*)"%s*$')
                    if k then strings[k] = v end
                end
                f:close()
                break
            end
        end
        return function(key) return strings[key] or key end
    end,
    sound = {
        stopSound = function(id, obj) st.stoppedSounds = st.stoppedSounds or {}; table.insert(st.stoppedSounds, id) end,
    },
    magic = { ENCHANTMENT_TYPE = {}, EFFECT_TYPE = {} },
    stats = { Skill = { record = function() return { skillGain = { 1, 1, 1, 1 } } end } },
}
-- contentFiles.has is called as a method in some scripts and plainly in others.
setmetatable(packages['openmw.core'].contentFiles, { __call = function(_, n) return true end })

local WEAPON_TYPE = {
    ShortBladeOneHand = 0, LongBladeOneHand = 1, LongBladeTwoHand = 2, BluntOneHand = 3,
    BluntTwoClose = 4, BluntTwoWide = 5, SpearTwoWide = 6, AxeOneHand = 7, AxeTwoHand = 8,
    MarksmanBow = 9, MarksmanCrossbow = 10, MarksmanThrown = 11, Arrow = 12, Bolt = 13,
}

local skillsProxy = setmetatable({}, { __index = function(_, name)
    return function(_actor)
        st.skills[name] = st.skills[name] or { base = 0, modifier = 0, damage = 0 }
        return statObject(st.skills[name])
    end
end })

local attributesProxy = setmetatable({}, { __index = function(_, name)
    return function(_actor)
        st.attributes[name] = st.attributes[name] or { base = 0, modifier = 0 }
        return statObject(st.attributes[name])
    end
end })

packages['openmw.types'] = {
    Actor = {
        STANCE = { Nothing = 0, Weapon = 1, Spell = 2 },
        EQUIPMENT_SLOT = { CarriedRight = 16, CarriedLeft = 15 },
        getStance = function() return st.stance end,
        getEquipment = function(_, slot) return st.equipped end,
        stats = { attributes = attributesProxy, dynamic = {} },
        objectIsInstance = function() return true end,
    },
    NPC = {
        objectIsInstance = function(o) return o ~= nil end,
        stats = { skills = skillsProxy },
    },
    Player = { objectIsInstance = function() return true end },
    Weapon = {
        TYPE = WEAPON_TYPE,
        objectIsInstance = function(o) return o ~= nil and o.recordId ~= nil end,
        record = function(idOrObj)
            local id = type(idOrObj) == "string" and idOrObj or (idOrObj and idOrObj.recordId)
            return id and st.weaponRecords[string.lower(id)]
        end,
        records = st.weaponRecords,
    },
    Armor = { objectIsInstance = function() return false end },
    Item = { itemData = function() return {} end },
    Miscellaneous = {},
    Static = {},
    Creature = {},
}

packages['openmw.animation'] = {
    PRIORITY = { Default = 0, WeaponLowerBody = 1, SneakIdleLowerBody = 2, SwimIdle = 3, Jump = 4,
                 Movement = 5, Hit = 6, Weapon = 7, Block = 8, Knockdown = 9, Torch = 10,
                 Storm = 11, Death = 12, Scripted = 13 },
    BLEND_MASK = { LowerBody = 1, Torso = 2, LeftArm = 4, RightArm = 8, UpperBody = 14, All = 15 },
    BONE_GROUP = { LowerBody = 0, Torso = 1, LeftArm = 2, RightArm = 3 },
    hasGroup = function(_, g) return st.groups[g] == true end,
    hasBone = function(_, b) return st.bones and st.bones[b] == true end,
    getTextKeyTime = function(_, key) return st.textKeys[string.lower(key)] end,
    getCurrentTime = function(_, g) return st.groups[g] and 0 or nil end,
    getCompletion = function() return 0 end,
    getSpeed = function() return 1 end,
    setSpeed = function() end,
    cancel = function(_, g) st.cancelled = st.cancelled or {}; table.insert(st.cancelled, g) end,
    addVfx = function(_, model, opts) st.vfx = { model = model, opts = opts } end,
    removeVfx = function() st.vfx = nil end,
}

packages['openmw.self'] = setmetatable(
    { object = {}, recordId = "player", controls = { sneak = false, run = false },
      type = packages['openmw.types'].Player },
    { __index = function() return nil end })

packages['openmw.camera'] = { getMode = function() return st.cameraMode or 0 end, MODE = { FirstPerson = 0, ThirdPerson = 1 } }
packages['openmw.nearby'] = {}
packages['openmw.vfs'] = { fileExists = function() return false end, open = function() return nil end,
                           pathsWithPrefix = function() return function() return nil end end }
packages['openmw.storage'] = {
    globalSection = function()
        return { asTable = function() return {} end, subscribe = function() end, get = function() end }
    end,
    playerSection = function()
        return { asTable = function() return {} end, subscribe = function() end, get = function() end }
    end,
    LIFE_TIME = { Temporary = 0, Persistent = 1 },
}
packages['openmw.async'] = { callback = function(f) return f end,
                             newUnsavableSimulationTimer = function() end }
packages['openmw.ui'] = { showMessage = function(m) st.messages = st.messages or {}; table.insert(st.messages, m) end,
                          TYPE = {}, ALIGNMENT = {}, content = function(t) return t end, create = function(t) return t end }
packages['openmw_aux.util'] = {
    shallowCopy = function(t) local o = {}; for k, v in pairs(t) do o[k] = v end; return o end,
    callEventHandlers = function(handlers, ...)
        for i = #handlers, 1, -1 do
            if handlers[i](...) == false then return end
        end
    end,
}
packages['openmw_aux.ui'] = { deepDestroy = function() end }

--- interfaces ---------------------------------------------------------------------------------------
M.playHandlers = {}
M.textKeyHandlers = {}
M.animEndedHandlers = {}
M.skillUsedHandlers = {}
M.onHitHandlers = {}

local I = {}
I.AnimationController = {
    addPlayBlendedAnimationHandler = function(f) table.insert(M.playHandlers, f) end,
    addTextKeyHandler = function(_, f) table.insert(M.textKeyHandlers, f) end,
    addAnimationEndedHandler = function(f) table.insert(M.animEndedHandlers, f) end,
    playBlendedAnimation = function(group, options)
        for _, h in ipairs(M.playHandlers) do h(group, options) end
        table.insert(st.played, { group = group, options = options })
    end,
}
I.MSS = {
    getEquipmentInfo = function(slot)
        if slot ~= 16 or st.equipped == nil then return nil end
        st.equipInfo = st.equipInfo or {}
        local cached = st.equipInfo[st.equipped]
        if not cached then
            cached = { item = st.equipped, recordId = st.equipped.recordId,
                       record = packages['openmw.types'].Weapon.record(st.equipped) }
            st.equipInfo[st.equipped] = cached
        end
        return cached
    end,
}
I.SkillProgression = {
    SKILL_USE_TYPES = { Weapon_SuccessfulHit = 0 },
    addSkillUsedHandler = function(f) table.insert(M.skillUsedHandlers, f) end,
    skillUsed = function(id, options)
        st.skillUses = st.skillUses or {}
        table.insert(st.skillUses, { skill = id, options = options })
        for i = #M.skillUsedHandlers, 1, -1 do
            if M.skillUsedHandlers[i](id, options) == false then return end
        end
    end,
}
I.Combat = {
    ATTACK_SOURCE_TYPES = { Magic = 'magic', Melee = 'melee', Ranged = 'ranged', Unspecified = 'unspecified' },
    ATTACK_TYPES = { Chop = 0, Slash = 1, Thrust = 2 },
    addOnHitHandler = function(f) table.insert(M.onHitHandlers, f) end,
}
I.Settings = { registerGroup = function() end, registerPage = function() end }
I.MWUI = { templates = { textNormal = { name = "textNormal" }, textParagraph = { name = "textParagraph" } } }
-- Inventory Extender, when a test asks for it. Set M.tooltipModifiers is filled by the mod.
M.tooltipModifiers = {}
function M.enableInventoryExtender()
    I.InventoryExtender = {
        registerTooltipModifier = function(id, fn) M.tooltipModifiers[id] = fn end,
    }
end
packages['openmw.interfaces'] = I
M.I = I

package.preload_openmw = packages
table.insert(package.searchers or package.loaders, 1, function(name)
    local p = packages[name]
    if p then return function() return p end end
    return nil
end)

return M

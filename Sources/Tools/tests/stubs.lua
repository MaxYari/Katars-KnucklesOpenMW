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
    files = {},           -- VFS paths that exist, for vfs.fileExists
    vfxById = {},         -- [vfxId] = { model, opts }
    groups = {},          -- [group] = true
    stance = 1,
    equipped = nil,       -- { recordId = ..., type = ... }
    skills = {},          -- [name] = { base, modifier, damage }
    attributes = { strength = { base = 40, modifier = 0 } },
    gmst = {
        fMinHandToHandMult = 0.1, fMaxHandToHandMult = 0.5,
        sSkillHandtohand = "Hand-to-hand", sSkillShortblade = "Short Blade",
        sSkillBluntweapon = "Blunt Weapon", fFightDispMult = 0.2, fHandtoHandHealthPer = 0.1, fCombatKODamageMult = 1.5,
    },
    weaponRecords = {},   -- [id] = { type = , model = }
    played = {},          -- log of playBlendedAnimation calls
    time = 0,
    timers = {},          -- pending async simulation timers: { at, fn }
    globalEvents = {},    -- log of core.sendGlobalEvent: { name, data }
    events = {},          -- log of object:sendEvent: { target, name, data }
    effects = {},         -- [effect id] = magnitude, as I.MSS.getActiveEffect / activeEffects see it
    activeSpells = {},    -- the actor's active spells: { id, activeSpellId, options }
    health = { base = 100, modifier = 0, damage = 0, current = 100 },
    fatigue = { base = 100, modifier = 0, damage = 0, current = 100 },
    spellRecords = {},    -- [lowercased id] = spell record
    enchantRecords = {},  -- [lowercased id] = enchantment record
    staticRecords = {},   -- [id] = { model = }
    skillRecords = {},    -- [skill id] = { school = { hitSound = } }
    sounds = {},          -- log of sounds played
    nearbyActors = {},
    created = 0,          -- records and objects made through the fake world
    sections = {},        -- [storage section name] = { values = {}, subscribers = {} }
    missingContent = {},  -- [content file name] = true for one that is not installed
    taught = {},          -- log of types.Actor.spells(actor):add: { actor, spell }
    spawnedVfx = {},      -- log of world.vfx.spawn
}
local st = M.state

--- A small vector, enough for positions and distances.
local vec3mt = {}
vec3mt.__index = vec3mt
vec3mt.__sub = function(a, b) return M.vec3(a.x - b.x, a.y - b.y, a.z - b.z) end
function vec3mt.length(v) return math.sqrt(v.x * v.x + v.y * v.y + v.z * v.z) end
function M.vec3(x, y, z) return setmetatable({ x = x, y = y, z = z }, vec3mt) end

--- A game object that records the events sent to it.
function M.object(fields)
    local o = fields or {}
    o.sendEvent = function(self, name, data)
        table.insert(st.events, { target = self, name = name, data = data })
    end
    o.isValid = o.isValid or function() return true end
    return o
end

--- Runs simulation time forward, firing the timers that come due, in order.
function M.advance(seconds)
    local target = st.time + seconds
    while true do
        local nextIndex, nextAt = nil, math.huge
        for i, t in ipairs(st.timers) do
            if t.at <= target and t.at < nextAt then nextIndex, nextAt = i, t.at end
        end
        if not nextIndex then break end
        local timer = table.remove(st.timers, nextIndex)
        st.time = timer.at
        timer.fn()
    end
    st.time = target
end

--- The events sent to one target, or of one name, most recent last.
function M.eventsNamed(name)
    local out = {}
    for _, e in ipairs(st.events) do if e.name == name then out[#out + 1] = e end end
    return out
end

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
    vector3 = function(x, y, z) return M.vec3(x, y, z) end,
    clamp = function(v, a, b) return math.max(a, math.min(b, v)) end,
    round = function(v) return math.floor(v + 0.5) end,
    makeStrictReadOnly = function(t) return t end,
    color = { rgb = function(r, g, b) return { r = r, g = g, b = b } end },
}

packages['openmw.core'] = {
    getGMST = function(name) return st.gmst[name] end,
    getSimulationTime = function() return st.time end,
    getRealTime = function() return st.time end,
    -- Called plainly (core.contentFiles.has(name)) as the API documents, or as a method by some mods.
    contentFiles = { has = function(a, b)
        local name = type(a) == "string" and a or b
        return not st.missingContent[name]
    end },
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
        -- The 0.51 name: stopSound3d. A stub under any other name would hide a call to one that does not exist.
        stopSound3d = function(id, obj) st.stoppedSounds = st.stoppedSounds or {}; table.insert(st.stoppedSounds, id) end,
        playSound3d = function(id) table.insert(st.sounds, id) end,
        playSoundFile3d = function(path) table.insert(st.sounds, path) end,
    },
    sendGlobalEvent = function(name, data) table.insert(st.globalEvents, { name = name, data = data }) end,
    magic = {
        ENCHANTMENT_TYPE = {},
        EFFECT_TYPE = { ResistPoison = "resistpoison", WeaknessToPoison = "weaknesstopoison", Paralyze = "paralyze" },
        RANGE = { Self = 0, Touch = 1, Target = 2 },
        -- Every effect exists, unless a test says it went missing.
        effects = { records = setmetatable({}, { __index = function(_, id)
            if st.missingEffects and st.missingEffects[id] then return nil end
            return { id = id }
        end }) },
        SPELL_TYPE = { Spell = 0, Ability = 1, Power = 5 },
        spells = {
            records = setmetatable({}, { __index = function(_, id)
                return type(id) == "string" and st.spellRecords[string.lower(id)] or nil
            end }),
            createRecordDraft = function(t) return t end,
        },
        enchantments = {
            records = setmetatable({}, { __index = function(_, id)
                return type(id) == "string" and st.enchantRecords[string.lower(id)] or nil
            end }),
            createRecordDraft = function(t) t.isEnchantment = true; return t end,
        },
    },
    stats = { Skill = {
        record = function() return { skillGain = { 1, 1, 1, 1 } } end,
        records = setmetatable({}, { __index = function(_, id) return st.skillRecords[id] end }),
    } },
}
-- contentFiles.has is called as a method in some scripts and plainly in others.
setmetatable(packages['openmw.core'].contentFiles, { __call = function(_, n) return not st.missingContent[n] end })

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
        setStance = function(_, stance) st.stance = stance end,
        spells = function(actor)
            return { add = function(_, id) table.insert(st.taught, { actor = actor, spell = id }) end }
        end,
        getEquipment = function(_, slot)
            if slot == nil then return { [16] = st.equipped } end
            return st.equipped
        end,
        setEquipment = function(_, equipment) st.equipped = equipment[16] end,
        getSelectedSpell = function() return st.selectedSpell end,
        stats = { attributes = attributesProxy, dynamic = {
            health = function() return statObject(st.health) end,
            fatigue = function() return statObject(st.fatigue) end,
        } },
        objectIsInstance = function(o) return o ~= nil and not o.isItem end,
        activeEffects = function()
            return { getEffect = function(_, id) return { magnitude = st.effects[id] or 0 } end }
        end,
        activeSpells = function()
            local list = {}
            for _, spell in ipairs(st.activeSpells) do list[#list + 1] = spell end
            return setmetatable(list, { __index = {
                add = function(_, options)
                    st.nextActiveSpellId = (st.nextActiveSpellId or 0) + 1
                    table.insert(st.activeSpells, { id = options.id, activeSpellId = st.nextActiveSpellId,
                                                    options = options })
                end,
                remove = function(_, activeSpellId)
                    for i, spell in ipairs(st.activeSpells) do
                        if spell.activeSpellId == activeSpellId then table.remove(st.activeSpells, i); return end
                    end
                end,
            } })
        end,
        inventory = function(actor) return { owner = actor } end,
    },
    NPC = {
        objectIsInstance = function(o) return o ~= nil end,
        isWerewolf = function() return st.werewolf == true end,
        stats = { skills = skillsProxy },
    },
    -- Everyone is the player unless marked otherwise.
    Player = { objectIsInstance = function(o) return not (o ~= nil and o.notPlayer) end },
    Weapon = {
        TYPE = WEAPON_TYPE,
        objectIsInstance = function(o) return o ~= nil and o.recordId ~= nil end,
        record = function(idOrObj)
            local id = type(idOrObj) == "string" and idOrObj or (idOrObj and idOrObj.recordId)
            -- As the engine: ids are case-insensitive, except a generated record's, which only
            -- parses as "Generated:0x..." (ESM::RefId::deserializeText) - lowercased, it names nothing.
            if id == nil or string.find(id, "^generated:") then return nil end
            return st.weaponRecords[string.lower(id)]
        end,
        records = st.weaponRecords,
        createRecordDraft = function(t)
            local draft = {}
            for k, v in pairs(t.template or {}) do draft[k] = v end
            for k, v in pairs(t) do if k ~= "template" then draft[k] = v end end
            return draft
        end,
    },
    Armor = { objectIsInstance = function() return false end },
    Item = { itemData = function(item)
        item.data = item.data or {}
        return item.data
    end },
    Miscellaneous = {},
    Static = { records = setmetatable({}, { __index = function(_, id) return st.staticRecords[id] end }) },
    Creature = {},
}

-- A fake world for the global script: records get generated ids, objects are plain tables.
packages['openmw.world'] = {
    vfx = { spawn = function(model, position, options)
        table.insert(st.spawnedVfx, { model = model, position = position, options = options })
    end },
    createRecord = function(draft)
        st.created = st.created + 1
        local record = {}
        for k, v in pairs(draft) do record[k] = v end
        record.id = "Generated:0x" .. st.created
        if draft.isEnchantment then
            st.enchantRecords[string.lower(record.id)] = record
        elseif draft.effects then
            st.spellRecords[string.lower(record.id)] = record
        else
            st.weaponRecords[string.lower(record.id)] = record
        end
        return record
    end,
    createObject = function(recordId)
        st.created = st.created + 1
        local object = M.object({ recordId = recordId, isItem = true })
        object.moveInto = function(self, inventory) self.movedInto = inventory end
        object.remove = function(self) self.removed = true; self.isValid = function() return false end end
        return object
    end,
}

packages['openmw.animation'] = {
    PRIORITY = { Default = 0, WeaponLowerBody = 1, SneakIdleLowerBody = 2, SwimIdle = 3, Jump = 4,
                 Movement = 5, Hit = 6, Weapon = 7, Block = 8, Knockdown = 9, Torch = 10,
                 Storm = 11, Death = 12, Scripted = 13 },
    BLEND_MASK = { LowerBody = 1, Torso = 2, LeftArm = 4, RightArm = 8, UpperBody = 14, All = 15 },
    BONE_GROUP = { LowerBody = 0, Torso = 1, LeftArm = 2, RightArm = 3 },
    hasGroup = function(_, g) return st.groups[g] == true end,
    isPlaying = function(_, g) return st.playing ~= nil and st.playing[g] == true end,
    hasBone = function(_, b) return st.bones and st.bones[b] == true end,
    getTextKeyTime = function(_, key) return st.textKeys[string.lower(key)] end,
    getCurrentTime = function(_, g) return st.groups[g] and 0 or nil end,
    getCompletion = function() return 0 end,
    getSpeed = function() return 1 end,
    setSpeed = function() end,
    cancel = function(_, g) st.cancelled = st.cancelled or {}; table.insert(st.cancelled, g) end,
    addVfx = function(_, model, opts)
        st.vfx = { model = model, opts = opts }
        st.vfxById = st.vfxById or {}
        st.vfxById[(opts and opts.vfxId) or ""] = { model = model, opts = opts }
    end,
    removeVfx = function(_, id)
        if st.vfx and st.vfx.opts and st.vfx.opts.vfxId == id then st.vfx = nil end
        if st.vfxById then st.vfxById[id or ""] = nil end
    end,
}

packages['openmw.self'] = setmetatable(
    { object = M.object({ name = "self" }), recordId = "player", controls = { sneak = false, run = false },
      type = packages['openmw.types'].Player, position = M.vec3(0, 0, 0),
      -- self is a GameObject too; an event sent to it is logged against its object.
      sendEvent = function(self, name, data)
          table.insert(st.events, { target = self.object, name = name, data = data })
      end },
    { __index = function() return nil end })

packages['openmw.debug'] = { isGodMode = function() return st.godMode == true end }
packages['openmw.camera'] = { getMode = function() return st.cameraMode or 0 end, MODE = { FirstPerson = 0, ThirdPerson = 1 } }
packages['openmw.nearby'] = setmetatable({}, { __index = function(_, k)
    if k == "actors" then return st.nearbyActors end
end })
packages['openmw.vfs'] = {
    fileExists = function(path) return st.files ~= nil and st.files[path] == true end,
    open = function() return nil end,
    pathsWithPrefix = function() return function() return nil end end,
}
-- Sections keep their values and tell their subscribers, so a test can change another mod's setting
-- and see the scripts react.
local function section(name)
    local sec = st.sections[name]
    if not sec then
        sec = { values = {}, subscribers = {} }
        st.sections[name] = sec
    end
    return {
        asTable = function() local t = {}; for k, v in pairs(sec.values) do t[k] = v end; return t end,
        get = function(_, key) return sec.values[key] end,
        set = function(_, key, value)
            sec.values[key] = value
            for _, fn in ipairs(sec.subscribers) do fn(name, key) end
        end,
        subscribe = function(_, fn) table.insert(sec.subscribers, fn) end,
        setLifeTime = function(_, lifeTime) sec.lifeTime = lifeTime end,
    }
end
M.section = section
packages['openmw.storage'] = {
    globalSection = section,
    playerSection = section,
    LIFE_TIME = { Persistent = 0, GameSession = 1, Temporary = 2 },
}
-- callback is called as async:callback(fn), like everything else on async.
packages['openmw.async'] = { callback = function(a, b) if type(a) == "function" then return a end return b end,
                             newUnsavableSimulationTimer = function(_, delay, fn)
                                 table.insert(st.timers, { at = st.time + delay, fn = fn })
                             end }
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
M.textKeyHandlersByGroup = {}
-- Fires a text key at the handlers registered for its group, as the engine does.
function M.textKey(group, key)
    for _, f in ipairs(M.textKeyHandlersByGroup[group] or {}) do f(group, key) end
end
M.animEndedHandlers = {}
M.skillUsedHandlers = {}
M.onHitHandlers = {}

local I = {}
I.AnimationController = {
    addPlayBlendedAnimationHandler = function(f) table.insert(M.playHandlers, f) end,
    addTextKeyHandler = function(group, f)
        table.insert(M.textKeyHandlers, f)
        group = group or "" -- "" or none: every group's keys
        M.textKeyHandlersByGroup[group] = M.textKeyHandlersByGroup[group] or {}
        table.insert(M.textKeyHandlersByGroup[group], f)
    end,
    addAnimationEndedHandler = function(f) table.insert(M.animEndedHandlers, f) end,
    playBlendedAnimation = function(group, options)
        for _, h in ipairs(M.playHandlers) do h(group, options) end
        table.insert(st.played, { group = group, options = options })
    end,
}
I.MSS = {
    getActiveEffect = function(id) return st.effects[id] or 0 end,
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
    SKILL_USE_TYPES = { Weapon_SuccessfulHit = 0, Spellcast_Success = 0 },
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

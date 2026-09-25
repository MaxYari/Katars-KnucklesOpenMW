-- Bound Fist: the tiers, the scaling, the records, the merchants, and binding and unbinding the weapon.
package.path = arg[0]:gsub("[^/]*$", "") .. "?.lua;" .. package.path
local stubs = require("stubs")
local K, R = stubs.findMods()
stubs.addRoot(R); stubs.addRoot(K)

local st = stubs.state
local fails, checks = 0, 0
local function check(ok, msg, extra)
    checks = checks + 1
    if not ok then fails = fails + 1; print("FAIL: " .. msg .. (extra and ("  [" .. tostring(extra) .. "]") or "")) end
end
local function near(a, b) return a ~= nil and b ~= nil and math.abs(a - b) < 1e-6 end

local U = require("scripts/MaxYari/H2HWeapons/scripts/uniques")
local formulas = require("scripts/MaxYari/H2HWeapons/scripts/formulas")
local D = U.BOUND_SCALING_DEFAULTS

-- The tier records as Katar.omwaddon writes them.
st.weaponRecords["h2h_bound_knuckle"] = { id = "h2h_bound_knuckle", type = 3, model = "meshes/daedric_knuckle_basic.nif",
    chopMinDamage = 5, chopMaxDamage = 13, slashMinDamage = 5, slashMaxDamage = 13, thrustMinDamage = 6, thrustMaxDamage = 12, weight = 0 }
st.weaponRecords["h2h_bound_knuckle_spiked"] = { id = "h2h_bound_knuckle_spiked", type = 3, model = "meshes/daedric_knuckle_sharp.nif",
    chopMinDamage = 5, chopMaxDamage = 13, slashMinDamage = 5, slashMaxDamage = 13, thrustMinDamage = 6, thrustMaxDamage = 12, weight = 0 }
st.weaponRecords["h2h_bound_katar"] = { id = "h2h_bound_katar", type = 0, model = "meshes/daedric_katar.nif",
    chopMinDamage = 8, chopMaxDamage = 21, slashMinDamage = 8, slashMaxDamage = 21, thrustMinDamage = 10, thrustMaxDamage = 19, weight = 0,
    enchant = "h2h_bound_fist_effect_en" }
-- Fortify Hand-to-hand 10, constant: what every tier carries (make_plugin.py).
st.enchantRecords["h2h_bound_fist_effect_en"] = { id = "h2h_bound_fist_effect_en", type = 3, charge = 0, cost = 0,
    isAutocalc = false, effects = { { id = "fortifyskill", affectedSkill = "handtohand", range = 0, area = 0,
    duration = 1, magnitudeMin = 10, magnitudeMax = 10 } } }
st.weaponRecords["katar_steel"] = { type = 0, model = "meshes/steel_katar.nif" }
st.spellRecords[U.BOUND_FIST_SPELL] = { id = U.BOUND_FIST_SPELL, effects = { { id = U.BOUND_FIST_EFFECT, index = 0 } } }
st.bones = { ["Weapon Bone"] = true, ["Weapon Bone.L"] = true }
st.groups = { weapononehand = true }
st.skills = {
    handtohand = { base = 50, modifier = 0, damage = 0 },
    shortblade = { base = 50, modifier = 0, damage = 0 },
    bluntweapon = { base = 50, modifier = 0, damage = 0 },
    conjuration = { base = 50, modifier = 0, damage = 0 },
}

--- the numbers ----------------------------------------------------------------------------------------
local tiers = U.BOUND_FIST_TIERS
check(formulas.boundTier(0, tiers) == 1 and formulas.boundTier(39, tiers) == 1, "under 40: plain knuckles")
check(formulas.boundTier(40, tiers) == 2 and formulas.boundTier(64.9, tiers) == 2, "40 to 64: spiked knuckles")
check(formulas.boundTier(65, tiers) == 3 and formulas.boundTier(200, tiers) == 3, "65 and up: the katar")
check(formulas.boundStep(47.9, 5) == 45, "Conjuration is taken in steps of 5, rounded down")
-- Unofficial TR Spells' defaults: 50% at 0, 0.7% a point more
check(near(formulas.boundDamageMult(0, D), 0.5), "half damage at Conjuration 0")
check(near(formulas.boundDamageMult(50, D), 0.85), "85% at 50")
check(near(formulas.boundDamageMult(100, D), 1.2), "120% at 100")
check(near(formulas.boundEnchantMult(0, D), 0.5) and near(formulas.boundEnchantMult(100, D), 1.2),
      "the enchantment scales the same way by default: 50% at 0, 120% at 100")
check(near(formulas.boundWeight(8.1, 0, D), 3.24), "40% of the original's weight at 0", formulas.boundWeight(8.1, 0, D))
check(near(formulas.boundWeight(8.1, 100, D), 1.62), "half that at 100", formulas.boundWeight(8.1, 100, D))
check(formulas.boundWeight(8.1, 300, D) == 0, "and never below nothing")

--- recognising the weapons ----------------------------------------------------------------------------
local weapons = require("scripts/MaxYari/H2HWeapons/scripts/weapons")
check(weapons.kindOfId("h2h_bound_katar") == "katar", "the bound katar is a katar")
check(weapons.kindOfId("h2h_bound_knuckle_spiked") == "knuckle", "the bound spiked knuckles are knuckles")
st.weaponRecords["generated:0x10"] = { type = 0, model = "meshes/daedric_katar.nif" }
st.weaponRecords["generated:0x11"] = { type = 3, model = "Meshes\\Daedric_Knuckle_Sharp.NIF" }
st.weaponRecords["generated:0x12"] = { type = 3, model = "meshes/daedric_katar.nif" }
check(weapons.kindOfId("Generated:0x10") == "katar", "a scaled copy is known by its mesh")
check(weapons.kindOfId("Generated:0x11") == "knuckle", "whatever the case and slashes of its path")
check(weapons.kindOfId("Generated:0x12") == false, "but only if its weapon type agrees")

--- the load-time records -------------------------------------------------------------------------------
local content = {
    RANGE = { Self = 0, Touch = 1, Target = 2 },
    magicEffects = { records = {
        poison = { id = "poison" }, spellabsorption = { id = "spellabsorption" }, reflect = { id = "reflect" },
        bounddagger = { id = "bounddagger" }, damagehealth = { id = "damagehealth" },
    } },
    -- As the engine: a static's model has to be a path under meshes.
    statics = { records = setmetatable({}, { __newindex = function(t, id, record)
        local model = string.lower(record.model or "")
        if not (model:find("^meshes/") or model:find("^meshes\\")) then error("Path should start with 'meshes\\'") end
        rawset(t, id, record)
    end }) },
    sounds = { records = {} },
    enchantments = { records = {}, TYPE = { CastOnce = 0, CastOnStrike = 1, CastOnUse = 2, ConstantEffect = 3 } },
    spells = { records = {}, TYPE = { Spell = 0 } },
}
package.preload_openmw['openmw.content'] = content
require("scripts/MaxYari/H2HWeapons/content").engineHandlers.onContentFilesLoaded()
local effect = content.magicEffects.records[U.BOUND_FIST_EFFECT]
check(effect and effect.template == content.magicEffects.records.bounddagger, "Bound Fist is Bound Dagger's effect")
check(effect and effect.nonRecastable == true, "that cannot be recast while it lasts")
check(effect and effect.allowsSpellmaking == false, "and cannot be put in a spell of the player's own")
local spell = content.spells.records[U.BOUND_FIST_SPELL]
check(spell and spell.effects[1].id == U.BOUND_FIST_EFFECT, "the spell carries it")
check(spell and spell.effects[1].duration == 60 and spell.cost == 6, "for 60 seconds at 6 magicka, like a vanilla bound weapon")
check(spell and spell.effects[1].magnitudeMin == 1, "with a magnitude above nothing, so it can be read")

--- the global side ----------------------------------------------------------------------------------------
local global = require("scripts.MaxYari.H2HWeapons.global")
local G = global.eventHandlers
local caster = stubs.object({ name = "caster" })
local function lastEvent(name)
    local list = stubs.eventsNamed(name)
    return list[#list]
end

G.H2HWeapons_BoundScaling({ enabled = false, values = D })
G.H2HWeapons_SummonFist({ actor = caster, tier = 2, conjuration = 50 })
local summoned = lastEvent("H2HWeapons_FistSummoned")
check(summoned and summoned.target == caster, "the weapon goes to the caster")
check(summoned and summoned.data.item.recordId == "h2h_bound_knuckle_spiked", "unscaled, the tier's own record")
check(summoned and summoned.data.item.movedInto.owner == caster, "into their inventory")

G.H2HWeapons_BoundScaling({ enabled = true, values = D })
local made = st.created
G.H2HWeapons_SummonFist({ actor = caster, tier = 3, conjuration = 100 })
local item = lastEvent("H2HWeapons_FistSummoned").data.item
local record = st.weaponRecords[string.lower(item.recordId)]
check(record ~= nil and item.recordId ~= "h2h_bound_katar", "scaled, a copy of it")
check(record and record.model == "meshes/daedric_katar.nif", "that keeps the tier's mesh")
check(record and record.chopMinDamage == 10 and record.chopMaxDamage == 25, "with 120% damage at 100",
      record and (record.chopMinDamage .. "-" .. record.chopMaxDamage))
check(record and near(record.weight, 1.62), "and the scaled weight", record and record.weight)
local enchantment = record and st.enchantRecords[string.lower(record.enchant or "")]
local fortify = enchantment and enchantment.effects[1]
check(fortify and fortify.magnitudeMin == 12 and fortify.magnitudeMax == 12 and fortify.affectedSkill == "handtohand",
      "and its Fortify Hand-to-hand scaled with it, 120% at 100", fortify and fortify.magnitudeMin)
check(enchantment and enchantment.type == 3, "still a constant effect")
local copies = st.created - made

made = st.created
G.H2HWeapons_SummonFist({ actor = caster, tier = 3, conjuration = 103 })
check(st.created - made == 1, "the same tier and step reuses its record, making only the item", st.created - made)
check(lastEvent("H2HWeapons_FistSummoned").data.item.recordId == item.recordId, "the same record")
made = st.created
G.H2HWeapons_BoundScaling({ enabled = true, values = { BOUND_DAMAGE_BASE = 60, BOUND_DAMAGE_BONUS_PER_LEVEL = 0.7,
    BOUND_WEIGHT_BASE = 40, BOUND_WEIGHT_REDUCTION_PER_LEVEL = 0.5,
    BOUND_ENCHANT_BASE = 50, BOUND_ENCHANT_BONUS_PER_LEVEL = 0.7 } })
G.H2HWeapons_SummonFist({ actor = caster, tier = 3, conjuration = 100 })
check(st.created - made == copies, "changed settings make a record of their own")

-- Back to Oblivion.
local held = stubs.object({ recordId = "h2h_bound_katar", isItem = true, count = 1, parentContainer = caster })
held.remove = function(self) self.removed = true end
st.spawnedVfx = {}
G.H2HWeapons_DismissFist({ item = held })
check(held.removed == true, "a dismissed weapon is removed")
check(#st.spawnedVfx == 0, "quietly, from an inventory")
local dropped = stubs.object({ recordId = "h2h_bound_katar", isItem = true, count = 1, cell = {}, position = stubs.vec3(0, 0, 0) })
dropped.remove = function(self) self.removed = true end
G.H2HWeapons_DismissFist({ item = dropped })
check(dropped.removed == true and #st.spawnedVfx == 1, "and with a puff from the ground")

-- The merchants, a content file of their own (H2HWeapons_SpellTraders.omwscripts).
check(global.engineHandlers.onActorActive == nil, "the main mod teaches nobody; that is the traders script's job")
local list = require("scripts/MaxYari/H2HWeapons/traders/list")
local traders = require("scripts/MaxYari/H2HWeapons/traders/traders")
local sellers = list[U.BOUND_FIST_SPELL]
local seen, duplicate = {}, nil
for _, id in ipairs(sellers) do
    if seen[string.lower(id)] then duplicate = id end
    seen[string.lower(id)] = true
end
check(duplicate == nil, "no merchant is listed twice", duplicate)
check(seen["masalinie merian"], "one sells it at the Balmora Guild of Mages")
check(seen["t_aid_customspellsguy"], "and John Conjuration sells it")

st.taught = {}
traders.engineHandlers.onActorActive(stubs.object({ recordId = "Masalinie Merian" }))
traders.engineHandlers.onActorActive(stubs.object({ recordId = "TR_M7_WATERFALL" }))
traders.engineHandlers.onActorActive(stubs.object({ recordId = "fargoth" }))
check(#st.taught == 2 and st.taught[1].spell == U.BOUND_FIST_SPELL, "a listed merchant is taught it, whatever the case of the id; anyone else is not",
      #st.taught)
local spellRecord = st.spellRecords[U.BOUND_FIST_SPELL]
st.spellRecords[U.BOUND_FIST_SPELL] = nil
st.taught = {}
traders.engineHandlers.onActorActive(stubs.object({ recordId = "masalinie merian" }))
check(#st.taught == 0, "with the main mod off, and so no spell, nobody is taught anything")
st.spellRecords[U.BOUND_FIST_SPELL] = spellRecord

--- the caster's side ---------------------------------------------------------------------------------------
local actorScript = require("scripts.MaxYari.H2HWeapons.actor")
local me = require('openmw.self').object
local releaseHandler = stubs.textKeyHandlers[#stubs.textKeyHandlers]
local function castRelease() releaseHandler("spellcast", "self release") end
local function newFist(recordId)
    local fist = stubs.object({ recordId = recordId or "h2h_bound_knuckle_spiked", isItem = true, count = 1, parentContainer = me })
    return fist
end

local previous = stubs.object({ recordId = "katar_steel", isItem = true, parentContainer = me })
st.equipped = previous
st.selectedSpell = st.spellRecords[U.BOUND_FIST_SPELL]
st.stance = 2 -- spell stance, as after a cast
st.playing = { spellcast = true }
st.globalEvents = {}
st.timers = {}

castRelease()
st.effects[U.BOUND_FIST_EFFECT] = 1
stubs.advance(0.3)
local request
for _, e in ipairs(st.globalEvents) do if e.name == "H2HWeapons_SummonFist" then request = e.data end end
check(request ~= nil, "once the effect is on, the weapon is asked for")
check(request and request.tier == 2 and request.conjuration == 50, "at the caster's tier", request and request.tier)

-- A second report of the same cast - Spell Framework Plus' as well as the release - changes nothing.
actorScript.eventHandlers.MagExp_CastResult({ spellId = U.BOUND_FIST_SPELL, success = true })
local fist = newFist()
actorScript.eventHandlers.H2HWeapons_FistSummoned({ item = fist })
check(st.equipped == fist, "the bound weapon goes into the hand")
stubs.advance(0.3)
check(st.stance == 2, "not drawn while the cast is still playing")
st.playing = {}
stubs.advance(0.3)
check(st.stance == 1, "drawn once it is done, as the engine does for the player")

local requests = 0
for _, e in ipairs(st.globalEvents) do if e.name == "H2HWeapons_SummonFist" then requests = requests + 1 end end
check(requests == 1, "one cast, one weapon", requests)

st.globalEvents = {}
st.effects[U.BOUND_FIST_EFFECT] = 0
stubs.advance(0.3)
check(st.equipped == previous, "when the effect ends, the previous weapon is back in hand")
local dismissal
for _, e in ipairs(st.globalEvents) do if e.name == "H2HWeapons_DismissFist" then dismissal = e.data end end
check(dismissal and dismissal.item == fist, "and the bound one is sent back")
check(#st.timers == 0, "and nothing is read any more")

-- A failed cast: the effect never shows, nothing is summoned.
st.globalEvents = {}
castRelease()
stubs.advance(1.5)
local anything = false
for _, e in ipairs(st.globalEvents) do if e.name == "H2HWeapons_SummonFist" then anything = true end end
check(not anything, "a cast whose effect never shows summons nothing")
check(#st.timers == 0, "and stops watching")

-- Cast by Spell Framework Plus (Oblivion-Style Spell Casting): no cast animation, only its report.
st.globalEvents = {}
st.selectedSpell = nil
actorScript.eventHandlers.MagExp_CastResult({ spellId = "fireball", success = true })
actorScript.eventHandlers.MagExp_CastResult({ spellId = U.BOUND_FIST_SPELL, success = false })
st.effects[U.BOUND_FIST_EFFECT] = 1
stubs.advance(0.3)
local reported = false
for _, e in ipairs(st.globalEvents) do if e.name == "H2HWeapons_SummonFist" then reported = true end end
check(not reported, "another spell, or a failed cast, reported by Spell Framework Plus binds nothing")
actorScript.eventHandlers.MagExp_CastResult({ spellId = U.BOUND_FIST_SPELL, success = true })
stubs.advance(0.3)
for _, e in ipairs(st.globalEvents) do if e.name == "H2HWeapons_SummonFist" then reported = true end end
check(reported, "a successful Bound Fist it reports binds the weapon, with no cast animation at all")
actorScript.eventHandlers.H2HWeapons_FistSummoned({ item = newFist() })
st.effects[U.BOUND_FIST_EFFECT] = 0
stubs.advance(0.3)
st.selectedSpell = st.spellRecords[U.BOUND_FIST_SPELL]

-- Dropped: the spell ends with it.
st.activeSpells = { { id = U.BOUND_FIST_SPELL, activeSpellId = 7, effects = { { id = U.BOUND_FIST_EFFECT } } } }
castRelease()
st.effects[U.BOUND_FIST_EFFECT] = 1
stubs.advance(0.3)
fist = newFist()
actorScript.eventHandlers.H2HWeapons_FistSummoned({ item = fist })
fist.parentContainer = nil -- dropped
st.equipped = nil
st.globalEvents = {}
stubs.advance(0.3)
check(#st.activeSpells == 0, "a bound weapon that leaves the inventory ends its spell", #st.activeSpells)
local sentBack = false
for _, e in ipairs(st.globalEvents) do if e.name == "H2HWeapons_DismissFist" and e.data.item == fist then sentBack = true end end
check(sentBack, "and is sent back from wherever it is")
st.effects[U.BOUND_FIST_EFFECT] = 0
stubs.advance(0.3)

-- Over before the weapon came: it is sent straight back, never equipped.
st.equipped = previous
castRelease()
st.effects[U.BOUND_FIST_EFFECT] = 1
stubs.advance(0.3)
st.effects[U.BOUND_FIST_EFFECT] = 0
stubs.advance(0.3)
st.globalEvents = {}
local late = newFist()
actorScript.eventHandlers.H2HWeapons_FistSummoned({ item = late })
check(st.equipped == previous, "a weapon that arrives after its spell has ended is not equipped")
check(st.globalEvents[1] and st.globalEvents[1].name == "H2HWeapons_DismissFist", "but sent back")
stubs.advance(1)

-- Saved with the weapon out: the load picks it up again.
castRelease()
st.effects[U.BOUND_FIST_EFFECT] = 1
stubs.advance(0.3)
fist = newFist()
actorScript.eventHandlers.H2HWeapons_FistSummoned({ item = fist })
local saved = actorScript.engineHandlers.onSave()
check(saved and saved.fist and saved.fist.item == fist and saved.fist.previous == previous,
      "a save remembers the bound weapon and what it replaced")
st.effects[U.BOUND_FIST_EFFECT] = 0
stubs.advance(0.3)

--- following Unofficial TR Spells' settings -----------------------------------------------------------------
st.stance = 1
st.equipped = previous
local player = require("scripts.MaxYari.H2HWeapons.player")
local function lastScaling()
    local found
    for _, e in ipairs(st.globalEvents) do if e.name == "H2HWeapons_BoundScaling" then found = e.data end end
    return found
end
local status = function() return stubs.section("SettingsPlayerH2HWeaponsStatus"):get("boundScaling") end

st.globalEvents = {}
player.engineHandlers.onUpdate(0.016)
check(lastScaling() and lastScaling().enabled == false, "with that mod installed and its scaling off, none")
check(status() == "From Unofficial TR Spells: off", "and the settings page says so", status())

local tr = stubs.section(U.TR_BOUND_SECTION)
st.globalEvents = {}
tr:set("BOUND_DAMAGE_BASE", 60)
tr:set("BOUND_SCALING_ENABLED", true)
local report = lastScaling()
check(report and report.enabled == true, "switching it on there switches it on here")
check(report and report.values.BOUND_DAMAGE_BASE == 60, "with that mod's numbers")
check(report and report.values.BOUND_WEIGHT_BASE == D.BOUND_WEIGHT_BASE, "and its defaults for any it has not saved")
check(status() == "From Unofficial TR Spells: on", "the page follows", status())

st.missingContent[U.TR_SPELLS_SCRIPTS] = true
player.engineHandlers.onLoad(nil)
st.globalEvents = {}
player.engineHandlers.onUpdate(0.016)
report = lastScaling()
check(report and report.enabled == true and report.values.BOUND_DAMAGE_BASE == D.BOUND_DAMAGE_BASE,
      "without that mod: its defaults, and on")
check(status() == "Unofficial TR Spells not installed: defaults, on", "the page says that too", status())

-- However else it was cast, the player's script notices the effect itself and says so - once.
st.missingContent[U.TR_SPELLS_SCRIPTS] = nil
st.events = {}
st.effects[U.BOUND_FIST_EFFECT] = 1
st.time = st.time + 1
player.engineHandlers.onUpdate(0.016)
local seen = stubs.eventsNamed("H2HWeapons_FistSeen")
check(#seen == 1 and seen[1].target == me, "the player's script sees the effect and tells the actor script")
st.time = st.time + 1
player.engineHandlers.onUpdate(0.016)
check(#stubs.eventsNamed("H2HWeapons_FistSeen") == 1, "once, not every check while it lasts")
st.globalEvents = {}
actorScript.eventHandlers.H2HWeapons_FistSeen()
stubs.advance(0.3)
reported = false
for _, e in ipairs(st.globalEvents) do if e.name == "H2HWeapons_SummonFist" then reported = true end end
check(reported, "and the weapon is bound from that alone")
st.effects[U.BOUND_FIST_EFFECT] = 0
st.time = st.time + 1
player.engineHandlers.onUpdate(0.016)
st.effects[U.BOUND_FIST_EFFECT] = 1
st.time = st.time + 1
player.engineHandlers.onUpdate(0.016)
check(#stubs.eventsNamed("H2HWeapons_FistSeen") == 2, "and again for the next cast")

print(string.format("\n%d checks, %d failures", checks, fails))
os.exit(fails == 0 and 0 or 1)

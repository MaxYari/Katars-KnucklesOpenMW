-- The two uniques: Ebony Rose's venom and burst, Mage Fury's stored spell, and the records behind them.
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
local function near(a, b, eps) return a ~= nil and b ~= nil and math.abs(a - b) <= (eps or 1e-6) end

st.weaponRecords["katar_ebony_rose"] = { type = 0, model = "meshes/ebony_rose.nif", enchant = "h2h_ebonyrose_en" }
st.weaponRecords["knuckle_mage_fury"] = { type = 3, model = "meshes/mage_fury.nif", enchant = "h2h_magefury_en" }
st.weaponRecords["katar_steel"] = { type = 0, model = "meshes/steel_katar.nif" }
st.files = { ["meshes/mage_fury_charged.nif"] = true }
st.bones = { ["Weapon Bone"] = true, ["Weapon Bone.L"] = true }
st.groups = { weapononehand = true, katar = true, kataralt = true, idlekatar = true }
st.skills = {
    handtohand = { base = 50, modifier = 0, damage = 0 },
    shortblade = { base = 50, modifier = 0, damage = 0 },
    bluntweapon = { base = 50, modifier = 0, damage = 0 },
}
st.stance = 1

local U = require("scripts/MaxYari/H2HWeapons/scripts/uniques")

--- the load-time records ------------------------------------------------------------------------------
-- A fake openmw.content, with the vanilla effects the script builds on. Creating an effect list that
-- names an effect that does not exist yet is an error in the engine, so the fake is just as strict.
local content = {
    RANGE = { Self = 0, Touch = 1, Target = 2 },
    magicEffects = { records = {
        poison = { id = "poison", name = "Poison", harmful = true },
        spellabsorption = { id = "spellabsorption" },
        reflect = { id = "reflect" },
        damagehealth = { id = "damagehealth" },
    } },
    -- As the engine: a static's model has to be a path under meshes.
    statics = { records = setmetatable({}, { __newindex = function(t, id, record)
        local model = string.lower(record.model or "")
        if not (model:find("^meshes/") or model:find("^meshes\\")) then error("Path should start with 'meshes\\'") end
        rawset(t, id, record)
    end }) },
    sounds = { records = {
        Steam = { id = "Steam", fileName = "sound/fx/envrn/steam.wav" },
        ["potion fail"] = { id = "potion fail", fileName = "sound/fx/item/potionfail.wav" },
        ["destruction hit"] = { id = "destruction hit", fileName = "sound/fx/magic/desth.wav",
                                volume = 255, minRange = 30, maxRange = 100 },
        ["destruction area"] = { id = "destruction area", fileName = "sound/fx/magic/desta.wav",
                                 volume = 255, minRange = 30, maxRange = 90 },
    } },
    enchantments = { records = {}, TYPE = { CastOnce = 0, CastOnStrike = 1, CastOnUse = 2, ConstantEffect = 3 } },
    spells = { records = {}, TYPE = { Spell = 0 } },
}
local function strictEffects(store)
    return setmetatable({}, { __newindex = function(t, id, record)
        for _, effect in ipairs(record.effects or {}) do
            if content.magicEffects.records[effect.id] == nil then
                error("effect list names a magic effect that does not exist: " .. tostring(effect.id))
            end
        end
        rawset(t, id, record)
    end })
end
content.enchantments.records = strictEffects()
content.spells.records = strictEffects()
package.preload_openmw['openmw.content'] = content

local contentScript = require("scripts/MaxYari/H2HWeapons/content")
local printed = {}
local realPrint = print
print = function(...) printed[#printed + 1] = table.concat({ ... }, " ") end
local ok, err = pcall(contentScript.engineHandlers.onContentFilesLoaded)
print = realPrint
check(ok, "the load script runs", err)
check(#printed == 0, "and makes every record without a complaint", printed[1])
-- Records made at load are in the game's own lists afterwards.
for id, record in pairs(content.spells.records) do st.spellRecords[string.lower(id)] = record end

local venomEffect = content.magicEffects.records[U.VENOM_EFFECT]
check(venomEffect ~= nil, "it makes the venom effect")
check(venomEffect and venomEffect.template == content.magicEffects.records.poison, "from poison")
check(venomEffect and venomEffect.hitStatic == "h2h_vfx_venomhit" and venomEffect.areaStatic == "h2h_vfx_venomarea",
      "with purple hit and area effects")
local strikeSound = content.sounds.records[U.VENOM_HIT_SOUND]
check(venomEffect and venomEffect.hitSound == U.VENOM_HIT_SOUND and strikeSound
      and strikeSound.fileName == "sound/katars/venom_hit_proper.wav"
      and strikeSound.template == content.sounds.records["destruction hit"],
      "a strike sounds with the mod's own file, in a copy of the Destruction hit's record")
local burstSound = content.sounds.records[U.VENOM_AREA_SOUND]
check(venomEffect and venomEffect.areaSound == U.VENOM_AREA_SOUND and burstSound
      and burstSound.fileName == "sound/katars/venom_burst_proper.wav"
      and burstSound.template == content.sounds.records["destruction area"],
      "and a burst with its own, in a copy of the Destruction area's")
check(strikeSound and strikeSound.volume == nil and strikeSound.minRange == nil and burstSound
      and burstSound.volume == nil, "volume and reach left to the vanilla records they copy")
check(content.statics.records.h2h_vfx_venomhit and content.statics.records.h2h_vfx_venomhit.model
      == "meshes/katars/vfx_venom_hit.nif", "whose statics point at the purple meshes")
check(venomEffect and venomEffect.allowsSpellmaking == false and venomEffect.allowsEnchanting == false,
      "and no spellmaker or enchanter can use it")

local strike = content.enchantments.records[U.VENOM_ENCHANT]
check(strike and strike.type == 1, "Ebony Rose's enchantment is cast on strike")
check(strike and strike.effects[1].id == U.VENOM_EFFECT and strike.effects[1].magnitudeMin == 3
      and strike.effects[1].duration == 3, "3 points of venom for 3 seconds")
check(venomEffect and venomEffect.name == "Poison", "shown as Poison", venomEffect and venomEffect.name)
check(venomEffect and venomEffect.isAppliedOnce == true,
      "applied whole, so a strike on the poisoned does not take the looping cloud off")
local note = strike and strike.effects[2]
local noteEffect = content.magicEffects.records[U.BURST_NOTE_EFFECT]
check(note and note.id == U.BURST_NOTE_EFFECT and note.magnitudeMin == 20 and note.duration == 1,
      "a second line tells of the burst, 20 points for 1 second")
check(noteEffect and noteEffect.name == "Volatile Venom (3rd strike on the poisoned, 10 ft)",
      "named for what sets it off and how far it reaches", noteEffect and noteEffect.name)
check(note and note.area == 0, "with no area of its own, so no strike explodes for it")
check(noteEffect and noteEffect.harmful == false and noteEffect.hitStatic == U.NO_VFX_STATIC
      and noteEffect.hitSound == U.SILENT_SOUND, "and nothing to see, hear or take offence at")
check(content.statics.records[U.NO_VFX_STATIC].model == "meshes/katars/vfx_none.nif"
      and content.sounds.records[U.SILENT_SOUND].volume == 0, "a model with nothing in it, a silent sound")
local burst = content.enchantments.records[U.BURST_ENCHANT]
check(burst and #burst.effects == 2, "the burst keeps the strike's own venom and adds the burst")
check(burst and burst.effects[2].area == 10 and burst.effects[2].magnitudeMin == 20,
      "20 points in 10 feet", burst and burst.effects[2].area)
check(burst and burst.effects[2].range == 1, "on touch, so it bursts around whoever is struck")
check(content.spells.records[U.FINISHER_SPELL].effects[1].id == "damagehealth",
      "the finishing blow is a Damage Health, which the engine credits")

-- One part the engine rejects does not take the others down with it.
do
    local realStatics = content.statics
    content.statics = { records = setmetatable({}, { __newindex = function(t, id, record)
        if id == "h2h_vfx_venomhit" then error("rejected") end
        rawset(t, id, record)
    end }) }
    content.magicEffects.records[U.BOUND_FIST_EFFECT] = nil
    local logged = {}
    local realPrint = print
    print = function(...) logged[#logged + 1] = table.concat({ ... }, " ") end
    contentScript.engineHandlers.onContentFilesLoaded()
    print = realPrint
    content.statics = realStatics
    check(logged[1] and logged[1]:find("Ebony Rose", 1, true) and logged[1]:find("rejected", 1, true),
          "a part that fails says which, and why", logged[1])
    check(content.magicEffects.records[U.BOUND_FIST_EFFECT] ~= nil, "and the rest are still made")
    contentScript.engineHandlers.onContentFilesLoaded()
end

local fury = content.enchantments.records[U.MAGE_FURY_ENCHANT]
check(fury and fury.type == 1 and fury.effects[1].id == U.MAGE_FURY_EFFECT and fury.effects[1].range == 1,
      "Mage Fury's enchantment is a Spell Channeling cast on strike, so the knuckles hold a charge")
check(fury and fury.cost == 16 and fury.charge == 160,
      "a channelled strike's price on every strike, and charge for 10 of them", fury and fury.charge)
check(strike and strike.cost == 16 and strike.charge == 160 and burst and burst.cost == 40,
      "Ebony Rose: 16 a strike, 40 a burst, charge for 10 strikes", strike and strike.charge)
check(content.magicEffects.records[U.MAGE_FURY_EFFECT].name
      == "Spell Channeling: 3 strikes after a cast deal damage in proportion to the spell",
      "whose name says what it does", content.magicEffects.records[U.MAGE_FURY_EFFECT].name)
for strikes = 1, U.MAGE_FURY_STRIKES do
    local spell = content.spells.records[U.MAGE_FURY_CHARGE_SPELLS[strikes]]
    check(spell and spell.effects[1].magnitudeMin == strikes, "a charge display for " .. strikes .. " strikes")
end

--- the victim's side ---------------------------------------------------------------------------------
local actorScript = require("scripts.MaxYari.H2HWeapons.actor")
local onHit = stubs.onHitHandlers[#stubs.onHitHandlers]
local attacker = stubs.object({ name = "attacker", position = stubs.vec3(50, 0, 0) })
local roseItem = { recordId = "katar_ebony_rose" }

local function hitWith(weapon)
    onHit({ successful = true, sourceType = "melee", attacker = attacker, strength = 1,
            weapon = weapon, damage = { health = 10 } })
end
local function lastEvent(name)
    local list = stubs.eventsNamed(name)
    return list[#list]
end

st.health.current = 100
st.effects[U.VENOM_EFFECT] = 3 -- the engine applied the strike's venom before the hit event
hitWith(roseItem)
local report = lastEvent("H2HWeapons_VenomStrike")
check(report and report.target == attacker, "a venom strike is reported to the wielder")
check(report and report.data.victim ~= nil, "naming who was struck, for the wielder to count")
check(report and report.data.burst == false, "and is no burst")

-- Damage is billed by the time between reads, so it is exact over any span; where a span's edge
-- falls between two reads is float noise in the fake clock, so each check allows one read's worth.
local function tickOf(perSecond) return perSecond * 0.1 + 1e-6 end

stubs.advance(1.0)
check(near(st.health.current, 97, tickOf(3)), "the venom deals its magnitude every second", st.health.current)

local function damageOver(seconds)
    local before = st.health.current
    stubs.advance(seconds)
    return before - st.health.current
end
stubs.advance(0.05)
st.effects.resistpoison = 50
check(near(damageOver(2.0), 3.0, tickOf(1.5)), "Resist Poison halves it")
st.effects.weaknesstopoison = 100
check(near(damageOver(2.0), 9.0, tickOf(4.5)), "Weakness to Poison outweighing it makes it worse")
st.effects.weaknesstopoison = nil
st.effects.resistpoison = 100
check(near(damageOver(2.0), 0, tickOf(4.5)), "and full resistance stops it")
st.effects.resistpoison = nil

-- Once the venom is gone, reading stops.
st.effects[U.VENOM_EFFECT] = 0
stubs.advance(2.0)
check(#st.timers == 0, "an actor with no venom stops reading it", #st.timers)

-- The killing blow is the engine's, cast by whoever poisoned the victim.
st.activeSpells = {}
st.effects[U.VENOM_EFFECT] = 20
st.health.current = 1
hitWith(roseItem)
stubs.advance(0.1)
check(near(st.health.current, U.FINISHER_HEALTH), "a lethal tick leaves a sliver", st.health.current)
local finisher = st.activeSpells[1]
check(finisher and finisher.id == U.FINISHER_SPELL, "and hands over the finishing Damage Health")
check(finisher and finisher.options.caster == attacker, "cast by whoever poisoned them, for the kill credit")
stubs.advance(0.3)
check(#st.activeSpells == 1, "one at a time", #st.activeSpells)
st.effects[U.VENOM_EFFECT] = 0
st.health.current = 0
stubs.advance(2)
st.activeSpells = {}

-- The burst: everyone close enough is told to watch, nobody else, never the wielder.
local nearActor = stubs.object({ name = "near", position = stubs.vec3(150, 0, 0) })
local farActor = stubs.object({ name = "far", position = stubs.vec3(900, 0, 0) })
st.nearbyActors = { nearActor, farActor, attacker, require('openmw.self').object }
st.health.current = 100
st.events = {}
hitWith({ recordId = "Generated:0x42" })
check(#stubs.eventsNamed("H2HWeapons_VenomStrike") == 0, "an unknown weapon does nothing")
st.weaponRecords["generated:0x44"] = { type = 0, model = "meshes/ebony_rose.nif", enchant = "h2h_ebonyrose_burst_en" }
hitWith({ recordId = "Generated:0x44" })
local watched = {}
for _, e in ipairs(stubs.eventsNamed("H2HWeapons_WatchVenom")) do watched[e.target.name] = e.data end
check(watched.near ~= nil, "an actor within the burst is told to watch for the venom")
check(watched.near and watched.near.source == attacker, "with whoever to credit")
check(watched.far == nil, "one well outside is not")
check(watched.attacker == nil, "and the wielder never is")
check(watched.self == nil, "nor the one struck, who is already watching")
check(lastEvent("H2HWeapons_VenomStrike").data.burst == true, "the wielder hears the burst went off")

-- An actor told to watch reads the venom from when it landed.
st.effects[U.VENOM_EFFECT] = 20
st.health.current = 100
actorScript.eventHandlers.H2HWeapons_WatchVenom({ source = attacker, since = st.time })
stubs.advance(1.0)
check(near(st.health.current, 80, tickOf(20)), "a watcher takes the burst's damage", st.health.current)
st.effects[U.VENOM_EFFECT] = 0
stubs.advance(2)
st.nearbyActors = {}

-- Mage Fury's discharge: the spell is applied the engine's way, and its hit effects are played.
st.spellRecords["generated:0x7"] = { id = "generated:0x7", effects = {
    { index = 0, id = "firedamage", effect = { id = "firedamage", hitStatic = "VFX_DestructHit",
        particle = "vfx_firealpha00A.tga", continuousVfx = true, hitSound = "", school = "destruction" } },
    { index = 1, id = "frostdamage", effect = { id = "frostdamage", hitStatic = "VFX_FrostHit",
        particle = "vfx_icestar.tga", continuousVfx = false, hitSound = "frost_hit", school = "destruction" } },
} }
st.staticRecords["VFX_DestructHit"] = { model = "meshes/e/magic_hit_dst.nif" }
st.staticRecords["VFX_FrostHit"] = { model = "meshes/e/magic_hit_frost.nif" }
st.skillRecords.destruction = { school = { hitSound = "Sound/Fx/magic/destH.wav" } }
st.activeSpells, st.vfxById, st.sounds = {}, {}, {}
actorScript.eventHandlers.H2HWeapons_MageFuryDischarge({ spell = "generated:0x7", caster = attacker, name = "Frostfire" })
local taken = st.activeSpells[1]
check(taken and taken.id == "generated:0x7", "the struck actor takes the stored spell")
check(taken and #taken.options.effects == 2 and taken.options.effects[1] == 0, "every effect of it")
check(taken and taken.options.caster == attacker and taken.options.stackable == true,
      "cast by the wielder, and three strikes stack like three casts")
check(st.vfxById["firedamage"] and st.vfxById["firedamage"].opts.loop == true,
      "a continuous effect loops under its own id, so the engine takes it off when it ends")
check(st.vfxById["firedamage"] and st.vfxById["firedamage"].opts.particleTextureOverride == "vfx_firealpha00A.tga",
      "in its own colours")
check(st.vfxById[""] and st.vfxById[""].model == "meshes/e/magic_hit_frost.nif", "a one-off effect plays once")
check(st.sounds[1] == "Sound/Fx/magic/destH.wav", "an effect with no hit sound plays its school's")
check(st.sounds[2] == "frost_hit", "one with its own plays that")

-- A Mage Fury strike is reported to the wielder, who decides whether it carries anything.
st.events = {}
hitWith({ recordId = "knuckle_mage_fury" })
check(lastEvent("H2HWeapons_MageFuryStrike") and lastEvent("H2HWeapons_MageFuryStrike").target == attacker,
      "a Mage Fury strike is reported to the wielder")
local npcKnuckles = { recordId = "knuckle_mage_fury" }
st.events, st.globalEvents = {}, {}
onHit({ successful = true, sourceType = "melee", attacker = stubs.object({ name = "npc", notPlayer = true }),
        strength = 1, weapon = npcKnuckles, damage = { health = 10 } })
local refund = st.globalEvents[#st.globalEvents]
check(#stubs.eventsNamed("H2HWeapons_MageFuryStrike") == 0 and refund and refund.name == "H2HWeapons_ChargeUse"
      and refund.data.item == npcKnuckles and refund.data.delta == U.MAGE_FURY_COST,
      "an NPC's strike, which never carries a spell, gets back what the engine took")

--- the wielder's side -----------------------------------------------------------------------------------
local api = require("scripts.MaxYari.ReAnimation_v3.ReAnimationAPI")
stubs.I.ReAnimation = api.interface
st.time = 1000
st.timers = {}
local player = require("scripts.MaxYari.H2HWeapons.player")
local onUpdate = player.engineHandlers.onUpdate
local fire = function(name, data) player.eventHandlers[name](data) end
local function playWeapon(startKey)
    stubs.I.AnimationController.playBlendedAnimation("weapononehand",
        { startKey = startKey, startkey = startKey, stopKey = "x", stopkey = "x", speed = 2, priority = 7, blendMask = 15 })
end
local function lastGlobal(name)
    for i = #st.globalEvents, 1, -1 do
        if st.globalEvents[i].name == name then return st.globalEvents[i].data end
    end
end

local rose = stubs.object({ recordId = "katar_ebony_rose", isItem = true })
st.equipped = rose
for _ = 1, 3 do onUpdate(0.016) end

-- Counting: the third strike in a run on one poisoned enemy is the one that bursts, each strike
-- renewing the countdown to the next.
local enemyA = stubs.object({ name = "enemy a" })
local enemyB = stubs.object({ name = "enemy b" })
st.effects[U.VENOM_EFFECT] = nil
fire("H2HWeapons_VenomStrike", { victim = enemyA })
st.effects[U.VENOM_EFFECT] = 3
check(not player.interface.isBurstArmed(), "one strike is not enough")
st.time = st.time + 1
fire("H2HWeapons_VenomStrike", { victim = enemyA })
check(player.interface.isBurstArmed(), "two on one poisoned enemy make the next swing the third")
st.effects[U.VENOM_EFFECT] = nil
check(not player.interface.isBurstArmed(), "not while they are not poisoned")
st.effects.poison = 5
check(player.interface.isBurstArmed(), "and any poison will do")
st.effects.poison = nil
st.effects[U.VENOM_EFFECT] = 3
fire("H2HWeapons_VenomStrike", { victim = enemyB })
check(not player.interface.isBurstArmed(), "a strike on someone else starts the count over")
fire("H2HWeapons_VenomStrike", { victim = enemyB })
st.time = st.time + U.BURST_CHAIN + 0.5
check(not player.interface.isBurstArmed(), "once the countdown runs out, the run is over")
fire("H2HWeapons_VenomStrike", { victim = enemyB })
check(not player.interface.isBurstArmed(), "and the next strike starts a new one")
st.time = st.time + 2.5
fire("H2HWeapons_VenomStrike", { victim = enemyB })
st.time = st.time + 2.5
check(player.interface.isBurstArmed(),
      "each strike renews the countdown, so a run can last longer than one countdown")

-- The swing that bursts.
st.globalEvents = {}
playWeapon("slash start")
local staged = lastGlobal("H2HWeapons_StageBurst")
check(staged and staged.item == rose, "winding up the third strike asks for the burst copy")
local copy = stubs.object({ recordId = "Generated:0x99", isItem = true })
st.weaponRecords["generated:0x99"] = { type = 0, model = "meshes/ebony_rose.nif", enchant = "h2h_ebonyrose_burst_en" }
fire("H2HWeapons_BurstStaged", { original = rose, copy = copy })
check(st.equipped == copy, "the copy goes in the hand for the swing")
onUpdate(0.016)
check(st.equipped == copy, "and stays there through the swing")
playWeapon("slash large follow start")
check(st.equipped == rose, "the follow-through puts the original back")
local done = lastGlobal("H2HWeapons_BurstDone")
check(done and done.copy == copy and done.original == rose, "and hands the copy back to be folded in")
fire("H2HWeapons_VenomStrike", { burst = true })
check(not player.interface.isBurstArmed(), "a burst that went off starts the count over")

-- A copy that comes after the swing is over is sent straight back.
for _ = 1, 2 do
    st.time = st.time + 1
    fire("H2HWeapons_VenomStrike", { victim = enemyA })
end
playWeapon("chop start")
playWeapon("chop small follow start")
st.globalEvents = {}
fire("H2HWeapons_BurstStaged", { original = rose, copy = copy })
check(st.equipped == rose, "a copy that arrives after the swing is not put in the hand")
check(lastGlobal("H2HWeapons_BurstDone") ~= nil, "but returned")

-- Sheathing mid-swing puts the original back.
playWeapon("thrust start")
fire("H2HWeapons_BurstStaged", { original = rose, copy = copy })
check(st.equipped == copy, "copy in hand")
st.stance = 0
onUpdate(0.016)
check(st.equipped == rose, "sheathing mid-swing puts the original back")
st.stance = 1
onUpdate(0.016)

-- Unarmed, a swing asks for nothing.
st.time = st.time + 10
st.globalEvents = {}
playWeapon("slash start")
playWeapon("slash large follow start")
check(lastGlobal("H2HWeapons_StageBurst") == nil, "an unarmed swing is an ordinary swing")

-- Mage Fury.
local furyItem = stubs.object({ recordId = "knuckle_mage_fury", isItem = true })
st.equipped = furyItem
st.stance = 0 -- casting puts the weapon away
onUpdate(0.016)
st.selectedSpell = { id = "fireball" }
st.globalEvents = {}
stubs.I.SkillProgression.skillUsed("destruction", { useType = 0 })
check(lastGlobal("H2HWeapons_ChargeMageFury") and lastGlobal("H2HWeapons_ChargeMageFury").spell == "fireball",
      "a successful cast with Mage Fury equipped asks for its charge")
st.globalEvents = {}
stubs.I.SkillProgression.skillUsed("bluntweapon", { useType = 0 })
check(lastGlobal("H2HWeapons_ChargeMageFury") == nil, "a weapon hit does not")
st.equipped = rose
onUpdate(0.016)
stubs.I.SkillProgression.skillUsed("destruction", { useType = 0 })
check(lastGlobal("H2HWeapons_ChargeMageFury") == nil, "nor a cast with anything else equipped")
st.equipped = furyItem
onUpdate(0.016)

st.activeSpells = {}
fire("H2HWeapons_MageFuryCharged", { spell = "generated:0x7", name = "Fireball" })
check(player.interface.mageFuryStrikes() == 3, "charged for three strikes")
check(#st.activeSpells == 1 and st.activeSpells[1].id == U.MAGE_FURY_CHARGE_SPELLS[3],
      "shown in the active effects with three strikes left")
check(st.activeSpells[1] and st.activeSpells[1].options.name == "Mage Fury: Fireball", "under the spell's name",
      st.activeSpells[1] and st.activeSpells[1].options.name)
check(player.interface.isCharged(), "the crystal is charged")
st.stance = 1
st.vfxById = {}
for _ = 1, 3 do onUpdate(0.016) end
check(st.vfxById["H2HWeapons_Charge_R"] ~= nil, "and glows once the knuckles are drawn")

local victim = stubs.object({ name = "victim" })
-- The engine charges every strike at the enchantment's price, or refuses when there is too little;
-- the wind-up sees the charge before, the report after.
local function furyStrike(before, after)
    furyItem.data = { enchantmentCharge = before }
    playWeapon("slash start")
    furyItem.data = { enchantmentCharge = after }
    st.events, st.globalEvents, st.messages = {}, {}, {}
    fire("H2HWeapons_MageFuryStrike", { victim = victim, item = furyItem })
    local use = lastGlobal("H2HWeapons_ChargeUse")
    local carried = lastEvent("H2HWeapons_MageFuryDischarge")
    playWeapon("slash large follow start")
    return use and use.delta, carried
end
local refund, discharge = furyStrike(200, 190)
check(discharge and discharge.target == victim and discharge.data.spell == "generated:0x7",
      "a strike hands the victim the stored share")
check(refund == nil, "and keeps what the engine charged for it")
check(player.interface.mageFuryStrikes() == 2, "and spends a charge")
check(#st.activeSpells == 1 and st.activeSpells[1].id == U.MAGE_FURY_CHARGE_SPELLS[2],
      "the display counts down, one entry at a time", #st.activeSpells)
refund, discharge = furyStrike(190, 184)
check(discharge ~= nil and refund == nil, "whatever the engine charged - less, with a better Enchant skill")
st.godMode = true
refund, discharge = furyStrike(5, 5)
check(discharge ~= nil and refund == nil, "in god mode the engine charges nothing, and the spell still goes")
st.godMode = false
fire("H2HWeapons_MageFuryCharged", { spell = "generated:0x7", name = "Fireball" })
furyStrike(200, 190)
furyStrike(190, 184)
refund, discharge = furyStrike(5, 5)
check(discharge == nil and refund == nil, "a strike the engine refused, too little left, carries nothing")
check(#st.messages == 0, "and it is the engine that says so, not this")
check(player.interface.mageFuryStrikes() == 1, "the spell stays channelled")
furyStrike(184, 174)
check(player.interface.mageFuryStrikes() == 0, "three strikes spend it")
check(#st.activeSpells == 0, "and the display goes")
onUpdate(0.016)
check(st.vfxById["H2HWeapons_Charge_R"] == nil, "and so does the glow")
refund, discharge = furyStrike(174, 164)
check(discharge == nil, "an uncharged strike carries nothing")
check(refund == 10, "and costs nothing: what the engine took goes back", refund)
refund = furyStrike(0, 0)
check(refund == nil, "empty, the engine took nothing, so nothing goes back")

fire("H2HWeapons_MageFuryCharged", { spell = "generated:0x7", name = "Fireball" })
st.time = st.time + U.MAGE_FURY_FADE + 1
onUpdate(0.016)
check(player.interface.mageFuryStrikes() == 0, "an unused charge fades")

-- Casts made by Spell Framework Plus (Oblivion-Style Spell Casting) are reported by name.
st.spellRecords["fireball"] = st.spellRecords["fireball"] or { id = "fireball", name = "Fireball", effects = {} }
st.spellRecords["frostbite"] = { id = "frostbite", name = "Frostbite", effects = {} }
local function charges()
    local out = {}
    for _, e in ipairs(st.globalEvents) do
        if e.name == "H2HWeapons_ChargeMageFury" then out[#out + 1] = e.data.spell end
    end
    return out
end
st.equipped = furyItem
onUpdate(0.016)
st.time = st.time + 5
st.globalEvents = {}
fire("MagExp_CastResult", { spellId = "frostbite", success = true })
check(charges()[1] == "frostbite", "a cast Spell Framework Plus reports charges Mage Fury with that spell")
st.globalEvents = {}
st.selectedSpell = { id = "fireball" }
stubs.I.SkillProgression.skillUsed("destruction", { useType = 0 })
check(#charges() == 0, "and a skill use reported for the same cast is not taken for another")

st.time = st.time + 5
st.globalEvents = {}
fire("H2HWeapons_MageFuryCharged", { spell = "generated:0x7", name = "Fireball" })
stubs.I.SkillProgression.skillUsed("destruction", { useType = 0 })
check(charges()[1] == "fireball", "a skill use alone charges from the selected spell")
fire("MagExp_CastResult", { spellId = "frostbite", success = true })
local order = charges()
check(order[2] == "frostbite", "but the report that follows it names the spell that was actually cast", order[2])
check(player.interface.mageFuryStrikes() == 0, "and the charge taken from the selected spell is undone first")

st.time = st.time + 5
st.globalEvents = {}
fire("MagExp_CastResult", { spellId = "frostbite", success = false })
fire("MagExp_CastResult", { spellId = "some enchantment", success = true })
check(#charges() == 0, "a failed cast, or an enchanted item's, charges nothing")

-- Saved mid-swing with the copy in hand: the load puts the original back.
local saved = { burstSwap = { original = rose, copy = copy } }
st.equipped = copy
player.engineHandlers.onLoad(saved)
st.globalEvents = {}
onUpdate(0.016)
check(st.equipped == rose, "a load mid-burst puts the original back")
check(lastGlobal("H2HWeapons_BurstDone") ~= nil, "and returns the copy")

--- the global side --------------------------------------------------------------------------------------
local global = require("scripts.MaxYari.H2HWeapons.global")
local playerObject = stubs.object({ name = "player" })

st.spellRecords["fireball"] = { id = "fireball", name = "Fireball", effects = {
    { id = "firedamage", range = 2, area = 10, duration = 5, magnitudeMin = 30, magnitudeMax = 60,
      effect = { harmful = true, hasMagnitude = true, hasDuration = true } },
    { id = "restorehealth", range = 0, area = 0, duration = 5, magnitudeMin = 10, magnitudeMax = 10,
      effect = { harmful = false, hasMagnitude = true, hasDuration = true } },
    { id = "paralyze", range = 2, area = 0, duration = 7, magnitudeMin = 0, magnitudeMax = 0,
      effect = { harmful = true, hasMagnitude = false, hasDuration = true } },
    { id = "drainhealth", range = 0, area = 0, duration = 5, magnitudeMin = 10, magnitudeMax = 10,
      effect = { harmful = true, hasMagnitude = true, hasDuration = true } },
} }
st.spellRecords["heal"] = { id = "heal", name = "Heal", effects = {
    { id = "restorehealth", range = 0, area = 0, duration = 1, magnitudeMin = 10, magnitudeMax = 10,
      effect = { harmful = false, hasMagnitude = true, hasDuration = true } },
} }

st.events = {}
global.eventHandlers.H2HWeapons_ChargeMageFury({ actor = playerObject, spell = "fireball" })
local charged = lastEvent("H2HWeapons_MageFuryCharged")
check(charged and charged.target == playerObject, "the global answers the wielder")
local share = charged and st.spellRecords[string.lower(charged.data.spell)]
check(share ~= nil, "with a spell record of its own")
check(share and #share.effects == 2, "holding only the harmful effects that reach past the caster",
      share and #share.effects)
local fire1, para = share and share.effects[1], share and share.effects[2]
check(fire1 and fire1.magnitudeMin == 10 and fire1.magnitudeMax == 20, "at a third of the magnitude",
      fire1 and (fire1.magnitudeMin .. "-" .. fire1.magnitudeMax))
check(fire1 and fire1.duration == 5, "for the whole duration")
check(fire1 and fire1.range == 1 and fire1.area == 0, "delivered by touch, with no area")
check(para and para.duration == 2, "an effect with no magnitude gets a third of its duration", para and para.duration)
check(charged and charged.data.name == "Fireball", "named for the spell it came from")

local made = st.created
global.eventHandlers.H2HWeapons_ChargeMageFury({ actor = playerObject, spell = "Fireball" })
check(st.created == made, "a spell cast again reuses its share")
st.events = {}
global.eventHandlers.H2HWeapons_ChargeMageFury({ actor = playerObject, spell = "heal" })
check(lastEvent("H2HWeapons_MageFuryCharged") == nil, "a spell with nothing to hand on does not charge")

local original = stubs.object({ recordId = "katar_ebony_rose", isItem = true,
                                data = { condition = 500, enchantmentCharge = 321 } })
st.events = {}
st.enchantRecords["h2h_magefury_en"] = { id = "h2h_magefury_en", charge = 100 }
local knuckles = stubs.object({ recordId = "knuckle_mage_fury", isItem = true, data = { enchantmentCharge = 50 } })
global.eventHandlers.H2HWeapons_ChargeUse({ item = knuckles, delta = -4 })
check(knuckles.data.enchantmentCharge == 46, "charge is spent", knuckles.data.enchantmentCharge)
global.eventHandlers.H2HWeapons_ChargeUse({ item = knuckles, delta = 80 })
check(knuckles.data.enchantmentCharge == 100, "and given back, never past what the enchantment holds")
global.eventHandlers.H2HWeapons_ChargeUse({ item = knuckles, delta = -500 })
check(knuckles.data.enchantmentCharge == 0, "or below nothing")

global.eventHandlers.H2HWeapons_StageBurst({ actor = playerObject, item = original })
local stagedEvent = lastEvent("H2HWeapons_BurstStaged")
local burstCopy = stagedEvent and stagedEvent.data.copy
check(burstCopy ~= nil, "staging a burst makes a copy")
check(burstCopy and st.weaponRecords[string.lower(burstCopy.recordId)].enchant == U.BURST_ENCHANT,
      "that carries the burst")
check(burstCopy and st.weaponRecords[string.lower(burstCopy.recordId)].model == "meshes/ebony_rose.nif",
      "and is otherwise the same weapon")
check(burstCopy and burstCopy.data.condition == 500 and burstCopy.data.enchantmentCharge == 321,
      "with the original's wear and charge")
check(burstCopy and burstCopy.movedInto and burstCopy.movedInto.owner == playerObject, "into the wielder's inventory")

made = st.created
global.eventHandlers.H2HWeapons_StageBurst({ actor = playerObject, item = original })
check(st.created == made + 1, "a second burst makes a new item but not a new record", st.created - made)

burstCopy.data.condition, burstCopy.data.enchantmentCharge = 480, 296
global.eventHandlers.H2HWeapons_BurstDone({ original = original, copy = burstCopy })
check(original.data.condition == 480 and original.data.enchantmentCharge == 296,
      "the swing's wear and charge are folded back into the original")
check(burstCopy.removed == true, "and the copy is gone")

local savedGlobal = global.engineHandlers.onSave()
check(savedGlobal and next(savedGlobal.furySpells) and next(savedGlobal.burstWeapons),
      "what was made is remembered in the save")

print(string.format("\n%d checks, %d failures", checks, fails))
os.exit(fails == 0 and 0 or 1)

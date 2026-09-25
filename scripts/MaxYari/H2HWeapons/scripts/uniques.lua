-- The two unique weapons' magic: record ids and numbers, in one place.
--
-- Read by the load-time script that makes the records (content.lua) as well as by everything that
-- acts on them at run time, so an id cannot say one thing in one file and another in the next.
-- Plain data only: content.lua runs before most of the openmw packages exist.
--
-- The weapon records and the stand-in enchantments they point at come from Katar.omwaddon
-- (Sources/Tools/make_plugin.py) - keep the ids there in step with these.
local M = {}

--- Ebony Rose -------------------------------------------------------------------------------------
-- Every strike leaves a short poison. Every strike on an enemy also starts a countdown, and one that
-- lands on them before it runs out renews it; the third in such a run, if that enemy is poisoned - by
-- the venom or by any other poison - bursts: it sets the venom off on everyone around them.
--
-- The venom is a magic effect of this mod's own - that is what lets it be purple and say what it
-- is - so the engine carries it (duration, stacking, the cloud on the victim, the burst, the crime)
-- but deals no damage for it: damage is keyed to the built-in effect ids. actor.lua ticks that part.
M.EBONY_ROSE = "katar_ebony_rose"
M.VENOM_EFFECT = "h2h_venom"
M.VENOM_ENCHANT = "h2h_ebonyrose_en"
-- The burst rides on a second enchantment. An item cannot change its enchantment, so for the one
-- swing that bursts the player holds a copy of the katar carrying this one instead (global.lua).
M.BURST_ENCHANT = "h2h_ebonyrose_burst_en"
-- A line in the Rose's own enchantment that only says what the burst does, so the tooltip does:
-- an effect that does nothing, cast with nothing to see or hear (content.lua).
M.BURST_NOTE_EFFECT = "h2h_venom_burst_note"
M.NO_VFX_STATIC = "h2h_vfx_none"
M.SILENT_SOUND = "h2h_silence"
-- Its sounds (content.lua): where a strike lands, and where a burst goes off. Vanilla Poison names
-- none, so the engine plays its school's - "destruction hit" and "destruction area" - and these are
-- those, over again: each a copy of that vanilla record, volume and reach and all, playing a file of
-- this mod's own, made from the vanilla one (Fx\magic\destH.wav, destA.wav): venom_hit_proper.wav
-- and venom_burst_proper.wav. Named on the effect, they are played exactly where and how the
-- school's would be.
M.VENOM_HIT_SOUND = "h2h_venom_hit"
M.VENOM_AREA_SOUND = "h2h_venom_burst"
M.VENOM_SOUNDS = {
    [M.VENOM_HIT_SOUND] = { file = "sound/katars/venom_hit_proper.wav", from = "destruction hit" },
    [M.VENOM_AREA_SOUND] = { file = "sound/katars/venom_burst_proper.wav", from = "destruction area" },
}
-- Lands the killing blow when the venom would kill, so the engine credits the kill (actor.lua).
M.FINISHER_SPELL = "h2h_venom_finisher"
-- The victim is left this much health and handed a Damage Health of this magnitude, which takes a
-- quarter of a point off within a frame or two at any frame rate. If something heals them first,
-- the most it can ever take is its magnitude for its one second.
M.FINISHER_HEALTH = 0.25
M.FINISHER_MAGNITUDE = 30

M.VENOM = { magnitude = 3, duration = 3 }
M.BURST = { magnitude = 20, duration = 1, area = 10 }  -- area in feet, like any spell

-- Charge. Both uniques hold enough for STRIKES_PER_CHARGE strikes that cost anything - the Rose's
-- every strike, Mage Fury's channelled ones - before the Enchant skill takes its share off (each point
-- above 10 takes 1% off the cost, getEffectiveEnchantmentCastCost). A burst costs more, so the Rose
-- manages fewer in practice. Ten strikes, as every vanilla weapon enchanted to cast on strike holds,
-- at a charge between the Fang of Haynekhtnamet's (110) and Mehrunes' Razor's (210). For scale: a
-- soul gem restores up to its creature's soul - a scamp 100, an ash ghoul 250, a golden saint 400 -
-- and the item gains 0.05 a second by itself.
M.STRIKES_PER_CHARGE = 10
M.VENOM_COST = 16
M.BURST_COST = 40

M.BURST_STRIKES = 3  -- the strike that bursts is the this-many-th in a run on one poisoned enemy ...
M.BURST_CHAIN = 3    -- ... each within this many seconds of the one before

-- explodeSpell measures an area in ceil(Constants::UnitsPerFoot) = 22 units a foot, from the point
-- the blow landed (spellcasting.cpp).
M.UNITS_PER_FOOT = 22

--- Mage Fury -----------------------------------------------------------------------------------------
-- A spell cast successfully with these on charges them; the next three strikes each deliver a third
-- of that spell's harmful effects to whoever they hit.
M.MAGE_FURY = "knuckle_mage_fury"
M.MAGE_FURY_ENCHANT = "h2h_magefury_en"
-- What the enchantment is: a constant effect that does nothing itself but name and explain the
-- weapon's trick in the tooltip and the active effects list.
M.MAGE_FURY_EFFECT = "h2h_magefury"
-- Shown on the player while the knuckles are charged, its magnitude the strikes left.
M.MAGE_FURY_CHARGE_EFFECT = "h2h_magefury_charge"
M.MAGE_FURY_CHARGE_SPELLS = { "h2h_magefury_charge_1", "h2h_magefury_charge_2", "h2h_magefury_charge_3" }

M.MAGE_FURY_STRIKES = 3
M.MAGE_FURY_SHARE = 1 / 3
-- What a strike that carries the spell costs; one that does not costs nothing.
M.MAGE_FURY_COST = 16
-- A charge fades this long after the cast, or after the strike that last drew on it.
M.MAGE_FURY_FADE = 30

--- Bound Fist ---------------------------------------------------------------------------------------
-- A conjuration spell that binds a daedric hand-to-hand weapon to the caster - which one depends on
-- their Conjuration when it lands, and with bound item scaling on, how hard it hits does too.
--
-- The engine's bound effects are hard-wired, one item per effect id (spelleffects.cpp,
-- getBoundItemsMap), so this is an effect of the mod's own and actor.lua does the binding: hand the
-- weapon over, take it back when the effect ends, give back what was in the hand before.
M.BOUND_FIST_SPELL = "h2h_bound_fist"
M.BOUND_FIST_EFFECT = "h2h_boundfist"
M.BOUND_FIST = { duration = 60, cost = 6 }  -- a vanilla bound weapon spell's

-- By the caster's Conjuration: the first tier whose `below` it is under. `weapon` is the record in
-- Katar.omwaddon (make_plugin.py BOUND_WEAPONS); a scaled copy of it has a generated id, and is known
-- for a katar or knuckledusters by its mesh (weapons.lua). `baseWeight` is the daedric original's,
-- which bound item scaling starts from (as Unofficial TR Spells does with its BOUND_BASE_WEIGHTS).
M.BOUND_FIST_TIERS = {
    { below = 40, weapon = "h2h_bound_knuckle", baseWeight = 4.5 },
    { below = 65, weapon = "h2h_bound_knuckle_spiked", baseWeight = 4.5 },
    { weapon = "h2h_bound_katar", baseWeight = 8.1 },
}

-- Who sells it: scripts/MaxYari/H2HWeapons/traders/list.lua.

-- Scaling follows Unofficial TR Spells' own bound item settings, so a bound fist scales exactly as
-- its bound weapons do. Without it, its defaults - and scaling on, since there is no switch to follow.
M.TR_SPELLS_SCRIPTS = "Unofficial TR Spells.omwscripts"
M.TR_BOUND_SECTION = "SettingsUnofficialTRSpellsBound Item Behaviour"
M.TR_BOUND_ENABLED = "BOUND_SCALING_ENABLED"
M.BOUND_SCALING_DEFAULTS = {
    BOUND_DAMAGE_BASE = 50,                -- percent of the weapon's damage at Conjuration 0
    BOUND_DAMAGE_BONUS_PER_LEVEL = 0.7,    -- percent more per point
    BOUND_WEIGHT_BASE = 40,                -- percent of the original's weight at Conjuration 0
    BOUND_WEIGHT_REDUCTION_PER_LEVEL = 0.5, -- percent less per point
    BOUND_ENCHANT_BASE = 50,               -- percent of its enchantment's magnitude at Conjuration 0
    BOUND_ENCHANT_BONUS_PER_LEVEL = 0.7,   -- percent more per point
}
M.BOUND_SCALING_STEP = 5  -- Conjuration is taken in steps of this, so a record is not made per point

return M

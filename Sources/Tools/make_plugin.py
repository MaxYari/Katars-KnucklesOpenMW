#!/usr/bin/env python3
"""Writes Katar.omwaddon: the WEAP records for every katar and knuckleduster and their shop-enchanted
versions (see ENCHANTED_VERSIONS), stand-ins for the two uniques' enchantments (see ENCHANTMENTS),
Bound Fist's spell and weapons, the notes (see NOTES), and the vanilla levelled lists extended with
the weapons (see LEVELLED_STAND_INS and ENCHANTED_LEVELLED - this needs --master, to read them from).
Tamriel Data's lists are make_tr_plugin.py's.

Damage is derived, not hand-picked: each weapon takes the vanilla shortsword of its own material and
scales it - katars to 80%, knuckledusters to 50% (DAMAGE_FACTOR), rounded to the nearest - which is
the rule the mod documents. Weight takes the same share of the shortsword's. Silver and daedric take
their damage from steel and ebony instead (SILVER_OVER_STEEL, DAEDRIC_OVER_EBONY). Change SHORTSWORDS or the factors and re-run; nothing else needs touching.

    python3 Sources/Tools/make_plugin.py -o Katar.omwaddon --master "<Data Files>/Morrowind.esm" \
        --master "<Data Files>/Tribunal.esm" --master "<Data Files>/Bloodmoon.esm"
"""
import argparse
import os
import struct

# Officially these are ordinary weapons - the engine has no hand-to-hand weapon type - so katars are
# short blades and knuckledusters are blunt. The scripts put the hand-to-hand skill back in charge.
SHORT_BLADE, BLUNT_ONE_HAND = 0, 3
# ESM::Weapon::Magical, "ignores normal weapon resistance" - which is what every vanilla silver weapon
# carries (esmtool: silver dagger, 0x1), and every bound one.
MAGICAL_FLAG = 0x1
# ESM::Weapon::Silver (0x2) makes a weapon hurt werewolves the more (combat.cpp, applyWerewolfDamageMult:
# fWereWolfSilverWeaponDamageMult). Morrowind.esm never sets it; Bloodmoon does, on every silver weapon -
# its nordic silver ones and the vanilla silver ones it carries over, both with Magical (3) - and so do
# these.
WEREWOLF_SILVER_FLAG = 0x2
SILVER_FLAG = MAGICAL_FLAG | WEREWOLF_SILVER_FLAG

# Vanilla shortswords, per material: (chop, slash, thrust, weight, value, health, enchant points).
# base_anim's daggers are too weak a baseline - a katar is a fist-mounted short blade, not a knife -
# and orcish has no vanilla shortsword, so it is interpolated between dwarven and ebony. Adamantium's
# is Tribunal's, and glass, which has none, is derived from ebony's below.
SHORTSWORDS = {
    "iron":    ((4, 9),   (4, 9),   (7, 11), 8,  20,    600,  40),
    "chitin":  ((3, 7),   (3, 7),   (4, 9),  4,  13,    540,  20),
    "steel":   ((5, 12),  (5, 12),  (7, 12), 8,  40,    750,  40),
    "silver":  ((5, 10),  (5, 10),  (7, 10), 6,  80,    570,  36),
    "orcish":  ((8, 16),  (8, 16),  (9, 17), 14, 800,   1600, 60),
    "adamantium": ((7, 15), (7, 15), (7, 20), 20, 1000,  900,  60),
    "nordic":  ((6, 12),  (6, 12),  (9, 15), 15, 1000,  500,  70),   # Bloodmoon's nordic silver
    "ebony":   ((10, 20), (10, 22), (15, 25), 16, 10000, 1200, 80),
    "daedric": ((10, 26), (10, 26), (12, 24), 24, 20000, 1500, 120),
}

# Three of those shortswords sit out of line with their material everywhere else, and their damage is
# derived instead (weight, value, condition and capacity stay their own):
#
# * Silver hits harder than steel at the top and softer at the bottom, as vanilla's silver spear
#   does over its steel one (5-23 against 6-17) - the silver shortsword alone falls short of steel.
#   Steel's damage, the maximum 30% higher and the minimum 1 lower.
# * Daedric outdoes ebony: across the vanilla lines that have both, its best attack tops out about
#   a fifth higher (longsword and war axe 1.19, spear 1.25, mace 1.15) while the minimum stays where
#   ebony's is - but the daedric shortsword's best attack comes out below the ebony one's. Ebony's
#   damage, the maximum 20% higher.
# * Adamantium comes close to ebony: across the weapons both have, Tribunal's and Tamriel Data's, its
#   best attack tops out at 0.95 of ebony's (the median of 19 - longsword and spear 0.94, war axe and
#   halberd 0.95, broadsword and dai-katana 0.96, katana 0.97) and mostly starts where ebony's does -
#   but Tribunal's shortsword hits 7-20, its minimum half the ebony one's. Ebony's damage, the
#   maximum 5% lower.
SILVER_OVER_STEEL = {"min_add": -1, "max_mult": 1.3}
DAEDRIC_OVER_EBONY = {"min_add": 0, "max_mult": 1.2}
ADAMANTIUM_UNDER_EBONY = {"min_add": 0, "max_mult": 0.95}


def stronger(attacks, min_add, max_mult):
    """Each attack's range, the minimum moved by min_add and the maximum scaled by max_mult - left
    unrounded, so the one rounding is the weapon's own (scale)."""
    return tuple((low + min_add, high * max_mult) for low, high in attacks)


SHORTSWORDS["silver"] = stronger(SHORTSWORDS["steel"][:3], **SILVER_OVER_STEEL) + SHORTSWORDS["silver"][3:]
SHORTSWORDS["daedric"] = stronger(SHORTSWORDS["ebony"][:3], **DAEDRIC_OVER_EBONY) + SHORTSWORDS["daedric"][3:]
SHORTSWORDS["adamantium"] = stronger(SHORTSWORDS["ebony"][:3], **ADAMANTIUM_UNDER_EBONY) \
    + SHORTSWORDS["adamantium"][3:]

# Glass has no shortsword in vanilla, so its is ebony's, scaled by what vanilla's glass longsword is to
# its ebony one - the one-handed blade both materials have: 0.3 of the weight, condition and capacity,
# 0.8 of the value, and the best attack's maximum 0.88 of ebony's, the minimum the same (4-30 against
# 4-34). The war axe has the weight, value and capacity in the same ratios and the maximum within a
# point (0.89). Tamriel Data's own glass shortsword comes out at the same weight and value (4.8, 8000).
GLASS_FROM_EBONY = {"min_add": 0, "max_mult": 0.88}
GLASS_SHARE_OF_EBONY = (0.3, 0.8, 0.3, 0.3)  # weight, value, health, enchant points
SHORTSWORDS["glass"] = stronger(SHORTSWORDS["ebony"][:3], **GLASS_FROM_EBONY) + tuple(
    stat * share for stat, share in zip(SHORTSWORDS["ebony"][3:], GLASS_SHARE_OF_EBONY))

DAMAGE_FACTOR = {"katar": 0.80, "knuckle": 0.50}
# Weight goes with damage: the same share of the shortsword - a katar 80% of its weight, a
# knuckleduster half. It is also what a swing costs: MWMechanics::applyFatigueLoss charges
# fFatigueAttackBase (2.0) + weight * attackStrength * fWeaponFatigueMult (0.25).
#
# Enchantment capacity is a measure of how much weapon there is to enchant, which is not the same
# question: it runs from the dagger of the same material to its shortsword, which holds about twice as
# much. A knuckleduster holds what the dagger does, a katar halfway between the two - the share of the
# way from one to the other.
ENCHANT_TOWARD_SHORTSWORD = {"katar": 0.5, "knuckle": 0.0}

# Vanilla daggers' capacity (the raw record field), per material.
DAGGERS_ENCHANT = {"chitin": 10, "iron": 20, "steel": 20, "silver": 16, "glass": 12, "daedric": 60,
                   "nordic": 70}
# Tribunal has no adamantium dagger, and its adamantium weapons do not keep the weight rule below - the
# shortsword holds 3.0 points a unit, not 5.0 - so that rule would put the dagger at 50, nearly the
# shortsword's 60. It is put where every vanilla dagger sits instead, at half its shortsword. Tamriel
# Data's adamantium dagger (45) would give the katar the same 5 points.
DAGGERS_ENCHANT["adamantium"] = 30

# There is no vanilla dagger in orcish or ebony, so their dagger (for capacity) is derived from the
# shortsword instead. Bethesda weighed every dagger at 0.375 of its shortsword - iron, steel, chitin and
# daedric exactly, silver at 0.400 - so one number covers the whole line.
DAGGER_WEIGHT_FACTOR = 0.375

# Enchantment capacity (the raw record field; the game shows a tenth of it). The engine has no
# formula for this - it reads the number off the record - but Bethesda wrote one weapon line at a
# time, and within a line the capacity is a fixed multiple of the weight, with the material
# carrying the weight: daggers run at 6.67 points per unit, shortswords 5.0, tantos 5.5,
# wakizashis 4.5, right across iron through daedric.
#
# The enchanting menu drops whatever is left over past a whole point (getMaxEnchantValue), so a
# fraction is never usable: the result is rounded to whole points, halves up - silver's 2.6-point
# katar holds 3.
DAGGER_ENCHANT_PER_WEIGHT = 6.67
# Weapon speed scales the attack animation's playback (character.cpp). These play the fist's own
# animations, which are quick already - at 1.0 about as quick as a sword's at 2.0 - so the speeds sit
# far below a vanilla blade's: knuckledusters at the fist's pace, katars a little under it.
SPEED = {"katar": 0.90, "knuckle": 1.00}
REACH = {"katar": 1.00, "knuckle": 0.80}
WEAPON_TYPE = {"katar": SHORT_BLADE, "knuckle": BLUNT_ONE_HAND}

# id, kind, material, display name, mesh, extra value multiplier, flags. Each weapon's inventory icon
# is named after its mesh (icon_for), so neither is ever out of step with the other.
ITEMS = [
    ("katar_steel",            "katar",   "steel",   "Steel Katar",             "steel_katar.nif",           1.0, 0),
    ("katar_silver",           "katar",   "silver",  "Silver Katar",            "silver_katar.nif",          1.0, SILVER_FLAG),
    ("katar_adamantium",       "katar",   "adamantium", "Adamantium Katar",      "adamantium_katar.nif",      1.0, 0),
    ("katar_glass",            "katar",   "glass",   "Glass Katar",             "glass_katar.nif",           1.0, 0),
    ("katar_ebony",            "katar",   "ebony",   "Ebony Katar",             "ebony_guarded_katar.nif",   1.0, 0),
    ("katar_ebony_rose",       "katar",   "ebony",   "Ebony Rose",              "ebony_rose.nif",            0.9, 0),
    ("katar_ebony_botched",    "katar",   "ebony",   "Botched Ebony Katar",     "ebony_guarded_katar.nif",   1.0, 0),
    ("katar_daedric",          "katar",   "daedric", "Daedric Katar",           "daedric_katar.nif",         1.0, 0),
    ("knuckle_iron",           "knuckle", "iron",    "Iron Knuckles",           "iron_knuckle.nif",          1.0, 0),
    ("knuckle_chitin",         "knuckle", "chitin",  "Chitin Knuckles",         "chitin_knuckle.nif",        1.0, 0),
    ("knuckle_silver",         "knuckle", "silver",  "Silver Knuckles",         "silver_knuckle.nif",        1.0, SILVER_FLAG),
    ("knuckle_nordic_silver",  "knuckle", "nordic",  "Nordic Silver Knuckles",  "nord_silver_knuckle.nif",   1.0, SILVER_FLAG),
    ("knuckle_orcish",         "knuckle", "orcish",  "Orcish Knuckles",         "orcish_knuckle.nif",        1.0, 0),
    ("knuckle_daedric",        "knuckle", "daedric", "Daedric Knuckles",        "daedric_knuckle_basic.nif", 1.0, 0),
    ("knuckle_daedric_spiked", "knuckle", "daedric", "Daedric Spiked Knuckles", "daedric_knuckle_sharp.nif", 1.2, 0),
    ("knuckle_wood",           "knuckle", "iron",    "Driftwood Beater",        "wooden_knuckle.nif",        1.0, 0),
    ("knuckle_mage_fury",      "knuckle", "iron",    "Mage Fury",               "mage_fury.nif",             1.0, 0),
]

# The slim ebony katar trades reach and bulk for speed.
# Per-item departures from the derivation above.
#   bulk             scales weight and capacity together - a weapon that is simply less of itself
#   damage_mult      scales the three damage figures only
#   damage           sets the one damage range outright, as (min, max)
#   enchant_material takes the capacity from a different material's dagger and shortsword
# anything else (speed, reach, weight, value) is set outright.
OVERRIDES = {
    # Three quarters of the guarded ebony katar, and quicker for it - by the same eighth a tanto has
    # over a shortsword.
    "katar_ebony_rose": {"speed": SPEED["katar"] * 9 / 8, "reach": 0.9, "bulk": 0.75},
    # Wood hits for two points less than the iron set's 4-6 at each end (2-4) and wears out twice as
    # fast, but takes an enchantment better than any knuckleduster short of orcish, Nordic silver and
    # daedric - it is
    # the medium, not the metal, that holds one: 3 in game (the raw field is ten times what it shows).
    "knuckle_wood": {"damage": (2, 4), "health": 150, "enchant": 30, "weight": 0.9, "value": 5},
    # Mage Fury is an iron knuckle in every other stat - weight, capacity, the lot - but the crystal set
    # in it costs it a point at each end of the iron set's 4-6. What it is worth carrying for is its
    # enchantment, and that is what it is priced on: 650, set by hand.
    "knuckle_mage_fury": {"damage": (3, 5), "value": 650},
    # A joke, placed by hand: an Ebony Katar a beginner tried to enchant. The botch costs it two points
    # at each end of the Ebony Katar's 12-20, and most of its price.
    "katar_ebony_botched": {"damage": (10, 18), "value": 500},
}

# Enchantments. The uniques' are vanilla stand-ins: the real ones use custom magic effects, which an
# ESM file cannot name (an effect there is a vanilla index), so scripts/MaxYari/H2HWeapons/content.lua
# replaces those records at load with the real thing. The stand-ins keep the plugin whole on its own
# and give the Construction Set something to show. Keep the ids in step with
# scripts/MaxYari/H2HWeapons/scripts/uniques.lua.
ENCH_CAST_ONCE, ENCH_WHEN_STRIKES, ENCH_WHEN_USED, ENCH_CONSTANT = 0, 1, 2, 3
RANGE_SELF, RANGE_TOUCH = 0, 1
EFFECT_FIRE_DAMAGE, EFFECT_FROST_DAMAGE, EFFECT_DAMAGE_FATIGUE, EFFECT_POISON = 14, 16, 25, 27
EFFECT_SPELL_ABSORPTION = 67
EFFECT_FORTIFY_SKILL, EFFECT_BOUND_DAGGER = 83, 120
SKILL_HAND_TO_HAND = 26
SPELL_TYPE_SPELL = 0

ENCHANTMENTS = {
    # id: (type, cost, charge, [(effect, range, area, duration, min, max[, skill]), ...])
    "h2h_ebonyrose_en": (ENCH_WHEN_STRIKES, 16, 160, [(EFFECT_POISON, RANGE_TOUCH, 0, 3, 3, 3)]),
    "h2h_magefury_en": (ENCH_WHEN_STRIKES, 16, 160, [(EFFECT_SPELL_ABSORPTION, RANGE_TOUCH, 0, 1, 5, 5)]),
    # Every vanilla bound weapon carries a constant +10 to its own skill ("bound dagger_effect_en" is
    # Fortify Short Blade 10), and the left Bound Gauntlet +10 Hand-to-hand - which is what these are
    # swung with. The real thing, not a stand-in. With bound item scaling on, global.lua scales it
    # the way Unofficial TR Spells scales a bound item's enchantment.
    "h2h_bound_fist_effect_en": (ENCH_CONSTANT, 0, 0,
                                 [(EFFECT_FORTIFY_SKILL, RANGE_SELF, 0, 1, 10, 10, SKILL_HAND_TO_HAND)]),
    # Two of the shop-enchanted versions (ENCHANTED_VERSIONS) carry one vanilla has no record for:
    # chitin knuckles hold a single point, the least any enchantment costs, and silver knuckles two.
    # Cost and charge as vanilla's weak ones have them - a point a strike, ten strikes to a charge.
    "h2h_chitin_shard_en": (ENCH_WHEN_STRIKES, 1, 10, [(EFFECT_FROST_DAMAGE, RANGE_TOUCH, 0, 1, 1, 3)]),
    "h2h_silver_shard_en": (ENCH_WHEN_STRIKES, 1, 10, [(EFFECT_FROST_DAMAGE, RANGE_TOUCH, 0, 1, 3, 6)]),
    # The glass katar's: vanilla's Wild blades' fire from 1 up, as much of it as fits a quarter of a point
    # under the katar's 2 (Fire 1-12 comes to 1.75). Cost and charge rounded from that, as vanilla's are.
    "h2h_glass_flame_en": (ENCH_WHEN_STRIKES, 2, 20, [(EFFECT_FIRE_DAMAGE, RANGE_TOUCH, 0, 1, 1, 12)]),
    # The Botched Ebony Katar's: a beginner's attempt that came out as next to nothing - 1-2 points of
    # fatigue on a strike - and, being an enchantment, leaves the katar unable to take a real one. The
    # real thing, not a stand-in, at the weak ones' cost and charge.
    "h2h_botched_en": (ENCH_WHEN_STRIKES, 1, 10, [(EFFECT_DAMAGE_FATIGUE, RANGE_TOUCH, 0, 1, 1, 2)]),
}

# Which weapon carries which.
WEAPON_ENCHANTMENTS = {
    "katar_ebony_rose": "h2h_ebonyrose_en",
    "knuckle_mage_fury": "h2h_magefury_en",
    "katar_ebony_botched": "h2h_botched_en",
    "h2h_bound_knuckle": "h2h_bound_fist_effect_en",
    "h2h_bound_knuckle_spiked": "h2h_bound_fist_effect_en",
    "h2h_bound_katar": "h2h_bound_fist_effect_en",
}


# Bound Fist, a conjuration spell of this mod's own. Like the enchantments it ships a vanilla stand-in
# - Bound Dagger - that content.lua replaces with the real effect. Keep in step with uniques.lua.
SPELLS = {
    # id: (name, type, cost, [(effect, range, area, duration, min, max), ...])
    "h2h_bound_fist": ("Bound Fist", SPELL_TYPE_SPELL, 6, [(EFFECT_BOUND_DAGGER, RANGE_SELF, 0, 60, 1, 1)]),
}

# What Bound Fist hands out, by the caster's Conjuration (uniques.lua BOUND_FIST_TIERS picks the
# tier). Each is the daedric weapon it is named for, weighing and costing nothing, ignoring normal
# weapon resistance and fortifying its wielder's skill, as every vanilla bound weapon does.
BOUND_WEAPONS = [
    # id, the weapon it copies, display name
    ("h2h_bound_knuckle",        "knuckle_daedric",        "Bound Knuckles"),
    ("h2h_bound_knuckle_spiked", "knuckle_daedric_spiked", "Bound Spiked Knuckles"),
    ("h2h_bound_katar",          "katar_daedric",          "Bound Katar"),
]

# Shop-enchanted versions: eight of the plain weapons as a merchant or a chest might have them, with a
# weak enchantment that casts on strike. Each enchantment is the weaker of two: the vanilla enchanted
# weapon of that material and element (Iron Sparkmace, Steel Flameblade, Silver Shardblade, and the
# glass Wild blades for orcish and ebony), and the most that fits three quarters of a point under the
# weapon's own capacity - so one bought is always a little weaker than one enchanted by hand. Where
# the vanilla one is the weaker, its own record is used: it is the same enchantment, and a mod that
# rebalances it rebalances these too. No daedric, as vanilla has no weak daedric ones, and none in
# adamantium either - vanilla's only enchanted one is the Dark Brotherhood's Jinkblade. Nordic silver gets
# what Bloodmoon gives it, as berserker gear rather than shop stock: the Berserker weapons' own bleed,
# whole, on the same knuckles at the same price, in the berserkers' list where theirs are and nowhere
# else. Glass is the one exception to the three
# quarters: the glass katar holds only 2, which would leave it next to nothing, so it takes the most that
# fits a quarter of a point under instead - still short of what the enchanting menu would let you put on.
#
# The price is the plain weapon's plus what vanilla adds for that enchantment, over the same weapon
# without it: Chitin Club 6 to Firebite Club 10, Iron Mace 24 to Iron Sparkmace 45, Steel Shortsword
# 40 to Steel Flameblade 55, Silver Shortsword 80 to Silver Shardblade 120, Glass Dagger 4000 to the
# Wild blades' 4100. Where ours is weaker than that vanilla one, only that markup comes down, in
# proportion to the enchantment points (ours over theirs) - the plain weapon's own worth stays whole.
ENCHANTED_VERSIONS = [
    # id, the plain weapon it is, display name, enchantment, price over the plain one
    ("knuckle_chitin_shard",    "knuckle_chitin", "Chitin Shardfang",    "h2h_chitin_shard_en", 4),   # 4 x 1.0/1.125
    ("knuckle_iron_spark",      "knuckle_iron",   "Iron Sparkfist",      "spark_enu",           21),
    ("katar_steel_smoulder",    "katar_steel",    "Smouldering Katar",   "cruel flame_en",      15),
    ("katar_silver_ice",        "katar_silver",   "Silver Ice Talon",    "dire shard_en",       40),
    ("knuckle_silver_shard",    "knuckle_silver", "Silver Shardknuckle", "h2h_silver_shard_en", 36),  # 40 x 1.25/1.375
    ("knuckle_orcish_smoulder", "knuckle_orcish", "Orcish Smoulderfist", "wild flame_en",       100),
    ("katar_ebony_spark",       "katar_ebony",    "Ebony Sparkneedle",   "wild spark_en",       100),
    ("katar_glass_flame",       "katar_glass",    "Wild Flamefang",      "h2h_glass_flame_en",  64),  # 100 x 1.75/2.75
    # Bloodmoon's Berserker weapons are their plain nordic silver ones, renamed, with the bleed and nothing
    # added to the price.
    ("knuckle_nordic_silver_ber", "knuckle_nordic_silver", "Berserker Silver Knuckles", "bloodletting_en", 0),
]


# Notes to leave in the world, made as vanilla makes its own (bk_notetoinorra is one): a scroll-type
# BOOK on the folded note mesh, weighing 0.1 and worth 1, its text in the Magic Cards font with a <BR>
# closing every line. An empty line leaves a blank one. Vanilla does not null-terminate the TEXT.
NOTE_MESH, NOTE_ICON = "m\\Text_Note_02.nif", "m\\Tx_note_02.tga"
NOTE_HEADER = '<DIV ALIGN="LEFT"><FONT COLOR="000000" SIZE="3" FACE="Magic Cards"><BR>\r\n'

NOTES = {
    # id: (title, [lines])
    "h2h_note_piece_found": ("About the piece you found", [
        "Apart from the agreed-upon armaments, I'm sending you the broken knuckles I mentioned. They look "
        "quite unique and seem vaguely responsive to magic - see if you can fix them.",
        "",
        "- M",
    ]),
}


def bound_items():
    """BOUND_WEAPONS as ITEMS rows, with their weight, value and capacity overridden to nothing."""
    by_id = {item[0]: item for item in ITEMS}
    rows = []
    for rid, base_id, display in BOUND_WEAPONS:
        base = by_id[base_id]
        rows.append((rid,) + base[1:3] + (display,) + base[4:6] + (MAGICAL_FLAG,))
        OVERRIDES.setdefault(rid, dict(OVERRIDES.get(base_id, {}))).update(
            {"weight": 0, "value": 0, "enchant": 0})
    return rows


def enchanted_items():
    """ENCHANTED_VERSIONS as ITEMS rows: the plain weapon under its own id and name, carrying its
    enchantment, at the plain one's price and the enchantment's on top."""
    by_id = {item[0]: item for item in ITEMS}
    rows = []
    for rid, base_id, display, enchantment, markup in ENCHANTED_VERSIONS:
        base = by_id[base_id]
        rows.append((rid,) + base[1:3] + (display,) + base[4:])
        WEAPON_ENCHANTMENTS[rid] = enchantment
        OVERRIDES.setdefault(rid, dict(OVERRIDES.get(base_id, {})))["value"] = single_stats(base)["value"] + markup
    return rows


def scale(value, factor):
    """Rounded to the nearest, but never away to nothing."""
    return max(1, min(255, int(value * factor + 0.5)))


def best_attack(chop, slash, thrust):
    """A fist hits the same whichever way it swings (getHandToHandDamage has no attack type), and so
    do these: one damage range for chop, slash and thrust alike - the shortsword's best attack, the
    one a player swings anyway. Picked as the engine picks it for "always use best attack"
    (character.cpp, getBestAttack): the highest min + max, and on a tie thrust, then slash."""
    total = {name: attack[0] + attack[1] for name, attack in
             (("chop", chop), ("slash", slash), ("thrust", thrust))}
    if total["slash"] == total["chop"] == total["thrust"]:
        return slash
    if total["thrust"] >= total["chop"] and total["thrust"] >= total["slash"]:
        return thrust
    if total["slash"] >= total["chop"] and total["slash"] >= total["thrust"]:
        return slash
    return chop


# Each of these is a pair, one for each hand, so a cheap one is priced as two: a price under
# PAIR_PRICE_LIMIT doubles. The plain weapon decides, and its enchanted versions follow it - an enchanted
# pair is two enchanted weapons - so an enchanted one never costs less than its plain pair.
PAIR_PRICE_LIMIT = 500


def stats(item):
    out = single_stats(item)
    plain = {row[0]: row[1] for row in ENCHANTED_VERSIONS}.get(item[0])
    plain_value = single_stats({i[0]: i for i in ITEMS}[plain])["value"] if plain else out["value"]
    if plain_value < PAIR_PRICE_LIMIT:
        out["value"] *= 2
    return out


def single_stats(item):
    """One weapon's stats, priced as one."""
    _id, kind, material, _name, _mesh, value_mult, _flags = item
    chop, slash, thrust, weight, value, health, _enchant = SHORTSWORDS[material]
    dmg = DAMAGE_FACTOR[kind]
    overrides = dict(OVERRIDES.get(_id, {}))
    bulk = overrides.pop("bulk", 1.0)
    dmg *= overrides.pop("damage_mult", 1.0)
    enchant_material = overrides.pop("enchant_material", material)

    dagger_enchant = DAGGERS_ENCHANT.get(enchant_material)
    if dagger_enchant is None:
        dagger_enchant = SHORTSWORDS[enchant_material][3] * DAGGER_WEIGHT_FACTOR * DAGGER_ENCHANT_PER_WEIGHT
    shortsword_enchant = SHORTSWORDS[enchant_material][6]
    enchant = dagger_enchant + (shortsword_enchant - dagger_enchant) * ENCHANT_TOWARD_SHORTSWORD[kind]
    damage = overrides.pop("damage", None) or tuple(scale(v, dmg) for v in best_attack(chop, slash, thrust))
    out = {
        "chop": damage,
        "slash": damage,
        "thrust": damage,
        "weight": round(weight * DAMAGE_FACTOR[kind] * bulk, 1),
        "enchant": int(enchant * bulk / 10 + 0.5) * 10,
        "value": int(value * dmg * value_mult),
        "health": int(health * dmg),
        "speed": SPEED[kind],
        "reach": REACH[kind],
        "type": WEAPON_TYPE[kind],
    }
    out.update(overrides)
    return out


def sub(name, payload):
    return name.encode("ascii") + struct.pack("<I", len(payload)) + payload


def zstr(text):
    return text.encode("ascii") + b"\0"


def record(name, payload, flags=0):
    return name.encode("ascii") + struct.pack("<III", len(payload), 0, flags) + payload


def ench_record(rid, spec):
    kind, cost, charge, effects = spec
    body = sub("NAME", zstr(rid)) + sub("ENDT", struct.pack("<iiii", kind, cost, charge, 0))
    for effect, rng, area, duration, low, high, *skill in effects:
        # effect index, skill, attribute (-1: none), range, area, duration, magnitude min/max
        enam = struct.pack("<hbbiiiii", effect, skill[0] if skill else -1, -1, rng, area, duration, low, high)
        assert len(enam) == 24, len(enam)
        body += sub("ENAM", enam)
    return record("ENCH", body)


def spel_record(rid, spec):
    name, kind, cost, effects = spec
    # Flags 0: not autocalculated, not a starting spell.
    body = sub("NAME", zstr(rid)) + sub("FNAM", zstr(name)) + sub("SPDT", struct.pack("<iii", kind, cost, 0))
    for effect, rng, area, duration, low, high in effects:
        body += sub("ENAM", struct.pack("<hbbiiiii", effect, -1, -1, rng, area, duration, low, high))
    return record("SPEL", body)


def book_record(rid, spec):
    title, lines = spec
    text = NOTE_HEADER + "".join(line + "<BR>\r\n" for line in lines)
    # weight, value, is a scroll, the skill it teaches (-1: none), enchantment capacity
    bkdt = struct.pack("<fiiii", 0.1, 1, 1, -1, 100)
    body = sub("NAME", zstr(rid)) + sub("MODL", zstr(NOTE_MESH)) + sub("FNAM", zstr(title)) \
        + sub("BKDT", bkdt) + sub("ITEX", zstr(NOTE_ICON)) + sub("TEXT", text.encode("ascii"))
    return record("BOOK", body)


def icon_for(mesh):
    """The inventory icon: Icons/katars/<the mesh's name>.tga. The mesh is named after the Blender empty
    the weapon was exported from (tools/mw_export.py), so the icon is too."""
    return "katars\\" + os.path.splitext(mesh)[0] + ".tga"


def weap_record(item):
    rid, _kind, _material, display, mesh, _mult, flags = item
    icon = icon_for(mesh)
    s = stats(item)
    wpdt = struct.pack(
        "<fiHHffH6BI",
        s["weight"], s["value"], s["type"], s["health"], s["speed"], s["reach"], s["enchant"],
        s["chop"][0], s["chop"][1], s["slash"][0], s["slash"][1], s["thrust"][0], s["thrust"][1],
        flags,
    )
    assert len(wpdt) == 32, len(wpdt)
    body = sub("NAME", zstr(rid)) + sub("MODL", zstr(mesh)) + sub("FNAM", zstr(display)) \
        + sub("WPDT", wpdt) + sub("ITEX", zstr(icon))
    if rid in WEAPON_ENCHANTMENTS:
        body += sub("ENAM", zstr(WEAPON_ENCHANTMENTS[rid]))
    return record("WEAP", body)


# --- Levelled lists ----------------------------------------------------------------------------------
# Where the weapons turn up: vanilla's own levelled lists, placed the way vanilla places its weapons.
# Each goes into every list the vanilla weapon it stands in for is in, at that weapon's level - its
# material's shortsword (a weapon may stand in for more than one, a tuple). The three uniques - Ebony Rose, Mage Fury and the Driftwood Beater - are in
# none: nobody sells them and no chest rolls them. Chests and crates draw on the
# random_<material>_weapon lists; a merchant's stock and an NPC's own weapon come from the
# l_n_wpn_melee_* lists in their inventories - so that is how traders get them too, and no NPC record
# is touched.
#
# A plugin cannot add to a list, only replace it, so each list is written out whole: vanilla's
# entries, read from the master, then these. A later mod that edits the same list replaces it in
# turn, which is what a merged-lists tool (DeltaPlugin, OMWLLF) is for. Each list is read from the last
# master that has it - Tribunal and Bloodmoon leave these alone, so it is Morrowind.esm's.
LEVELLED_STAND_INS = {
    "katar_steel":            "steel shortsword",
    "katar_silver":           "silver shortsword",
    # Vanilla deals no adamantium weapon from a list - Tribunal places them by hand - so this one only
    # matches Tamriel Data's lists (make_tr_plugin.py); without them it is Bols Indalen's to sell
    # (CONTAINER_ADDITIONS).
    "katar_adamantium":       "adamantium_shortsword",
    # There is no vanilla glass shortsword; the glass dagger is the one glass short blade.
    "katar_glass":            "glass dagger",
    "katar_ebony":            "ebony shortsword",
    "katar_daedric":          "daedric shortsword",
    "knuckle_chitin":         "chitin shortsword",
    "knuckle_iron":           "iron shortsword",
    "knuckle_silver":         "silver shortsword",
    # Bloodmoon deals nordic silver on Solstheim only - its Nord hunters', nordic silver and smugglers' lists.
    "knuckle_nordic_silver":  "bm nordic silver shortsword",
    # There is no vanilla orcish shortsword; its stats sit between dwarven and ebony, and so does this.
    # It also goes where vanilla's own orcish weapons are rolled - random_orcish_weapons, by the
    # warhammer, the only one-handed-or-blunt orcish weapon in it.
    "knuckle_orcish":         ("dwarven shortsword", "orcish warhammer"),
    "knuckle_daedric":        "daedric shortsword",
    "knuckle_daedric_spiked": "daedric shortsword",
}

# Lists a stand-in is in that these do not belong in.
LEVELLED_SKIP = {
    "l_m_wpn_melee_short blade",   # enchanted stock; these are plain
    "l_m_wpn_melee_blunt",
    "random_golden_saint_weapon",  # what golden saints carry
    "random_dwemer_weapon",        # orcish borrows the dwarven shortsword's places, not the Dwemer's
    "imperial guard random weapon",
    "bm_imperial guard random weapon",  # and Bloodmoon's, Fort Frostmoth's guards
}

# Knuckledusters are blunt: where their stand-in is on a short blade list, they go on the blunt one.
BLUNT_LIST_FOR = {"l_n_wpn_melee_short blade": "l_n_wpn_melee_blunt"}

# Where the shop-enchanted versions go: the lists vanilla deals its own weak enchanted weapons from -
# the enchanted short blade and blunt lists (merchants, and the NPCs and chests that roll them) and the
# special loot most chests of note draw on. Katars go where enchanted short blades are, knuckledusters
# where enchanted blunt weapons and staves are, and each only where its material is already on offer
# at least twice, at the middle of those weapons' levels. Ours are kept to 15% of a list's enchanted
# weapons at most. Long blade, axe and spear lists are left alone: an NPC rolling one is after a
# weapon for that skill.
ENCHANTED_LEVELLED = {
    "l_m_wpn_melee_short blade": [("katar_steel_smoulder", 7), ("katar_silver_ice", 9),
                                  ("katar_ebony_spark", 15), ("katar_glass_flame", 16)],
    "l_m_wpn_melee_blunt": [("knuckle_chitin_shard", 2), ("knuckle_iron_spark", 5),
                            ("knuckle_silver_shard", 8), ("knuckle_orcish_smoulder", 12)],
    "random_loot_special": [("knuckle_iron_spark", 1), ("knuckle_silver_shard", 1),
                            ("katar_steel_smoulder", 1), ("katar_silver_ice", 1)],
    # Where every berserker rolls a weapon, and Bloodmoon puts its Berserker ones, at their level.
    "bm_randomweapon_berserker": [("knuckle_nordic_silver_ber", 60)],
}


# Shop stock added by hand, where a merchant already sells the weapon one of these is cut from - as
# many as the chest holds of that weapon, and restocking (a negative count) if it restocks. The chest's
# own record is read from the masters and written out with these added, so it is the vanilla chest with
# them on top; as with the lists, a mod loaded later that edits the same chest wins it (TES3Merge and
# DeltaPlugin merge containers; OMWLLF does not).
CONTAINER_ADDITIONS = {
    # Kjeld, the smuggler in Druscashti, sells from this chest of his (lock 20), Ebony Shortsword and all.
    "dwrv_chest00_kjeld2": [("katar_ebony", 1)],
    # Bols Indalen, the smith in Mournhold's Craftsmen's Hall (Tribunal), restocks every adamantium
    # weapon from this chest of his, the shortsword among them.
    "com_chest_02_v_indalen": [("katar_adamantium", -1)],
}


def read_records(master_paths, tag, ids):
    """{lowercased id: (record flags, raw body)} for the records of one type with these ids, each as the
    last of the masters to have it leaves it."""
    found = {}
    for path in master_paths:
        found.update(_read_records(path, tag, ids))
    return found


def _read_records(master_path, tag, ids):
    wanted = {i.lower() for i in ids}
    with open(master_path, "rb") as fh:
        data = fh.read()
    found, pos = {}, 0
    while pos + 16 <= len(data):
        rtag = data[pos:pos + 4]
        size, _unused, flags = struct.unpack_from("<III", data, pos + 4)
        body = data[pos + 16:pos + 16 + size]
        pos += 16 + size
        if rtag != tag:
            continue
        name_size = struct.unpack_from("<I", body, 4)[0]
        rid = body[8:8 + name_size].rstrip(b"\0").decode("latin-1").lower()
        if rid in wanted:
            found[rid] = (flags, body)
    return found


def container_record(flags, body, extra):
    """A container as the master has it, with these items added to what it holds."""
    for item, count in extra:
        body += sub("NPCO", struct.pack("<i", count) + item.encode("ascii").ljust(32, b"\0"))
    return record("CONT", body, flags)


def add_enchanted(additions, lists, present, table):
    """Merge a list -> [(id, level)] table of enchanted versions into the stand-in additions."""
    for key, extra in table.items():
        if key in lists:
            additions.setdefault(key, []).extend((rid, lvl) for rid, lvl in extra if rid in present)
    return additions


def latin_zstr(text):
    return text.encode("latin-1") + b"\0"


def read_levelled_lists(master_path):
    """{lowercased id: {id, flags, chance, items: [(item id, level)]}} for every LEVI in a master."""
    with open(master_path, "rb") as fh:
        data = fh.read()
    lists, pos = {}, 0
    while pos + 16 <= len(data):
        tag = data[pos:pos + 4]
        size = struct.unpack_from("<I", data, pos + 4)[0]
        body = data[pos + 16:pos + 16 + size]
        pos += 16 + size
        if tag != b"LEVI":
            continue
        rec, spos, pending = {"items": [], "flags": 0, "chance": 0}, 0, None
        while spos + 8 <= len(body):
            name = body[spos:spos + 4]
            ssize = struct.unpack_from("<I", body, spos + 4)[0]
            payload = body[spos + 8:spos + 8 + ssize]
            spos += 8 + ssize
            if name == b"NAME":
                rec["id"] = payload.rstrip(b"\0").decode("latin-1")
            elif name == b"DATA":
                rec["flags"] = struct.unpack("<I", payload)[0]
            elif name == b"NNAM":
                rec["chance"] = payload[0]
            elif name == b"INAM":
                pending = payload.rstrip(b"\0").decode("latin-1")
            elif name == b"INTV":
                rec["items"].append((pending, struct.unpack("<H", payload)[0]))
        lists[rec["id"].lower()] = rec
    return lists


def levelled_additions(lists, present, stand_in_table=None, skip=None, blunt_list_for=None):
    """{list key: [(item id, level)]} - what goes where, for the weapons that are in the plugin. The
    tables default to vanilla's; make_tr_plugin.py passes Tamriel Data's."""
    stand_in_table = LEVELLED_STAND_INS if stand_in_table is None else stand_in_table
    skip = LEVELLED_SKIP if skip is None else skip
    blunt_list_for = BLUNT_LIST_FOR if blunt_list_for is None else blunt_list_for
    kind_of = {item[0]: item[1] for item in ITEMS}
    additions = {}
    for rid, stand_ins in stand_in_table.items():
        if rid not in present:
            continue
        if isinstance(stand_ins, str):
            stand_ins = (stand_ins,)
        for key, rec in sorted(lists.items()):
            if key in skip:
                continue
            level = next((lvl for item, lvl in rec["items"] if item.lower() in stand_ins), None)
            if level is None:
                continue
            target = blunt_list_for.get(key, key) if kind_of[rid] == "knuckle" else key
            if target in lists and rid not in (item for item, _ in additions.get(target, [])):
                additions.setdefault(target, []).append((rid, level))
    return additions


def levi_record(rec, extra):
    items = list(rec["items"]) + extra
    body = sub("NAME", latin_zstr(rec["id"])) + sub("DATA", struct.pack("<I", rec["flags"])) \
        + sub("NNAM", struct.pack("<B", rec["chance"])) + sub("INDX", struct.pack("<I", len(items)))
    for item, level in items:
        body += sub("INAM", latin_zstr(item)) + sub("INTV", struct.pack("<H", level))
    return record("LEVI", body)


def build(master_paths, meshes_dir):
    items, missing = [], []
    for item in ITEMS + bound_items() + enchanted_items():
        if meshes_dir and not os.path.exists(os.path.join(meshes_dir, item[4])):
            missing.append(item)
        else:
            items.append(item)
    for item in missing:
        print("  skipping %-24s meshes/%s is not there yet" % (item[0], item[4]))
    for item in items:
        icon = os.path.join("Icons", icon_for(item[4]).replace("\\", os.sep))
        if not os.path.exists(icon):
            print("  warning: %-24s has no icon yet, %s" % (item[0], icon))
    present = {i[0] for i in items}

    # An enchantment is only written if a weapon that is in the plugin uses it.
    used = {WEAPON_ENCHANTMENTS[i] for i in present if i in WEAPON_ENCHANTMENTS}
    enchantments = [(rid, spec) for rid, spec in ENCHANTMENTS.items() if rid in used]

    # The spell only if the weapons it hands out are in.
    spells = [(rid, spec) for rid, spec in SPELLS.items()
              if all(b[0] in present for b in BOUND_WEAPONS)]

    additions, levelled, containers = {}, {}, []
    if master_paths:
        for path in master_paths:
            levelled.update(read_levelled_lists(path))
        additions = add_enchanted(levelled_additions(levelled, present), levelled, present,
                                  ENCHANTED_LEVELLED)
        chests = read_records(master_paths, b"CONT", CONTAINER_ADDITIONS)
        for key, extra in sorted(CONTAINER_ADDITIONS.items()):
            extra = [(rid, count) for rid, count in extra if rid in present]
            if key in chests and extra:
                containers.append((key, extra, container_record(*chests[key], extra)))
    else:
        print("  no master given - the weapons go into no levelled list")

    records = b"".join(ench_record(rid, spec) for rid, spec in enchantments)
    records += b"".join(spel_record(rid, spec) for rid, spec in spells)
    records += b"".join(weap_record(i) for i in items)
    records += b"".join(book_record(rid, spec) for rid, spec in NOTES.items())
    records += b"".join(levi_record(levelled[key], extra) for key, extra in sorted(additions.items()))
    records += b"".join(rec for _key, _extra, rec in containers)

    author = b"Max Yari".ljust(32, b"\0")
    description = b"Katars and Knuckledusters - hand-to-hand weapons.".ljust(256, b"\0")
    hedr = struct.pack("<fi", 1.3, 0) + author + description \
        + struct.pack("<i", len(items) + len(enchantments) + len(spells) + len(NOTES) + len(additions)
                      + len(containers))
    assert len(hedr) == 300, len(hedr)

    header = sub("HEDR", hedr)
    for path in master_paths:
        header += sub("MAST", zstr(os.path.basename(path)))
        header += sub("DATA", struct.pack("<Q", os.path.getsize(path)))

    return record("TES3", header) + records, items, enchantments, spells, additions, containers


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("-o", "--out", default="Katar.omwaddon")
    ap.add_argument("--master", action="append", default=[],
                    help="a master to read from and record, in load order: Morrowind.esm, then Tribunal.esm")
    ap.add_argument("--meshes", default="meshes",
                    help="where the meshes live; an item whose mesh is missing is left out")
    args = ap.parse_args()
    for path in args.master:
        if not os.path.exists(path):
            ap.error("no such master: %s" % path)

    data, items, enchantments, spells, additions, containers = build(args.master, args.meshes)
    with open(args.out, "wb") as fh:
        fh.write(data)

    # What a full-strength swing costs the attacker, against the 2.0 a bare fist pays.
    fist, weapon_mult = 2.0, 0.25

    print("%-24s %-26s %-8s %-9s %-9s %-9s %5s %6s %6s %6s %13s" % (
        "id", "name", "type", "chop", "slash", "thrust", "wt", "value", "speed", "ench", "swing cost"))
    for item in items:
        s = stats(item)
        cost = fist + s["weight"] * weapon_mult
        print("%-24s %-26s %-8s %-9s %-9s %-9s %5s %6d %6.2f %6.1f %6.2f %+5.0f%%" % (
            item[0], item[3], "blade" if s["type"] == SHORT_BLADE else "blunt",
            "%d-%d" % s["chop"], "%d-%d" % s["slash"], "%d-%d" % s["thrust"],
            s["weight"], s["value"], s["speed"], s["enchant"] / 10.0,
            cost, 100 * (cost - fist) / fist))
    print("\nlevelled lists:")
    for key, extra in sorted(additions.items()):
        print("  %-30s + %s" % (key, ", ".join("%s (%d)" % pair for pair in extra)))
    print("\ncontainers:")
    for key, extra, _rec in containers:
        print("  %-30s + %s" % (key, ", ".join("%s x%d" % pair for pair in extra)))
    print("\nwrote %s (%d bytes, %d weapons, %d enchantments, %d spells, %d notes, %d levelled lists, "
          "%d containers)" % (args.out, len(data), len(items), len(enchantments), len(spells), len(NOTES),
                              len(additions), len(containers)))


if __name__ == "__main__":
    main()

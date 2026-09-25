#!/usr/bin/env python3
"""Writes Katar.omwaddon: the WEAP records for every katar and knuckleduster, stand-ins for the two
uniques' enchantments (see ENCHANTMENTS), Bound Fist's spell and weapons, and the vanilla levelled
lists extended with the weapons (see LEVELLED_STAND_INS - this needs --master, to read them from).

Damage is derived, not hand-picked: each weapon takes the vanilla shortsword of its own material and
scales it - katars to 80%, knuckledusters to 50% (DAMAGE_FACTOR) - which is the rule the mod
documents. Change SHORTSWORDS or the factors and re-run; nothing else needs touching.

    python3 Sources/Tools/make_plugin.py -o Katar.omwaddon --master "<Morrowind>/Data Files/Morrowind.esm"
"""
import argparse
import os
import struct

# Officially these are ordinary weapons - the engine has no hand-to-hand weapon type - so katars are
# short blades and knuckledusters are blunt. The scripts put the hand-to-hand skill back in charge.
SHORT_BLADE, BLUNT_ONE_HAND = 0, 3
# ESM::Weapon::Magical, "ignores normal weapon resistance" - which is what every vanilla silver weapon
# carries (esmtool: silver dagger, 0x1), and every bound one. ESM::Weapon::Silver (0x2) is unused there.
MAGICAL_FLAG = 0x1
SILVER_FLAG = MAGICAL_FLAG

# Vanilla shortswords, per material: (chop, slash, thrust, weight, value, health, enchant points).
# base_anim's daggers are too weak a baseline - a katar is a fist-mounted short blade, not a knife -
# and orcish has no vanilla shortsword, so it is interpolated between dwarven and ebony.
SHORTSWORDS = {
    "iron":    ((4, 9),   (4, 9),   (7, 11), 8,  20,    600,  40),
    "chitin":  ((3, 7),   (3, 7),   (4, 9),  4,  13,    540,  20),
    "steel":   ((5, 12),  (5, 12),  (7, 12), 8,  40,    750,  40),
    "silver":  ((5, 10),  (5, 10),  (7, 10), 6,  80,    570,  36),
    "orcish":  ((8, 16),  (8, 16),  (9, 17), 14, 800,   1600, 60),
    "ebony":   ((10, 20), (10, 22), (15, 25), 16, 10000, 1200, 80),
    "daedric": ((10, 26), (10, 26), (12, 24), 24, 20000, 1500, 120),
}

DAMAGE_FACTOR = {"katar": 0.80, "knuckle": 0.50}
# Weight and enchantment capacity are both measured against the dagger of the same material, not
# the shortsword the damage comes from - but at different shares, for different reasons.
#
# Weight is what a swing costs you: MWMechanics::applyFatigueLoss charges
# fFatigueAttackBase (2.0) + weight * attackStrength * fWeaponFatigueMult (0.25), and bare fists
# pay only the 2.0, having no weapon at all. So weight is tuned against that floor rather than
# against the weapon it is cut from: a knuckleduster is half a dagger and a katar nine tenths,
# which puts a full-strength swing at roughly a fifth and a third over a fist's cost at the
# iron/steel tier.
DAGGER_WEIGHT_SHARE = {"katar": 0.9, "knuckle": 0.5}

# Capacity is a measure of how much weapon there is to enchant, which is not the same question -
# a katar is two thirds of a dagger there, a knuckleduster a third.
DAGGER_ENCHANT_SHARE = {"katar": 2 / 3, "knuckle": 1 / 3}

# There is no vanilla dagger in orcish or ebony, so the dagger is derived from the shortsword
# instead. Bethesda weighed every dagger at 0.375 of its shortsword - iron, steel, chitin and
# daedric exactly, silver at 0.400 - so one number covers the whole line.
DAGGER_WEIGHT_FACTOR = 0.375

# Enchantment capacity (the raw record field; the game shows a tenth of it). The engine has no
# formula for this - it reads the number off the record - but Bethesda wrote one weapon line at a
# time, and within a line the capacity is a fixed multiple of the weight, with the material
# carrying the weight: daggers run at 6.67 points per unit, shortswords 5.0, tantos 5.5,
# wakizashis 4.5, right across iron through daedric.
#
DAGGER_ENCHANT_PER_WEIGHT = 6.67
# Weapon speed scales the attack animation's playback (character.cpp). These play the fist's own
# animations, which are quick already - at 1.0 about as quick as a sword's at 2.0 - so the speeds sit
# far below a vanilla blade's: knuckledusters at the fist's pace, katars a little under it.
SPEED = {"katar": 0.90, "knuckle": 1.00}
REACH = {"katar": 1.00, "knuckle": 0.80}
WEAPON_TYPE = {"katar": SHORT_BLADE, "knuckle": BLUNT_ONE_HAND}

# id, kind, material, display name, mesh, icon, extra value multiplier, flags
ITEMS = [
    ("katar_steel",            "katar",   "steel",   "Steel Katar",             "steel_katar.nif",           "steel_katar.tga",   1.0, 0),
    ("katar_silver",           "katar",   "silver",  "Silver Katar",            "silver_katar.nif",          "steel_katar.tga",   1.0, SILVER_FLAG),
    ("katar_ebony",            "katar",   "ebony",   "Ebony Katar",             "ebony_guarded_katar.nif",   "steel_katar.tga",   1.0, 0),
    ("katar_ebony_rose",       "katar",   "ebony",   "Ebony Rose",              "ebony_rose.nif",            "steel_katar.tga",   0.9, 0),
    ("katar_daedric",          "katar",   "daedric", "Daedric Katar",           "daedric_katar.nif",         "steel_katar.tga",   1.0, 0),
    ("knuckle_iron",           "knuckle", "iron",    "Iron Knuckles",           "iron_knuckle.nif",          "iron_knuckle.tga",  1.0, 0),
    ("knuckle_chitin",         "knuckle", "chitin",  "Chitin Knuckles",         "chitin_knuckle.nif",        "chitin_knuckle.tga", 1.0, 0),
    ("knuckle_silver",         "knuckle", "silver",  "Silver Knuckles",         "silver_knuckle.nif",        "silver_knuckle.tga", 1.0, SILVER_FLAG),
    ("knuckle_orcish",         "knuckle", "orcish",  "Orcish Knuckles",         "orcish_knuckle.nif",        "iron_knuckle.tga",  1.0, 0),
    ("knuckle_daedric",        "knuckle", "daedric", "Daedric Knuckles",        "daedric_knuckle_basic.nif", "iron_knuckle.tga",  1.0, 0),
    ("knuckle_daedric_spiked", "knuckle", "daedric", "Daedric Spiked Knuckles", "daedric_knuckle_sharp.nif", "iron_knuckle.tga",  1.2, 0),
    ("knuckle_wood",           "knuckle", "iron",    "Wooden Knuckles",         "wooden_knuckle.nif",        "iron_knuckle.tga",  1.0, 0),
    ("knuckle_mage_fury",      "knuckle", "iron",    "Mage Fury",               "mage_fury.nif",             "iron_knuckle.tga",  1.0, 0),
]

# The slim ebony katar trades reach and bulk for speed.
# Per-item departures from the derivation above.
#   bulk             scales weight and capacity together - a weapon that is simply less of itself
#   damage_mult      scales the three damage figures only
#   enchant_material takes the capacity from a different material's dagger
# anything else (speed, reach, weight, value) is set outright.
OVERRIDES = {
    # Three quarters of the guarded ebony katar, and quicker for it - by the same eighth a tanto has
    # over a shortsword.
    "katar_ebony_rose": {"speed": SPEED["katar"] * 9 / 8, "reach": 0.9, "bulk": 0.75},
    # Wood hits for half of what the iron set does, but takes an enchantment as well as silver -
    # it is the medium, not the metal, that holds one.
    # Weight is set outright rather than through bulk, which would drag the capacity down with it.
    "knuckle_wood": {"damage_mult": 0.5, "enchant_material": "silver", "weight": 0.9, "value": 5},
    # Mage Fury is an iron knuckle in every stat - damage, weight, capacity, the lot. What it is worth
    # carrying for is its enchantment, so the numbers stay ordinary and no override is needed.
}

# Enchantments. The uniques' are vanilla stand-ins: the real ones use custom magic effects, which an
# ESM file cannot name (an effect there is a vanilla index), so scripts/MaxYari/H2HWeapons/content.lua
# replaces those records at load with the real thing. The stand-ins keep the plugin whole on its own
# and give the Construction Set something to show. Keep the ids in step with
# scripts/MaxYari/H2HWeapons/scripts/uniques.lua.
ENCH_CAST_ONCE, ENCH_WHEN_STRIKES, ENCH_WHEN_USED, ENCH_CONSTANT = 0, 1, 2, 3
RANGE_SELF, RANGE_TOUCH = 0, 1
EFFECT_POISON, EFFECT_SPELL_ABSORPTION, EFFECT_FORTIFY_SKILL, EFFECT_BOUND_DAGGER = 27, 67, 83, 120
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
}

# Which weapon carries which.
WEAPON_ENCHANTMENTS = {
    "katar_ebony_rose": "h2h_ebonyrose_en",
    "knuckle_mage_fury": "h2h_magefury_en",
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


def bound_items():
    """BOUND_WEAPONS as ITEMS rows, with their weight, value and capacity overridden to nothing."""
    by_id = {item[0]: item for item in ITEMS}
    rows = []
    for rid, base_id, display in BOUND_WEAPONS:
        base = by_id[base_id]
        rows.append((rid,) + base[1:3] + (display,) + base[4:7] + (MAGICAL_FLAG,))
        OVERRIDES.setdefault(rid, dict(OVERRIDES.get(base_id, {}))).update(
            {"weight": 0, "value": 0, "enchant": 0})
    return rows


def scale(value, factor):
    """Damage never rounds away to nothing."""
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


def stats(item):
    _id, kind, material, _name, _mesh, _icon, value_mult, _flags = item
    chop, slash, thrust, weight, value, health, _enchant = SHORTSWORDS[material]
    dmg = DAMAGE_FACTOR[kind]
    overrides = dict(OVERRIDES.get(_id, {}))
    bulk = overrides.pop("bulk", 1.0)
    dmg *= overrides.pop("damage_mult", 1.0)
    enchant_material = overrides.pop("enchant_material", material)

    dagger_weight = weight * DAGGER_WEIGHT_FACTOR
    enchant_weight = SHORTSWORDS[enchant_material][3] * DAGGER_WEIGHT_FACTOR
    damage = tuple(scale(v, dmg) for v in best_attack(chop, slash, thrust))
    out = {
        "chop": damage,
        "slash": damage,
        "thrust": damage,
        "weight": round(dagger_weight * DAGGER_WEIGHT_SHARE[kind] * bulk, 1),
        "enchant": int(round(enchant_weight * DAGGER_ENCHANT_PER_WEIGHT
                             * DAGGER_ENCHANT_SHARE[kind] * bulk)),
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


def weap_record(item):
    rid, _kind, _material, display, mesh, icon, _mult, flags = item
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
# material's shortsword. The three uniques - Ebony Rose, Mage Fury and the wooden knuckles - are in
# none: nobody sells them and no chest rolls them. Chests and crates draw on the
# random_<material>_weapon lists; a merchant's stock and an NPC's own weapon come from the
# l_n_wpn_melee_* lists in their inventories - so that is how traders get them too, and no NPC record
# is touched.
#
# A plugin cannot add to a list, only replace it, so each list is written out whole: vanilla's
# entries, read from the master, then these. A later mod that edits the same list replaces it in
# turn, which is what a merged-lists tool (DeltaPlugin, OMWLLF) is for. Tribunal and Bloodmoon leave
# these lists alone, so Morrowind.esm's are the ones to extend.
LEVELLED_STAND_INS = {
    "katar_steel":            "steel shortsword",
    "katar_silver":           "silver shortsword",
    "katar_ebony":            "ebony shortsword",
    "katar_daedric":          "daedric shortsword",
    "knuckle_chitin":         "chitin shortsword",
    "knuckle_iron":           "iron shortsword",
    "knuckle_silver":         "silver shortsword",
    # There is no vanilla orcish shortsword; its stats sit between dwarven and ebony, and so does this.
    "knuckle_orcish":         "dwarven shortsword",
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
}

# Knuckledusters are blunt: where their stand-in is on a short blade list, they go on the blunt one.
BLUNT_LIST_FOR = {"l_n_wpn_melee_short blade": "l_n_wpn_melee_blunt"}


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


def levelled_additions(lists, present):
    """{list key: [(item id, level)]} - what goes where, for the weapons that are in the plugin."""
    kind_of = {item[0]: item[1] for item in ITEMS}
    additions = {}
    for rid, stand_in in LEVELLED_STAND_INS.items():
        if rid not in present:
            continue
        for key, rec in sorted(lists.items()):
            if key in LEVELLED_SKIP:
                continue
            level = next((lvl for item, lvl in rec["items"] if item.lower() == stand_in), None)
            if level is None:
                continue
            target = BLUNT_LIST_FOR.get(key, key) if kind_of[rid] == "knuckle" else key
            if target in lists:
                additions.setdefault(target, []).append((rid, level))
    return additions


def levi_record(rec, extra):
    items = list(rec["items"]) + extra
    body = sub("NAME", latin_zstr(rec["id"])) + sub("DATA", struct.pack("<I", rec["flags"])) \
        + sub("NNAM", struct.pack("<B", rec["chance"])) + sub("INDX", struct.pack("<I", len(items)))
    for item, level in items:
        body += sub("INAM", latin_zstr(item)) + sub("INTV", struct.pack("<H", level))
    return record("LEVI", body)


def build(master_path, meshes_dir):
    items, missing = [], []
    for item in ITEMS + bound_items():
        if meshes_dir and not os.path.exists(os.path.join(meshes_dir, item[4])):
            missing.append(item)
        else:
            items.append(item)
    for item in missing:
        print("  skipping %-24s meshes/%s is not there yet" % (item[0], item[4]))
    present = {i[0] for i in items}

    # An enchantment is only written if a weapon that is in the plugin uses it.
    used = {WEAPON_ENCHANTMENTS[i] for i in present if i in WEAPON_ENCHANTMENTS}
    enchantments = [(rid, spec) for rid, spec in ENCHANTMENTS.items() if rid in used]

    # The spell only if the weapons it hands out are in.
    spells = [(rid, spec) for rid, spec in SPELLS.items()
              if all(b[0] in present for b in BOUND_WEAPONS)]

    additions, levelled = {}, {}
    if master_path and os.path.exists(master_path):
        levelled = read_levelled_lists(master_path)
        additions = levelled_additions(levelled, present)
    else:
        print("  no master given - the weapons go into no levelled list")

    records = b"".join(ench_record(rid, spec) for rid, spec in enchantments)
    records += b"".join(spel_record(rid, spec) for rid, spec in spells)
    records += b"".join(weap_record(i) for i in items)
    records += b"".join(levi_record(levelled[key], extra) for key, extra in sorted(additions.items()))

    author = b"Max Yari".ljust(32, b"\0")
    description = b"Katars and Knuckledusters - hand-to-hand weapons.".ljust(256, b"\0")
    hedr = struct.pack("<fi", 1.3, 0) + author + description \
        + struct.pack("<i", len(items) + len(enchantments) + len(spells) + len(additions))
    assert len(hedr) == 300, len(hedr)

    header = sub("HEDR", hedr)
    if master_path and os.path.exists(master_path):
        header += sub("MAST", zstr(os.path.basename(master_path)))
        header += sub("DATA", struct.pack("<Q", os.path.getsize(master_path)))

    return record("TES3", header) + records, items, enchantments, spells, additions


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("-o", "--out", default="Katar.omwaddon")
    ap.add_argument("--master", default="", help="path to Morrowind.esm, to record it as a master")
    ap.add_argument("--meshes", default="meshes",
                    help="where the meshes live; an item whose mesh is missing is left out")
    args = ap.parse_args()

    data, items, enchantments, spells, additions = build(args.master, args.meshes)
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
    print("\nwrote %s (%d bytes, %d weapons, %d enchantments, %d spells, %d levelled lists)"
          % (args.out, len(data), len(items), len(enchantments), len(spells), len(additions)))


if __name__ == "__main__":
    main()

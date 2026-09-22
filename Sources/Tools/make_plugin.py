#!/usr/bin/env python3
"""Writes Katar.omwaddon: the WEAP records for every katar and knuckleduster.

Damage is derived, not hand-picked: each weapon takes the vanilla shortsword of its own material and
scales it - katars to 90%, knuckledusters to 60% - which is the rule the mod documents. Change
SHORTSWORDS or the factors and re-run; nothing else needs touching.

    python3 Sources/Tools/make_plugin.py -o Katar.omwaddon
"""
import argparse
import os
import struct

# Officially these are ordinary weapons - the engine has no hand-to-hand weapon type - so katars are
# short blades and knuckledusters are blunt. The scripts put the hand-to-hand skill back in charge.
SHORT_BLADE, BLUNT_ONE_HAND = 0, 3
SILVER_FLAG = 0x1  # ESM::Weapon::Silver: counts as a silver weapon against werewolves

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
# A katar is a blade strapped to a bar; knuckles are a bar. Both are lighter than the sword they
# are cut from, and knuckles are quick.
WEIGHT_FACTOR = {"katar": 0.75, "knuckle": 0.40}
SPEED = {"katar": 2.00, "knuckle": 2.50}
REACH = {"katar": 1.00, "knuckle": 0.80}
WEAPON_TYPE = {"katar": SHORT_BLADE, "knuckle": BLUNT_ONE_HAND}

# id, kind, material, display name, mesh, icon, extra value multiplier, flags
ITEMS = [
    ("katar_steel",            "katar",   "steel",   "Steel Katar",             "steel_katar.nif",           "steel_katar.tga",   1.0, 0),
    ("katar_silver",           "katar",   "silver",  "Silver Katar",            "silver_katar.nif",          "steel_katar.tga",   1.0, SILVER_FLAG),
    ("katar_ebony",            "katar",   "ebony",   "Ebony Katar",             "ebony_katar.nif",           "steel_katar.tga",   1.0, 0),
    ("katar_ebony_slim",       "katar",   "ebony",   "Ebony Slim Katar",        "ebony_slim_katar.nif",      "steel_katar.tga",   0.9, 0),
    ("katar_daedric",          "katar",   "daedric", "Daedric Katar",           "daedric_katar.nif",         "steel_katar.tga",   1.0, 0),
    ("knuckle_iron",           "knuckle", "iron",    "Iron Knuckles",           "iron_knuckle.nif",          "iron_knuckle.tga",  1.0, 0),
    ("knuckle_chitin",         "knuckle", "chitin",  "Chitin Knuckles",         "chitin_knuckle.nif",        "chitin_knuckle.tga", 1.0, 0),
    ("knuckle_silver",         "knuckle", "silver",  "Silver Knuckles",         "silver_knuckle.nif",        "silver_knuckle.tga", 1.0, SILVER_FLAG),
    ("knuckle_orcish",         "knuckle", "orcish",  "Orcish Knuckles",         "orcish_knuckle.nif",        "iron_knuckle.tga",  1.0, 0),
    ("knuckle_daedric",        "knuckle", "daedric", "Daedric Knuckles",        "daedric_knuckle.nif",       "iron_knuckle.tga",  1.0, 0),
    ("knuckle_daedric_spiked", "knuckle", "daedric", "Daedric Spiked Knuckles", "daedric_knuckle_sharp.nif", "iron_knuckle.tga",  1.2, 0),
]

# The slim ebony katar trades reach and bulk for speed.
OVERRIDES = {"katar_ebony_slim": {"speed": 2.25, "weight": 9.0, "reach": 0.9}}


def scale(value, factor):
    """Damage never rounds away to nothing."""
    return max(1, min(255, int(value * factor + 0.5)))


def stats(item):
    _id, kind, material, _name, _mesh, _icon, value_mult, _flags = item
    chop, slash, thrust, weight, value, health, enchant = SHORTSWORDS[material]
    dmg = DAMAGE_FACTOR[kind]
    out = {
        "chop": tuple(scale(v, dmg) for v in chop),
        "slash": tuple(scale(v, dmg) for v in slash),
        "thrust": tuple(scale(v, dmg) for v in thrust),
        "weight": round(weight * WEIGHT_FACTOR[kind], 1),
        "value": int(value * dmg * value_mult),
        "health": int(health * dmg),
        "enchant": int(enchant * dmg),
        "speed": SPEED[kind],
        "reach": REACH[kind],
        "type": WEAPON_TYPE[kind],
    }
    out.update(OVERRIDES.get(_id, {}))
    return out


def sub(name, payload):
    return name.encode("ascii") + struct.pack("<I", len(payload)) + payload


def zstr(text):
    return text.encode("ascii") + b"\0"


def record(name, payload, flags=0):
    return name.encode("ascii") + struct.pack("<III", len(payload), 0, flags) + payload


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
    return record("WEAP", body)


def build(master_path):
    records = b"".join(weap_record(i) for i in ITEMS)

    author = b"Max Yari".ljust(32, b"\0")
    description = b"Katars and Knuckledusters - hand-to-hand weapons.".ljust(256, b"\0")
    hedr = struct.pack("<fi", 1.3, 0) + author + description + struct.pack("<i", len(ITEMS))
    assert len(hedr) == 300, len(hedr)

    header = sub("HEDR", hedr)
    if master_path and os.path.exists(master_path):
        header += sub("MAST", zstr(os.path.basename(master_path)))
        header += sub("DATA", struct.pack("<Q", os.path.getsize(master_path)))

    return record("TES3", header) + records


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("-o", "--out", default="Katar.omwaddon")
    ap.add_argument("--master", default="", help="path to Morrowind.esm, to record it as a master")
    args = ap.parse_args()

    data = build(args.master)
    with open(args.out, "wb") as fh:
        fh.write(data)

    print("%-24s %-26s %-8s %-9s %-9s %-9s %5s %6s %6s" % (
        "id", "name", "type", "chop", "slash", "thrust", "wt", "value", "speed"))
    for item in ITEMS:
        s = stats(item)
        print("%-24s %-26s %-8s %-9s %-9s %-9s %5s %6d %6.2f" % (
            item[0], item[3], "blade" if s["type"] == SHORT_BLADE else "blunt",
            "%d-%d" % s["chop"], "%d-%d" % s["slash"], "%d-%d" % s["thrust"],
            s["weight"], s["value"], s["speed"]))
    print("\nwrote %s (%d bytes, %d records)" % (args.out, len(data), len(ITEMS)))


if __name__ == "__main__":
    main()

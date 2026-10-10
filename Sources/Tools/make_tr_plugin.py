#!/usr/bin/env python3
"""Writes Katars&Knuckles_TamrielRebuilt.omwaddon: Tamriel Data's Morrowind levelled lists - the ones
Tamriel Rebuilt's merchants, chests and NPCs roll - extended with the weapons, the way
Katars&Knuckles.omwaddon extends vanilla's. Nothing else: the weapons themselves are
Katars&Knuckles.omwaddon's, which is a master of this one.

Plain weapons go where their material's shortsword is (TR_STAND_INS), as in vanilla, and the
shop-enchanted versions into the enchanted lists (TR_ENCHANTED_LEVELLED). Only the t_mw lists - the
Morrowind ones; Tamriel Data's lists for Cyrodiil, Skyrim, Hammerfell and the rest are other
projects' - and no list Tamriel Rebuilt does not use for weapons a katar belongs among (TR_SKIP).

    python3 Sources/Tools/make_tr_plugin.py -o "Katars&Knuckles_TamrielRebuilt.omwaddon" \\
        --master "<Morrowind>/Data Files/Morrowind.esm" --tamriel-data "<path>/Tamriel_Data.esm"
"""
import argparse
import os
import struct

import make_plugin as mp
from make_plugin import record, sub, zstr

PLUGIN = "Katars&Knuckles.omwaddon"

# The Morrowind lists, by prefix: t_mw_ itself, the Dunmer and Imperial ones.
TR_PREFIXES = ("t_mw_", "t_mwde_", "t_mwimp_")

# As LEVELLED_STAND_INS, with Tamriel Data's own orcish shortsword - there is one here - and the
# orcish warhammer, which is how t_mw_lvl_weaponsorcish deals orcish weapons, as vanilla's
# random_orcish_weapons does.
TR_STAND_INS = dict(mp.LEVELLED_STAND_INS)
TR_STAND_INS["knuckle_orcish"] = ("dwarven shortsword", "t_orc_regular_shortsword_01", "orcish warhammer")
# Tamriel Data has a glass shortsword too, and the katar is dealt where it is, not where the dagger is.
TR_STAND_INS["katar_glass"] = "t_de_glass_shortsword_01"

TR_SKIP = {
    "t_mw_random_weaponshlaguard",      # what Hlaalu guards carry
    "t_mw_random_weaponcenturion",      # Dwemer centurions'
    "t_mw_random_weaponsdwemer",        # orcish borrows the dwarven shortsword's places, not the Dwemer's
    "t_mw_random_weaponsshortenclvl1",  # enchanted stock; the plain go elsewhere
    "t_mw_lvl_weaponsblunttwohandcls",  # two-handed: an NPC rolling it is after a two-handed weapon
}

# Knuckledusters are blunt: where their stand-in is on the one-handed short blade list, they go on
# the one-handed blunt one.
TR_BLUNT_LIST_FOR = {"t_mw_lvl_weaponsshortonehand": "t_mw_lvl_weaponsbluntonehand"}

# The enchanted versions, by the same rule as ENCHANTED_LEVELLED: where Tamriel Data deals enchanted
# short blades and blunt weapons, each only where its material is already on offer at least twice,
# at the middle of those weapons' levels, and ours 15% of a list's enchanted weapons at most.
TR_ENCHANTED_LEVELLED = {
    "t_mw_lvl_e_wpnsshortblade": [("katar_steel_smoulder", 7), ("katar_silver_ice", 6),
                                  ("katar_ebony_spark", 18), ("katar_glass_flame", 18)],
    "t_mw_lvl_e_wpnsbluntmain": [("knuckle_chitin_shard", 1), ("knuckle_iron_spark", 3),
                                 ("knuckle_silver_shard", 6), ("knuckle_orcish_smoulder", 14)],
    "t_mw_lvl_weaponsshortonehand": [("katar_steel_smoulder", 3), ("katar_silver_ice", 4),
                                     ("katar_ebony_spark", 20), ("katar_glass_flame", 20)],
    # Tamriel Data's own list of enchanted glass weapons, as the plain glass katar is in its glass one.
    "t_mw_random_weaponsglassenchant": [("katar_glass_flame", 1)],
    "t_mw_random_weaponsshortenclvl1": [("katar_steel_smoulder", 1), ("katar_silver_ice", 1)],
    "t_mw_random_weaponsshortenclvl2": [("katar_steel_smoulder", 1), ("katar_silver_ice", 1),
                                        ("katar_ebony_spark", 1)],
    "t_mw_random_weaponsbluntenclvl1": [("knuckle_chitin_shard", 1), ("knuckle_iron_spark", 1)],
    "t_mw_random_weaponsbluntenclvl2": [("knuckle_orcish_smoulder", 1), ("knuckle_silver_shard", 1)],
}


def master_records(paths):
    """MAST and DATA for each master, in load order."""
    out = b""
    for path in paths:
        out += sub("MAST", zstr(os.path.basename(path))) + sub("DATA", struct.pack("<Q", os.path.getsize(path)))
    return out


def build(morrowind, tamriel_data, katar):
    lists = mp.read_levelled_lists(tamriel_data)
    lists = {key: rec for key, rec in lists.items() if key.startswith(TR_PREFIXES)}
    present = {item[0] for item in mp.ITEMS} | {row[0] for row in mp.ENCHANTED_VERSIONS}

    additions = mp.levelled_additions(lists, present, TR_STAND_INS, TR_SKIP, TR_BLUNT_LIST_FOR)
    mp.add_enchanted(additions, lists, present, TR_ENCHANTED_LEVELLED)
    records = b"".join(mp.levi_record(lists[key], extra) for key, extra in sorted(additions.items()))

    author = b"Max Yari".ljust(32, b"\0")
    description = b"Katars & Knuckles - in Tamriel Rebuilt's levelled lists.".ljust(256, b"\0")
    hedr = struct.pack("<fi", 1.3, 0) + author + description + struct.pack("<i", len(additions))
    header = sub("HEDR", hedr) + master_records([morrowind, tamriel_data, katar])
    return record("TES3", header) + records, additions


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("-o", "--out", default="Katars&Knuckles_TamrielRebuilt.omwaddon")
    ap.add_argument("--master", required=True, help="path to Morrowind.esm")
    ap.add_argument("--tamriel-data", required=True, help="path to Tamriel_Data.esm")
    ap.add_argument("--plugin", default=PLUGIN,
                    help="path to Katars&Knuckles.omwaddon, recorded as a master")
    args = ap.parse_args()

    data, additions = build(args.master, args.tamriel_data, args.plugin)
    with open(args.out, "wb") as fh:
        fh.write(data)
    print("levelled lists:")
    for key, extra in sorted(additions.items()):
        print("  %-34s + %s" % (key, ", ".join("%s (%d)" % pair for pair in extra)))
    print("\nwrote %s (%d bytes, %d levelled lists)" % (args.out, len(data), len(additions)))


if __name__ == "__main__":
    main()

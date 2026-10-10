#!/usr/bin/env python3
"""Writes HybridWeaponDefinitions/<record id>.yaml for every weapon Katars&Knuckles.omwaddon has -
make_plugin.py's ITEMS, ENCHANTED_VERSIONS and BOUND_WEAPONS - saying what makes each one a hybrid: a hand-to-hand
weapon that trains Hand to Hand first and its weapon skill second. The scripts read these
(scripts/MaxYari/H2HWeapons/scripts/definitions.lua); README.md documents the fields for other mods.

Re-run after adding a weapon to make_plugin.py. Files for weapons that are gone are left for you to
delete.

    python3 Sources/Tools/make_hybrid_definitions.py
"""
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import make_plugin  # noqa: E402

OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..", "00 Core", "HybridWeaponDefinitions")

TOOLTIP = ("Hand-to-Hand weapon: effectiveness is determined by the %{primarySkill} skill (%{primary}), "
           "with a minor bonus from %{secondarySkill} (%{bonus}).")

# What each kind is. A katar keeps its own blade's whoosh, sharp and under the fist's; knuckledusters
# whoosh as a fist alone. Fatigue damage is the share of a bare-fisted hit's: a katar hits for 80% of
# the shortsword it is cut from and trades the least for bruising, knuckledusters 50% and the most
# (make_plugin.py DAMAGE_FACTOR).
KINDS = {
    "katar": {
        "secondarySkill": "shortblade",
        "fatigueDamage": 0.5,
        "swingSounds": [
            {"sound": "HandToHand", "volume": 1},
            {"sound": "own", "volume": 0.85, "groups": ["sharpMetal"]},
        ],
    },
    "knuckle": {
        "secondarySkill": "bluntweapon",
        "fatigueDamage": 0.75,
        "swingSounds": [
            {"sound": "HandToHand", "volume": 1},
        ],
    },
}


def weapons():
    """(record id, display name, kind) for every weapon the plugin makes."""
    kind_of = {}
    for item in make_plugin.ITEMS:
        record_id, kind, _material, name = item[:4]
        kind_of[record_id] = kind
        yield record_id, name, kind
    for record_id, plain, name, *_ in make_plugin.ENCHANTED_VERSIONS:
        yield record_id, name, kind_of[plain]
    for record_id, copied, name in make_plugin.BOUND_WEAPONS:
        yield record_id, name, kind_of[copied]


def number(value):
    return f"{value:g}"


def definition(name, kind):
    k = KINDS[kind]
    lines = [
        f"# {name}, from Katars & Knuckles - written by Sources/Tools/make_hybrid_definitions.py.",
        "# What each field does: the mod's README, \"Hybrid weapons for modders\".",
        "primarySkill: handtohand",
        f"secondarySkill: {k['secondarySkill']}",
        "primaryExperience: 0.7",
        "secondaryExperience: 0.3",
        "scaling: minorSecondaryBonus",
        "moveset: handToHand",
        f"fatigueDamage: {number(k['fatigueDamage'])}",
        "silentDraw: true",
        "swingSounds:",
    ]
    for sound in k["swingSounds"]:
        lines.append(f"  - sound: {sound['sound']}")
        lines.append(f"    volume: {number(sound['volume'])}")
        if "groups" in sound:
            lines.append(f"    groups: [{', '.join(sound['groups'])}]")
    lines.append(f'tooltip: "{TOOLTIP}"')
    return "\n".join(lines) + "\n"


def main():
    os.makedirs(OUT, exist_ok=True)
    count = 0
    for record_id, name, kind in weapons():
        with open(os.path.join(OUT, record_id.lower() + ".yaml"), "w", newline="\n") as fh:
            fh.write(definition(name, kind))
        count += 1
    print(f"wrote {count} definitions to {os.path.normpath(OUT)}")


if __name__ == "__main__":
    main()

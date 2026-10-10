#!/usr/bin/env python3
"""Writes "02 FBA Compatibility": the katar's first-person animations for OpenMW Full Body Awareness.

FBA shows the whole body in first person and plays third-person legs on it. Our first-person
animations play on the whole body there - legs, hips and the root the engine moves the player by -
so with FBA the legs hung in the first-person rig's pose. This runs ReAnimation's FBA builder
(Sources/Tools/FBACompat/build_compat.py in ReAnimation's repository) on
"00 Core/Animations/xbase_anim.1st", the way ReAnimation's own FBA Compatibility is built: FBA's
legs and root motion under our upper body, with its default settings.

Our groups are named after the katar, so they are pointed at FBA's hand-to-hand ones: the attacks
and the equip ("katar", "kataralt") at "handtohand", everything else ("runforwardkatar",
"idlekatar"...) at its "hh" group. The footsteps are read from our SoundGenRef keys.

Re-run it after any first-person change (after export_katar_anims.py):

    python3 Sources/Tools/make_fba_compat.py [--reanimation DIR] [--fba DIR]

Needs FBA installed (found from openmw.cfg) and ReAnimation's source folder next to this mod.
"""
import argparse
import os
import subprocess
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
MOD = os.path.normpath(os.path.join(HERE, "..", ".."))
ANIMS = os.path.join(MOD, "00 Core", "Animations", "xbase_anim.1st")
OUT = os.path.join(MOD, "02 FBA Compatibility", "Animations", "xbase_anim.1st")
ALIASES = ["^katar(alt)?$=handtohand", "katar=hh"]


def find_reanimation(given):
    if given:
        return given
    mods = os.path.dirname(MOD)
    for name in sorted(os.listdir(mods)):
        if name.lower().startswith("reanimation") and os.path.isfile(
                os.path.join(mods, name, "Sources", "Tools", "FBACompat", "build_compat.py")):
            return os.path.join(mods, name)
    sys.exit("ReAnimation's source folder not found next to this mod - give it with --reanimation")


def main():
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("--reanimation", help="ReAnimation's folder (has Sources/Tools/FBACompat)")
    ap.add_argument("--fba", help="FBA's folder, if openmw.cfg does not list it")
    args = ap.parse_args()
    builder = os.path.join(find_reanimation(args.reanimation), "Sources", "Tools", "FBACompat", "build_compat.py")
    # Only what the builder writes: a kf dropped from 00 Core must not linger here.
    if os.path.isdir(OUT):
        for name in os.listdir(OUT):
            if name.lower().endswith(".kf"):
                os.remove(os.path.join(OUT, name))
    cmd = [sys.executable, builder, "-y", "--anims", ANIMS, "--out", OUT]
    for alias in ALIASES:
        cmd += ["--alias", alias]
    if args.fba:
        cmd += ["--fba", args.fba]
    sys.exit(subprocess.call(cmd))


if __name__ == "__main__":
    main()

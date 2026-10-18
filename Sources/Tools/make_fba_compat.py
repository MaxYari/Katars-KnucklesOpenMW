#!/usr/bin/env python3
"""Writes "02 FBA Compatibility": the hand-to-hand first-person animations for OpenMW Full Body Awareness.

FBA shows the whole body in first person and plays third-person legs on it. Our first-person
animations play on the whole body there - legs, hips and the root the engine moves the player by -
so with FBA the legs hung in the first-person rig's pose. This runs ReAnimation's FBA builder
(Sources/Tools/FBACompat/build_compat.py in ReAnimation's repository) on
"00 Core/Animations/xbase_anim.1st", the way ReAnimation's own FBA Compatibility is built: FBA's
legs and root motion under our upper body, with its default settings.

Our groups are named after the weapons, so they are pointed at FBA's hand-to-hand ones: the attacks
and the equip ("knuckle", "knucklealt") at "handtohand", everything else ("runforwardknuckle",
"idlekatar"...) at its "hh" group. The footsteps are read from our SoundGenRef keys.

Re-run it after any first-person change (after export_katar_anims.py):

    python3 Sources/Tools/make_fba_compat.py [--reanimation DIR] [--fba DIR] [-o DIR]

Needs FBA installed (found from openmw.cfg) and ReAnimation's source folder next to this mod.
"""
import argparse
import os
import shutil
import subprocess
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
MOD = os.path.normpath(os.path.join(HERE, "..", ".."))
ANIMS = os.path.join(MOD, "00 Core", "Animations", "xbase_anim.1st")
OUT = os.path.join(MOD, "02 FBA Compatibility", "Animations", "xbase_anim.1st")
ALIASES = ["^(knuckle|katar)(alt)?$=handtohand", "knuckle|katar=hh"]


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
    ap.add_argument("-o", "--out", default=OUT,
                    help="the folder to write to (default: 02 FBA Compatibility/Animations/xbase_anim.1st)")
    args = ap.parse_args()
    builder = os.path.join(find_reanimation(args.reanimation), "Sources", "Tools", "FBACompat", "build_compat.py")
    # Built aside and moved in only once the builder has succeeded, so a failed run leaves the patch
    # as it was.
    scratch = tempfile.mkdtemp(prefix="katars_fba_")
    try:
        cmd = [sys.executable, builder, "-y", "--anims", ANIMS, "--out", scratch]
        for alias in ALIASES:
            cmd += ["--alias", alias]
        if args.fba:
            cmd += ["--fba", args.fba]
        code = subprocess.call(cmd)
        built = sorted(n for n in os.listdir(scratch) if n.lower().endswith(".kf"))
        if code or not built:
            sys.exit("the FBA builder %s - %s left as it was"
                     % ("failed" if code else "wrote nothing", args.out))
        # Only what the builder writes: a kf dropped from 00 Core must not linger here.
        os.makedirs(args.out, exist_ok=True)
        for name in os.listdir(args.out):
            if name.lower().endswith(".kf"):
                os.remove(os.path.join(args.out, name))
        for name in built:
            shutil.copyfile(os.path.join(scratch, name), os.path.join(args.out, name))
        print("wrote %d file(s) to %s" % (len(built), args.out))
    finally:
        shutil.rmtree(scratch, ignore_errors=True)


if __name__ == "__main__":
    main()

#!/usr/bin/env python3
"""Adds a "Weapon Bone.L" node to Morrowind's actor skeletons.

OpenMW can only attach something to a bone the skeleton actually has (Animation::addEffect throws
"Can't find bone" otherwise), and it builds its bone map once, from the skeleton .nif - nothing a .kf
adds later shows up there. So the off-hand weapon bone has to exist in base_anim*.nif itself.

The new node is the mirror of the vanilla "Weapon Bone" in the left hand. The mirror is not guessed:
vanilla already ships a mirror pair in the same two hands, "Weapon Bone" under Bip01 R Hand and
"Shield Bone" under Bip01 L Hand, and the transform between them is exactly

    translation -> (x, y, -z)
    rotation    -> diag(1, 1, -1) . R . diag(-1, 1, 1)

in hand-local space, in every skeleton file. Applying that to each file's own Weapon Bone gives the
right answer for 1st person, 3rd person and the beast-race rigs alike, and it reproduces the bone
the Blender source places by hand to within 2e-4.

Usage:
    python3 patch_skeleton.py <input dir or .nif> ... -o <output meshes dir>

Input files are the vanilla meshes/base_anim*.nif, extracted from Morrowind.bsa (or taken from
whichever skeleton replacer you use - patch that one instead and this mod will follow it).
"""
import argparse
import os
import sys

import numpy as np

BONE = "Weapon Bone.L"
SOURCE_BONE = "Weapon Bone"
LEFT_HAND = "Bip01 L Hand"

MIRROR_T = np.array([1.0, 1.0, -1.0])
MIRROR_PRE = np.diag([1.0, 1.0, -1.0])
MIRROR_POST = np.diag([-1.0, 1.0, 1.0])

SKELETONS = [
    "base_anim.nif", "base_anim_female.nif", "base_animkna.nif",
    "base_anim.1st.nif", "base_anim_female.1st.nif", "base_animkna.1st.nif",
]


def find_lib():
    """es3 ships inside Greatness7's Blender add-on; use it wherever it is installed."""
    for root in (
        os.environ.get("IO_SCENE_MW", ""),
        os.path.expanduser("~/.config/blender"),
        os.path.expanduser("~/Library/Application Support/Blender"),
        os.path.expanduser("~/AppData/Roaming/Blender Foundation/Blender"),
    ):
        if not root:
            continue
        if os.path.isdir(os.path.join(root, "es3")):
            return root
        for dirpath, dirnames, _ in os.walk(root):
            if os.path.basename(dirpath) == "lib" and "es3" in dirnames:
                return dirpath
    return None


lib = find_lib()
if lib and lib not in sys.path:
    sys.path.append(lib)
try:
    from es3.nif import NiNode, NiStream
except ImportError:
    sys.exit("Could not find the es3 library. Install Greatness7's io_scene_mw Blender add-on, or "
             "point IO_SCENE_MW at its 'lib' folder.")


def walk(node):
    yield node
    for child in getattr(node, "children", None) or []:
        if child is not None:
            yield from walk(child)


def patch(path, out_path):
    stream = NiStream()
    stream.load(path)
    root = stream.roots[0]

    by_name = {}
    for node in walk(root):
        by_name.setdefault(getattr(node, "name", ""), node)

    source = by_name.get(SOURCE_BONE)
    hand = by_name.get(LEFT_HAND)
    if source is None or hand is None:
        return "skipped (no %s / %s)" % (SOURCE_BONE, LEFT_HAND)

    existing = by_name.get(BONE)
    if existing is not None:
        hand.children = [c for c in hand.children if c is not existing]

    bone = NiNode()
    bone.name = BONE
    bone.flags = source.flags
    bone.scale = source.scale
    bone.translation = np.array(source.translation) * MIRROR_T
    bone.rotation = MIRROR_PRE @ np.array(source.rotation) @ MIRROR_POST
    hand.children = list(hand.children) + [bone]

    os.makedirs(os.path.dirname(out_path) or ".", exist_ok=True)
    stream.save(out_path)
    return "added %s at %s" % (BONE, np.round(bone.translation, 4).tolist())


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("inputs", nargs="+", help="vanilla base_anim*.nif files, or a folder holding them")
    ap.add_argument("-o", "--out", required=True, help="output meshes folder")
    args = ap.parse_args()

    files = []
    for item in args.inputs:
        if os.path.isdir(item):
            files += [os.path.join(item, n) for n in SKELETONS if os.path.exists(os.path.join(item, n))]
        else:
            files.append(item)
    if not files:
        sys.exit("No skeleton files found.")

    for path in files:
        name = os.path.basename(path)
        print("%-28s %s" % (name, patch(path, os.path.join(args.out, name))))


if __name__ == "__main__":
    main()

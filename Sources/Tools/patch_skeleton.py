#!/usr/bin/env python3
"""Adds a "Weapon Bone.L" node to Morrowind's actor skeletons.

OpenMW can only attach something to a bone the skeleton actually has (Animation::addEffect throws
"Can't find bone" otherwise), and it builds its bone map once, from the skeleton .nif - nothing a .kf
adds later shows up there. So the off-hand weapon bone has to exist in base_anim*.nif itself.

The new node carries the vanilla "Weapon Bone" transform verbatim, just under the left hand instead
of the right. No mirror is applied, and that is the point: Bip01 L Hand and Bip01 R Hand are already
anatomical mirrors of each other, so the same offset within the hand's own frame lands mirrored in
the world. Anything cleverer gets it wrong - deriving the transform from Shield Bone, the one mirror
pair vanilla actually ships, puts the blade through the forearm, because a shield is not held the
way a blade is.

The check at the bottom is what settles it: the blade axis has to lead the punch, measured against
the actor's own forearm, exactly as the right-hand one does.

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
RIGHT_HAND = "Bip01 R Hand"

# A katar runs along its own local +X, grip at the origin, tip about 17 units out.
BLADE_AXIS = np.array([1.0, 0.0, 0.0])

# Every file MWRender::getActorSkeleton (apps/openmw/mwrender/actorutil.cpp) can return for a
# biped. Note the first-person male one: it is xbase_anim.1st.nif, the animation-carrying file, not
# base_anim.1st.nif - the engine never loads that one as a skeleton at all. Only the female and
# beast first-person rigs use the "base_" names.
#
#   3rd person   male base_anim.nif   female base_anim_female.nif   beast base_animkna.nif
#   1st person   male xbase_anim.1st.nif  female base_anim_female.1st.nif  beast base_animkna.1st.nif
#
# base_anim.1st.nif is patched too, harmlessly, because other tools and mods do reference it.
# Werewolf skins are left alone: a werewolf cannot hold a weapon.
SKELETONS = [
    "base_anim.nif", "base_anim_female.nif", "base_animkna.nif",
    "xbase_anim.1st.nif", "base_anim_female.1st.nif", "base_animkna.1st.nif",
    "base_anim.1st.nif",
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


def world_matrices(root):
    """Accumulated transform of every node, by name."""
    out = {}

    def descend(node, parent):
        local = np.eye(4)
        local[:3, :3] = np.array(node.rotation) * float(node.scale)
        local[:3, 3] = np.array(node.translation)
        matrix = parent @ local
        out[getattr(node, "name", "")] = matrix
        for child in getattr(node, "children", None) or []:
            if child is not None:
                descend(child, matrix)

    descend(root, np.eye(4))
    return out


def leads_the_punch(world, bone, side):
    """How well a weapon on `bone` points the way that arm punches. 1 is straight down the arm."""
    hand = world["Bip01 %s Hand" % side][:3, 3]
    forearm = world["Bip01 %s Forearm" % side][:3, 3]
    along_arm = hand - forearm
    along_arm = along_arm / np.linalg.norm(along_arm)
    return float(np.dot(world[bone][:3, :3] @ BLADE_AXIS, along_arm))


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
    bone.translation = np.array(source.translation)
    bone.rotation = np.array(source.rotation)
    hand.children = list(hand.children) + [bone]

    # The blade has to lead the punch on the left as it does on the right. A rig whose hands are
    # not mirrors of each other would fail here rather than ship a weapon pointing backwards.
    world = world_matrices(root)
    right = leads_the_punch(world, SOURCE_BONE, "R")
    left = leads_the_punch(world, BONE, "L")
    if left < 0.5:
        return "REFUSED: the blade would point backwards (left %+.3f vs right %+.3f)" % (left, right)

    os.makedirs(os.path.dirname(out_path) or ".", exist_ok=True)
    stream.save(out_path)
    return "added %s at %s, blade %+.3f (right hand %+.3f)" % (
        BONE, np.round(bone.translation, 4).tolist(), left, right)


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

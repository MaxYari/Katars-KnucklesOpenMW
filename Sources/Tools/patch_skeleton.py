#!/usr/bin/env python3
"""Adds a "Weapon Bone.L" node to Morrowind's actor skeletons - by patching them, or (--bones-out) by
the route that does not replace them at all.

OpenMW can only attach something to a bone the skeleton actually has (Animation::addEffect throws
"Can't find bone" otherwise), and it builds its bone map once, from the skeleton .nif - nothing a .kf
adds later shows up there. So the off-hand weapon bone has to exist in base_anim*.nif itself.

The new node carries "Weapon Bone"'s transform conjugated into the left hand's frame - see
mirror_bone.py, which works out how this rig mirrors from the rig's own left/right bone pairs rather
than assuming. For every vanilla skeleton that comes out as a flip of the bone's local Z.

The bone is that plain mirror and nothing more, so a weapon modelled the vanilla way - blade up the
bone's +Y - hangs from it the right way up. Anything a particular weapon needs on top, like the
katar's half turn about its blade, belongs in that weapon's animations (mirror_weapon_track.py),
not here, where it would turn every other weapon too.

Two ways to deliver it:

  -o <meshes dir>          writes patched copies of the skeletons. Works, but every skeleton this
                           touches conflicts with any other mod that ships one.
  --bones-out <Animations> writes, per skeleton, animations/<skeleton name>/h2h_weapon_bone_l.nif:
                           just "Bip01 L Hand" with the bone under it. With "use additional
                           animation sources" on (ReAnimation needs it anyway), OpenMW grafts every
                           node marked with an NiStringExtraData "BONE" from any .nif in that folder
                           onto the skeleton when it loads it, under the node named like its parent
                           (Animation::injectCustomBones, nifloader.cpp:712). Nothing is replaced,
                           so it cannot conflict. The folder is named after the skeleton file the
                           engine actually loads - which is not always the one getActorSkeleton
                           names: correctActorModelPath swaps in the "x" twin whenever an x<name>.kf
                           exists, so third-person male loads xbase_anim.nif and is injected from
                           animations/xbase_anim/, not animations/base_anim/. Give this both the
                           plain and the x skeletons and it writes a folder for each; only the one
                           actually loaded is ever read, so nothing is added twice.

Only one file per folder may carry the bone - every marked copy is grafted, so two would make two.

Usage:
    python3 patch_skeleton.py <input dir or .nif> ... -o <output meshes dir>
    python3 patch_skeleton.py <input dir or .nif> ... --bones-out Animations

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
    # The "x" twins, which are what the engine loads whenever an x<name>.kf exists
    # (Misc::ResourceHelpers::correctActorModelPath) - in vanilla, every one above but the female
    # first-person rig.
    "xbase_anim.nif", "xbase_anim_female.nif", "xbase_animkna.nif", "xbase_animkna.1st.nif",
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
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import mirror_bone  # noqa: E402  (needs the path set up above)

try:
    from es3.nif import NiNode, NiStream, NiStringExtraData
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


def local_matrices(root):
    """Each node's transform relative to its parent, by name."""
    out = {}
    for node in walk(root):
        local = np.eye(4)
        local[:3, :3] = np.array(node.rotation) * float(node.scale)
        local[:3, 3] = np.array(node.translation)
        out[getattr(node, "name", "")] = local
    return out


# The file each skeleton's bone goes in, inside animations/<skeleton name>/. Its name only has to be
# a .nif nobody else ships.
BONE_FILE = "h2h_weapon_bone_l.nif"
# The engine's marker for "graft me onto the skeleton" (NifOsg: NiStringExtraData "BONE").
BONE_MARKER = "BONE"


def write_bone_source(out_dir, skeleton_name, bone):
    """animations/<skeleton name>/h2h_weapon_bone_l.nif, holding the bone under its parent's name."""
    parent = NiNode()
    parent.name = LEFT_HAND

    marker = NiStringExtraData()
    marker.string_data = BONE_MARKER
    bone.extra_data = marker

    parent.children = [bone]
    root = NiNode()
    root.name = BONE_FILE
    root.children = [parent]

    folder = os.path.join(out_dir, os.path.splitext(skeleton_name)[0])
    os.makedirs(folder, exist_ok=True)
    stream = NiStream()
    stream.roots = [root]
    path = os.path.join(folder, BONE_FILE)
    stream.save(path)
    return path


def patch(path, out_path, bones_out=None):
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

    # How this rig mirrors, measured on the rig rather than assumed.
    signs, error, margin = mirror_bone.fit_signs(local_matrices(root))
    if margin < 2.0:
        return "REFUSED: no clear mirror convention (best %s, only %.1fx better than the next)" % (
            signs, margin)

    source_local = np.eye(4)
    source_local[:3, :3] = np.array(source.rotation) * float(source.scale)
    source_local[:3, 3] = np.array(source.translation)
    # Conjugate into the left hand's frame. No half turn: that is the katar's, and its animations
    # carry it - see mirror_bone.SPIN_AXIS.
    mirrored = mirror_bone.conjugate(source_local, signs)

    bone = NiNode()
    bone.name = BONE
    bone.flags = source.flags
    bone.scale = source.scale
    bone.translation = mirrored[:3, 3]
    bone.rotation = mirrored[:3, :3] / float(source.scale)
    # All three axes, not just the blade: leaving the conjugation out still points the blade roughly
    # forwards while burying the weapon in the forearm, so a one-axis check would pass it.
    check = mirror_bone.conjugate(source_local, signs)
    if not np.allclose(check[:3, :3], mirrored[:3, :3], atol=1e-6):
        return "REFUSED: rotation did not round-trip"

    summary = "%s at %s (mirror %s, fit %.4f, %.0fx clear)" % (
        BONE, np.round(bone.translation, 3).tolist(), signs, error, margin)
    if bones_out:
        written = write_bone_source(bones_out, os.path.basename(path), bone)
        return "wrote %s -> %s" % (summary, os.path.relpath(written))

    hand.children = list(hand.children) + [bone]
    os.makedirs(os.path.dirname(out_path) or ".", exist_ok=True)
    stream.save(out_path)
    return "added " + summary


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("inputs", nargs="+", help="vanilla base_anim*.nif files, or a folder holding them")
    target = ap.add_mutually_exclusive_group(required=True)
    target.add_argument("-o", "--out", help="output meshes folder, for patched skeleton copies")
    target.add_argument("--bones-out", help="output Animations folder, for injected bones instead")
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
        if args.bones_out and name == "base_anim.1st.nif":
            # Never loaded as a skeleton, so no folder of its name is ever scanned.
            print("%-28s skipped (not a skeleton the engine loads)" % name)
            continue
        out = os.path.join(args.out, name) if args.out else None
        print("%-28s %s" % (name, patch(path, out, args.bones_out)))


if __name__ == "__main__":
    main()

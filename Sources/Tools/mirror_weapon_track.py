#!/usr/bin/env python3
"""Gives "Weapon Bone.L" the same animation track as "Weapon Bone" in a .kf.

An animation that poses the weapon bone - which the katar set does, to seat the katar in the grip -
leaves the off-hand one wherever the skeleton's rest pose put it, because nothing authored before
the bone existed has a track for it. The two weapons then sit differently in their hands.

The track is copied across verbatim, for the same reason patch_skeleton.py copies the rest transform
verbatim: a keyframe track is relative to the bone's parent, Bip01 L Hand and Bip01 R Hand are
anatomical mirrors of each other, so the same values inside the hand come out mirrored in the world.

Run it after every export; it replaces an existing Weapon Bone.L track rather than stacking another.

    python3 mirror_weapon_track.py <file.kf or directory> ...
    python3 mirror_weapon_track.py Animations/xbase_anim.1st

A Morrowind .kf is a NiSequenceStreamHelper whose NiStringExtraData chain names the targets and
whose NiKeyframeController chain animates them, paired in order - so a new track is one of each,
appended to the end of both chains.
"""
import argparse
import copy
import os
import sys

SOURCE_BONE = "Weapon Bone"
BONE = "Weapon Bone.L"


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
    from es3.nif import NiKeyframeController, NiStringExtraData, NiStream
except ImportError:
    sys.exit("Could not find the es3 library. Install Greatness7's io_scene_mw Blender add-on, or "
             "point IO_SCENE_MW at its 'lib' folder.")


def chain(obj, first):
    """Walk one of the .next-linked chains hanging off the sequence root."""
    cur = getattr(obj, first, None)
    while cur is not None:
        yield cur
        cur = getattr(cur, "next", None)


def last(items):
    return items[-1] if items else None


def key_count(component):
    """len() of a key array, which is numpy and so cannot be truth-tested."""
    keys = getattr(component, "keys", None)
    return 0 if keys is None else len(keys)


def patch(path):
    stream = NiStream()
    stream.load(path)
    root = stream.roots[0]

    extras = list(chain(root, "extra_data"))
    controllers = list(chain(root, "controller"))
    targets = [e for e in extras if isinstance(e, NiStringExtraData)]

    names = [e.string_data for e in targets]
    if SOURCE_BONE not in names:
        return "no %s track" % SOURCE_BONE
    if len(targets) != len(controllers):
        return "SKIPPED: %d targets against %d controllers" % (len(targets), len(controllers))

    source = controllers[names.index(SOURCE_BONE)]

    # Replace rather than stack, so the tool can be re-run.
    if BONE in names:
        index = names.index(BONE)
        existing = controllers[index]
        existing.data = copy.deepcopy(source.data)
        for field in ("flags", "frequency", "phase", "start_time", "stop_time"):
            setattr(existing, field, getattr(source, field))
        stream.save(path)
        return "updated %s (%d translation keys)" % (BONE, key_count(existing.data.translations))

    target = NiStringExtraData()
    target.string_data = BONE
    last(extras).next = target

    controller = NiKeyframeController()
    controller.data = copy.deepcopy(source.data)
    for field in ("flags", "frequency", "phase", "start_time", "stop_time"):
        setattr(controller, field, getattr(source, field))
    last(controllers).next = controller

    stream.save(path)
    return "added %s (%d translation keys, %d rotation keys)" % (
        BONE, key_count(controller.data.translations), key_count(controller.data.rotations))


def main():
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("inputs", nargs="+", help=".kf files, or directories holding them")
    args = ap.parse_args()

    files = []
    for item in args.inputs:
        if os.path.isdir(item):
            files += sorted(os.path.join(item, n) for n in os.listdir(item)
                            if n.lower().endswith(".kf"))
        else:
            files.append(item)

    for path in files:
        print("%-28s %s" % (os.path.basename(path), patch(path)))


if __name__ == "__main__":
    main()

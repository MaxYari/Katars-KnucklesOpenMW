#!/usr/bin/env python3
"""Gives "Weapon Bone.L" the same animation track as "Weapon Bone" in a .kf.

An animation that poses the weapon bone - which the katar set does, to seat the katar in the grip -
leaves the off-hand one wherever the skeleton's rest pose put it, because nothing authored before
the bone existed has a track for it. The two weapons then sit differently in their hands.

A keyframe track is relative to the bone's parent, so it needs the same conjugation into the left
hand's frame that the rest transform does - see mirror_bone.py. Translations and their tangents are
sign-flipped; rotations are quaternions, where conjugating by a reflection maps the axis through it
and negates the angle. Copying the track across unchanged buries the weapon in the forearm.

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

import numpy as np

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

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import mirror_bone  # noqa: E402  (needs the path set up above)

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


def mirror_data(data, signs):
    """Conjugate a NiKeyframeData in place, into the other hand's frame."""
    translations = getattr(data.translations, "keys", None)
    if translations is not None and len(translations):
        keys = np.asarray(translations, dtype=float)
        # [time, x, y, z] plus, for the spline key types, an in and an out tangent - all vectors in
        # the same space, so all of them get the same treatment.
        for start in range(1, keys.shape[1], 3):
            if start + 3 <= keys.shape[1]:
                keys[:, start:start + 3] = mirror_bone.conjugate_vectors(keys[:, start:start + 3], signs)
        data.translations.keys = keys

    rotations = getattr(data.rotations, "keys", None)
    if rotations is not None and len(rotations):
        keys = np.asarray(rotations, dtype=float)
        if keys.shape[1] < 5:
            raise ValueError("rotation keys are %d wide, not the [time, w, x, y, z] this handles"
                             % keys.shape[1])
        keys[:, 1:5] = mirror_bone.conjugate_quaternion(keys[:, 1:5], signs)
        data.rotations.keys = keys

    # Scales are scalars; nothing to mirror.
    return data


def patch(path, signs):
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
        existing.data = mirror_data(copy.deepcopy(source.data), signs)
        for field in ("flags", "frequency", "phase", "start_time", "stop_time"):
            setattr(existing, field, getattr(source, field))
        stream.save(path)
        return "updated %s (%d translation keys)" % (BONE, key_count(existing.data.translations))

    target = NiStringExtraData()
    target.string_data = BONE
    last(extras).next = target

    controller = NiKeyframeController()
    controller.data = mirror_data(copy.deepcopy(source.data), signs)
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
    ap.add_argument("--signs", default="1,1,-1",
                    help="the rig's mirror convention (patch_skeleton.py prints the one it fitted)")
    args = ap.parse_args()
    signs = tuple(int(v) for v in args.signs.split(","))

    files = []
    for item in args.inputs:
        if os.path.isdir(item):
            files += sorted(os.path.join(item, n) for n in os.listdir(item)
                            if n.lower().endswith(".kf"))
        else:
            files.append(item)

    for path in files:
        print("%-28s %s" % (os.path.basename(path), patch(path, signs)))


if __name__ == "__main__":
    main()

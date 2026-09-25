#!/usr/bin/env python3
"""Makes the katar moveset from ReAnimation's hand-to-hand one.

Every hand-to-hand animation ReAnimation ships - attacks and their mirrored variants, idle, sneak
idle, jump, equip and unequip, walk, run and sneak - is copied into this mod's first-person
animation folder under the katar's names, ready for scripts/MaxYari/H2HWeapons/animations.lua to
play over the one-handed groups the engine uses for these weapons. Three things change on the way:

1. The groups are renamed: handtohand -> katar, idlehh -> idlekatar, walkforwardhh ->
   walkforwardkatar and so on (GROUPS). Footstep keys (SoundGen) are left alone.

2. Weapon Bone is put where the katar sits. The fist animations hold it at the rig's rest pose; the
   katar set holds it at the pose that seats a katar in the grip, and the weapons are modelled for
   that. Both are constant over the animation, so the seat is read once from an existing katar
   animation (--seat-from) and written over the whole track.

3. Weapon Bone.L gets the mirrored track (mirror_weapon_track.py), so the off-hand weapon sits in
   the left hand as the right one does in the right.

Run it again after ReAnimation's animations change; it overwrites what it wrote before, and the seat
it reads from is one it wrote itself, so the result does not drift.

    python3 import_h2h_set.py "<ReAnimation>/Animations/xbase_anim.1st" Animations/xbase_anim.1st
"""
import argparse
import copy
import os
import re
import shutil
import sys

import numpy as np

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import mirror_weapon_track  # noqa: E402  (also puts the es3 library on the path)
from es3.nif import NiStream, NiStringExtraData, NiTextKeyExtraData  # noqa: E402

# ReAnimation's file (no extension) -> this mod's.
FILES = {
    "xh2hChop": "xKatarChop",
    "xh2hChopMirrored": "xKatarChopMirrored",
    "xh2hSlash": "xKatarSlash",
    "xh2hSlashMirrored": "xKatarSlashMirrored",
    "xh2hThrust": "xKatarThrust",
    "xh2hThrustMirrored": "xKatarThrustMirrored",
    "xh2hEqUneq": "xKatarEqUneq",
    "xh2hIdle": "xKatarIdle",
    "xh2hIdleSneak": "xKatarIdleSneak",
    "xh2hJump": "xKatarJump",
    "xhhMovement": "xKatarMovement",
    "xhhSneakMovement": "xKatarSneakMovement",
}

# Lowercased group -> new group. Anything not here and not in KEEP stops the run: an unexpected
# group would otherwise go on overriding the fists.
GROUPS = {
    "handtohand": "Katar",
    "handtohandalt": "KatarAlt",
    "idlehh": "IdleKatar",
    "idlehhsneak": "IdleKatarSneak",
    "jumphh": "JumpKatar",
}
for _move in ("walk", "run", "sneak"):
    for _way in ("forward", "back", "left", "right"):
        GROUPS[_move + _way + "hh"] = _move.capitalize() + _way.capitalize() + "Katar"
KEEP = {"soundgen"}

SEAT_BONE = "Weapon Bone"
KEY_LINE = re.compile(r"^(\s*)([^:]+?)(\s*:.*)$")


def rename_line(line, path):
    m = KEY_LINE.match(line)
    if not m:
        return line
    group = m.group(2).strip().lower()
    if group in KEEP:
        return line
    if group not in GROUPS:
        sys.exit("%s has a key in group %r, which this does not know what to call - add it to GROUPS"
                 % (os.path.basename(path), m.group(2)))
    return m.group(1) + GROUPS[group] + m.group(3)


def rename_groups(stream, path):
    renamed = 0
    for obj in stream.objects():
        if not isinstance(obj, NiTextKeyExtraData):
            continue
        keys = obj.keys.copy()
        for i in range(len(keys)):
            text = keys[i][1]
            new = "\r\n".join(rename_line(line, path) for line in text.split("\r\n"))
            if new != text:
                keys[i] = (keys[i][0], new)
                renamed += 1
        obj.keys = keys
    return renamed


def chains(root):
    extras, e = [], root.extra_data
    while e is not None:
        extras.append(e)
        e = e.next
    controllers, c = [], root.controller
    while c is not None:
        controllers.append(c)
        c = c.next
    targets = [x for x in extras if isinstance(x, NiStringExtraData)]
    return targets, controllers


def track(stream, bone):
    targets, controllers = chains(stream.roots[0])
    names = [t.string_data for t in targets]
    return controllers[names.index(bone)] if bone in names else None


def read_seat(path):
    """The katar's Weapon Bone pose: (translation, rotation quaternion), constant over its track."""
    stream = NiStream()
    stream.load(path)
    controller = track(stream, SEAT_BONE)
    if controller is None:
        sys.exit("%s has no %s track to take the seat from" % (path, SEAT_BONE))
    t = np.asarray(controller.data.translations.keys, dtype=float)
    r = np.asarray(controller.data.rotations.keys, dtype=float)
    if np.ptp(t[:, 1:4], axis=0).max() > 1e-4 or np.ptp(r[:, 1:5], axis=0).max() > 1e-4:
        sys.exit("%s moves its %s - the seat has to be a single pose" % (path, SEAT_BONE))
    return t[0, 1:4].copy(), r[0, 1:5].copy()


def seat(stream, seat_pose):
    """Hold Weapon Bone at the seat for the whole track, at its own key times."""
    controller = track(stream, SEAT_BONE)
    if controller is None:
        return False
    translation, rotation = seat_pose
    data = controller.data
    t = np.asarray(data.translations.keys, dtype=float).copy()
    t[:, 1:4] = translation
    t[:, 4:] = 0.0  # any tangents: the pose does not move
    data.translations.keys = t
    r = np.asarray(data.rotations.keys, dtype=float).copy()
    r[:, 1:5] = rotation
    r[:, 5:] = 0.0
    data.rotations.keys = r
    return True


def main():
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("source", help="ReAnimation's Animations/xbase_anim.1st")
    ap.add_argument("dest", help="this mod's Animations/xbase_anim.1st")
    ap.add_argument("--seat-from", default=None,
                    help="katar animation to take Weapon Bone's seat from (default: dest/xKatarIdle.kf)")
    ap.add_argument("--signs", default="1,1,-1", help="the rig's mirror convention, as for mirror_weapon_track.py")
    args = ap.parse_args()
    signs = tuple(int(v) for v in args.signs.split(","))

    # Read before anything is overwritten - the default seat source is one of the files written.
    seat_pose = read_seat(args.seat_from or os.path.join(args.dest, "xKatarIdle.kf"))
    print("seat: Weapon Bone at %s, rotation %s" % (np.round(seat_pose[0], 3).tolist(),
                                                     np.round(seat_pose[1], 3).tolist()))

    for src, dst in FILES.items():
        kf_in = os.path.join(args.source, src + ".kf")
        kf_out = os.path.join(args.dest, dst + ".kf")
        stream = NiStream()
        stream.load(kf_in)
        renamed = rename_groups(stream, kf_in)
        seated = seat(stream, seat_pose)
        stream.save(kf_out)
        mirrored = mirror_weapon_track.patch(kf_out, signs)

        # The companion .nif carries no text keys, only the skeleton subset; copied as it is.
        shutil.copyfile(os.path.join(args.source, src + ".nif"), os.path.join(args.dest, dst + ".nif"))
        extra = ""
        yaml_in = os.path.join(args.source, src + ".yaml")
        if os.path.exists(yaml_in):
            # Blending rules, matched by pattern rather than by group name, so they carry over as they are.
            shutil.copyfile(yaml_in, os.path.join(args.dest, dst + ".yaml"))
            extra = " + blending rules"
        print("%-22s -> %-22s %2d keys renamed, %s, %s%s" % (
            src, dst, renamed, "seated" if seated else "NO WEAPON BONE", mirrored, extra))


if __name__ == "__main__":
    main()

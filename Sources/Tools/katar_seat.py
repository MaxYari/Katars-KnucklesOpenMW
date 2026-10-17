#!/usr/bin/env python3
"""Seats the katar in another mod's animation: both weapon bones held where the katar idle holds them.

Anyone else's animation keys `Weapon Bone` at the skeleton's rest seat, or not at all, and has no
`Weapon Bone.L` track, so a katar drawn under it floats off the fist and the off-hand one sits at
rest. This writes a copy whose `Weapon Bone` keeps the seat the katar idle of the same view has, and
adds `Weapon Bone.L` at the idle's off-hand seat. Key times and key types stay the animation's own;
every other track is left alone. Only a fixed seat is handled, which is all the katar set has.

    python3 katar_seat.py --idle "00 Core/Animations/xbase_anim.1st/xKatarIdle.kf" <in.kf> <out.kf>

A track is relative to its bone's parent, the hand, so the seat goes across unchanged as long as the
idle and the animation are for the same view's skeleton.
"""
import argparse
import copy
import os
import sys

import numpy as np

BONES = ("Weapon Bone", "Weapon Bone.L")
SEAT_TOLERANCE = 0.01  # units, and quaternion components: a seat that moves more than this is not one

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import es3_path  # noqa: E402  (puts the es3 library on the path)

try:
    from es3.nif import NiKeyframeController, NiStringExtraData, NiStream  # noqa: E402
except ImportError as exc:
    sys.exit(es3_path.MISSING % exc)
from mirror_weapon_track import chain, last  # noqa: E402


def tracks(root):
    """{bone: controller} of a loaded .kf, plus its two chains."""
    extras = list(chain(root, "extra_data"))
    controllers = list(chain(root, "controller"))
    targets = [e for e in extras if isinstance(e, NiStringExtraData)]
    if len(targets) != len(controllers):
        sys.exit("%d targets against %d controllers" % (len(targets), len(controllers)))
    return dict(zip((t.string_data for t in targets), controllers)), extras, controllers


def held(keys, columns, what):
    """The one value a fixed track holds throughout."""
    keys = np.asarray(keys, dtype=float)[:, columns]
    if np.abs(keys - keys[0]).max() > SEAT_TOLERANCE:
        sys.exit("%s moves - only a fixed seat is handled" % what)
    return keys[0]


def read_seats(path):
    stream = NiStream()
    stream.load(path)
    found, _, _ = tracks(stream.roots[0])
    seats = {}
    for bone in BONES:
        if bone not in found:
            sys.exit("%s: no %s track" % (path, bone))
        data = found[bone].data
        seats[bone] = (held(data.translations.keys, slice(1, 4), bone + " translation"),
                       held(data.rotations.keys, slice(1, 5), bone + " rotation"))
    return seats


def seated(data, seat):
    """A copy of a track's data holding the seat at each of its own keys."""
    data = copy.deepcopy(data)
    trans, quat = seat
    keys = np.asarray(data.translations.keys, dtype=float)
    keys[:, 1:4] = trans
    keys[:, 4:] = 0.0  # spline tangents: a held value has none
    data.translations.keys = keys
    keys = np.asarray(data.rotations.keys, dtype=float)
    if keys.shape[1] != 5:
        raise ValueError("rotation keys are %d wide, not the [time, w, x, y, z] this handles" % keys.shape[1])
    keys[:, 1:5] = quat
    data.rotations.keys = keys
    return data


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--idle", required=True, help="the katar idle .kf of the animation's view")
    ap.add_argument("input")
    ap.add_argument("output")
    args = ap.parse_args()

    seats = read_seats(args.idle)
    stream = NiStream()
    stream.load(args.input)
    found, extras, controllers = tracks(stream.roots[0])
    source = found.get(BONES[0])
    if source is None:
        sys.exit("%s: no %s track to take the key times from" % (args.input, BONES[0]))

    for bone in BONES:
        data = seated(source.data, seats[bone])
        if bone in found:
            found[bone].data = data
            continue
        target = NiStringExtraData()
        target.string_data = bone
        last(extras).next = target
        controller = NiKeyframeController()
        controller.data = data
        for field in ("flags", "frequency", "phase", "start_time", "stop_time"):
            setattr(controller, field, getattr(source, field))
        last(controllers).next = controller
        extras.append(target)
        controllers.append(controller)

    os.makedirs(os.path.dirname(os.path.abspath(args.output)), exist_ok=True)
    stream.save(args.output)
    print("%s: %s seated from %s" % (args.output, " and ".join(BONES), os.path.basename(args.idle)))


if __name__ == "__main__":
    main()

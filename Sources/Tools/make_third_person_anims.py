#!/usr/bin/env python3
"""Builds the third-person hand-to-hand animations - what NPCs, and the player in third person, play
with a katar or knuckledusters in hand - from the first-person ones.

There are no third-person ones of their own. Both sets, the knuckledusters' and the katars', are the
fist's - ReAnimation's hand-to-hand animations, changed a little - so these are built exactly as
ReAnimation builds its own hand-to-hand set for third person, with its
Sources/Tools/FirstToThird/first_to_third.py (see its README): the first-person animations
(00 Core/Animations/xbase_anim.1st) on the third person's hand-to-hand ones, Animation Compilation's
by default. One run per set, as the tool takes one set of names for each of the engine's stances:
'knuckle=hh' pairs knuckle and knucklealt with handtohand, idleknuckle with idlehh, walkforwardknuckle
with walkforwardhh, jumpknuckle with jumphh, 'katar=hh' the katar's, and gives them every setting
hand-to-hand gets: the upper body turned the way the first person turns it,
on the third person's legs, hips and root motion; attacks at the first person's timing, held in place
and ending on the idle's first frame; the head looking straight ahead; idles breathing; walks, runs and
sneaks at the third person's timing, the torso moving over the legs as people's do, the arms bouncing
with half the spring, in the walk's own time, and keeping three quarters of the way they face as the
torso swings under them (ARM_BOUNCE, ARM_FACING). Everything else is that tool's defaults.

What this adds to the tool's build, for this mod:
  * Footsteps. Ours carry them as SoundGenRef keys (footstep_refs.py), which sound nothing. The tool
    puts the walks in step with the legs by their footsteps, so it is given them as SoundGen keys, and
    what it writes gets references again.
  * The weapon bones keep the first-person seat. Vanilla's first- and third-person hand meshes put the
    palm in the same place on the hand bone, so the katar keeps the seat it has in first person; the
    tool moves every bone's offset to the third-person skeleton's, and the skeletons' own weapon bones
    differ by about a finger's width, which sat it that much off in the palm.
  * The fingers are fitted, not copied (third_person_fingers.py): the third-person hand has two-joint
    fingers, the last three as one, at other lengths and rest angles, so first-person rotations
    copied onto it twisted the thumbs. The first-person hand mesh is posed with the animation and
    the third-person finger rotations that put the same vertices in the same places are solved for.
    Beasts take the same fingers: their skeleton's finger offsets are the same.
  * Only the bones the skeletons have are written. The first-person rig has fingers the third-person
    one does not (Finger02, the third and fourth fingers) and a human has no toes, and every track
    for a bone the skeleton lacks is a "can't find bone" warning in openmw.log, once per actor that
    loads the file. The off-hand weapon bone stays: the mod grafts it on (h2h_weapon_bone_l.nif).
  * Each kf's blending rules (<kf>.yaml) are copied along.

The walks, runs and sneaks are not converted: they are made from the idles, on the one-handed walk's
legs - each set's idle's upper body over the one-handed walks and runs, its sneaking idle's over the
one-handed sneaks - and play whole in game (animations.lua), so the pace, the steps and the root
motion are exactly those of the one-handed walk they play over, and the torso moves over the legs.
Leaning as that walk leans against its own idle, at least 3 degrees forward walking and 8 running.
The turns are made so too, from the idle on the one-handed turn's legs, and play over it in third
person. The jump is ours, on the hand-to-hand jump's legs. The katars have no swings or equip of their
own: they play the knuckledusters'.

One set per third-person skeleton folder the engine loads (npcanimation.cpp, updateNpcBase):
xbase_anim is loaded for every NPC, xbase_animkna on top of it for beasts, with their own legs;
xbase_anim_female only for what women's own animations change, if anything.

    python3 Sources/Tools/make_third_person_anims.py

Needs Morrowind.bsa (found from openmw.cfg, or --data-files), ReAnimation's source folder (found beside
this mod, or --reanimation) and Animation Compilation (found beside this mod, or --third; '--third
vanilla' builds on vanilla's hand-to-hand instead).
"""
import argparse
import copy
import glob
import os
import shutil
import struct
import subprocess
import sys
import tempfile

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import footstep_refs  # noqa: E402

HERE = os.path.dirname(os.path.abspath(__file__))
MOD = os.path.normpath(os.path.join(HERE, '..', '..'))
FIRST_PERSON = os.path.join(MOD, '00 Core', 'Animations', 'xbase_anim.1st')
OUT = os.path.join(MOD, '00 Core', 'Animations')
# Third-person skeleton folder -> the skeletons that play its files: the bones a file may have are the
# ones all of them have. Beasts play xbase_anim's files too, under their own; their skeleton has every
# human bone.
SKELETONS = {
    'xbase_anim': ('meshes\\xbase_anim.nif', 'meshes\\xbase_anim_female.nif'),
    'xbase_animkna': ('meshes\\xbase_animkna.nif',),
    'xbase_anim_female': ('meshes\\xbase_anim_female.nif',),
}
OFF_HAND_BONE = 'Weapon Bone.L'
# Their seat stays as the first person has it, on the hand bone (see above).
WEAPON_BONES = ('Weapon Bone', OFF_HAND_BONE)
SEAT_TOLERANCE = 0.01  # units: a seat that moves more than this is not a seat
# The sets, by the name of their groups and files (xKnuckleIdle.kf, idleknuckle).
SETS = ('Knuckle', 'Katar')
# Not converted: the walks and sneaks laid out as the first-person one-handed ones are
# (make_katar_1h_movement.py), first person's alone, and the plain ones, which third person makes
# from the idles instead (see above).
NOT_CONVERTED = tuple('x%s%s.kf' % (s, kind) for s in SETS
                      for kind in ('1hMovement', '1hSneakMovement', 'Movement', 'SneakMovement'))
MADE = tuple('x%sTurn.kf' % s for s in SETS)  # made from the idle, as the walks are: the mod's spelling
MOVES = [m + d for m in ('walk', 'run', 'sneak') for d in ('forward', 'back', 'left', 'right')] + ['turnleft', 'turnright']
# How far the arms lag behind the walk's bob and spring back, from 0 to the whole of the tool's spring - in
# the walk's own time (--arm-bounce-real-time): stepped a frame per sample, as the tool does by default, a
# forward walk, with three or four samples to a frame, hardly bounced at all.
ARM_BOUNCE = '0.5'
# How much the arms keep the way they face while a walk's torso nods, swings and leans under them, the hands
# carried by the shoulders: a guard held forward, as a spell is, stays partly pointed ahead.
ARM_FACING = '0.75'


def settings(name):
    """The tool's settings for one set (see the top of this file); everything else is its default."""
    name = name.lower()
    # --keep-bones: the fingers are fitted on the first person's whole hand, and the off-hand weapon bone
    # kept, before finish() leaves out what the skeletons lack.
    return ['--alias', '%s=hh' % name, '--idle-moves', 'hh', '--idle-sneak', 'hh', '--prefix', '',
            '--skip', '', '--skip-files', '', '--keep-bones', '--arm-bounce', ARM_BOUNCE,
            '--keep-arm-facing', ARM_FACING, '--arm-bounce-real-time', 'y',
            '--legs-from', ', '.join('%s%s=%s1h' % (m, name, m) for m in MOVES)]


def find_mod(given, starts, inside):
    """A folder beside this mod whose name starts with `starts` and that has `inside` in it."""
    if given:
        return given
    mods = os.path.dirname(MOD)
    for name in sorted(os.listdir(mods)):
        if name.lower().startswith(starts.lower()) and os.path.exists(os.path.join(mods, name, inside)):
            return os.path.join(mods, name)
    return None


def find_third(given):
    """What to build on: Animation Compilation's folder (its whole-set kfs in Meshes), or '' for vanilla."""
    if given is not None:
        return '' if given.lower() == 'vanilla' else given
    found = find_mod(None, 'animation compilation', 'Animation Compilation')
    if found:
        return os.path.join(found, 'Animation Compilation')
    sys.exit("Animation Compilation not found next to this mod - give its folder with --third, or "
             "'--third vanilla' to build on vanilla's hand-to-hand")


def bsa_files(path, wanted):
    """{name: bytes} of the wanted files (lowercase, backslashes) in a Morrowind BSA."""
    data = open(path, 'rb').read()
    _version, hash_offset, count = struct.unpack('<III', data[:12])
    records = [struct.unpack('<II', data[12 + 8 * i:20 + 8 * i]) for i in range(count)]
    names_at = 12 + 8 * count
    name_offsets = struct.unpack('<%dI' % count, data[names_at:names_at + 4 * count])
    names_start = names_at + 4 * count
    data_start = 12 + hash_offset + 8 * count
    out = {}
    for i in range(count):
        start = names_start + name_offsets[i]
        name = data[start:data.index(b'\0', start)].decode('latin-1').lower()
        if name in wanted:
            size, offset = records[i]
            out[name] = data[data_start + offset:data_start + offset + size]
    missing = set(wanted) - set(out)
    if missing:
        sys.exit('%s has no %s' % (path, ', '.join(sorted(missing))))
    return out


def skeleton_bones(nif):
    """A skeleton's node names, lowercased as the engine looks them up: each NiNode's name follows
    its type name."""
    tag = struct.pack('<I', 6) + b'NiNode'
    names, at = set(), nif.find(tag)
    while at >= 0:
        start = at + len(tag)
        size = struct.unpack('<I', nif[start:start + 4])[0]
        names.add(nif[start + 4:start + 4 + size].decode('latin-1').lower())
        at = nif.find(tag, start)
    return names


def drop_tracks(kf, keep):
    """Takes every track for a bone not in `keep` (lowercased names) out of a kf: its name, its
    controller and its keyframe data, with the block references renumbered. Returns the bones."""
    helper = kf.blocks[0][1]

    def chain(first):
        out = []
        while first >= 0:
            out.append(first)
            first = kf.blocks[first][1]['next']
        return out

    # The bone names follow the text keys on the extra data chain, paired in order with the controllers.
    extras, ctrls = chain(helper['extra']), chain(helper['ctrl'])
    names = [e for e in extras if kf.blocks[e][0] == 'NiStringExtraData']
    gone, dropped = set(), []
    for name, ctrl in zip(names, ctrls):
        bone = kf.blocks[name][1]['value']
        if bone.lower() in keep:
            continue
        dropped.append(bone)
        gone |= {name, ctrl}
        if kf.blocks[ctrl][1]['data'] >= 0:
            gone.add(kf.blocks[ctrl][1]['data'])
    if not dropped:
        return dropped

    index = {}
    for old in range(len(kf.blocks)):
        if old not in gone:
            index[old] = len(index)

    def relink(blocks, first):
        kept = [b for b in blocks if b not in gone]
        helper[first] = index[kept[0]] if kept else -1
        for this, after in zip(kept, kept[1:] + [None]):
            kf.blocks[this][1]['next'] = index[after] if after is not None else -1

    relink(extras, 'extra')
    relink(ctrls, 'ctrl')
    for ctrl in ctrls:
        if ctrl in gone:
            continue
        p = kf.blocks[ctrl][1]
        for ref in ('data', 'target'):
            if p[ref] >= 0:
                p[ref] = index[p[ref]]
    kf.blocks = [block for old, block in enumerate(kf.blocks) if old not in gone]
    kf._index()
    return dropped


class FirstPersonHand:
    """A written kf's hand as the first person's, for the finger fit: its rotations - the first
    person's, which the tool copies - on the first-person rig's offsets, which it moved."""

    def __init__(self, written, first):
        self.written, self.first = written, first

    def data(self, bone):
        d = copy.copy(self.written.data(bone))
        d.trans = self.first.data(bone).trans
        return d


def seat(E, kf, bone, name):
    """A weapon bone's offset in a first-person kf: the one it holds throughout."""
    keys = kf.data(bone).trans['keys']
    if not keys:
        return None
    first = keys[0][1]
    if any(max(abs(a - b) for a, b in zip(k[1], first)) > SEAT_TOLERANCE for k in keys):
        sys.exit('%s: %s moves - only a fixed seat is handled' % (name, bone))
    return tuple(first)


def finish(T, E, fingers, finger_cache, written_path, first_kf, name, keep, out_path, stats):
    """One kf the tool wrote, made this mod's (see the top of this file)."""
    import nifkf
    kf = nifkf.KF.load(written_path)
    for bone in WEAPON_BONES:
        place = seat(E, first_kf, bone, name)
        if place is not None and bone in kf.bone_data:
            d = kf.data(bone)
            d.trans = {'itype': 1, 'keys': [(t, place, ()) for t, _, _ in d.trans['keys']] or [(0.0, place, ())]}
    hand = FirstPersonHand(kf, first_kf)
    for side in sorted(fingers.rest):
        bones = ['Bip01 %s %s' % (side, b) for b in ['Hand'] + fingers.F.FIT_BONES]
        if not all(b in kf.bone_data and b in first_kf.bone_data for b in bones):
            continue
        times = sorted({k[0] for b in bones for k in kf.data(b).quat_keys})
        fitted = {b: [] for b in fingers.rest[side]}
        for t in times:
            # The fit depends on the hand's pose alone: the same pose is solved once, for every skeleton.
            pose = tuple(tuple(round(c, 6) for c in E.rotation(hand.data(b), t)) for b in bones)
            if (side, pose) not in finger_cache:
                finger_cache[(side, pose)] = fingers.solve(hand, side, t, key=(name, side))
            rots, error = finger_cache[(side, pose)]
            stats.append(error)
            for b, rot in rots.items():
                fitted[b].append((t, E.qnorm(rot), ()))
        for b, keys in fitted.items():
            bone = 'Bip01 %s %s' % (side, b)
            if bone not in kf.bone_data or not keys:
                continue
            fixed = []
            for t, q, extra in keys:
                if fixed and sum(x * y for x, y in zip(fixed[-1][1], q)) < 0:
                    q = tuple(-c for c in q)
                fixed.append((t, q, extra))
            d = kf.data(bone)
            d.rot_type = 1
            d.quat_keys = T.thin(fixed, lambda a, b, f: E.qslerp(a, b, f),
                                 lambda a, b: E.qangle(a, b) < T.ANGLE_TOLERANCE)
    tk = kf.blocks[kf.textkey_block][1]
    tk['keys'] = [(t, footstep_refs.to_ref(text)) for t, text in tk['keys']]
    dropped = drop_tracks(kf, keep)
    kf.save(out_path)
    return dropped


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument('--data-files', help="Morrowind's Data Files folder, with Morrowind.bsa")
    ap.add_argument('--reanimation', help="ReAnimation's folder, with Sources/Tools/FirstToThird")
    ap.add_argument('--third', help="the third-person animations to build on, as first_to_third.py's --third "
                                    "(default: Animation Compilation, found beside this mod; 'vanilla' for vanilla's)")
    ap.add_argument('-v', '--verbose', action='store_true')
    args = ap.parse_args()

    reanimation = find_mod(args.reanimation, 'reanimation', os.path.join('Sources', 'Tools', 'FirstToThird',
                                                                         'first_to_third.py'))
    if not reanimation:
        sys.exit("ReAnimation's source folder not found next to this mod - give it with --reanimation")
    tools = os.path.join(reanimation, 'Sources', 'Tools')
    sys.path.insert(0, os.path.join(tools, 'FBACompat'))
    sys.path.insert(0, os.path.join(tools, 'FirstToThird'))
    import fba_fingers
    import first_to_third as T
    import kfeval as E
    import nifkf
    import params
    import third_person_fingers

    third = find_third(args.third)
    data_files = args.data_files or params.find_data_files()
    if not data_files:
        sys.exit('Morrowind.bsa not found from openmw.cfg - give --data-files')
    bsa = os.path.join(data_files, 'Morrowind.bsa')
    fingers = third_person_fingers.FingerFit(fba_fingers, E, bsa)
    skeletons = bsa_files(bsa, {s for names in SKELETONS.values() for s in names})

    with tempfile.TemporaryDirectory() as scratch:
        first = {}
        for name in SETS:
            first_dir = os.path.join(scratch, name, 'xbase_anim.1st')
            os.makedirs(first_dir)
            sources = sorted(p for p in glob.glob(os.path.join(FIRST_PERSON, 'x%s*.kf' % name))
                             if os.path.basename(p) not in NOT_CONVERTED)
            for path in sources:
                kf = nifkf.KF.load(path)
                tk = kf.blocks[kf.textkey_block][1]
                tk['keys'] = [(t, footstep_refs.from_ref(text)) for t, text in tk['keys']]
                kf.save(os.path.join(first_dir, os.path.basename(path)))
                first[os.path.basename(path)] = kf
            command = [sys.executable, os.path.join(tools, 'FirstToThird', 'first_to_third.py'), '-y',
                       '--first', first_dir, '--third', third, '--out', os.path.join(scratch, name, 'built'),
                       '--data-files', data_files] + settings(name)
            if args.verbose:
                command.append('-v')
            print('first_to_third.py on %s, the %s set' % (third or "vanilla's animations", name.lower()))
            subprocess.run(command, check=True)

        finger_cache = {}  # (side, the hand's pose) -> fitted rotations, shared by every skeleton
        for folder in SKELETONS:
            written = sorted(p for name in SETS for p in glob.glob(os.path.join(scratch, name, 'built', folder, '*.kf')))
            if not written:
                continue
            keep = set.intersection(*(skeleton_bones(skeletons[s]) for s in SKELETONS[folder]))
            keep.add(OFF_HAND_BONE.lower())
            out_dir = os.path.join(OUT, folder)
            os.makedirs(out_dir, exist_ok=True)
            print('%s:' % folder)
            for path in written:
                # What the tool made from an idle (xkatarMovement.kf) under the mod's own spelling.
                name = next((n for n in NOT_CONVERTED + MADE + tuple(first) if n.lower() == os.path.basename(path).lower()),
                            os.path.basename(path))
                own_set = next(s for s in SETS if name.lower().startswith('x' + s.lower()))
                errors = []
                # The seat and the hand's offsets are the same in every first-person file.
                dropped = finish(T, E, fingers, finger_cache, path, first.get(name, first['x%sIdle.kf' % own_set]),
                                 name, keep, os.path.join(out_dir, name), errors)
                print('  %-26s fingers fitted to %.2f units on average, %.2f at worst; %d tracks the skeleton '
                      'has no bone for left out' % (name, sum(errors) / max(len(errors), 1), max(errors, default=0.0),
                                                    len(dropped)))
                rules = os.path.join(FIRST_PERSON, os.path.splitext(name)[0] + '.yaml')
                if os.path.isfile(rules):
                    shutil.copyfile(rules, os.path.join(out_dir, os.path.basename(rules)))


if __name__ == '__main__':
    main()

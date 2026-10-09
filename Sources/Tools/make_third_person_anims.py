#!/usr/bin/env python3
"""Builds the third-person katar animations - what NPCs, and the player in third person, play with a
katar or knuckledusters in hand - from the first-person ones.

There are no third-person katar animations of their own. These are the first-person ones
(Animations/xbase_anim.1st) with vanilla's third-person hand-to-hand legs under them, merged the way
ReAnimation builds its Full Body Awareness compatibility (its Sources/Tools/FBACompat/fba_merge.py,
which this runs): our upper body, their lower body - Bip01, pelvis, spine, legs - and their root
motion, their time warped through the text keys both share so that ours are kept exactly. Our
attack timings are the ones that count; the legs follow them.

Where this differs from that build:
  * Group names. Ours end in "katar" and take the legs of the hand-to-hand ("hh") group of the same
    base: idlekatar <- idlehh, walkforwardkatar <- walkforwardhh, jumpkatar <- jumphh, and the
    attacks and equip ("katar", "kataralt") <- handtohand.
  * No chest lean, and the whole hip lunge (so no leg IK): nothing here has to stay out of a camera.
  * The walk, run and sneak play only from the chest up in game (animations.lua): the legs, hips and
    spine are the one-handed walk's they play over, and with them the actor's pace and footsteps.
    So ours are keyed from Bip01 Spine1 - where the engine's upper body starts - to sit on the
    vanilla one-handed walk's spine as it is on average, and inherit whatever that walk does with it:
    its sway, and another walk's lean. Their legs and spine are left here as they are, unused in game.
  * Morrowind's skeletons hang the thighs - and a beast's tail - off Bip01 Spine, not the pelvis.
    Everywhere else the merge turns the spine so our upper body keeps its orientation; the thighs and
    tail are turned back here, so the legs stay exactly where the third person put them.
  * The upper body's bone offsets are moved from the first-person skeleton's to the third-person
    one's - but not the weapon bones'. Vanilla's first- and third-person hand meshes put the palm in
    the same place on the hand bone, so the katar keeps the seat it has in first person; the
    skeletons' own weapon bones differ by about a finger's width, which sat it that much off in the
    palm.
  * The fingers are fitted, not copied (third_person_fingers.py): the third-person hand has two-joint
    fingers, the last three as one, at other lengths and rest angles, so first-person rotations
    copied onto it twisted the thumbs. The first-person hand mesh is posed with the animation and
    the third-person finger rotations that put the same vertices in the same places are solved for.
    Beasts take the same fingers: their skeleton's finger offsets are the same.
  * The head looks ahead through every swing and draw. In first person the whole upper body, head and
    all, turns into a punch - up to 95 degrees - which the camera never shows, since it takes the
    head's position and not its turn. Here the head is turned back each frame to the way it looks in
    the idle, which is also how the jump and the draw hold it, so nothing snaps between them; the
    neck, and the arms that hang off it, move as animated. (The mirrored swings also pitch the head
    some 12 degrees up, invisibly in first person, and this does away with that too.) The engine's
    own head tracking, which turns an NPC's head to whoever it is fighting, goes on top.

One set per third-person skeleton folder the engine loads (npcanimation.cpp, updateNpcBase):
xbase_anim is loaded for every NPC, xbase_animkna on top of it for beasts, with their own legs.
Female NPCs play xbase_anim's hand-to-hand, so they need nothing of their own. Each kf's
blending rules (<kf>.yaml) are copied along.

    python3 Sources/Tools/make_third_person_anims.py

Needs Morrowind.bsa (found from openmw.cfg, or --data-files) and ReAnimation's source folder (found
beside this mod, or --reanimation).
"""
import argparse
import glob
import os
import shutil
import struct
import sys
import tempfile

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import footstep_refs  # noqa: E402

HERE = os.path.dirname(os.path.abspath(__file__))
MOD = os.path.normpath(os.path.join(HERE, '..', '..'))
FIRST_PERSON = os.path.join(MOD, 'Animations', 'xbase_anim.1st')
# Third-person skeleton folder -> the vanilla kf whose hand-to-hand gives the legs.
TARGETS = {
    'xbase_anim': 'meshes\\xbase_anim.kf',
    'xbase_animkna': 'meshes\\xbase_animkna.kf',
}
FIRST_PERSON_KF = 'meshes\\xbase_anim.1st.kf'
BONE_FILE = 'h2h_weapon_bone_l.nif'
OFF_HAND_BONE = 'Weapon Bone.L'
# Their seat stays as the first person has it, on the hand bone (see above).
WEAPON_BONES = ('Weapon Bone', OFF_HAND_BONE)

# Bones under Bip01 Spine that are not the upper body: they follow the lower body, and are turned
# back when the spine is turned.
SPINE_CHILDREN = ('Bip01 L Thigh', 'Bip01 R Thigh', 'Bip01 Tail')
EXTRA_LOWER = ('Bip01 L Toe0', 'Bip01 R Toe0', 'Bip01 Tail', 'Bip01 Tail1', 'Bip01 Tail2', 'Bip01 Tail3')
# The groups whose head keeps looking ahead (see above), and the idle it looks ahead as in.
STEADY_HEAD_GROUPS = ('katar', 'kataralt')
HEAD, NECK = 'Bip01 Head', 'Bip01 Neck'
CHEST = 'Bip01 Spine1'  # where the engine's upper body starts (animation.cpp, detectBlendMask)
FORWARD_FROM = ('xKatarIdle.kf', 'idlekatar')
# First person only: the katar's walk and sneak laid out as the first-person one-handed ones are
# (make_katar_1h_movement.py), for their own layout. Third person plays the plain ones.
FIRST_PERSON_ONLY = ('xKatar1hMovement.kf', 'xKatar1hSneakMovement.kf')


def find_reanimation(given):
    if given:
        return given
    mods = os.path.dirname(MOD)
    for name in sorted(os.listdir(mods)):
        folder = os.path.join(mods, name, 'Sources', 'Tools', 'FBACompat')
        if name.lower().startswith('reanimation') and os.path.isfile(os.path.join(folder, 'fba_merge.py')):
            return os.path.join(mods, name)
    sys.exit("ReAnimation's source folder not found next to this mod - give it with --reanimation")


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


def off_hand_rest(folder):
    """The injected off-hand bone's translation, read straight out of h2h_weapon_bone_l.nif: its name,
    then the extra data and controller refs and the flags, then the translation (NiAVObject)."""
    data = open(os.path.join(folder, BONE_FILE), 'rb').read()
    name = OFF_HAND_BONE.encode('latin-1')
    at = data.index(struct.pack('<I', len(name)) + name) + 4 + len(name)
    return struct.unpack('<3f', data[at + 10:at + 22])


def rest_translations(kf):
    """Each bone's translation in a vanilla kf, which is its skeleton's own: they are never animated."""
    out = {}
    for bone in kf.bone_data:
        keys = kf.data(bone).trans['keys']
        if keys:
            out[bone] = keys[0][1]
    return out


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument('--data-files', help="Morrowind's Data Files folder, with Morrowind.bsa")
    ap.add_argument('--reanimation', help="ReAnimation's folder, with Sources/Tools/FBACompat")
    ap.add_argument('-v', '--verbose', action='store_true')
    args = ap.parse_args()

    tools = os.path.join(find_reanimation(args.reanimation), 'Sources', 'Tools', 'FBACompat')
    sys.path.insert(0, tools)
    import fba_fingers
    import fba_merge as M
    import kfeval as E
    import nifkf
    import params
    import third_person_fingers

    data_files = args.data_files or params.find_data_files()
    if not data_files:
        sys.exit('Morrowind.bsa not found from openmw.cfg - give --data-files')
    fingers = third_person_fingers.FingerFit(fba_fingers, E, os.path.join(data_files, 'Morrowind.bsa'))
    finger_cache = {}  # (first-person file, side, its time) -> fitted rotations, shared by both skeletons
    vanilla = bsa_files(os.path.join(data_files, 'Morrowind.bsa'),
                        set(TARGETS.values()) | {FIRST_PERSON_KF})
    # nifkf reads from a file; Bethesda's never land anywhere near the mod.
    scratch_dir = tempfile.TemporaryDirectory()
    scratch = scratch_dir.name

    def load_vanilla(name):
        path = os.path.join(scratch, name.split('\\')[-1])
        with open(path, 'wb') as fh:
            fh.write(vanilla[name])
        return nifkf.KF.load(path)

    # The merge's settings for third person (see the top of this file).
    M.HIP_MOTION = 1.0
    M.SWAY = 1.0
    M.IDLE_WHEN_FEET_LIFT = False
    M.VERBOSE = args.verbose
    for child in SPINE_CHILDREN:
        E.PARENT[child] = 'Bip01 Spine'
    E.PARENT.update({'Bip01 Tail1': 'Bip01 Tail', 'Bip01 Tail2': 'Bip01 Tail1', 'Bip01 Tail3': 'Bip01 Tail2'})

    def their_group(name, their_groups):
        if name.startswith('katar'):
            return 'handtohand'
        hh = name.replace('katar', 'hh')
        if hh in their_groups:
            return hh
        if name.startswith('idle') and name.endswith('sneak') and 'idlesneak' in their_groups:
            return 'idlesneak'
        return None

    M.their_group_for = their_group
    M.idle_group_for = lambda name, their_groups: 'idlehh'

    first_rest = rest_translations(load_vanilla(FIRST_PERSON_KF))
    first_rest[OFF_HAND_BONE] = off_hand_rest(FIRST_PERSON)
    sources = sorted(p for p in glob.glob(os.path.join(FIRST_PERSON, '*.kf'))
                     if os.path.basename(p) not in FIRST_PERSON_ONLY)

    # The head's orientation in the idle, in the character's frame: still, looking ahead.
    idle = nifkf.KF.load(os.path.join(FIRST_PERSON, FORWARD_FROM[0]))
    idle_start = M.all_group_keys(M.text_lines(idle))[FORWARD_FROM[1]]['start']
    head_forward = E.world(idle, HEAD, idle_start)[0]

    for folder, kf_name in TARGETS.items():
        theirs_kf = load_vanilla(kf_name)
        out_dir = os.path.join(MOD, 'Animations', folder)
        third_rest = rest_translations(theirs_kf)
        third_rest[OFF_HAND_BONE] = off_hand_rest(out_dir)
        lower = list(M.LOWER_BONES[:9]) + [b for b in EXTRA_LOWER if b in theirs_kf.bone_data]
        M.LOWER_BONES = lower
        print('%s: legs from %s' % (folder, kf_name.split('\\')[-1]))
        for source in sources:
            name = os.path.basename(source)
            M.WARNINGS.clear()
            fit_errors = []
            segments = merge(M, E, nifkf, source, theirs_kf, os.path.join(out_dir, name),
                             lower, first_rest, third_rest, head_forward,
                             fingers, finger_cache, fit_errors)
            print('  %-26s %s; fingers fitted to %.2f units on average, %.2f at worst'
                  % (name, ', '.join(s.name for s in segments),
                     sum(fit_errors) / max(len(fit_errors), 1), max(fit_errors, default=0.0)))
            if args.verbose:
                M.report(segments)
            for w in M.WARNINGS:
                print('    warning: ' + w)
            rules = os.path.splitext(source)[0] + '.yaml'
            if os.path.isfile(rules):
                shutil.copyfile(rules, os.path.join(out_dir, os.path.basename(rules)))
    scratch_dir.cleanup()


def mean_spine(E, kf, group, groups, samples=60):
    """A group's spine, held as it is on average over its loop: its world rotation."""
    keys = groups[group]
    start, stop = keys.get('loop start', keys['start']), keys.get('loop stop', keys['stop'])
    total = [0.0, 0.0, 0.0, 0.0]
    first = None
    for i in range(samples):
        q = E.world(kf, 'Bip01 Spine', start + (stop - start) * i / samples)[0]
        first = first or q
        if sum(a * b for a, b in zip(q, first)) < 0:
            q = tuple(-c for c in q)
        total = [a + b for a, b in zip(total, q)]
    return E.qnorm(total)


# Keys the ones either side of them reproduce within this much are left out: the merge samples every
# bone 30 times a second, most of them still.
ANGLE_TOLERANCE = 0.05  # degrees
MOVE_TOLERANCE = 0.01   # units


def lerp(a, b, f):
    return tuple(x + (y - x) * f for x, y in zip(a, b))


def thin(keys, interpolate, close):
    """Linear keys without those their neighbours already give: each one is kept only if the span
    from the last kept key to the next one would miss something in between."""
    if len(keys) <= 2:
        return keys
    kept = [keys[0]]
    anchor = 0
    for i in range(1, len(keys) - 1):
        a, b = keys[anchor], keys[i + 1]
        span = b[0] - a[0]
        fits = span > 0 and all(close(interpolate(a[1], b[1], (keys[j][0] - a[0]) / span), keys[j][1])
                                for j in range(anchor + 1, i + 1))
        if not fits:
            kept.append(keys[i])
            anchor = i
    kept.append(keys[-1])
    return kept


def merge(M, E, nifkf, ours_path, theirs_kf, out_path, lower, first_rest, third_rest, head_forward,
          fingers, finger_cache, fit_errors):
    """fba_merge.build, for third person: the thighs and tail turned back under the turned spine,
    the beast's extra leg and tail bones taken too, the upper body's offsets moved to the
    third-person skeleton (the weapon bones' excepted), the fingers fitted to the first person's
    hand, and the head held looking ahead through the swings. Each fitted frame's mean distance from
    the first-person hand goes into fit_errors."""
    finger_bones = {'Bip01 %s %s' % (side, b): (side, b) for side in fingers.rest for b in fingers.rest[side]}
    M._current_file[0] = os.path.basename(ours_path)
    ours_kf = nifkf.KF.load(ours_path)
    # Ours carry their footsteps as references (footstep_refs.py); the merge matches the legs by them
    # as footsteps, and they go back to references in what it writes.
    tk = ours_kf.blocks[ours_kf.textkey_block][1]
    tk['keys'] = [(t, footstep_refs.from_ref(s)) for t, s in tk['keys']]
    for bone in lower:
        if bone not in ours_kf.bone_data:
            ours_kf.add_bone(bone)

    our_lines = M.text_lines(ours_kf)
    their_lines = M.text_lines(theirs_kf)
    our_groups = M.all_group_keys(our_lines)
    their_groups = M.all_group_keys(their_lines)
    names = sorted(our_groups, key=lambda g: (min(our_groups[g].values()), g))

    segments = []
    rebased = {}  # locomotion segment -> the spine it is keyed onto
    offset = 0.0
    for name in names:
        keys = our_groups[name]
        target = M.their_group_for(name, their_groups)
        if target is None:
            sys.exit('%s: %s has no third-person group to take legs from' % (ours_path, name))
        if M.LOCOMOTION.match(name) and 'start' in keys and 'stop' in keys:
            ours = M.Group(our_lines, name)
            theirs = M.Group(their_lines, target)
            if not (ours.steps_usable() and theirs.steps_usable()):
                # Ours have no footstep markers: their loop is stretched over ours.
                ours.steps = [(0.0, 'loop')]
                theirs.steps = [(0.0, 'loop')]
            seg = M.LocomotionSegment(ours, theirs, theirs_kf, offset)
            # In game only its upper body plays (animations.lua), on the one-handed walk's legs and
            # spine: ours is keyed from the chest up to sit on that spine, held as it is on average.
            seg.sway = 0.0
            seg.mean_sway = M.mean_sway(ours_kf, seg)
            rebased[seg] = mean_spine(E, theirs_kf, name.replace('katar', '1h') if
                                      name.replace('katar', '1h') in their_groups else target, their_groups)
        else:
            seg = M.StillSegment(name, keys, ours_kf, theirs_kf, their_groups, offset)
            if seg.own:
                sys.exit('%s: %s shares too few keys with %s' % (ours_path, name, target))
        segments.append(seg)
        offset += seg.length + M.SEGMENT_GAP

    new_data = {b: nifkf.KeyframeData() for b in ours_kf.bone_data}
    for d in new_data.values():
        d.rot_type = 1
        d.trans = {'itype': 1, 'keys': []}
        d.scale = {'itype': 1, 'keys': []}

    spine_extra = set()
    for b in lower[:3]:
        if ours_kf.data(b).quat_keys or ours_kf.data(b).xyz:
            spine_extra |= M.key_times(ours_kf.data(b))
    for seg in segments:
        seg.waist_twist = []
        seg.swing = []
        for tau in seg.sample_times(spine_extra):
            t_out = seg.offset + tau
            pose = seg.lower_pose(tau)
            if seg in rebased:
                # Their legs and spine as they are: the game shows the one-handed walk's instead.
                seg.waist_twist.append(0.0)
                for bone in lower:
                    rot, trans = pose[bone]
                    new_data[bone].quat_keys.append((t_out, E.qnorm(rot), ()))
                    new_data[bone].trans['keys'].append((t_out, tuple(trans), ()))
                continue
            their_spine = pose[M.COMPENSATED_BONE][0]
            ours_world, their_pelvis, theirs_world = M.spine_worlds(ours_kf, seg, tau, pose)
            target = ours_world
            if seg.sway:
                swing = E.qmul(E.qmul(theirs_world, E.qconj(ours_world)), E.qconj(seg.mean_sway))
                seg.swing.append(E.qangle(swing, M.IDENTITY))
                target = E.qmul(E.qslerp(M.IDENTITY, swing, seg.sway), ours_world)
            compensated = E.qmul(E.qconj(their_pelvis), target)
            seg.waist_twist.append(E.qangle(compensated, their_spine))
            pose[M.COMPENSATED_BONE] = (compensated, pose[M.COMPENSATED_BONE][1])
            # What hangs off the spine keeps the place the third person gave it.
            back = E.qmul(E.qconj(compensated), their_spine)
            for child in SPINE_CHILDREN:
                if child in pose:
                    rot, trans = pose[child]
                    pose[child] = (E.qmul(back, rot), E.qrot(back, trans))
            for bone in lower:
                rot, trans = pose[bone]
                new_data[bone].quat_keys.append((t_out, E.qnorm(rot), ()))
                new_data[bone].trans['keys'].append((t_out, tuple(trans), ()))
        for side in sorted(fingers.rest):
            hand = ['Bip01 %s %s' % (side, b) for b in ['Hand'] + fingers.F.FIT_BONES]
            if not all(b in ours_kf.bone_data for b in hand):
                continue
            times = set()
            for b in hand:
                times |= M.key_times(ours_kf.data(b))
            for tau in seg.sample_times(times):
                t_ours = seg.our_time(tau)
                key = (os.path.basename(ours_path), side, round(t_ours, 5))
                if key not in finger_cache:
                    finger_cache[key] = fingers.solve(ours_kf, side, t_ours,
                                                      key=(os.path.basename(ours_path), side))
                rots, error = finger_cache[key]
                fit_errors.append(error)
                for b, rot in rots.items():
                    name = 'Bip01 %s %s' % (side, b)
                    if name not in new_data:
                        continue
                    new_data[name].quat_keys.append((seg.offset + tau, E.qnorm(rot), ()))
                    offset = third_rest.get(name, fingers.rest[side][b][1])
                    new_data[name].trans['keys'].append((seg.offset + tau, tuple(offset), ()))
        for bone, dst in new_data.items():
            if bone in lower or bone in finger_bones:
                continue
            src = ours_kf.data(bone)
            shift = (0.0, 0.0, 0.0)
            if bone in first_rest and bone in third_rest and bone not in WEAPON_BONES:
                shift = tuple(b - a for a, b in zip(first_rest[bone], third_rest[bone]))
            steady = bone == HEAD and seg.name in STEADY_HEAD_GROUPS
            rebase = bone == CHEST and seg in rebased
            for tau in seg.sample_times(M.key_times(src) | (spine_extra if rebase else set())):
                t_ours = seg.our_time(tau)
                t_out = seg.offset + tau
                rot = E.rotation(src, t_ours)
                if rebase and rot is not None:
                    # The chest where ours has it - our spine held upright, as a still segment's
                    # is - but on their average spine rather than on our own.
                    ours_spine = E.qmul(M.pelvis_world_rotation(ours_kf, t_ours),
                                        E.rotation(ours_kf.data(M.COMPENSATED_BONE), t_ours))
                    rot = E.qmul(E.qconj(rebased[seg]), E.qmul(ours_spine, rot))
                if steady:
                    # The neck is where ours puts it (these are still segments: the spine keeps our
                    # orientation), so the head's own turn is what is left to look ahead with.
                    rot = E.qmul(E.qconj(E.world(ours_kf, NECK, t_ours)[0]), head_forward)
                trans = E.translation(src, t_ours)
                scale = E._interp_group(src.scale['keys'], src.scale['itype'], t_ours, 1)
                if rot is not None:
                    dst.quat_keys.append((t_out, E.qnorm(rot), ()))
                if trans is not None:
                    dst.trans['keys'].append((t_out, tuple(a + b for a, b in zip(trans, shift)), ()))
                if scale is not None:
                    dst.scale['keys'].append((t_out, scale, ()))

    for d in new_data.values():
        fixed = []
        for t, q, extra in d.quat_keys:
            if fixed and sum(a * b for a, b in zip(fixed[-1][1], q)) < 0:
                q = tuple(-c for c in q)
            fixed.append((t, q, extra))
        d.quat_keys = thin(fixed, lambda a, b, f: E.qslerp(a, b, f),
                           lambda a, b: E.qangle(a, b) < ANGLE_TOLERANCE)
        d.trans['keys'] = thin(d.trans['keys'], lerp, lambda a, b: max(abs(x - y) for x, y in zip(a, b)) < MOVE_TOLERANCE)
        d.scale['keys'] = thin(d.scale['keys'], lambda a, b, f: a + (b - a) * f, lambda a, b: abs(a - b) < 1e-4)
        if not d.quat_keys:
            d.rot_type = 0
        for channel in ('trans', 'scale'):
            if not d.__dict__[channel]['keys']:
                d.__dict__[channel] = {'itype': 0, 'keys': []}

    for bone, di in ours_kf.bone_data.items():
        t, _ = ours_kf.blocks[di]
        ours_kf.blocks[di] = (t, new_data[bone])
    end = segments[-1].offset + segments[-1].length
    for t, p in ours_kf.blocks:
        if t == 'NiKeyframeController':
            p['start'] = 0.0
            p['stop'] = end

    # Each group's own keys, and every other key (sounds) in its range, per segment.
    sep = '\r\n' if any('\r\n' in s for _, s in ours_kf.text_keys()) else '\n'
    by_time = {}
    for seg in segments:
        for tm, line in our_lines:
            name, key = M.split_line(line) if ':' in line else (None, None)
            if name == seg.name:
                tau = seg.group_key_time(key)
                taus = [tau] if tau is not None else seg.local_times_of(tm)[:1]
            elif name not in our_groups:
                taus = seg.local_times_of(tm)
            else:
                continue
            for tau in taus:
                lines = by_time.setdefault(round(seg.offset + tau, 5), [])
                if line not in lines:
                    lines.append(line)
    tk = ours_kf.blocks[ours_kf.textkey_block][1]
    tk['keys'] = [(t, footstep_refs.to_ref(sep.join(lines))) for t, lines in sorted(by_time.items())]

    ours_kf.save(out_path)
    return segments


if __name__ == '__main__':
    main()

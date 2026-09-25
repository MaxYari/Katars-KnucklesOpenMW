"""Brings ReAnimation's hand-to-hand [Raw] actions into this blend as the katar moveset.

The Blender half of Sources/Tools/import_h2h_set.py, which does the same to the exported .kf files -
so the rig, not only the export, carries the katar moveset:

1. Appends every "[Raw] h2h ..." action from ReAnimation's source blend as "[Raw] Katar ...", the
   names the exports go out under (xKatarChop.kf and so on).
2. Renames their text-key markers' groups: HandToHand -> Katar, Idlehh -> Idlekatar,
   RunForwardhh -> RunForwardkatar and so on. SoundGen stays.
3. Holds the 'Weapon Bone' controller at the katar's seat - the pose the existing katar actions key
   it at, which the weapons are modelled for. ReAnimation's hand-to-hand actions leave it at rest.
4. Keys the 'Weapon Bone.L' controller at that seat mirrored into the left hand, plus the katar's
   half turn about its blade - what mirror_weapon_track.py writes into the exported track, so the
   preview here is what the game shows. The bone's rest is the plain mirror (add_weapon_bone_l.py);
   the turn is the katar's, so it lives in the katar's actions. Worked out on the evaluated Bip01
   pose, so the controller ends up wherever the deform bone needs it.

An existing action this would overwrite is kept, renamed "<name> (old)". Run it again and it replaces
only what it made itself (tagged h2h_import), so nothing drifts and nothing of yours is lost.

    blender -b "Reanimv  starts Katsr.blend" --python Sources/Tools/import_h2h_actions.py -- \\
        --source "<ReAnimation>/Sources/Reanimv3.blend" --save
"""
import math
import re
import sys

import bpy
from bpy_extras.io_utils import axis_conversion
from mathutils import Matrix

ACTIONS = {
    "[Raw] h2h Chop": "[Raw] Katar Chop",
    "[Raw] h2h Chop Mirrored": "[Raw] Katar Chop Mirrored",
    "[Raw] h2h Slash": "[Raw] Katar Slash",
    "[Raw] h2h Slash Mirrored": "[Raw] Katar Slash Mirrored",
    "[Raw] h2h Thrust": "[Raw] Katar Thrust",
    "[Raw] h2h Thrust Mirrored": "[Raw] Katar Thrust Mirrored",
    "[Raw] h2h Eq Uneq": "[Raw] Katar Eq Uneq",
    "[Raw] h2h Idle": "[Raw] Katar Idle",
    "[Raw] h2h Idle Sneak": "[Raw] Katar Idle Sneak",
    "[Raw] h2h Jump": "[Raw] Katar Jump",
    "[Raw] h2h Walk": "[Raw] Katar Walk",
    "[Raw] h2h Sneak": "[Raw] Katar Sneak",
}
GROUPS = {
    "handtohand": "Katar",
    "handtohandalt": "KatarAlt",
    "idlehh": "Idlekatar",
    "idlehhsneak": "IdlekatarSneak",
    "jumphh": "Jumpkatar",
}
MOVE_GROUP = re.compile(r"^((?:walk|run|sneak)(?:forward|back|left|right))hh$", re.I)
KEEP = {"soundgen"}
TAG = "h2h_import"

RIGHT, LEFT = "Weapon Bone", "Weapon Bone.L"
HAND_R, HAND_L = "Bip01 Hand.R", "Bip01 Hand.L"
SEAT_FROM = "[Raw] Katar Idle"
MIRRORED = ["UpperArm", "Forearm", "Hand", "Finger0", "Finger1", "Finger2", "Finger3", "Finger4",
            "Thigh", "Calf", "Foot", "Toe0"]

# io_scene_mw's import axis corrections - "Bip01" bones one way, the weapon bones another - which
# put the .nif's mirror and half turn on different axes here (see add_weapon_bone_l.py).
BIPED_AXES = axis_conversion('-X', 'Z', 'Y', 'Z').to_4x4()
OTHER_AXES = axis_conversion('Y', 'Z', '-Z', '-Y').to_4x4()
KATAR_TURN = Matrix.Diagonal((1.0, -1.0, -1.0, 1.0))  # about the blade, X - mirror_bone.SPIN_AXIS


def args():
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    out = {"source": None, "save": False}
    i = 0
    while i < len(argv):
        if argv[i] == "--source":
            out["source"] = argv[i + 1]
            i += 1
        elif argv[i] == "--save":
            out["save"] = True
        i += 1
    if not out["source"]:
        sys.exit("give --source <ReAnimation's Reanimv3.blend>")
    return out


def fcurves(action):
    for layer in action.layers:
        for strip in layer.strips:
            for slot in action.slots:
                bag = strip.channelbag(slot)
                if bag:
                    yield from bag.fcurves


def bone_curves(action, bone):
    """The bone's transform curves (its custom properties, like ARP's "cc", are left alone)."""
    prefix = 'pose.bones["%s"].' % bone
    return [fc for fc in fcurves(action) if fc.data_path.startswith(prefix)]


def remove_bone_curves(action, bone):
    prefix = 'pose.bones["%s"].' % bone
    for layer in action.layers:
        for strip in layer.strips:
            for slot in action.slots:
                bag = strip.channelbag(slot)
                if bag:
                    for fc in [fc for fc in bag.fcurves if fc.data_path.startswith(prefix)]:
                        bag.fcurves.remove(fc)


def rename_group(group):
    key = group.strip().lower()
    if key in KEEP:
        return group
    if key in GROUPS:
        return GROUPS[key]
    m = MOVE_GROUP.match(group.strip())
    if m:
        return m.group(1) + "katar"
    sys.exit("marker group %r has no katar name - add it to GROUPS" % group)


def rename_markers(action):
    n = 0
    for marker in action.pose_markers:
        if ":" not in marker.name:
            continue
        group, rest = marker.name.split(":", 1)
        new = rename_group(group) + ":" + rest
        if new != marker.name:
            marker.name = new
            n += 1
    return n


def read_seat(action):
    """{(property, index): value} of the right weapon bone, which the katar actions hold constant."""
    seat = {}
    for fc in bone_curves(action, RIGHT):
        prop = fc.data_path.split("].", 1)[1]
        values = [k.co[1] for k in fc.keyframe_points]
        if values and max(values) - min(values) > 1e-4:
            sys.exit("%s moves %s.%s[%d] - the seat has to be a single pose"
                     % (action.name, RIGHT, prop, fc.array_index))
        if values:
            seat[(prop, fc.array_index)] = values[0]
    return seat


def apply_seat(action, seat):
    for fc in bone_curves(action, RIGHT):
        prop = fc.data_path.split("].", 1)[1]
        value = seat.get((prop, fc.array_index))
        if value is None:
            continue
        for key in fc.keyframe_points:
            key.co[1] = value
            key.handle_left[1] = value
            key.handle_right[1] = value
        fc.update()


def fit_signs(bip):
    def local(name):
        bone = bip.data.bones[name]
        return bone.parent.matrix_local.inverted() @ bone.matrix_local if bone.parent else bone.matrix_local
    pairs = [(local("Bip01 %s.L" % b), local("Bip01 %s.R" % b)) for b in MIRRORED
             if "Bip01 %s.L" % b in bip.data.bones and "Bip01 %s.R" % b in bip.data.bones]
    scored = []
    for sx in (1, -1):
        for sy in (1, -1):
            for sz in (1, -1):
                S = Matrix.Diagonal((sx, sy, sz, 1.0))
                err = sum(max(abs(L[r][c] - (S @ R @ S)[r][c]) for r in range(4) for c in range(4))
                          for L, R in pairs) / len(pairs)
                scored.append((err, S))
    scored.sort(key=lambda s: s[0])
    return scored[0][1]


def main():
    opts = args()
    rig = bpy.data.objects["rig"]
    bip = bpy.data.objects["Bip01"]
    scene = bpy.context.scene

    # The seat comes from the katar actions this blend already has - the originals, whatever they are
    # called by now - before anything is renamed or replaced.
    seat_action = bpy.data.actions.get(SEAT_FROM + " (old)") or bpy.data.actions.get(SEAT_FROM)
    if seat_action is None:
        sys.exit("no %r to take the weapon bone's seat from" % SEAT_FROM)
    seat = read_seat(seat_action)
    print("seat from %r: %s" % (seat_action.name, {k: round(v, 4) for k, v in sorted(seat.items())}))

    # Make room: what this script made before goes; anything else under a wanted name is kept, as old.
    for target in ACTIONS.values():
        existing = bpy.data.actions.get(target)
        if existing is None:
            continue
        if existing.get(TAG):
            bpy.data.actions.remove(existing)
        else:
            existing.name = target + " (old)"
            existing.use_fake_user = True
            print("kept %r as %r" % (target, existing.name))

    with bpy.data.libraries.load(opts["source"], link=False) as (src, dst):
        missing = [name for name in ACTIONS if name not in src.actions]
        if missing:
            sys.exit("not in the source blend: %s" % missing)
        dst.actions = list(ACTIONS)

    # The mirror, fitted from the rig as add_weapon_bone_l.py fits it: the hand's flip on the hand's
    # side, the same flip carried into the weapon bone's axes on the other, then the katar's turn.
    S = fit_signs(bip)
    weapon_signs = OTHER_AXES.inverted() @ BIPED_AXES @ S @ BIPED_AXES.inverted() @ OTHER_AXES
    turn = OTHER_AXES.inverted() @ KATAR_TURN @ OTHER_AXES
    mirror = lambda right_in_hand: S @ right_in_hand @ weapon_signs @ turn

    rest = lambda name: bip.data.bones[name].matrix_local
    plain = S @ (rest(HAND_R).inverted() @ rest(RIGHT)) @ weapon_signs
    off = plain.inverted() @ (rest(HAND_L).inverted() @ rest(LEFT))
    print("mirror signs %s; the left bone's rest is %.1f degrees off the plain mirror%s"
          % (tuple(int(S[i][i]) for i in range(3)), math.degrees(off.to_quaternion().angle),
             "" if off.to_quaternion().angle < 1e-3 else " - run add_weapon_bone_l.py"))

    # The rig lives in collections disabled in viewports, which the depsgraph then skips; they are
    # switched on for the work and back off before saving.
    hidden = [c for ob in (rig, bip) for c in ob.users_collection if c.hide_viewport]
    for collection in hidden:
        collection.hide_viewport = False

    # Evaluated poses: in the background, the original objects' pose matrices keep whatever the file
    # was saved with.
    bip_eval = lambda: bip.evaluated_get(bpy.context.evaluated_depsgraph_get())
    pose = lambda name: bip_eval().pose.bones[name].matrix

    previous = rig.animation_data.action if rig.animation_data else None
    slot_id = (rig.animation_data.action_slot.identifier
               if rig.animation_data and rig.animation_data.action_slot else "OBSlot 1")
    left_pb = rig.pose.bones[LEFT]

    for loaded in dst.actions:
        source_name = next(k for k in ACTIONS if loaded.name == k or loaded.name.startswith(k + "."))
        target = ACTIONS[source_name]
        loaded.name = target
        loaded[TAG] = True
        loaded.use_fake_user = True
        renamed = rename_markers(loaded)
        apply_seat(loaded, seat)

        # Any left weapon bone keys the source had would hold the fist's rest; they are replaced below.
        remove_bone_curves(loaded, LEFT)

        rig.animation_data_create()
        rig.animation_data.action = loaded
        # The slot the rig plays its actions through; "Idle Sneak" carries a stray second one.
        slot = next((s for s in loaded.slots if s.identifier == slot_id), None) or loaded.slots[0]
        rig.animation_data.action_slot = slot
        first, last = int(loaded.frame_range[0]), int(loaded.frame_range[1])
        scene.frame_set(first)
        right_in_hand = pose(HAND_R).inverted() @ pose(RIGHT)
        wanted = pose(HAND_L) @ mirror(right_in_hand)
        # The controller's own transform that puts it there (Bip01's bone copies its world transform),
        # worked out against the evaluated hand, not the stale one on the original object.
        rig_eval = rig.evaluated_get(bpy.context.evaluated_depsgraph_get())
        in_rig = rig_eval.matrix_world.inverted() @ bip_eval().matrix_world @ wanted
        left_pb.matrix_basis = rig_eval.convert_space(pose_bone=rig_eval.pose.bones[LEFT], matrix=in_rig,
                                                      from_space='POSE', to_space='LOCAL')

        rotation = "rotation_quaternion" if left_pb.rotation_mode == "QUATERNION" else (
            "rotation_axis_angle" if left_pb.rotation_mode == "AXIS_ANGLE" else "rotation_euler")
        for frame in sorted({first, last}):
            for prop in ("location", rotation, "scale"):
                left_pb.keyframe_insert(prop, frame=frame, group=LEFT)

        # Check it on the deform bone, where the export reads it - played back from the keys.
        scene.frame_set(last)
        scene.frame_set(first)
        got = pose(HAND_L).inverted() @ pose(LEFT)
        want = mirror(right_in_hand)
        err = max(abs(got[r][c] - want[r][c]) for r in range(4) for c in range(4))
        print("%-26s -> %-28s %2d markers renamed, seat held, %s keyed (off by %.5f)"
              % (source_name, target, renamed, LEFT, err))
        if err > 1e-3:
            sys.exit("the left weapon bone did not land where it should in %s" % target)

    # Back to the action that was open - or, if it was one of the katar actions just replaced, its
    # replacement.
    if previous is not None:
        name = previous.name[:-len(" (old)")] if previous.name.endswith(" (old)") else previous.name
        rig.animation_data.action = bpy.data.actions.get(name) or previous
        action = rig.animation_data.action
        rig.animation_data.action_slot = next(
            (s for s in action.slots if s.identifier == slot_id), None) or action.slots[0]
        scene.frame_set(int(action.frame_range[0]))

    for collection in hidden:
        collection.hide_viewport = True

    if opts["save"]:
        bpy.ops.wm.save_mainfile()
        print("saved", bpy.data.filepath)


main()

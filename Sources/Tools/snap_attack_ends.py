"""Ends every katar attack on the pose [Raw] Katar Idle starts on.

When an attack's follow-through is over the engine goes back to the idle, so an attack whose last
frame is some other pose jumps to it. ReAnimation's chop and thrust end on it. The slash started and
ended on an older idle, and the mirrored attacks on the idle mirrored: hands rolled 20 degrees, head
turned 11.

In each attack ([Raw] Katar Chop, Slash and Thrust, and their Mirrored), the last key and every other
key holding the same pose (the slash's first and second-to-last) get the values Idle keys at its first
frame. Every channel, but for:

- the arms' IK/FK switch: the attacks swing the arms in FK, and Idle keeps its FK controllers on the
  pose its IK arms make, so they carry over as they are;
- the weapon seat, 'Weapon Bone' and 'Weapon Bone.L' - reseat_weapon_bones.py's;
- constraint switches, and channels Idle does not key.

It checks the result on the evaluated Bip01 pose, which is what the export reads. Run it again after
changing Idle's first frame; running it twice changes nothing the second time. The "(old)" actions
import_h2h_actions.py keeps are left alone. Then export as usual (export_katar_anims.py, then
make_third_person_anims.py).

From Blender: Text Editor > Open this file, Run Script, then save the .blend. Headless:
    blender -b "Reanimv  starts Katsr.blend" --python Sources/Tools/snap_attack_ends.py -- --save
"""
import importlib
import math
import pathlib
import sys

import bpy

ATTACKS = ["[Raw] Katar %s%s" % (attack, side) for attack in ("Chop", "Slash", "Thrust")
           for side in ("", " Mirrored")]
# A key holding the attack's last pose to within this is snapped along with it.
SAME_POSE_DEGREES = 2.5
SAME_POSE_DISTANCE = 0.005
# What the snapped pose may be off the idle's by, on any Bip01 bone.
MAX_DEGREES = 0.5
MAX_DISTANCE = 1e-3
LOG = []


def log(msg):
    LOG.append(msg)
    print(msg)


def _tools_dir():
    """Where import_h2h_actions.py is. Run from the Text Editor, __file__ is the .blend's path with
    the text's name on the end, so beside the opened file and Sources/Tools next to the .blend are
    tried too."""
    here = pathlib.Path(__file__)
    candidates = [here.resolve().parent]
    text = bpy.data.texts.get(here.name)
    if text is not None and text.filepath:
        candidates.append(pathlib.Path(bpy.path.abspath(text.filepath)).resolve().parent)
    if bpy.data.filepath:
        candidates.append(pathlib.Path(bpy.data.filepath).resolve().parent / "Sources" / "Tools")
    for folder in candidates:
        if (folder / "import_h2h_actions.py").is_file():
            return folder
    raise ImportError("import_h2h_actions.py not found -- looked in "
                      + ", ".join(str(c) for c in candidates))


if str(_tools_dir()) not in sys.path:
    sys.path.insert(0, str(_tools_dir()))
import import_h2h_actions as h2h  # noqa: E402
h2h = importlib.reload(h2h)

SKIP_BONES = (h2h.RIGHT, h2h.LEFT)


def snapped(fc):
    """Whether this channel takes Idle's value."""
    path = fc.data_path
    if path.endswith('["ik_fk_switch"]') or ".constraints[" in path:
        return False
    return not any(path.startswith('pose.bones["%s"]' % bone) for bone in SKIP_BONES)


def bone_of(fc):
    return fc.data_path.split('"')[1] if fc.data_path.startswith('pose.bones["') else None


def play(rig, action, slot_id):
    rig.animation_data.action = action
    rig.animation_data.action_slot = next(
        (s for s in action.slots if s.identifier == slot_id), None) or action.slots[0]


def bip_pose(bip, frame):
    """Every Bip01 bone's evaluated matrix at this frame - the pose the export reads."""
    bpy.context.scene.frame_set(int(frame))
    evaluated = bip.evaluated_get(bpy.context.evaluated_depsgraph_get())
    return {pb.name: pb.matrix.copy() for pb in evaluated.pose.bones}


def pose_gap(a, b):
    """The largest turn (degrees) and shift any bone has between two poses, and which bone."""
    worst = (0.0, 0.0, "")
    for name, m in a.items():
        n = b[name]
        turn = math.degrees(m.to_quaternion().rotation_difference(n.to_quaternion()).angle)
        turn = min(turn, 360.0 - turn)
        shift = (m.translation - n.translation).length
        if (turn, shift) > worst[:2]:
            worst = (turn, shift, name)
    return worst


def close(gap, degrees, distance):
    return gap[0] <= degrees and gap[1] <= distance


def key_frames(action):
    return sorted({round(kp.co[0]) for fc in h2h.fcurves(action) for kp in fc.keyframe_points})


def set_key(fc, frame, value):
    """Puts the key at this frame at `value`, the handles moved with it; adds one if there is none.
    Returns how far it moved."""
    for kp in fc.keyframe_points:
        if abs(kp.co[0] - frame) < 1e-3:
            delta = value - kp.co[1]
            kp.co[1] = value
            kp.handle_left[1] += delta
            kp.handle_right[1] += delta
            return abs(delta)
    fc.keyframe_points.insert(frame, value, options={"FAST"})
    return abs(value - fc.evaluate(frame))


def quaternion_sign(action, bone, frame, target, frames):
    """+1 or -1: whichever way round Idle's quaternion is nearer the attack's own neighbouring key, so
    it doesn't turn the long way round into it."""
    others = [f for f in frames if f != frame]
    if not others:
        return 1.0
    near = max((f for f in others if f < frame), default=min(others))
    curves = {fc.array_index: fc for fc in h2h.fcurves(action)
              if fc.data_path == 'pose.bones["%s"].rotation_quaternion' % bone}
    dot = sum(target[i] * curves[i].evaluate(near) for i in range(4) if i in curves and i in target)
    return -1.0 if dot < 0 else 1.0


def snap(action, idle_values, frames):
    """Gives the action Idle's values at these frames. Returns how many keys moved."""
    moved = 0
    quaternions = {}
    for (path, index), value in idle_values.items():
        if path.endswith(".rotation_quaternion"):
            quaternions.setdefault(path.split('"')[1], {})[index] = value
    for frame in frames:
        signs = {bone: quaternion_sign(action, bone, frame, q, frames) for bone, q in quaternions.items()}
        for fc in h2h.fcurves(action):
            value = idle_values.get((fc.data_path, fc.array_index))
            if value is None or not snapped(fc):
                continue
            if fc.data_path.endswith(".rotation_quaternion"):
                value *= signs.get(bone_of(fc), 1.0)
            if set_key(fc, frame, value) > 1e-6:
                moved += 1
    for fc in h2h.fcurves(action):
        fc.update()
    return moved


def launched_with_save():
    argv = sys.argv
    if "--" not in argv:
        return False
    head = argv[:argv.index("--")]
    if not any(pathlib.Path(a).name == pathlib.Path(__file__).name for a in head):
        return False
    return "--save" in argv[argv.index("--") + 1:]


def main():
    rig = bpy.data.objects["rig"]
    bip = bpy.data.objects["Bip01"]
    if bpy.context.object and bpy.context.object.mode != "OBJECT":
        bpy.ops.object.mode_set(mode="OBJECT")

    idle = bpy.data.actions.get(h2h.SEAT_FROM)
    if idle is None:
        raise RuntimeError("no %r in this blend" % h2h.SEAT_FROM)
    missing = [name for name in ATTACKS if name not in bpy.data.actions]
    if missing:
        raise RuntimeError("not in this blend: %s" % ", ".join(missing))
    start = idle.frame_range[0]
    idle_values = {(fc.data_path, fc.array_index): fc.evaluate(start) for fc in h2h.fcurves(idle)}

    scene = bpy.context.scene
    frame_was = scene.frame_current
    hidden = h2h.show_rig(rig, bip)
    previous = rig.animation_data.action if rig.animation_data else None
    slot_id = h2h.rig_slot(rig)
    try:
        play(rig, idle, slot_id)
        target = bip_pose(bip, start)
        log("the idle's pose: %r, frame %d" % (idle.name, start))
        for name in ATTACKS:
            action = bpy.data.actions[name]
            play(rig, action, slot_id)
            frames = key_frames(action)
            end = frames[-1]
            last = bip_pose(bip, end)
            before = pose_gap(last, target)
            holding = [f for f in frames
                       if close(pose_gap(bip_pose(bip, f), last), SAME_POSE_DEGREES, SAME_POSE_DISTANCE)]
            moved = snap(action, idle_values, holding)
            play(rig, action, slot_id)
            worst = max((pose_gap(bip_pose(bip, f), target) for f in holding), key=lambda g: g[:2])
            log("  %-28s frames %-12s %s, was off by %.1f deg (%s), now %.2f deg / %.4f (%s)"
                % (name, ",".join(str(f) for f in holding),
                   "%d keys moved" % moved if moved else "already on it",
                   before[0], before[2], worst[0], worst[1], worst[2] or "-"))
            if not close(worst, MAX_DEGREES, MAX_DISTANCE):
                raise RuntimeError("%s did not land on the idle's pose: %s off by %.2f deg / %.4f"
                                   % (name, worst[2], worst[0], worst[1]))
    finally:
        h2h.restore_action(rig, previous, slot_id)
        scene.frame_set(frame_was)
        for collection in hidden:
            collection.hide_viewport = True

    if launched_with_save():
        bpy.ops.wm.save_mainfile()
        log("saved %s" % bpy.data.filepath)
    elif bpy.app.background:
        log("not saved -- pass --save")
    else:
        log("done -- save the .blend to keep it")


def show_in_blender(failed):
    def draw(self, _context):
        for line in LOG:
            self.layout.label(text=line)
    bpy.context.window_manager.popup_menu(draw, title="snap_attack_ends: "
                                          + ("stopped" if failed else "done"),
                                          icon="ERROR" if failed else "INFO")


if __name__ == "__main__":
    LOG.clear()
    try:
        main()
    except RuntimeError as exc:
        log("ERROR: %s" % exc)
        if bpy.app.background:
            raise SystemExit(1)
        show_in_blender(True)
    else:
        if not bpy.app.background:
            show_in_blender(False)

"""Gives the katar's moves the katar idle's wider guard: each is its knuckle move, corrected.

[Raw] Katar Idle is [Raw] Knuckle Idle with the hands set further apart and its keys otherwise the
same: the right hand moved by the corrector it follows ('Hand Position Tweaker'), the left by one of
its own ('Hand Position Tweaker L', which it follows through 'Left Hand Follow Left Position Tweaker'
in place of the shared one), and the elbow poles and forearm twists set to suit. For each katar move
below, made from the knuckle move beside it:

1. a katar move that is not in the blend yet is made as a copy of its knuckle move, the markers'
   groups renamed (Jumpknuckle -> Jumpkatar, RunForwardKnuckle -> RunForwardKatar);
2. both correctors are posed so that each hand moves as it does from the knuckle idle to the katar
   idle - the idle's correction on top of wherever the knuckle move has the shared corrector, or of
   none where that hand does not follow it - and the hands follow them as in the katar idle;
3. every other channel the two idles hold at different values (the poles, the twists) takes the
   katar idle's value. The knuckle move has to hold the knuckle idle's value there.

Only those channels are written: anything else changed in a katar move stays. Delete a katar move
and run this again to make it afresh from its knuckle move. Running it twice changes nothing.

This is the blend only. Afterwards make_katar_1h_movement.py lays the walk and sneak out the
one-handed way, then export (export_katar_anims.py).

From Blender: Text Editor > Open this file, Run Script, then save the .blend. Headless:
    blender -b "Sources/Katars and animations.blend" --python Sources/Tools/widen_katar_moves.py -- --save
"""
import pathlib
import re
import sys

import bpy
from mathutils import Matrix, Quaternion, Vector

KNUCKLE_IDLE, KATAR_IDLE = "[Raw] Knuckle Idle", "[Raw] Katar Idle"
# katar move: the knuckle move it is made from
MOVES = {
    "[Raw] Katar Idle Sneak": "[Raw] Knuckle Idle Sneak",
    "[Raw] Katar Jump": "[Raw] Knuckle Jump",
    "[Raw] Katar Walk": "[Raw] Knuckle Walk",
    "[Raw] Katar Sneak": "[Raw] Knuckle Sneak",
}
SHARED, OWN_L = "Hand Position Tweaker", "Hand Position Tweaker L"
RIGHT_FOLLOWS = 'pose.bones["c_hand_ik.r"].constraints["Follow Position Tweaker"].enabled'
LEFT_FOLLOWS_SHARED = 'pose.bones["c_hand_ik.l"].constraints["Left Hand Follow Position Tweaker"].enabled'
LEFT_FOLLOWS_OWN = 'pose.bones["c_hand_ik.l"].constraints["Left Hand Follow Left Position Tweaker"].enabled'
SWITCHES = (RIGHT_FOLLOWS, LEFT_FOLLOWS_SHARED, LEFT_FOLLOWS_OWN)
TRANSFORM = (("location", 3), ("rotation_quaternion", 4), ("scale", 3))
TOLERANCE = 1e-5
LOG = []


def log(msg):
    LOG.append(msg)
    print(msg)


def bone_of(path):
    m = re.match(r'pose\.bones\["(.+?)"\]', path)
    return m.group(1) if m else None


def channelbags(action):
    """{slot identifier: channelbag}"""
    out = {}
    for layer in action.layers:
        for strip in layer.strips:
            for slot in action.slots:
                bag = strip.channelbag(slot)
                if bag is not None:
                    out[slot.identifier] = bag
    return out


def held(fc):
    """The value a curve holds through the action, or None if it moves. One key holds whatever its
    handles say, unless the curve extrapolates them."""
    value = fc.keyframe_points[0].co[1]
    if len(fc.keyframe_points) == 1 and fc.extrapolation == "CONSTANT":
        return value
    for k in fc.keyframe_points:
        ys = [k.co[1]] + ([k.handle_left[1], k.handle_right[1]] if k.interpolation == "BEZIER" else [])
        if any(abs(y - value) > TOLERANCE for y in ys):
            return None
    return value


def held_value(action, bag, path, index=0, default=None):
    fc = bag.fcurves.find(path, index=index)
    if fc is None or not len(fc.keyframe_points):
        if default is None:
            raise RuntimeError("%r does not key %s[%d]" % (action.name, path, index))
        return default
    value = held(fc)
    if value is None:
        raise RuntimeError("%r moves %s[%d] - only a corrector held still is handled" % (action.name, path, index))
    return value


def follows(action, bag, path):
    return held_value(action, bag, path) > 0.5


def basis(action, bag, bone):
    """The corrector's own pose (its local transform) as a matrix. Unkeyed is the rest pose."""
    rest = {"location": (0.0, 0.0, 0.0), "rotation_quaternion": (1.0, 0.0, 0.0, 0.0), "scale": (1.0, 1.0, 1.0)}
    v = {prop: [held_value(action, bag, 'pose.bones["%s"].%s' % (bone, prop), i, rest[prop][i])
                for i in range(n)] for prop, n in TRANSFORM}
    return Matrix.LocRotScale(Vector(v["location"]), Quaternion(v["rotation_quaternion"]).normalized(),
                              Vector(v["scale"]))


def pose_values(matrix):
    loc, rot, scale = matrix.decompose()
    if rot.w < 0:
        rot.negate()
    return {"location": tuple(loc), "rotation_quaternion": tuple(rot), "scale": tuple(scale)}


def write_held(action, bag, path, index, value):
    """Every key of the curve to this value, or a new curve with one key at the action's start."""
    fc = bag.fcurves.find(path, index=index)
    if fc is None:
        fc = bag.fcurves.new(path, index=index)
        bone = bone_of(path)
        if bone:
            fc.group = bag.groups.get(bone) or bag.groups.new(bone)
        fc.keyframe_points.insert(action.frame_range[0], value, options={"FAST"})
    for k in fc.keyframe_points:
        k.co[1] = value
        k.handle_left[1] = value
        k.handle_right[1] = value
    fc.update()


def single_bag(action):
    bags = channelbags(action)
    if len(bags) != 1:
        raise RuntimeError("%r has %d slots - the idles are read from one" % (action.name, len(bags)))
    return next(iter(bags.values()))


def correction():
    """What takes the knuckle idle to the katar idle: (right hand's corrector matrix, left hand's,
    {(path, index): katar idle's value} for the rest)."""
    knuckle, katar = (bpy.data.actions.get(n) for n in (KNUCKLE_IDLE, KATAR_IDLE))
    if knuckle is None or katar is None:
        raise RuntimeError("needs both %r and %r" % (KNUCKLE_IDLE, KATAR_IDLE))
    kb, wb = single_bag(knuckle), single_bag(katar)
    if not (follows(knuckle, kb, RIGHT_FOLLOWS) and follows(knuckle, kb, LEFT_FOLLOWS_SHARED)
            and not follows(knuckle, kb, LEFT_FOLLOWS_OWN)):
        raise RuntimeError("%r: both hands should follow the shared corrector, and the left not its own"
                           % knuckle.name)
    if not (follows(katar, wb, RIGHT_FOLLOWS) and not follows(katar, wb, LEFT_FOLLOWS_SHARED)
            and follows(katar, wb, LEFT_FOLLOWS_OWN)):
        raise RuntimeError("%r: the right hand should follow the shared corrector and the left its own"
                           % katar.name)
    narrow = basis(knuckle, kb, SHARED).inverted()
    right, left = basis(katar, wb, SHARED) @ narrow, basis(katar, wb, OWN_L) @ narrow

    others = {}
    theirs = {(fc.data_path, fc.array_index): fc for fc in kb.fcurves}
    ours = {(fc.data_path, fc.array_index): fc for fc in wb.fcurves}
    for key in sorted(set(theirs) | set(ours)):
        path, index = key
        if path in SWITCHES or bone_of(path) in (SHARED, OWN_L):
            continue
        if key not in theirs or key not in ours:
            raise RuntimeError("%s[%d] is keyed in only one of the two idles" % key)
        a, b = held(theirs[key]), held(ours[key])
        if a is not None and b is not None:
            if abs(a - b) > TOLERANCE:
                others[key] = (a, b)
        elif [tuple(k.co) for k in theirs[key].keyframe_points] != [tuple(k.co) for k in ours[key].keyframe_points]:
            raise RuntimeError("the two idles move %s[%d] differently - only a held correction can be "
                               "carried over" % key)
    return right, left, others


def katar_group(group):
    return group.replace("Knuckle", "Katar").replace("knuckle", "katar")


def make_move(name, source):
    action = source.copy()
    action.name = name
    action.use_fake_user = True
    for marker in action.pose_markers:
        group, colon, text = marker.name.partition(":")
        if colon:
            marker.name = katar_group(group) + colon + text
    return action


def widen(target, source, right, left, others):
    source_bags = channelbags(source)
    for slot, bag in channelbags(target).items():
        if slot not in source_bags:
            raise RuntimeError("%r has a slot %r its knuckle move %r has not" % (target.name, slot, source.name))
        src = source_bags[slot]
        if follows(source, src, LEFT_FOLLOWS_OWN):
            raise RuntimeError("%r has the left hand on its own corrector already" % source.name)
        shared = basis(source, src, SHARED)
        on_right = shared if follows(source, src, RIGHT_FOLLOWS) else Matrix.Identity(4)
        on_left = shared if follows(source, src, LEFT_FOLLOWS_SHARED) else Matrix.Identity(4)
        for bone, matrix in ((SHARED, right @ on_right), (OWN_L, left @ on_left)):
            for prop, values in pose_values(matrix).items():
                for i, value in enumerate(values):
                    write_held(target, bag, 'pose.bones["%s"].%s' % (bone, prop), i, value)
        for path, value in ((RIGHT_FOLLOWS, 1.0), (LEFT_FOLLOWS_SHARED, 0.0), (LEFT_FOLLOWS_OWN, 1.0)):
            write_held(target, bag, path, 0, value)
        for (path, index), (narrow, wide) in others.items():
            if abs(held_value(source, src, path, index) - narrow) > TOLERANCE:
                raise RuntimeError("%r holds %s[%d] otherwise than %r does - widen it by hand"
                                   % (source.name, path, index, KNUCKLE_IDLE))
            write_held(target, bag, path, index, wide)


def launched_with_save():
    argv = sys.argv
    if "--" not in argv:
        return False
    head = argv[:argv.index("--")]
    if not any(pathlib.Path(a).name == pathlib.Path(__file__).name for a in head):
        return False
    return "--save" in argv[argv.index("--") + 1:]


def main():
    right, left, others = correction()
    log("the katar idle's correction: right hand %s, left hand %s; also %s"
        % (shown(right), shown(left), ", ".join("%s[%d]" % k for k in sorted(others)) or "nothing else"))
    for name, source_name in MOVES.items():
        source = bpy.data.actions.get(source_name)
        if source is None:
            raise RuntimeError("no %r to make %r from" % (source_name, name))
        target = bpy.data.actions.get(name)
        made = target is None
        if made:
            target = make_move(name, source)
        widen(target, source, right, left, others)
        log("  %-24s %s %r" % (name, "made from" if made else "corrected over", source_name))

    if launched_with_save():
        bpy.ops.wm.save_mainfile()
        log("saved %s" % bpy.data.filepath)
    elif bpy.app.background:
        log("not saved -- pass --save")
    else:
        log("done -- save the .blend to keep it")


def shown(matrix):
    loc, rot, _scale = matrix.decompose()
    return "(%.4f, %.4f, %.4f) and %.1f deg" % (*loc, rot.angle * 57.29578)


def show_in_blender(failed):
    def draw(self, _context):
        for line in LOG:
            self.layout.label(text=line)
    bpy.context.window_manager.popup_menu(draw, title="widen_katar_moves: " + ("stopped" if failed else "done"),
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

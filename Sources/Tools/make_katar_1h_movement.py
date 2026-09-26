"""Lays the katar's walk and sneak out as the first-person one-handed ones are, to play over them.

The katar's walk, run and sneak are each one step cycle - a left foot and a right, 32 frames - and
every group of xKatarMovement.kf and xKatarSneakMovement.kf is one loop of one. A katar is a short
blade, and moves over ReAnimation's short blade set (walkforward1s, sneakforward1s), which is laid
out the same way. Knuckledusters are blunt weapons, which have no set of their own, and move over
the one-handed set (walkforward1h, sneakforward1h), which is not:

    walk and run   an 8-frame lead-in that plays once, then three step cycles to the loop
    sneak          two step cycles to the loop, which starts a frame after a right foot

animations.lua keeps each in step with its parent by how far through its loop each one is, and one
cycle cannot follow two or three: the arms drifted off the footsteps. This lays each katar cycle out
the one-handed way, as "[Raw] Katar Walk 1h" and "[Raw] Katar Sneak 1h":

1. Copies of the cycle back to back, from the phase the one-handed loop starts at, after the lead-in
   where there is one. These are the raw keys themselves, cut exactly where a copy has to begin or
   end, with the cycle's own handles, so every curve is the cycle's - checked by evaluating both.
2. The markers laid out alike: <Move>Katar1h start at 0, loop start after the lead-in, loop stop and
   stop at the end, and the cycle's footsteps in every copy.

The sneak's cycle is also stretched a little, from 32 frames to 34. ReAnimation's moveset builder
makes every direction from the one raw action - sneaking forward at 2.7 times its length, sideways
at 2.5 - and the one-handed sneak's two loops (180 and 172 frames) are not in that proportion. At 34
frames both come within 2%, which the phase sync takes up.

Run it again and it replaces what it made before; an action of one of those names it did not make is
kept, renamed "<name> (old)".

--export then runs ReAnimation's own build_and_export_moveset.py, as its Sources/Reanimv3.blend has
it, on each: baked off the Auto-Rig Pro rig by Bizarre Morrowind Animation Utilities, laid out as
every direction by the build_moveset_action.py beside it, and exported for the first-person skeleton
- at 30 frames a second, which every .kf is timed at; this file's scene runs at 25. Each file then
gets Weapon Bone.L's track from mirror_weapon_track.py, its footsteps made references that sound
nothing by footstep_refs.py - the one-handed set underneath sounds its own - and its step cycles,
footsteps and loop lengths are checked against the one-handed set's. The export changes the file in memory, so --save
saves first.

    blender -b "Reanimv  starts Katsr.blend" --python Sources/Tools/make_katar_1h_movement.py -- \\
        --save --export Animations/xbase_anim.1st
"""
import os
import shutil
import sys
import tempfile

import bpy

HERE = os.path.dirname(os.path.abspath(__file__))
MOD = os.path.normpath(os.path.join(HERE, "..", ".."))

# Frames are the source cycle's. `start` is the phase of the cycle the loop starts at, `lead_in` how
# much of the cycle before it plays once first, and `length` a cycle's frames in the new action.
LAYOUTS = [
    {"source": "[Raw] Katar Walk", "target": "[Raw] Katar Walk 1h",
     "group": "RunForwardkatar", "new_group": "RunForwardKatar1h",
     "lead_in": 8, "start": 0, "cycles": 3, "length": 32,
     "out": "xKatar1hMovement", "theirs": "x1hMovement.kf"},
    {"source": "[Raw] Katar Sneak", "target": "[Raw] Katar Sneak 1h",
     "group": "SneakForwardkatar", "new_group": "SneakForwardKatar1h",
     "lead_in": 0, "start": 1, "cycles": 2, "length": 34,
     "out": "xKatar1hSneakMovement", "theirs": "x1hSneakMovement.kf"},
]
TAG = "katar_1h_movement"
TOLERANCE = 1e-5          # how far a laid-out curve may stray from the cycle it came from

ADDON = "BizarreMorrowindAnimatonUtilities"
SCRIPT = "build_and_export_moveset.py"  # a text in ReAnimation's Sources/Reanimv3.blend
FPS = 30
# How far the exported loops may be from the one-handed ones: in length, and in where each footstep
# falls, as parts of the loop. The phase sync takes up the first.
MAX_LENGTH_OFF = 0.05
MAX_STEP_OFF = 0.02

KEY_PROPERTIES = ("interpolation", "easing", "type", "amplitude", "back", "period")


def args():
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    out = {"save": False, "export": None, "reanimation": None}
    i = 0
    while i < len(argv):
        if argv[i] == "--save":
            out["save"] = True
        elif argv[i] in ("--export", "--reanimation"):
            out[argv[i][2:]] = os.path.abspath(argv[i + 1])
            i += 1
        i += 1
    return out


def find_reanimation(given):
    if given:
        return given
    mods = os.path.dirname(MOD)
    for name in sorted(os.listdir(mods)):
        if name.lower().startswith("reanimation") and os.path.isfile(
                os.path.join(mods, name, "Sources", "build_moveset_action.py")):
            return os.path.join(mods, name)
    sys.exit("ReAnimation's source folder not found next to this mod - give it with --reanimation")


def fcurves(action):
    for layer in action.layers:
        for strip in layer.strips:
            for slot in action.slots:
                bag = strip.channelbag(slot)
                if bag:
                    yield from bag.fcurves


def is_cyclic(fc):
    return any(m.type == "CYCLES" for m in fc.modifiers)


def snapshot(fc):
    return [{"co": tuple(k.co), "left": tuple(k.handle_left), "right": tuple(k.handle_right),
             "left_type": k.handle_left_type, "right_type": k.handle_right_type,
             "props": {p: getattr(k, p) for p in KEY_PROPERTIES}} for k in fc.keyframe_points]


def moved(key, offset=0.0, scale=1.0):
    def place(point):
        return ((point[0] + offset) * scale, point[1])
    return dict(key, co=place(key["co"]), left=place(key["left"]), right=place(key["right"]))


def lerp(a, b, t):
    return (a[0] + (b[0] - a[0]) * t, a[1] + (b[1] - a[1]) * t)


def cut(keys, frame):
    """The cycle's keys with one more at `frame`, where the segment it falls in is cut in two the way
    de Casteljau cuts a Bezier, so that neither half changes shape. The handles are Blender's after
    its own correction of a segment's overlong handles (fcurve.cc, correct_bezpart)."""
    i = next(i for i in range(len(keys) - 1) if keys[i]["co"][0] < frame < keys[i + 1]["co"][0])
    a, b = keys[i], keys[i + 1]
    kind = a["props"]["interpolation"]
    if kind in ("CONSTANT", "LINEAR"):
        f = (frame - a["co"][0]) / (b["co"][0] - a["co"][0])
        value = a["co"][1] if kind == "CONSTANT" else lerp(a["co"], b["co"], f)[1]
        middle = dict(a, co=(frame, value), left=(frame, value), right=(frame, value))
        return keys[:i + 1] + [middle] + keys[i + 1:]
    if kind != "BEZIER":
        sys.exit("no way to cut a %s segment" % kind)
    p0, p1, p2, p3 = a["co"], a["right"], b["left"], b["co"]
    h1, h2 = p0[0] - p1[0], p3[0] - p2[0]
    span, reach = p3[0] - p0[0], abs(h1) + abs(h2)
    if reach > span:
        f = span / reach
        p1 = (p0[0] - f * h1, p0[1] - f * (p0[1] - p1[1]))
        p2 = (p3[0] - f * h2, p3[1] - f * (p3[1] - p2[1]))
    lo, hi = 0.0, 1.0
    for _ in range(60):  # the corrected segment only moves forward in time, so halving finds it
        t = (lo + hi) / 2
        q = lerp(lerp(lerp(p0, p1, t), lerp(p1, p2, t), t), lerp(lerp(p1, p2, t), lerp(p2, p3, t), t), t)
        lo, hi = (t, hi) if q[0] < frame else (lo, t)
    t = (lo + hi) / 2
    p01, p12, p23 = lerp(p0, p1, t), lerp(p1, p2, t), lerp(p2, p3, t)
    p012, p123 = lerp(p01, p12, t), lerp(p12, p23, t)
    middle = dict(a, co=(frame, lerp(p012, p123, t)[1]), left=p012, right=p123)
    return keys[:i] + [dict(a, right=p01), middle, dict(b, left=p23)] + keys[i + 2:]


def repeat(keys, period, layout):
    """The cycle's keys laid out as `layout` has it. Where one copy ends on the frame the next one
    starts, the key takes its left side from the first and its right side from the second.

    Every handle is the one the cycle has. Its automatic handles are solved over the whole curve
    (Continuous Acceleration), and solved again over this one they would bend every segment a
    little; so they are kept where they are, aligned if they were, free if the join put two
    different keys' handles together."""
    lead_in, start, cycles = layout["lead_in"], layout["start"], layout["cycles"]
    end = lead_in + cycles * period
    # The phases the action begins and ends at, where the cycle may have no key.
    phases = [p for p in sorted({(start - lead_in) % period, start % period})
              if p and not any(k["co"][0] == p for k in keys)]
    cut_keys = keys
    for phase in phases:
        cut_keys = cut(cut_keys, phase)
    placed = {}
    for copy in range(-1, cycles + 1):
        offset = lead_in - start + copy * period
        # Cut only in the copies the action begins or ends in; the others are the cycle as it is.
        copied = cut_keys if any(p + offset in (0, end) for p in phases) else keys
        for key in copied:
            frame = key["co"][0] + offset
            if frame < 0 or frame > end:
                continue
            here = moved(key, offset)
            joined = placed.get(frame)
            if joined is not None:
                here["left"] = joined["left"]
            placed[frame] = here
    scale = layout["length"] / period
    laid = [moved(placed[f], scale=scale) for f in sorted(placed)]
    for key in laid:
        (lx, ly), (x, y), (rx, ry) = key["left"], key["co"], key["right"]
        cross = (x - lx) * (ry - y) - (y - ly) * (rx - x)
        size = max(1e-9, abs(x - lx) + abs(y - ly)) * max(1e-9, abs(rx - x) + abs(ry - y))
        key["left_type"] = key["right_type"] = "ALIGNED" if abs(cross) <= 1e-6 * size else "FREE"
    return laid


def hold(keys, period, layout):
    """A curve that holds one value over the cycle: the same value, held over the whole new action."""
    if len(keys) == 1:
        return keys
    if len(keys) == 2 and keys[0]["co"][1] == keys[1]["co"][1] and keys[1]["co"][0] == period:
        end = (layout["lead_in"] + layout["cycles"] * period) * layout["length"] / period
        return [keys[0], moved(keys[1], end - period)]
    return None


def write(fc, keys):
    points = fc.keyframe_points
    points.clear()
    points.add(len(keys))
    for point, key in zip(points, keys):
        # Types before positions: update() recomputes automatic handles from them.
        for name, value in key["props"].items():
            setattr(point, name, value)
        point.handle_left_type = key["left_type"]
        point.handle_right_type = key["right_type"]
        point.co = key["co"]
        point.handle_left = key["left"]
        point.handle_right = key["right"]
    fc.update()


def lay_out_markers(source, target, period, layout):
    lead_in, start, cycles = layout["lead_in"], layout["start"], layout["cycles"]
    scale = layout["length"] / period
    end = lead_in + cycles * period
    at = {"start": 0, "loop start": lead_in, "loop stop": end, "stop": end}
    for marker in list(target.pose_markers):
        target.pose_markers.remove(marker)
    for marker in source.pose_markers:
        group, colon, text = marker.name.partition(":")
        if colon and group.strip().lower() == layout["group"].lower():
            key = text.strip().lower()
            if key not in at:
                sys.exit("%r: no place for %r in the one-handed layout" % (source.name, marker.name))
            target.pose_markers.new("%s: %s" % (layout["new_group"], text.strip())).frame = \
                round(at[key] * scale)
        elif 0 < marker.frame <= period:
            # Every copy's, in the loop: one on the loop start would sound again on every pass.
            for copy in range(-1, cycles + 1):
                frame = marker.frame + lead_in - start + copy * period
                if lead_in < frame <= end:
                    target.pose_markers.new(marker.name).frame = round(frame * scale)
        else:
            sys.exit("%r: marker %r at frame %d is outside the cycle" % (source.name, marker.name,
                                                                          marker.frame))


def check_curves(source, target, period, layout):
    """Every curve of the new action against the cycle it came from, at quarter frames."""
    theirs = {(fc.data_path, fc.array_index): fc for fc in fcurves(source)}
    scale = layout["length"] / period
    end = (layout["lead_in"] + layout["cycles"] * period) * scale
    shift = layout["start"] - layout["lead_in"]
    worst, where = 0.0, None
    for fc in fcurves(target):
        cycle = theirs[(fc.data_path, fc.array_index)]
        for step in range(int(end * 4) + 1):
            frame = step / 4
            # The cycle's own modifier wraps the frame; the held values are held either way.
            err = abs(fc.evaluate(frame) - cycle.evaluate(frame / scale + shift))
            if err > worst:
                worst, where = err, "%s[%d] at frame %g" % (fc.data_path, fc.array_index, frame)
    print("the laid-out curves are the cycle's to within %.2g (worst: %s)" % (worst, where))
    if worst > TOLERANCE:
        sys.exit("%r does not follow the cycle" % target.name)


def make_action(layout):
    source = bpy.data.actions.get(layout["source"])
    if source is None:
        sys.exit("no %r to lay out" % layout["source"])
    spans = {(fc.keyframe_points[0].co[0], fc.keyframe_points[-1].co[0])
             for fc in fcurves(source) if is_cyclic(fc)}
    if len(spans) != 1 or next(iter(spans))[0] != 0:
        sys.exit("%r: its cycling curves do not all run from frame 0 to one end - %s"
                 % (source.name, spans))
    period = int(next(iter(spans))[1])

    name = layout["target"]
    existing = bpy.data.actions.get(name)
    if existing is not None:
        if existing.get(TAG) or existing.get("katar_1h_walk"):
            bpy.data.actions.remove(existing)
        else:
            existing.name = name + " (old)"
            existing.use_fake_user = True
            print("kept %r as %r" % (name, existing.name))

    target = source.copy()
    target.name = name
    target.use_fake_user = True
    for prop in list(target.keys()):
        del target[prop]
    target[TAG] = True

    for fc in fcurves(target):
        keys = snapshot(fc)
        if is_cyclic(fc):
            laid = repeat(keys, period, layout)
            # The loop is not the whole action now: a cycle over it would repeat the lead-in.
            for modifier in [m for m in fc.modifiers if m.type == "CYCLES"]:
                fc.modifiers.remove(modifier)
        else:
            laid = hold(keys, period, layout)
            if laid is None:
                sys.exit("%s[%d] neither cycles nor holds still - no way to lay it out"
                         % (fc.data_path, fc.array_index))
        write(fc, laid)

    lay_out_markers(source, target, period, layout)
    check_curves(source, target, period, layout)
    print("%r: %d cycles of %d frames%s, frames %d-%d; markers %s" % (
        name, layout["cycles"], layout["length"],
        ", after a %d-frame lead-in" % layout["lead_in"] if layout["lead_in"] else "",
        *target.frame_range,
        ", ".join("%d %s" % (m.frame, m.name)
                  for m in sorted(target.pose_markers, key=lambda m: (m.frame, m.name)))))
    return target


def load_script(reanimation):
    """ReAnimation's bake, build and export in one, as its Reanimv3.blend carries it."""
    blend = os.path.join(reanimation, "Sources", "Reanimv3.blend")
    with bpy.data.libraries.load(blend, link=False) as (theirs, ours):
        if SCRIPT not in theirs.texts:
            sys.exit("%s has no %s" % (blend, SCRIPT))
        ours.texts = [SCRIPT]
    text = ours.texts[0]
    source = text.as_string()
    bpy.data.texts.remove(text)
    return source


def export(layouts, out_dir, reanimation):
    scene = bpy.context.scene
    scene.render.fps, scene.render.fps_base = FPS, 1.0
    script = load_script(reanimation)
    # It finds build_moveset_action.py beside itself: ReAnimation's Sources has the same one.
    script_path = os.path.join(reanimation, "Sources", SCRIPT)
    rig = bpy.data.objects["rig"]

    prefs = bpy.context.preferences.addons[ADDON].preferences
    settings = {"export_as": "1ST_PERSON", "retained_extra_bones": "", "enable_root_motion_arp": False,
                "negate_camera_motion": False}
    saved = {name: getattr(prefs, name) for name in list(settings) + ["export_folder"]}
    scratch = tempfile.mkdtemp()
    try:
        for name, value in settings.items():
            setattr(prefs, name, value)
        prefs.export_folder = scratch
        for layout in layouts:
            raw = bpy.data.actions[layout["target"]]
            rig.animation_data_create()
            rig.animation_data.action = raw
            rig.animation_data.action_slot = raw.slots[0]
            bpy.context.view_layer.objects.active = rig
            exec(compile(script, script_path, "exec"), {"__file__": script_path, "__name__": "__main__"})
    finally:
        for name, value in saved.items():
            setattr(prefs, name, value)

    sys.path.insert(0, HERE)
    import footstep_refs
    import mirror_weapon_track
    os.makedirs(out_dir, exist_ok=True)
    for layout in layouts:
        kf = os.path.join(scratch, layout["out"] + ".kf")
        if not os.path.isfile(kf):
            sys.exit("no %s among what was exported: %s" % (os.path.basename(kf), sorted(os.listdir(scratch))))
        print("%s: %s, %d footsteps made references" % (os.path.basename(kf), mirror_weapon_track.patch(kf, (1, 1, -1)),
                                                        footstep_refs.rename(kf)))
        check_loops(kf, os.path.join(reanimation, "Animations", "xbase_anim.1st", layout["theirs"]))
        for ext in (".kf", ".nif"):
            shutil.copyfile(os.path.join(scratch, layout["out"] + ext), os.path.join(out_dir, layout["out"] + ext))
            print("wrote", os.path.join(out_dir, layout["out"] + ext))
    shutil.rmtree(scratch)


def loops(path):
    """{group: (start, loop start, loop stop, stop, [footstep times after start, up to stop])}"""
    from es3.nif import NiStream, NiTextKeyExtraData
    stream = NiStream()
    stream.load(path)
    keys, steps = {}, []
    for extra in stream.objects_of_type(NiTextKeyExtraData):
        for time, value in extra.keys:
            for line in value.replace("\r\n", "\n").split("\n"):
                group, colon, text = line.partition(":")
                group, text = group.strip().lower(), text.strip().lower()
                if group in ("soundgen", "soundgenref"):
                    steps.append(float(time))
                elif colon:
                    keys.setdefault(group, {})[text] = float(time)
    return {group: (k["start"], k["loop start"], k["loop stop"], k["stop"],
                    sorted(t for t in steps if k["start"] < t <= k["stop"]))
            for group, k in keys.items()}


def check_loops(ours_path, theirs_path):
    """Each group against the one-handed group it plays over, as the phase sync sees them: as parts of
    the way from start to stop."""
    ours, theirs = loops(ours_path), loops(theirs_path)
    off = []
    for group in sorted(ours):
        their_group = group.replace("katar1h", "1h")
        if their_group not in theirs:
            off.append("%s: %s has no %s" % (group, os.path.basename(theirs_path), their_group))
            continue
        a, b = ours[group], theirs[their_group]
        a_len, b_len = a[3] - a[0], b[3] - b[0]
        a_at = [(t - a[0]) / a_len for t in [a[1]] + a[4]]
        b_at = [(t - b[0]) / b_len for t in [b[1]] + b[4]]
        length_off = a_len / b_len - 1
        if len(a_at) != len(b_at):
            off.append("%s: %d footsteps to the loop, %s %d" % (group, len(a[4]), their_group, len(b[4])))
            continue
        step_off = max(abs(x - y) for x, y in zip(a_at, b_at))
        print("  %-20s %.3f s against %.3f (%+.1f%%), %d footsteps, each within %.1f%% of the way"
              % (group, a_len, b_len, 100 * length_off, len(a[4]), 100 * step_off))
        if abs(length_off) > MAX_LENGTH_OFF or step_off > MAX_STEP_OFF:
            off.append("%s: too far off %s" % (group, their_group))
    if off:
        sys.exit("not laid out as %s:\n  %s" % (os.path.basename(theirs_path), "\n  ".join(off)))
    print("laid out as %s" % os.path.basename(theirs_path))


def main():
    opts = args()
    for layout in LAYOUTS:
        make_action(layout)
    if opts["save"]:
        bpy.ops.wm.save_mainfile()
        print("saved", bpy.data.filepath)
    if opts["export"]:
        export(LAYOUTS, opts["export"], find_reanimation(opts["reanimation"]))


if __name__ == "__main__":
    main()

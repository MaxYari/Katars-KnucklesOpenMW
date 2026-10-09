"""Spreads the katar's weapon seat from [Raw] Katar Idle to the rest of the katar moveset.

'Weapon Bone' holds one pose - the seat - through every katar action, and 'Weapon Bone.L' holds its
mirror in the left hand, plus the katar's half turn (import_h2h_actions.py). Move the right bone in
[Raw] Katar Idle, run this, and:

1. every other [Raw] Katar action holding the seat the rest of the set shares gets Idle's new one.
   An action holding some other seat, or moving the bone, is left alone and listed;
2. 'Weapon Bone.L' is keyed afresh at the new seat's mirror in all of them, Idle included.

The "(old)" actions import_h2h_actions.py keeps are left as they were. Running it twice changes
nothing the second time.

This is the blend only. The game's .kf files take their seat from
Animations/xbase_anim.1st/xKatarIdle.kf (import_h2h_set.py).

From Blender: Text Editor > Open this file, Run Script, then save the .blend. Headless:
    blender -b "Reanimv  starts Katsr.blend" --python Sources/Tools/reseat_weapon_bones.py -- --save
"""
import collections
import importlib
import pathlib
import sys

import bpy

TOLERANCE = 1e-5
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


def held_seat(action):
    """{(property, index): value} the right weapon bone holds still, or None if it moves."""
    seat = {}
    for fc in h2h.bone_curves(action, h2h.RIGHT):
        values = [k.co[1] for k in fc.keyframe_points]
        if not values:
            continue
        if max(values) - min(values) > 1e-4:
            return None
        seat[(fc.data_path.split("].", 1)[1], fc.array_index)] = values[0]
    return seat


def same(a, b, keys):
    return all(k in a and k in b and abs(a[k] - b[k]) <= TOLERANCE for k in keys)


def shown(seat, keys):
    return "loc (%s)" % ", ".join("%.4f" % seat[("location", i)] for i in range(3)
                                  if ("location", i) in seat) if keys else "-"


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
    new = held_seat(idle)
    if not new:
        raise RuntimeError("%r moves its %s - the seat has to be one pose held through the action"
                           % (idle.name, h2h.RIGHT))
    keys = sorted(new)

    others = [a for a in bpy.data.actions if a.name.startswith("[Raw] Katar ")
              and not a.name.endswith(" (old)") and a is not idle and h2h.bone_curves(a, h2h.RIGHT)]
    seats = {a.name: held_seat(a) for a in others}
    # The seat Idle used to hold is the one the rest of the set still shares.
    counts = collections.Counter(tuple(round(s[k], 5) for k in keys)
                                 for s in seats.values() if s and all(k in s for k in keys))
    old = dict(zip(keys, counts.most_common(1)[0][0])) if counts else None

    log("new seat, from %r: %s" % (idle.name, shown(new, keys)))
    if old and not same(old, new, keys):
        log("old seat, held by %d of %d other actions: %s"
            % (counts.most_common(1)[0][1], len(others), shown(old, keys)))

    targets = [idle]
    for action in sorted(others, key=lambda a: a.name):
        seat = seats[action.name]
        if seat is None:
            log("  left alone: %r moves its %s" % (action.name, h2h.RIGHT))
        elif same(seat, new, keys) or (old and same(seat, old, keys)):
            targets.append(action)
        else:
            log("  left alone: %r holds a seat of its own, %s" % (action.name, shown(seat, keys)))

    mirror = h2h.weapon_mirror(bip)
    hidden = h2h.show_rig(rig, bip)
    previous = rig.animation_data.action if rig.animation_data else None
    slot_id = h2h.rig_slot(rig)
    try:
        for action in targets:
            moved = not same(held_seat(action), new, keys)
            h2h.apply_seat(action, new)
            err = h2h.key_left(rig, bip, action, slot_id, mirror)
            log("  %-30s %s, %s keyed at its mirror (off by %.5f)"
                % (action.name, "re-seated" if moved else "already seated", h2h.LEFT, err))
            if err > 1e-3:
                raise RuntimeError("the left weapon bone did not land where it should in %s"
                                   % action.name)
    finally:
        h2h.restore_action(rig, previous, slot_id)
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
    bpy.context.window_manager.popup_menu(draw, title="reseat_weapon_bones: "
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

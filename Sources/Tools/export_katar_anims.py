"""Exports the katar's first-person animations from this blend - the blend is where they live.

Every "[Raw] Katar ..." action (not the "(old)" ones import_h2h_actions.py keeps) goes through the
same three steps ReAnimation's build_and_export_moveset.py takes, its own helpers doing them:

1. Bizarre Anim's Bake Animation, off the Auto-Rig Pro rig onto Bip01;
2. for a walk, run or sneak, ReAnimation's build_moveset_action.py, which lays the one cycle out as
   every direction;
3. Bizarre Anim's Export Animation for the first-person skeleton, at 30 frames a second, with
   'Weapon Bone.L' kept - the blend keys it (import_h2h_actions.py, reseat_weapon_bones.py), so
   nothing is mirrored into the file afterwards. Camera motion is not negated: ReAnimation's own
   first-person exports were not, and the katar set is theirs.

Nothing is changed in a file once it is written. The blend already carries what the game wants:
the katar's group names, the weapon seat, the left weapon bone, and footsteps as SoundGenRef - keys
that sound nothing, since the one-handed animation underneath sounds its own (footstep_refs.py).
What is checked: that no file carries a SoundGen key, and that the one-handed walk and sneak loops
lie where the one-handed set's do (make_katar_1h_movement.check_loops).

The .kf files - only those, not the .nif the exporter writes beside each - land in
00 Core/Animations/xbase_anim.1st under the names already there, whatever case the export gives them:
ReAnimation's builder names a movement set from its marker group, so "[Raw] Katar Walk" comes out
as xkatarMovement. Then run make_third_person_anims.py for the third-person sets.

From Blender: Text Editor > Open this file, Run Script. Headless:
    blender -b "Reanimv  starts Katsr.blend" --python Sources/Tools/export_katar_anims.py
    ... -- --only Idle            only actions whose name contains it
"""
import contextlib
import os
import pathlib
import shutil
import sys
import tempfile

import bpy

PREFIX = "[Raw] Katar "
ADDON = "BizarreMorrowindAnimatonUtilities"
SCRIPT = "build_and_export_moveset.py"   # a text in ReAnimation's Sources/Reanimv3.blend
HELPERS_END = "# --------------------------------------------------------------------- Validate"
MOVEMENT = ("runforward", "walkforward", "sneakforward")
FPS = 30
SETTINGS = {"export_as": "1ST_PERSON", "retained_extra_bones": "Weapon Bone.L",
            "enable_root_motion_arp": False, "negate_camera_motion": False}
# Actions laid out over a one-handed set: checked against ReAnimation's file of that set.
ONE_HANDED = {"xKatar1hMovement": "x1hMovement.kf", "xKatar1hSneakMovement": "x1hSneakMovement.kf"}
LOG = []


def log(msg):
    LOG.append(msg)
    print(msg)


def _tools_dir():
    """Run from the Text Editor, __file__ is the .blend's path with the text's name on the end."""
    here = pathlib.Path(__file__)
    candidates = [here.resolve().parent]
    text = bpy.data.texts.get(here.name)
    if text is not None and text.filepath:
        candidates.append(pathlib.Path(bpy.path.abspath(text.filepath)).resolve().parent)
    if bpy.data.filepath:
        candidates.append(pathlib.Path(bpy.data.filepath).resolve().parent / "Sources" / "Tools")
    for folder in candidates:
        if (folder / "make_katar_1h_movement.py").is_file():
            return folder
    raise ImportError("Sources/Tools not found -- looked in " + ", ".join(str(c) for c in candidates))


TOOLS = _tools_dir()
MOD = TOOLS.parent.parent
OUT = MOD / "00 Core" / "Animations" / "xbase_anim.1st"
if str(TOOLS) not in sys.path:
    sys.path.insert(0, str(TOOLS))
import make_katar_1h_movement as one_handed  # noqa: E402


def reanimation_helpers(reanimation):
    """build_and_export_moveset.py's helpers - everything before its run - and the addon's exporter."""
    blend = os.path.join(reanimation, "Sources", "Reanimv3.blend")
    with bpy.data.libraries.load(blend, link=False) as (theirs, ours):
        if SCRIPT not in theirs.texts:
            raise RuntimeError("%s has no %s" % (blend, SCRIPT))
        ours.texts = [SCRIPT]
    text = ours.texts[0]
    source = text.as_string()
    bpy.data.texts.remove(text)
    if HELPERS_END not in source:
        raise RuntimeError("%s has changed: no '%s' line to take its helpers up to" % (SCRIPT, HELPERS_END))
    # It finds build_moveset_action.py beside itself; ReAnimation's Sources has the same one.
    path = os.path.join(reanimation, "Sources", SCRIPT)
    helpers = {"__file__": path, "__name__": "build_and_export_moveset_helpers"}
    exec(compile(source[:source.index(HELPERS_END)], path, "exec"), helpers)
    return helpers


@contextlib.contextmanager
def export_settings(exporter, folder):
    """The addon preferences and frame rate the export wants, put back afterwards."""
    prefs = exporter.get_prefs()
    scene = bpy.context.scene
    saved = {name: getattr(prefs, name) for name in list(SETTINGS) + ["export_folder"]}
    fps = scene.render.fps, scene.render.fps_base
    try:
        for name, value in SETTINGS.items():
            setattr(prefs, name, value)
        prefs.export_folder = folder
        scene.render.fps, scene.render.fps_base = FPS, 1.0
        yield
    finally:
        for name, value in saved.items():
            setattr(prefs, name, value)
        scene.render.fps, scene.render.fps_base = fps


def is_movement(action):
    groups = {m.name.partition(":")[0].strip().lower() for m in action.pose_markers if ":" in m.name}
    return any(g.startswith(MOVEMENT) for g in groups)


def export_one(h, exporter, rig, bip, raw):
    """Bake, build if it is movement, export. Returns the action that was exported."""
    rig.animation_data_create()
    rig.animation_data.action = raw
    rig.animation_data.action_slot = raw.slots[0]
    before = {a.session_uid for a in bpy.data.actions}
    h["solo_select"](rig)
    with h["view3d_context"]() as viewport:
        h["require_visible"](rig, viewport)
        if "FINISHED" not in bpy.ops.export.bake_animation():
            raise RuntimeError("Bake Animation did not finish for %s" % raw.name)
    baked = h["find_new_bake"](exporter.replace_raw_with_baked(raw.name), before)
    h["solo_select"](bip)
    h["bind_action"](bip, baked)
    exported = h["run_builder"](h["resolve_builder"]()) if is_movement(raw) else baked
    h["solo_select"](bip)
    with h["view3d_context"]() as viewport:
        h["require_visible"](bip, viewport)
        if "FINISHED" not in bpy.ops.export.animation():
            raise RuntimeError("Export Animation did not finish for %s" % raw.name)
    return exported


def live_footsteps(path):
    """SoundGen keys a file carries - each one would sound a step twice in game."""
    import mirror_weapon_track  # noqa: F401  (puts the es3 library on the path)
    from es3.nif import NiStream, NiTextKeyExtraData
    stream = NiStream()
    stream.load(path)
    found = 0
    for extra in stream.objects_of_type(NiTextKeyExtraData):
        for _time, text in extra.keys:
            found += sum(1 for line in text.replace("\r\n", "\n").split("\n")
                         if line.partition(":")[0].strip().lower() == "soundgen")
    return found


def destination(name, out_dir):
    """The file already there under this name in any case, else the name as exported."""
    existing = {n.lower(): n for n in os.listdir(out_dir)} if os.path.isdir(out_dir) else {}
    return os.path.join(out_dir, existing.get(name.lower(), name))


def export_actions(names, out_dir=OUT, reanimation=None):
    """Export these actions into out_dir. Returns the .kf paths written."""
    reanimation = one_handed.find_reanimation(reanimation)
    h = reanimation_helpers(reanimation)
    exporter = h["addon_exporter"]()
    rig = bpy.data.objects["rig"]
    bip = exporter.find_morrowind_rig_controlled_by(rig)
    if bpy.context.object and bpy.context.object.mode != "OBJECT":
        bpy.ops.object.mode_set(mode="OBJECT")
    previous = rig.animation_data.action if rig.animation_data else None
    previous_slot = rig.animation_data.action_slot if rig.animation_data else None
    bip_previous = bip.animation_data.action if bip.animation_data else None

    scratch = tempfile.mkdtemp()
    actions_before = {a.session_uid for a in bpy.data.actions}
    visibility = h["reveal"](rig) + h["reveal"](bip)
    bpy.context.view_layer.update()
    exported = []
    try:
        with export_settings(exporter, scratch):
            for name in names:
                before = set(os.listdir(scratch))
                made = export_one(h, exporter, rig, bip, bpy.data.actions[name])
                new = sorted(set(os.listdir(scratch)) - before)
                kf = [n for n in new if n.lower().endswith(".kf")]
                if len(kf) != 1:
                    raise RuntimeError("%s exported %s, not one .kf" % (name, new))
                exported.append((name, made.name, kf[0]))
    finally:
        h["restore_visibility"](visibility)
        if previous is not None:
            rig.animation_data.action = previous
            if previous_slot is not None:
                rig.animation_data.action_slot = previous_slot
        if bip.animation_data is not None:
            bip.animation_data.action = bip_previous
        # The bakes and built movesets are only the way to the file; the blend keeps its [Raw] ones.
        for action in [a for a in bpy.data.actions if a.session_uid not in actions_before]:
            if action.users <= (1 if action.use_fake_user else 0):
                bpy.data.actions.remove(action)

    os.makedirs(out_dir, exist_ok=True)
    written, problems = [], []
    for raw_name, made_name, kf in exported:
        path = os.path.join(scratch, kf)
        steps = live_footsteps(path)
        if steps:
            problems.append("%s carries %d SoundGen key(s): name its footstep markers SoundGenRef"
                            % (raw_name, steps))
        stem = kf[:-3]
        if stem.lower() in {k.lower() for k in ONE_HANDED}:
            theirs = ONE_HANDED[next(k for k in ONE_HANDED if k.lower() == stem.lower())]
            try:
                one_handed.check_loops(path, os.path.join(reanimation, "Animations", "xbase_anim.1st",
                                                          theirs))
            except SystemExit as exc:          # it exits on a mismatch; a Text Editor run must not
                problems.append(str(exc))
        # Only the .kf: the exporter's .nif beside it is never read. The engine plays the .kf against
        # the actor's own skeleton (Animation::addSingleAnimSource), and takes nothing from a .nif in
        # the folder but nodes marked BONE (injectCustomBones), which these have none of.
        target = destination(stem + ".kf", out_dir)
        shutil.copyfile(path, target)
        written.append(target)
        log("  %-30s -> %s" % (raw_name, os.path.relpath(target, MOD)))
    shutil.rmtree(scratch)
    if problems:
        raise RuntimeError("; ".join(problems))
    return written


def main(only=None):
    names = sorted(a.name for a in bpy.data.actions if a.name.startswith(PREFIX)
                   and not a.name.endswith(" (old)") and (only is None or only.lower() in a.name.lower()))
    if not names:
        raise RuntimeError("no %r actions%s" % (PREFIX + "...", " matching %r" % only if only else ""))
    log("exporting %d action(s) to %s" % (len(names), os.path.relpath(OUT, MOD)))
    written = export_actions(names)
    log("wrote %d file(s); run make_third_person_anims.py for the third-person sets" % len(written))


def only_arg():
    argv = sys.argv
    if "--" not in argv or not any(pathlib.Path(a).name == pathlib.Path(__file__).name
                                   for a in argv[:argv.index("--")]):
        return None
    rest = argv[argv.index("--") + 1:]
    return rest[rest.index("--only") + 1] if "--only" in rest[:-1] else None


def show_in_blender(failed):
    def draw(self, _context):
        for line in LOG[-40:]:
            self.layout.label(text=line)
    bpy.context.window_manager.popup_menu(draw, title="export_katar_anims: "
                                          + ("stopped" if failed else "done"),
                                          icon="ERROR" if failed else "INFO")


if __name__ == "__main__":
    LOG.clear()
    try:
        main(only_arg())
    except RuntimeError as exc:
        log("ERROR: %s" % exc)
        if bpy.app.background:
            raise SystemExit(1)
        show_in_blender(True)
    else:
        if not bpy.app.background:
            show_in_blender(False)

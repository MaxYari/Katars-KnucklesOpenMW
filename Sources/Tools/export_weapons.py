"""Exports every katar / knuckleduster in the blend to its own Morrowind .nif.

Each weapon is an empty with its meshes parented under it. The empties are laid out in a display row,
so before exporting, the hierarchy is moved so that the grip bar - the piece the hand closes around,
and the one part every one of these weapons shares - sits at the origin. That is what the engine puts
on "Weapon Bone", so it is what the file has to be centred on.

From Blender: set OUT below, then Text Editor > Open this file, Run Script. Headless:
    blender -b <the .blend> --python Sources/Tools/export_weapons.py -- <output folder>
"""
import os
import sys
import bpy
from mathutils import Matrix, Vector

# The folder a run from the Text Editor writes to; relative to the .blend's folder. Run headless, the
# folder after "--" says instead.
OUT = None

# (empty name, output file, the grip-bar child that marks the origin)
WEAPONS = [
    ('steel katar',           'steel_katar.nif',           'Cube.007'),
    ('Silver Katar',          'silver_katar.nif',          'Cube.024'),
    ('Daedric Katar',         'daedric_katar.nif',         'Cube.032'),
    ('ebony guarded katar',   'ebony_katar.nif',           'Cube.016'),
    ('Ebony lean katar',      'ebony_slim_katar.nif',      'Cube.021'),
    ('Iron knuckle',          'iron_knuckle.nif',          'Cube.004'),
    ('Chitin knuckle',        'chitin_knuckle.nif',        'Cube.008'),
    ('Silver Knuckle',        'silver_knuckle.nif',        'Cube.010'),
    ('Orcish Knuckle',        'orcish_knuckle.nif',        'Cube.018'),
    ('Daedric knuckle basic', 'daedric_knuckle.nif',       'Cube.037'),
    ('Daedric Knuckle Sharp', 'daedric_knuckle_sharp.nif', 'Cube.028'),
]


def out_dir():
    argv = sys.argv
    if "--" in argv and any(os.path.basename(a) == os.path.basename(__file__)
                            for a in argv[:argv.index("--")]):
        rest = argv[argv.index("--") + 1:]
        if not rest:
            raise RuntimeError("give the output folder after --")
        return os.path.abspath(rest[0])
    if not OUT:
        raise RuntimeError("set OUT at the top of this script to the folder to export to")
    return os.path.join(bpy.path.abspath("//"), bpy.path.abspath(OUT))


def world_center(obj):
    """Centre of an object's evaluated geometry in world space."""
    vs = [obj.matrix_world @ v.co for v in obj.data.vertices]
    lo = Vector((min(v.x for v in vs), min(v.y for v in vs), min(v.z for v in vs)))
    hi = Vector((max(v.x for v in vs), max(v.y for v in vs), max(v.z for v in vs)))
    return (lo + hi) / 2


def descendants(obj):
    out = [obj]
    for c in obj.children:
        out.extend(descendants(c))
    return out


def export(out, scene, view_layer, empty_name, filename, grip_name):
    empty = bpy.data.objects[empty_name]
    grip = bpy.data.objects[grip_name]
    assert grip.parent is empty, "%s is not a child of %s" % (grip_name, empty_name)

    # The empty sits on the grip bar; centring on it is what puts the hand's grip at the origin.
    # (The grip objects' own origins are useless here - their matrix_parent_inverse cancels the
    # empty's scale, so their .location is in unscaled parent units.)
    original = empty.matrix_world.copy()
    offset = original.to_translation()
    drift = (world_center(grip) - offset) * 100  # in Morrowind units
    assert drift.length < 2.0, ("%s: grip bar is %.2f units off its empty" % (empty_name, drift.length), tuple(drift))
    print("  %-24s grip bar %.2f units from the empty" % (empty_name, drift.length))

    # Put back afterwards, error or not, so the next weapon starts from the file as it was.
    kept = (empty.parent, empty.matrix_parent_inverse.copy(), empty.matrix_basis.copy())
    root = None
    try:
        empty.matrix_world = Matrix.Translation(-offset) @ original
        view_layer.update()

        # A root NiNode named after the file, exactly like the existing exports: the weapon's own node
        # keeps its scale underneath it, and the root stays at identity.
        root = bpy.data.objects.new(filename, None)
        scene.collection.objects.link(root)
        root.matrix_world = Matrix.Identity(4)
        empty_matrix = empty.matrix_world.copy()
        empty.parent = root
        empty.matrix_parent_inverse = Matrix.Identity(4)
        empty.matrix_world = empty_matrix
        view_layer.update()

        for o in view_layer.objects:
            o.select_set(False)
        objects = descendants(root)
        for o in objects:
            o.select_set(True)
        view_layer.objects.active = root

        path = os.path.join(out, filename)
        bpy.ops.export_scene.mw(
            filepath=path,
            use_selection=True,
            use_active_collection=False,
            export_animations=False,
            extract_keyframe_data=False,
            preserve_root_tranforms=False,
            preserve_material_names=True,
            strip_numeric_suffixes=True,
            vertex_precision=0.001,
        )
        print("exported %-28s -> %s (%d objects)" % (empty_name, filename, len(objects)))
    finally:
        empty.parent, empty.matrix_parent_inverse, empty.matrix_basis = kept
        if root is not None:
            bpy.data.objects.remove(root)
        view_layer.update()


def main():
    out = out_dir()
    os.makedirs(out, exist_ok=True)
    scene = bpy.context.scene
    view_layer = bpy.context.view_layer
    active = view_layer.objects.active
    selected = {o.name for o in view_layer.objects if o.select_get()}
    try:
        for empty_name, filename, grip_name in WEAPONS:
            export(out, scene, view_layer, empty_name, filename, grip_name)
    finally:
        for o in view_layer.objects:
            if o.select_get() != (o.name in selected):
                o.select_set(o.name in selected)
        view_layer.objects.active = active
    print("DONE")


if __name__ == "__main__":
    try:
        main()
    except RuntimeError as exc:
        print("ERROR: %s" % exc)
        if not bpy.app.background:
            raise
        raise SystemExit(1)

"""
mw_export.py -- export every weapon in the blend to its own Morrowind .nif.

WHAT IT EXPORTS
    Every EMPTY sitting directly in the "Exports" collection, together with
    everything parented under it, however deeply nested. Nothing is listed in
    this file: to add or remove a weapon, drag its empty in or out of that
    collection in Blender.

    Each empty is moved to the world origin for the export and put back
    afterwards, so the display layout in the blend does not matter.

OUTPUT NAME
    <empty name> slugified, so "Daedric Knuckle Sharp" becomes
    daedric_knuckle_sharp.nif. To pin a different filename -- because the plugin
    already refers to one -- put a custom property on the empty:

        mw_nif = "ebony_slim_katar.nif"

TRANSLUCENCY
    io_scene_mw only writes a NiAlphaProperty when the material has
    use_alpha_blend set (nif_export.py:1011 returns early otherwise), so an
    untouched material always exports opaque. Tag the MATERIAL name:

        [Alpha]       alpha blending, for glass and crystal
        [AlphaClip]   alpha testing, for cut-out foliage and the like

MATERIAL REPAIR
    Runs mw_bake.repair_all_materials() first. Duplicating a MW material in
    Blender loses io_scene_mw's bookkeeping, and the exporter then silently
    writes no texture at all -- the mesh renders plain white in game.

USAGE
    blender -b your.blend --python tools/mw_export.py
    blender -b your.blend --python tools/mw_export.py -- --overwrite

    --overwrite       replace .nif files that already exist (default: skip them)
    --only NAME       only weapons whose empty name contains NAME
    --collection NAME use a different collection (default: Exports)
    --outdir DIR      write somewhere other than <blend>/meshes
    --list            show what would be exported and stop
    --help            this text
"""

import pathlib
import re
import sys

import bpy

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))
import mw_bake  # noqa: E402

CONFIG = {
    # Case-insensitive; the first one that exists is used.
    "collections": ["Exports", "Export"],
    "out_dir": "meshes",

    # Custom property on an empty that pins its output filename.
    "name_property": "mw_nif",

    # Passed straight to io_scene_mw's exporter.
    "export_options": {
        "use_selection": True,
        "export_animations": False,      # these are static weapon meshes
        "preserve_material_names": True,
        "preserve_root_tranforms": False,
        "vertex_precision": 0.001,
    },

    # Blending with alpha still at 1.0 renders opaque, so a value is needed too.
    "alpha_value": 0.65,
}


def log(msg=""):
    print(f"[mw_export] {msg}" if msg else "")


def die(message, detail=None):
    log("")
    log(f"ERROR: {message}")
    if detail:
        for line in detail:
            log(f"  {line}")
    log("")
    log("Run with --help for the full description.")
    raise SystemExit(1)


def nif_name(empty):
    pinned = empty.get(CONFIG["name_property"])
    if pinned:
        name = str(pinned)
        return name if name.lower().endswith(".nif") else f"{name}.nif"
    slug = re.sub(r"\[[^\]]*\]", " ", empty.name)
    slug = re.sub(r"[^0-9A-Za-z]+", "_", slug).strip("_").lower()
    return f"{slug or 'weapon'}.nif"


def descendants(obj):
    out = [obj]
    for child in obj.children:
        out.extend(descendants(child))
    return out


def find_collection():
    wanted = [c.lower() for c in CONFIG["collections"]]
    by_name = {c.name.lower(): c for c in bpy.data.collections}
    for name in wanted:
        coll = by_name.get(name)
        if coll is not None and len(coll.objects):
            return coll
    # a named-but-empty collection is worth reporting separately from a missing one
    for name in wanted:
        if name in by_name:
            die(f"collection {by_name[name].name!r} is empty",
                ["Put each weapon's root empty directly inside it.",
                 "Children do not need to be in the collection, only the empty."])
    die(f"no collection named {' or '.join(CONFIG['collections'])}",
        ["Collections in this file: " + (", ".join(sorted(c.name for c in bpy.data.collections)) or "none"),
         "Create one and put each weapon's root empty directly inside it."])


def collect_weapons(coll, only=None):
    """Empties sitting DIRECTLY in the collection, with everything under them."""
    weapons, skipped = [], []
    for obj in coll.objects:
        if obj.type != "EMPTY":
            skipped.append((obj.name, f"not an empty (it is a {obj.type})"))
            continue
        family = descendants(obj)
        meshes = [o for o in family if o.type == "MESH"]
        if not meshes:
            skipped.append((obj.name, "no meshes parented under it"))
            continue
        if only and only.lower() not in obj.name.lower():
            continue
        weapons.append((obj, family, meshes))
    return weapons, skipped


def apply_alpha(objects):
    """Turn on alpha blending where a material's name asks for it. Work copy only."""
    done = []
    for obj in objects:
        for slot in obj.material_slots:
            mat = slot.material
            if mat is None:
                continue
            tags = mw_bake.name_tags(mat.name)
            clip, blend = "[alphaclip]" in tags, "[alpha]" in tags
            if not (blend or clip):
                continue
            try:
                if clip:
                    mat.mw.use_alpha_clip = True
                else:
                    mat.mw.use_alpha_blend = True
                    if mat.mw.alpha >= 1.0:
                        mat.mw.alpha = CONFIG["alpha_value"]
                done.append(f"{mat.name} ({'clip' if clip else 'blend'})")
            except Exception as exc:
                log(f"  !! could not set alpha on {mat.name!r}: {exc}")
    for entry in sorted(set(done)):
        log(f"  alpha: {entry}")


def flatten_mesh_parenting(empty):
    """Re-parent meshes that hang off other meshes up to the nearest non-mesh.

    In a Morrowind NIF geometry is a NiTriShape, and a NiTriShape cannot hold
    children -- only a NiNode can. io_scene_mw therefore DROPS a mesh parented
    under another mesh, silently and with nothing in the log: the part simply
    does not appear in game.

    Parenting meshes under meshes is a perfectly reasonable way to organise a
    blend, so rather than refuse it, the hierarchy is flattened here (work copy
    only) with world transforms preserved.
    """
    moved = []
    for obj in list(empty.children_recursive):
        if obj.type != "MESH" or obj.parent is None or obj.parent.type != "MESH":
            continue
        target = obj.parent
        while target is not None and target.type == "MESH":
            target = target.parent
        if target is None:
            target = empty
        world = obj.matrix_world.copy()
        old_parent = obj.parent.name
        obj.parent = target
        obj.matrix_parent_inverse = target.matrix_world.inverted()
        obj.matrix_world = world
        moved.append((obj.name, old_parent, target.name))

    for name, was, now in moved:
        log(f"  re-parented {name!r}: {was!r} -> {now!r} "
            f"(a NiTriShape cannot have children; it would have been dropped)")
    return moved


def _owner(obj):
    root = obj
    while root.parent is not None:
        root = root.parent
    return root.name


def check_mirrored_objects(meshes):
    """Refuse to export an object whose world transform is a reflection.

    Negative scale on an odd number of axes gives the world matrix a negative
    determinant. A NIF node carries one uniform float scale, so the exporter's
    decompose_uniform() folds that into a NEGATIVE uniform scale, which inverts
    triangle winding -- with backface culling on, the mesh renders inside-out.

    This is not fixed automatically: un-mirroring means applying the scale and
    flipping the winding, which changes the mesh, and that is the author's call.
    """
    bad = []
    for obj in meshes:
        if obj.matrix_world.determinant() < 0:
            bad.append((obj.name, tuple(round(v, 5) for v in obj.scale), _owner(obj)))
    if not bad:
        return

    detail = []
    for name, scale, owner in sorted(bad):
        detail.append(f"{name:14s} in {owner!r}   scale {scale}")
    detail += [
        "",
        "A NIF node has only a uniform float scale, so a reflection cannot be",
        "represented: it becomes a negative uniform scale and the mesh renders",
        "inside-out. Fix each object in Blender, then re-run:",
        "",
        "   select it, Ctrl+A > Scale, then Edit Mode > Mesh > Normals > Flip",
        "",
        "or rebuild the mirroring with a Mirror modifier instead of -1 scale.",
    ]
    die(f"{len(bad)} object(s) have a mirrored (negative-determinant) transform", detail)


def check_evaluated_materials(meshes):
    """Warn about meshes whose EVALUATED geometry carries no material.

    io_scene_mw reads materials off the evaluated mesh, so a modifier that drops
    the material slots makes the shape export with no NiMaterialProperty and no
    NiTexturingProperty at all -- it renders plain white in game, with nothing
    in the log to say why. Geometry Nodes is the usual culprit: Dual Mesh and
    friends rebuild topology and do not carry material assignment through.
    """
    bad = []
    depsgraph = bpy.context.evaluated_depsgraph_get()
    for obj in meshes:
        if not len(obj.material_slots):
            continue
        eval_obj = obj.evaluated_get(depsgraph)
        me = eval_obj.to_mesh()
        try:
            empty_slots = len(me.materials) == 0
        finally:
            eval_obj.to_mesh_clear()
        if empty_slots:
            culprits = [m.name for m in obj.modifiers if m.type == "NODES"]
            bad.append((obj.name, culprits))

    for name, culprits in bad:
        log(f"  !! {name!r} evaluates to geometry with NO material slots -- it will "
            f"export untextured (white in game)")
        if culprits:
            log(f"     the Geometry Nodes modifier(s) {culprits} drop the material; "
                f"add a 'Set Material' node before the Group Output")
    return bad


def export_weapon(empty, family, meshes, out_dir, overwrite):
    path = out_dir / nif_name(empty)
    if path.exists() and not overwrite:
        log(f"  SKIP {empty.name!r} -> {path.name} already exists (use --overwrite)")
        return None

    original_location = tuple(empty.location)
    try:
        empty.location = (0.0, 0.0, 0.0)
        bpy.context.view_layer.update()

        bpy.ops.object.select_all(action="DESELECT")
        for obj in family:
            obj.hide_viewport = False
            obj.hide_set(False)
            obj.select_set(True)
        bpy.context.view_layer.objects.active = empty

        out_dir.mkdir(parents=True, exist_ok=True)
        bpy.ops.export_scene.mw(filepath=str(path), **CONFIG["export_options"])
    finally:
        empty.location = original_location
        bpy.context.view_layer.update()

    pinned = " (name pinned)" if empty.get(CONFIG["name_property"]) else ""
    log(f"  {empty.name!r} -> {path.name}  "
        f"[{len(meshes)} meshes, {len(family)} nodes]{pinned}")
    return path


def parse_args(argv):
    args = {"only": None, "overwrite": False, "outdir": None,
            "collection": None, "list": False}
    argv = argv[argv.index("--") + 1:] if "--" in argv else []

    takes_value = {"--only": "only", "--outdir": "outdir", "--collection": "collection"}
    i = 0
    while i < len(argv):
        a = argv[i]
        if a in ("--help", "-h"):
            print(__doc__)
            raise SystemExit(0)
        elif a == "--overwrite":
            args["overwrite"] = True
        elif a == "--list":
            args["list"] = True
        elif a in takes_value:
            if i + 1 >= len(argv) or argv[i + 1].startswith("--"):
                die(f"{a} needs a value after it",
                    [{"--only": "e.g. --only daedric",
                      "--outdir": "e.g. --outdir /tmp/test_meshes",
                      "--collection": "e.g. --collection Exports"}[a]])
            i += 1
            args[takes_value[a]] = argv[i]
        else:
            die(f"unknown option {a!r}",
                ["Valid options: --overwrite --only NAME --collection NAME "
                 "--outdir DIR --list --help"])
        i += 1
    return args


def main():
    args = parse_args(list(sys.argv))

    if not bpy.data.filepath:
        die("this .blend has never been saved",
            ["Output paths are worked out relative to the .blend file."])

    if args["collection"]:
        CONFIG["collections"] = [args["collection"]]

    log("=" * 68)
    log("Exports every empty in the 'Exports' collection to its own .nif.")
    log("Drag an empty in or out of that collection to change what ships.")
    log("=" * 68)

    if bpy.context.object and bpy.context.object.mode != "OBJECT":
        bpy.ops.object.mode_set(mode="OBJECT")

    coll = find_collection()
    weapons, skipped = collect_weapons(coll, args["only"])

    blend = pathlib.Path(bpy.data.filepath).parent
    out_dir = pathlib.Path(args["outdir"]) if args["outdir"] else blend / CONFIG["out_dir"]

    log(f"collection : {coll.name!r} ({len(coll.objects)} objects in it)")
    log(f"output     : {out_dir}")
    if args["only"]:
        log(f"filter     : names containing {args['only']!r}")
    log()

    for name, why in skipped:
        log(f"  ignored {name!r}: {why}")

    if not weapons:
        if args["only"]:
            die(f"nothing in {coll.name!r} matches --only {args['only']!r}",
                ["Empties there: " + ", ".join(o.name for o in coll.objects if o.type == "EMPTY")])
        die(f"found no exportable empties in {coll.name!r}",
            ["An entry has to be an EMPTY with at least one mesh parented under it."])

    if args["list"]:
        log(f"would export {len(weapons)} weapon(s):")
        for empty, family, meshes in weapons:
            log(f"  {empty.name!r} -> {nif_name(empty)}  "
                f"[{len(meshes)} meshes, {len(family)} nodes]")
        return

    mw_bake.repair_all_materials()

    for empty, _family, _meshes in weapons:
        flatten_mesh_parenting(empty)
    # the hierarchy just changed, so rebuild the families
    weapons = [(empty, descendants(empty), [o for o in descendants(empty) if o.type == "MESH"])
               for empty, _f, _m in weapons]

    all_meshes = [o for _, family, _ in weapons for o in family if o.type == "MESH"]
    apply_alpha(all_meshes)
    check_mirrored_objects(all_meshes)
    check_evaluated_materials(all_meshes)

    log(f"exporting {len(weapons)} weapon(s)")
    written = []
    for empty, family, meshes in sorted(weapons, key=lambda w: w[0].name.lower()):
        path = export_weapon(empty, family, meshes, out_dir, args["overwrite"])
        if path:
            written.append(path)

    log()
    log("=" * 68)
    log(f"wrote {len(written)} file(s) to {out_dir}")
    for path in written:
        log(f"  {path.name:34s} {path.stat().st_size:>9,} bytes")


if __name__ == "__main__":
    main()

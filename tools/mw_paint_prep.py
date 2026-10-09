"""
mw_paint_prep.py -- bake a mesh's vanilla textures onto a layout of its own,
ready for texture painting.

The mesh's UV map can stack its islands on the vanilla textures however it
likes; painting needs every face to own its texels. For every mesh with
"[Paint]" in its name -- run from Blender's Text Editor, the selected meshes
instead -- this:

1. Finds the paint layout: a UV map named "PaintUV", else the first UV map no
   material reads its texture through -- in practice your second one. It is
   used as it is when it lies inside 0-1, nothing in it overlaps, and it is not
   just a copy of the first. Otherwise "PaintUV" is made from the islands of
   the UV map the textures are read through. Never re-unwrapped: every island
   keeps its shape, is sized to the vanilla texels it covers (so a 32x256 blade
   texture does not come out stretched 8:1), may turn by 90 degrees, and is
   packed with a margin around it. An island folded over itself -- mirrored
   halves meeting on one UV seam -- is cut along the fold, so each half gets
   its own texels.
2. Bakes every material's texture through its own UV map onto that layout, at
   CONFIG["density"] times the vanilla texel density: Cycles' EMIT bake, the
   same no-lighting copy mw_bake.py makes, tint included. Written to
   bake_source/paint/<name>.png.
3. Points each material slot at a new MW material reading that image through
   the paint layout. It keeps the old material's name, tags and all, so
   mw_bake.py and mw_export.py treat the mesh as before. The old material stays
   in the file, recorded on the new one as "mw_paint_source".

Before changing anything it copies each UV map the textures are read through
to <name>_backup in the mesh's UV map list. PaintUV is left the active UV map,
so that is what the UV editor shows; click UVMap in the list for the original.

Then select the mesh and switch to Texture Paint. Blender does not save a
painted image with the .blend: Image > Save (Alt+S) writes it to the PNG.

An object already prepared is skipped, so painting is never baked over.
--overwrite re-bakes it from the original materials; the painting is kept as
<name>_previous.png, as is any texture of that name already there.

FROM BLENDER
    Text Editor > Open > tools/mw_paint_prep.py, select the meshes (or tag
    them), Run Script. Flags cannot be passed there: set RUN_OPTIONS below
    instead. What happened shows in a popup, and in full in the system console.
    mw_bake.py is found beside the opened file or in tools/ next to the .blend.

HEADLESS
    blender -b your.blend --python tools/mw_paint_prep.py -- --save
    blender -b your.blend --python tools/mw_paint_prep.py -- --check

Flags (after the "--"):
    --save          save the .blend when finished
    --only NAME     only objects whose name contains NAME
    --check         report each mesh's paint layout and change nothing; with
                    nothing tagged, every mesh that has a second UV map
    --relayout      make PaintUV afresh even when the layout in place is fine
    --overwrite     re-bake an object that is already prepared
    --res N         force the texture to N x N
"""

import importlib
import math
import os
import pathlib
import sys

import bpy
import numpy as np
from bpy_extras import mesh_utils

# What the flags would say, for a run from Blender's Text Editor.
RUN_OPTIONS = {
    "check": False,       # --check
    "relayout": False,    # --relayout
    "overwrite": False,   # --overwrite
    "res": None,          # --res N
    "only": None,         # --only NAME
}


def _tools_dir():
    """The folder holding mw_bake.py.

    Run from the Text Editor, __file__ is the .blend's path with the text's
    name on the end, so it is looked for beside the file the text was opened
    from, then in tools/ next to the .blend.
    """
    here = pathlib.Path(__file__)
    candidates = [here.resolve().parent]
    text = bpy.data.texts.get(here.name)
    if text is not None and text.filepath:
        candidates.append(pathlib.Path(bpy.path.abspath(text.filepath)).resolve().parent)
    if bpy.data.filepath:
        candidates.append(pathlib.Path(bpy.data.filepath).resolve().parent / "tools")
    for folder in candidates:
        if (folder / "mw_bake.py").is_file():
            return folder
    raise ImportError("mw_bake.py not found -- looked in " + ", ".join(str(c) for c in candidates))


if str(_tools_dir()) not in sys.path:
    sys.path.insert(0, str(_tools_dir()))
import mw_bake  # noqa: E402
# A second run in the same Blender session would otherwise keep the first one's copy.
mw_bake = importlib.reload(mw_bake)

CONFIG = {
    "tag": "[paint]",
    "layer": "PaintUV",
    "out_dir": "bake_source/paint",
    # Paint texels per vanilla texel, along each axis. Painting at vanilla
    # density leaves no room for a line finer than the texture already has.
    "density": 2.0,
    "min_size": 256,
    "max_size": 4096,
    # Pixels between islands in the final texture: 8 up to 1024, then 16 at
    # 2048. The bake pads each island by half of it, which fills the gap.
    "gap_divisor": 128,
    "min_gap_px": 8,
    # The overlap/gap check rasterises at most this many pixels across.
    "check_size": 2048,
    # Assumed for a material with no texture, as in mw_bake.count_source_texels.
    "fallback_texture": (256, 256),
    "source_property": "mw_paint_source",
    # Each UV map the textures are read through is copied to <name>_backup
    # before anything is changed, once.
    "backup_suffix": "_backup",
}


LOG = []


class Abort(Exception):
    """Stops the run. Not SystemExit: from the Text Editor that can close Blender."""


def log(msg=""):
    LOG.append(msg)
    print(f"[mw_paint_prep] {msg}" if msg else "")


def die(message, detail=None):
    log("")
    log(f"ERROR: {message}")
    for line in detail or []:
        log(f"  {line}")
    raise Abort(message)


def next_pow2(n):
    return 1 << max(0, int(math.ceil(n)) - 1).bit_length()


# --------------------------------------------------------------------------
# reading the mesh
# --------------------------------------------------------------------------

def source_material(mat):
    """The material a slot is baked from: its recorded original, else itself."""
    if mat is None:
        return None
    return mat.get(CONFIG["source_property"]) or mat


def is_prepared(obj):
    return any(s.material is not None and CONFIG["source_property"] in s.material.keys()
               for s in obj.material_slots)


def slot_sources(obj):
    """Per slot: (source material, image, uv layer, interpolation, extension)."""
    me = obj.data
    out = []
    for slot in obj.material_slots:
        src = source_material(slot.material)
        image, uv, interp, ext = mw_bake.mw_base_texture(src)
        if not (uv and me.uv_layers.get(uv)):
            uv = me.uv_layers[0].name
        out.append({"material": src, "image": image, "uv": uv, "interp": interp, "ext": ext})
    return out


def mesh_arrays(me):
    starts = np.empty(len(me.polygons), dtype=np.int64)
    totals = np.empty(len(me.polygons), dtype=np.int64)
    mats = np.empty(len(me.polygons), dtype=np.int64)
    me.polygons.foreach_get("loop_start", starts)
    me.polygons.foreach_get("loop_total", totals)
    me.polygons.foreach_get("material_index", mats)
    loop_poly = np.repeat(np.arange(len(me.polygons)), totals)
    return starts, totals, np.clip(mats, 0, None), loop_poly


def read_uv(me, name):
    uv = np.empty(len(me.loops) * 2, dtype=np.float64)
    me.uv_layers[name].uv.foreach_get("vector", uv)
    return uv.reshape(-1, 2)


def source_uv_texels(obj, sources):
    """Every loop's source UV in vanilla texels: u * width, v * height."""
    me = obj.data
    _starts, _totals, mats, loop_poly = mesh_arrays(me)
    slot_of_loop = np.clip(mats[loop_poly], 0, max(len(sources) - 1, 0))
    texels = np.zeros((len(me.loops), 2))
    for layer in {s["uv"] for s in sources}:
        uv = read_uv(me, layer)
        for i, src in enumerate(sources):
            if src["uv"] != layer:
                continue
            image = src["image"]
            size = (image.size[0], image.size[1]) if image and image.size[0] else CONFIG["fallback_texture"]
            pick = slot_of_loop == i
            texels[pick] = uv[pick] * size
    return texels


def poly_areas(uv, starts, totals):
    """Signed shoelace area of every polygon."""
    nxt = np.arange(len(uv)) + 1
    ends = starts + totals
    nxt[ends - 1] = starts                       # each polygon's last loop wraps to its first
    cross = uv[:, 0] * uv[nxt, 1] - uv[nxt, 0] * uv[:, 1]
    return np.add.reduceat(cross, starts) * 0.5 if len(starts) else np.zeros(0)


# --------------------------------------------------------------------------
# checking a layout
# --------------------------------------------------------------------------

def uv_islands(me, layer):
    """Island index per polygon, by UV connectivity on that layer."""
    active = me.uv_layers.active.name if me.uv_layers.active else None
    me.uv_layers.active = me.uv_layers[layer]
    try:
        islands = mesh_utils.mesh_linked_uv_islands(me)
    finally:
        if active:
            me.uv_layers.active = me.uv_layers[active]
    out = np.zeros(len(me.polygons), dtype=np.int32)
    for i, polys in enumerate(islands):
        out[polys] = i
    return out, len(islands)


def rasterise(me, uv, island_of_poly, size):
    """Per pixel centre: how many triangles cover it, and an island covering it.

    Strictly inside only, so two triangles sharing an edge never both claim the
    pixels on it: any count above 1 is a real overlap. Also returns the
    polygons caught in one.
    """
    me.calc_loop_triangles()
    tris = np.empty(len(me.loop_triangles) * 3, dtype=np.int64)
    me.loop_triangles.foreach_get("loops", tris)
    tri_poly = np.empty(len(me.loop_triangles), dtype=np.int64)
    me.loop_triangles.foreach_get("polygon_index", tri_poly)
    pts = uv[tris.reshape(-1, 3)] * size - 0.5          # pixel centres at whole numbers

    count = np.zeros((size, size), dtype=np.uint8)
    owner = np.full((size, size), -1, dtype=np.int64)
    overlapping = set()
    for (a, b, c), poly in zip(pts, tri_poly):
        x0 = max(int(math.floor(min(a[0], b[0], c[0]))), 0)
        x1 = min(int(math.ceil(max(a[0], b[0], c[0]))), size - 1)
        y0 = max(int(math.floor(min(a[1], b[1], c[1]))), 0)
        y1 = min(int(math.ceil(max(a[1], b[1], c[1]))), size - 1)
        if x1 < x0 or y1 < y0:
            continue
        det = (b[1] - c[1]) * (a[0] - c[0]) + (c[0] - b[0]) * (a[1] - c[1])
        if abs(det) < 1e-12:
            continue
        xs, ys = np.meshgrid(np.arange(x0, x1 + 1), np.arange(y0, y1 + 1))
        w0 = ((b[1] - c[1]) * (xs - c[0]) + (c[0] - b[0]) * (ys - c[1])) / det
        w1 = ((c[1] - a[1]) * (xs - c[0]) + (a[0] - c[0]) * (ys - c[1])) / det
        inside = (w0 > 1e-6) & (w1 > 1e-6) & (1.0 - w0 - w1 > 1e-6)
        ys, xs = ys[inside], xs[inside]
        taken = owner[ys, xs]
        if (taken >= 0).any():
            overlapping.add(int(poly))
            overlapping.update(int(p) for p in np.unique(taken[taken >= 0]))
        count[ys, xs] += 1
        owner[ys, xs] = poly
    label = np.where(owner >= 0, island_of_poly[np.clip(owner, 0, None)], -1).astype(np.int32)
    return count, label, overlapping


def island_gap(label, max_px):
    """Roughly how many pixels separate the two closest islands, or None if more than max_px.

    Grows every island outwards one pixel at a time until two of them meet.
    """
    lab = label.copy()
    h, w = lab.shape
    for step in range(max_px // 2 + 2):
        pad = np.pad(lab, 1, constant_values=-1)
        hi = lab.copy()
        lo = np.where(lab >= 0, lab, np.iinfo(np.int32).max)
        for dy, dx in ((0, 1), (2, 1), (1, 0), (1, 2), (0, 0), (0, 2), (2, 0), (2, 2)):
            n = pad[dy:dy + h, dx:dx + w]
            hi = np.maximum(hi, n)
            lo = np.where(n >= 0, np.minimum(lo, n), lo)
        if ((hi >= 0) & (lo != hi)).any():
            return 2 * step
        grow = (lab < 0) & (hi >= 0)
        if not grow.any():
            return None
        lab[grow] = hi[grow]
    return None


def check_layout(obj, layer, sources, size=None):
    """Is this UV map a usable paint layout? Returns a report dict."""
    me = obj.data
    starts, totals, _mats, _loop_poly = mesh_arrays(me)
    uv = read_uv(me, layer)
    report = {"layer": layer, "problems": []}

    lo, hi = uv.min(axis=0), uv.max(axis=0)
    if (lo < -1e-4).any() or (hi > 1 + 1e-4).any():
        report["problems"].append(f"reaches outside 0-1 (u {lo[0]:.2f}..{hi[0]:.2f}, "
                                  f"v {lo[1]:.2f}..{hi[1]:.2f})")
    if any(s["uv"] == layer for s in sources):
        report["problems"].append("it is the UV map the vanilla textures are read through")
    else:
        for src_layer in {s["uv"] for s in sources}:
            if np.allclose(uv, read_uv(me, src_layer), atol=1e-6):
                report["problems"].append(f"it is a copy of {src_layer!r}")

    # Texel density: UV area against the vanilla texels it stands for.
    texel_area = np.abs(poly_areas(source_uv_texels(obj, sources), starts, totals)).sum()
    uv_area = np.abs(poly_areas(uv, starts, totals)).sum()
    per_texel = math.sqrt(uv_area / texel_area) if texel_area > 0 else 0.0
    report["uv_per_texel"] = per_texel
    report["size"] = size or pick_size(per_texel)

    raster = min(report["size"], CONFIG["check_size"])
    scale = report["size"] / raster
    islands, n_islands = uv_islands(me, layer)
    count, label, overlapping = rasterise(me, uv, islands, raster)
    overlap = int((count > 1).sum())
    report["islands"] = n_islands
    report["overlapping_polys"] = sorted(overlapping)
    report["overlap"] = None
    if overlap:
        covered = max(int((count > 0).sum()), 1)
        report["overlap"] = (f"overlaps on {overlap} px ({overlap / covered:.1%} of what it "
                             f"covers, {len(overlapping)} faces)")
    report["coverage"] = float((count > 0).mean())

    want = gap_px(report["size"])
    gap = island_gap(label, int(math.ceil(2 * want / scale)))
    report["gap_px"] = None if gap is None else gap * scale
    ys, xs = np.nonzero(label >= 0)
    report["border_px"] = (min(xs.min(), ys.min(), raster - 1 - xs.max(), raster - 1 - ys.max()) * scale
                           if len(xs) else 0)
    return report


def describe(report):
    gap = report["gap_px"]
    gap_text = "more than twice the margin" if gap is None else f"~{gap:.0f} px"
    return (f"{report['islands']} islands, {report['coverage']:.0%} of a {report['size']}px "
            f"texture, closest islands {gap_text} apart, {report['border_px']:.0f} px from the edge")


# --------------------------------------------------------------------------
# making a layout
# --------------------------------------------------------------------------

def gap_px(size):
    return max(CONFIG["min_gap_px"], size // CONFIG["gap_divisor"])


def pick_size(uv_per_texel):
    if FORCED_SIZE:
        return FORCED_SIZE
    if uv_per_texel <= 0:
        return 1024
    want = next_pow2(CONFIG["density"] / uv_per_texel)
    return int(min(CONFIG["max_size"], max(CONFIG["min_size"], want)))


def pack(obj, layer, size):
    """Blender's own packer on the islands as they stand: uniform scale, 90-degree turns."""
    me = obj.data
    me.uv_layers.active = me.uv_layers[layer]
    bpy.ops.object.select_all(action="DESELECT")
    obj.select_set(True)
    bpy.context.view_layer.objects.active = obj
    bpy.ops.object.mode_set(mode="EDIT")
    try:
        bpy.ops.mesh.reveal(select=True)
        bpy.ops.mesh.select_all(action="SELECT")
        bpy.ops.uv.select_all(action="SELECT")
        # CARDINAL: the islands keep vanilla's texel grid square to the image,
        # so the bake resamples it without smearing. merge_overlap off is the
        # point of the whole exercise. FRACTION pads every island by the
        # margin, so two of them end up twice that apart.
        bpy.ops.uv.pack_islands(udim_source="CLOSEST_UDIM", rotate=True, rotate_method="CARDINAL",
                                scale=True, merge_overlap=False, margin_method="FRACTION",
                                margin=gap_px(size) / 2 / size, shape_method="CONCAVE")
    finally:
        bpy.ops.object.mode_set(mode="OBJECT")


def make_layout(obj, sources):
    """PaintUV from the source islands: texel-sized, unfolded, packed. Returns its size."""
    me = obj.data
    starts, totals, _mats, loop_poly = mesh_arrays(me)
    texels = source_uv_texels(obj, sources)

    # Mirrored halves sharing a seam form one island folded over itself, which
    # no packer can lay flat. Its faces wind the other way round in UV, so
    # nudging those apart cuts the island along the fold.
    area = poly_areas(texels, starts, totals)
    flipped = (area < -1e-9)[loop_poly]

    lo = texels.min(axis=0)
    extent = max(float((texels.max(axis=0) - lo).max()), 1e-9)
    uv = (texels - lo) / extent * 0.98
    uv[flipped, 0] += 0.01
    texel_area = np.abs(area).sum()

    layer = me.uv_layers.get(CONFIG["layer"]) or me.uv_layers.new(name=CONFIG["layer"], do_init=False)
    layer.uv.foreach_set("vector", uv.ravel())

    # Packing scales the islands to fit, so the texel density -- and with it
    # the texture size and the margin in UV units -- is only known after a
    # first pass. The second packs with the margin that size wants.
    size = 1024
    for _ in range(2):
        pack(obj, CONFIG["layer"], size)
        uv_area = np.abs(poly_areas(read_uv(me, CONFIG["layer"]), starts, totals)).sum()
        size = pick_size(math.sqrt(uv_area / texel_area) if texel_area > 0 else 0.0)
    if flipped.any():
        log(f"  cut {int(np.count_nonzero(area < -1e-9))} mirrored face(s) loose from the "
            f"islands they were folded onto")
    return size


# --------------------------------------------------------------------------
# baking and relinking
# --------------------------------------------------------------------------

def bake(obj, sources, layer, size, path):
    name = path.name
    margin = gap_px(size) // 2
    target = mw_bake.new_target_image(f"__paint_{name}", size, size, False, (0, 0, 0, 1))
    mats = [mw_bake.build_emit_material(f"__paint_emit_{i}", color=mw_bake.mw_diffuse_color(s["material"]),
                                        image=s["image"], uv_name=s["uv"], interpolation=s["interp"],
                                        extension=s["ext"], tint=mw_bake.mw_diffuse_color(s["material"]))
            for i, s in enumerate(sources)]
    me = obj.data
    render_layer = next((l.name for l in me.uv_layers if l.active_render), None)
    try:
        mw_bake.run_bake(obj, target, mats, margin=margin, uv_layer=layer)
        path.parent.mkdir(parents=True, exist_ok=True)
        target.file_format = "PNG"
        target.filepath_raw = str(path)
        target.save()
    finally:
        for m in mats:
            bpy.data.materials.remove(m)
        bpy.data.images.remove(target)
        if render_layer:
            me.uv_layers[render_layer].active_render = True

    image = next((i for i in bpy.data.images
                  if i.filepath and os.path.normpath(bpy.path.abspath(i.filepath)) == str(path)), None)
    if image is None:
        image = bpy.data.images.load(str(path))
        image.name = name
    else:
        image.reload()
    try:
        image.filepath = bpy.path.relpath(str(path))
    except ValueError:
        pass                                     # another drive: keep it absolute
    return image


def copy_alpha(src, dst):
    """The translucency the old material had; the colours are baked into the image."""
    try:
        dst.mw.alpha_flags = src.mw.alpha_flags
        dst.mw.alpha = src.mw.alpha
        if src.mw.use_alpha_blend:
            dst.mw.use_alpha_blend = True
        elif src.mw.use_alpha_clip:
            dst.mw.use_alpha_clip = True
        dst.alpha_threshold = src.alpha_threshold
        dst.use_backface_culling = src.use_backface_culling
    except Exception as exc:
        log(f"  !! could not copy translucency from {src.name!r}: {exc}")


def relink(obj, sources, image, layer, leave=()):
    from io_scene_mw import nif_shader
    for i, (slot, src) in enumerate(zip(obj.material_slots, sources)):
        source = src["material"]
        if source is None or i in leave:
            continue
        mat = slot.material if slot.material is not source else None
        if mat is None:
            mat = nif_shader.create_material(f"{source.name} paint")
            mat[CONFIG["source_property"]] = source   # an ID pointer keeps the original saved
            copy_alpha(source, mat)
            slot.material = mat
        mat.mw.base_texture.image = image
        mat.mw.base_texture.layer = layer
        mat.mw.base_texture.use_mipmaps = True
        mat.mw.base_texture.use_repeat = False
    obj.data.uv_layers.active = obj.data.uv_layers[layer]


# --------------------------------------------------------------------------
# per object
# --------------------------------------------------------------------------

def find_layout(obj, sources):
    """The UV map to check as the paint layout: PaintUV, else the first one no texture reads."""
    me = obj.data
    if is_prepared(obj):
        for slot in obj.material_slots:
            if slot.material is not None and CONFIG["source_property"] in slot.material.keys():
                layer = slot.material.mw.base_texture.layer
                if me.uv_layers.get(layer):
                    return layer
    if me.uv_layers.get(CONFIG["layer"]):
        return CONFIG["layer"]
    used = {s["uv"] for s in sources}
    return next((l.name for l in me.uv_layers
                 if l.name not in used and not l.name.endswith(CONFIG["backup_suffix"])), None)


def back_up_uvs(obj, sources):
    """Copy every UV map the textures are read through to <name>_backup, once.

    The script never writes to them, but a backup in the UV map list is the
    quickest way back to the original mapping whatever happens while painting.
    """
    me = obj.data
    active = me.uv_layers.active.name if me.uv_layers.active else None
    for name in sorted({s["uv"] for s in sources}):
        backup = name + CONFIG["backup_suffix"]
        if me.uv_layers.get(backup) or me.uv_layers.get(name) is None:
            continue
        layer = me.uv_layers.new(name=backup, do_init=False)
        if layer is None:
            log(f"  !! no room for {backup!r} -- a mesh holds at most 8 UV maps")
            continue
        layer.uv.foreach_set("vector", read_uv(me, name).ravel())
        log(f"  backed up {name!r} as {backup!r}")
    if active:
        me.uv_layers.active = me.uv_layers[active]


def keep_previous(path):
    """Move an existing texture aside as <name>_previous.png rather than bake over it."""
    if not path.is_file():
        return
    previous = path.with_name(f"{path.stem}_previous{path.suffix}")
    path.replace(previous)
    log(f"  the old {path.name} is kept as {previous.name}")


def select_faces(me, polys):
    """Leave exactly these faces selected, for Edit Mode."""
    _starts, _totals, _mats, loop_poly = mesh_arrays(me)
    faces = np.zeros(len(me.polygons), dtype=bool)
    faces[list(polys)] = True
    loops = faces[loop_poly]
    loop_verts = np.empty(len(me.loops), dtype=np.int64)
    me.loops.foreach_get("vertex_index", loop_verts)
    loop_edges = np.empty(len(me.loops), dtype=np.int64)
    me.loops.foreach_get("edge_index", loop_edges)
    verts = np.zeros(len(me.vertices), dtype=bool)
    verts[loop_verts[loops]] = True
    edges = np.zeros(len(me.edges), dtype=bool)
    edges[loop_edges[loops]] = True
    me.vertices.foreach_set("select", verts)
    me.edges.foreach_set("select", edges)
    me.polygons.foreach_set("select", faces)


def mirror_note(obj):
    for mod in obj.modifiers:
        if mod.type == "MIRROR" and mod.show_render and not (mod.use_mirror_u or mod.use_mirror_v
                                                              or mod.offset_u or mod.offset_v):
            log(f"  note: {mod.name!r} lays both halves on the same texels, so painting one paints "
                f"the other -- apply it first to paint them apart")
            return


def process(obj, args, out_dir):
    log(f"--- {obj.name}")
    for slot in obj.material_slots:
        mw_bake.repair_mw_material(source_material(slot.material))
    if not obj.material_slots or not obj.data.uv_layers:
        log("  !! no materials or no UV map -- skipped")
        return None

    prepared = is_prepared(obj)
    path = out_dir / f"{mw_bake.slugify(obj.name)}.png"
    if prepared and not args["overwrite"] and not args["check"]:
        log(f"  already prepared ({path.name}) -- left alone so the painting survives; "
            f"--overwrite re-bakes it from the vanilla textures")
        return None

    sources = slot_sources(obj)
    # On a [Bake] object mw_bake.py ships an untagged material as it is, so it
    # must keep reading its vanilla texture: the game cannot load one from
    # bake_source/. It still gets its place in the layout, unpainted.
    baked_later = mw_bake.CONFIG["bake_tag"] in obj.name.lower()
    leave = {i for i, src in enumerate(sources)
             if baked_later and not mw_bake.material_is_baked(src["material"])}
    for i, src in enumerate(sources):
        image = src["image"]
        if image is not None and not image.size[0]:
            log(f"  !! {image.name!r} is missing on disk -- that part would bake magenta")
        log(f"  slot {src['material'].name if src['material'] else None!r}: "
            f"{image.name if image else 'no texture'} through {src['uv']!r}")
        if i in leave:
            log(f"  {src['material'].name!r} keeps its own texture, as mw_bake.py will ship it "
                f"untagged -- tag it to paint it")

    layer = find_layout(obj, sources)
    report = check_layout(obj, layer, sources) if layer else None
    # An overlap rules out a layout of yours, but not PaintUV: making that
    # again would only bring back the same twisted faces, and lose any fixing
    # done to it by hand.
    problems = [] if report is None else report["problems"] + (
        [report["overlap"]] if report["overlap"] and layer != CONFIG["layer"] else [])
    if report is None:
        log("  no second UV map")
    elif problems:
        log(f"  {layer!r} cannot be painted on: {'; '.join(problems)}")
    else:
        note = f"; still {report['overlap']}" if report["overlap"] else ""
        log(f"  {layer!r} is a usable layout: {describe(report)}{note}")

    usable = report is not None and not problems
    if args["check"]:
        if not usable:
            log(f"  -> would make {CONFIG['layer']!r} from the islands of {sources[0]['uv']!r}")
        return None
    back_up_uvs(obj, sources)
    if args["relayout"] or not usable:
        if layer and layer != CONFIG["layer"]:
            log(f"  {layer!r} is left as it is; the new layout goes in {CONFIG['layer']!r}")
        size = make_layout(obj, sources)
        layer = CONFIG["layer"]
        report = check_layout(obj, layer, sources, size)
        problems = report["problems"] + ([report["overlap"]] if report["overlap"] else [])
        state = "made" if not problems else "made, but " + "; ".join(problems)
        log(f"  {layer!r} {state}: {describe(report)}")
        if report["overlapping_polys"]:
            # Packing moves whole islands. A face twisted or folded in the
            # source UV map stays that way, and only re-unwrapping it would
            # change that.
            select_faces(obj.data, report["overlapping_polys"])
            log(f"  those {len(report['overlapping_polys'])} faces are twisted or folded in "
                f"{sources[0]['uv']!r} itself; painting there lands on both. Left selected "
                f"in Edit Mode")
    size = report["size"]
    per_texel = report["uv_per_texel"] * size
    log(f"  texture {size}x{size}: {per_texel:.1f} px per vanilla texel, "
        f"{gap_px(size)} px between islands")

    mirror_note(obj)
    keep_previous(path)
    if mw_bake.CONFIG["bake_tag"] not in obj.name.lower():
        log("  note: not tagged [Bake] -- the game cannot load a texture from bake_source/. "
            "With [Bake], mw_bake.py makes the game texture from the painting")
    image = bake(obj, sources, layer, size, path)
    relink(obj, sources, image, layer, leave)
    log(f"  baked -> {path.relative_to(mw_bake.blend_dir())}")
    return path


# --------------------------------------------------------------------------
# entry point
# --------------------------------------------------------------------------

FORCED_SIZE = None


def parse_args(argv):
    args = {"save": False, **RUN_OPTIONS}
    # Flags are only this script's when Blender was started with it (--python);
    # run as a text block, whatever followed a "--" was meant for something else.
    head = argv[:argv.index("--")] if "--" in argv else argv
    if not any(pathlib.Path(a).name == pathlib.Path(__file__).name for a in head) or "--" not in argv:
        return args
    argv = argv[argv.index("--") + 1:]
    flags = {"--save": "save", "--check": "check", "--relayout": "relayout", "--overwrite": "overwrite"}
    i = 0
    while i < len(argv):
        a = argv[i]
        if a in ("--help", "-h"):
            print(__doc__)
            raise Abort("help")
        elif a in flags:
            args[flags[a]] = True
        elif a in ("--only", "--res"):
            if i + 1 >= len(argv) or argv[i + 1].startswith("--"):
                die(f"{a} needs a value after it", ["e.g. --only silver", "e.g. --res 2048"])
            i += 1
            args[a[2:]] = argv[i]
        else:
            die(f"unknown option {a!r}",
                ["Valid options: --save --only NAME --check --relayout --overwrite --res N --help"])
        i += 1
    if args["res"] is not None:
        try:
            args["res"] = int(args["res"])
        except ValueError:
            die(f"--res wants a whole number, got {args['res']!r}")
    return args


def find_targets(args):
    meshes = [o for o in bpy.context.scene.objects if o.type == "MESH"]
    # Run by hand, the selection is what was meant. Otherwise the tagged
    # meshes, and those already prepared however they were picked.
    targets = [o for o in bpy.context.selected_objects if o.type == "MESH"] if not bpy.app.background else []
    how = "selected"
    if not targets:
        targets = [o for o in meshes if CONFIG["tag"] in o.name.lower() or is_prepared(o)]
        how = "tagged [Paint] or already prepared"
    if not targets and args["check"]:
        targets = [o for o in meshes if len(o.data.uv_layers) > 1]
        how = "with a second UV map"
    if args["only"]:
        targets = [o for o in targets if args["only"].lower() in o.name.lower()]
    return targets, how


def main():
    global FORCED_SIZE
    args = parse_args(list(sys.argv))
    FORCED_SIZE = args["res"]
    if not bpy.data.filepath:
        die("this .blend has never been saved", ["The texture is written next to it."])

    targets, how = find_targets(args)
    if not targets and args["check"] and not args["only"]:
        log("no mesh is tagged [Paint] and none has a second UV map: tagging one makes "
            f"{CONFIG['layer']!r} for it from its own islands")
        return
    if not targets and args["only"]:
        die(f"nothing {how} matches --only {args['only']!r}")
    if not targets:
        die("found nothing to prepare",
            ["Put [Paint] in the OBJECT name of each mesh you want to paint,",
             "or select them and run this from Blender's Text Editor."])
    log(f"{len(targets)} mesh(es) {how}" + (" -- checking only" if args["check"] else ""))

    if bpy.context.object and bpy.context.object.mode != "OBJECT":
        bpy.ops.object.mode_set(mode="OBJECT")
    selected = [o for o in bpy.context.selected_objects]
    active = bpy.context.view_layer.objects.active

    out_dir = mw_bake.blend_dir() / CONFIG["out_dir"]
    written = []
    for obj in targets:
        # Edit Mode refuses a hidden object, and packing needs it.
        hidden = obj.hide_viewport, obj.hide_render, obj.hide_get()
        obj.hide_viewport = obj.hide_render = False
        obj.hide_set(False)
        try:
            path = process(obj, args, out_dir)
        finally:
            obj.hide_viewport, obj.hide_render = hidden[:2]
            obj.hide_set(hidden[2])
        if path:
            written.append((obj.name, path))

    bpy.ops.object.select_all(action="DESELECT")
    for obj in selected:
        obj.select_set(True)
    bpy.context.view_layer.objects.active = active

    if written:
        log("=" * 60)
        for name, path in written:
            log(f"{name}  ->  {path.relative_to(mw_bake.blend_dir())}")
        log("Paint in Texture Paint mode; Image > Save (Alt+S) writes the painting to the PNG.")
    if args["save"] and not args["check"]:
        bpy.ops.wm.save_mainfile()
        log(f"saved {bpy.data.filepath}")


def show_in_blender(failed):
    """The log, minus the per-slot detail, as a popup -- the console is easy to miss."""
    lines = [line for line in LOG if line and not line.startswith("  slot ")]

    def draw(self, _context):
        for line in lines:
            self.layout.label(text=line)

    bpy.context.window_manager.popup_menu(
        draw, title="mw_paint_prep: " + ("stopped" if failed else "done"),
        icon="ERROR" if failed else "INFO")


if __name__ == "__main__":
    LOG.clear()
    try:
        main()
    except Abort as exc:
        if bpy.app.background:
            raise SystemExit(0 if str(exc) == "help" else 1)
        show_in_blender(True)
    else:
        if not bpy.app.background:
            show_in_blender(False)

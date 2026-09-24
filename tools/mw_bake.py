"""
mw_bake.py -- albedo bake / PBR spec map / normal map for Morrowind weapon meshes.

Bakes every mesh whose object name contains "[Bake]" down to ONE albedo texture,
writes a matching "Aesthetically Shiny Things"-style _spec.dds PBR map, and a
_n.dds normal map, then points the object at them ready for io_scene_mw export.

Requires: Blender 4.x/5.x, the io_scene_mw addon, and ImageMagick ("magick").

Run headless:
    blender -b your.blend --python tools/mw_bake.py -- --save

Flags (after the "--"):
    --save            save the .blend when finished
    --only NAME       only process objects whose name contains NAME
    --no-spec         skip _spec.dds generation
    --no-norm         skip _n.dds generation
    --res N           force every bake to N x N

------------------------------------------------------------------------------
SETTING MATERIAL PROPERTIES FROM INSIDE BLENDER
------------------------------------------------------------------------------
Everything below is driven by Blender custom properties, so nothing has to be
edited in this file. Add them in the Properties editor under
"Custom Properties" -- on the MATERIAL (preferred; it can differ per slot) or
on the OBJECT (applies to all its slots).

MATERIAL NAME TAGS (the usual way to drive this)
    [Metal]       like the iron spear head  -- 206, 60, 132
    [MetalRough]  like the daedric brackets -- 255, 89, 132   (= [RoughMetal])
    [PlateRough]  like the orcish bracket   -- 173, 85, 132   (= [RoughPlate])
    [Glass]       volcanic glass            -- 250, 81, 132
    [NormGen]     normal map from this material's baked albedo
    [Bump]        the supplied tiling metal normal instead
    [Alpha]       translucent (read by mw_export.py, not by this script)
    A material with no metal tag bakes as plain non-metal.

CUSTOM PROPERTIES (per material, or per object as a fallback)
    mw_spec            "tarnished"        a preset name from SPEC_PRESETS
                       "206,60,132"       or explicit R,G,B bytes
                                          R = metalness, G = roughness, B = AO
    mw_metal           206                override just one channel (0-255)
    mw_rough           60
    mw_ao              132
    mw_albedo_gain     1.25               opt-in albedo multiplier (default 1.0 = off)
    mw_normal          "both"             none | detail | albedo | both
    mw_normal_slope    62                 target max slope in degrees (albedo relief)
    mw_detail_tiles    1.5                how often the detail normal repeats
    mw_detail_slope    5.5                detail-only slope in degrees
    mw_max_res         256                clamp this object's baked texture

Resolution order: material custom property > object custom property >
"Aesthetically Shiny Things" lookup > keyword fallback > default.

Object name tags still work too: "[Bake]" marks it for baking, and "[NormGen]"
switches its normal map from the supplied tiling metal grain to albedo-derived
relief. It is one or the other, never both.
"""

import binascii
import hashlib
import math
import pathlib
import re
import struct
import subprocess
import sys

import bpy
import mathutils
import numpy as np

# --------------------------------------------------------------------------
# PBR presets  (R = metalness, G = roughness, B = ambient occlusion, 0-255)
# --------------------------------------------------------------------------
#
# Values are raw bytes as OpenMW-PBR reads them:
#     metallicity = specTex.r
#     roughness   = specTex.g ** 2      (squared! small G changes matter a lot)
#     ao          = specTex.b           (a straight multiplier on ambient light)
#
# Metalness is a COVERAGE mask, not a shininess dial: use it to say how much of
# the texel is bare metal. For "shiny but softer", raise roughness instead.
#
# The one honest exception is exactly what "tarnished" is: an oxide film is a
# dielectric layer sitting on top of metal, so partial coverage is real.
#
# Note on the 206 values: that is Aesthetically Shiny Things' own figure for
# tx_w_spear_iron_top and tx_w_iron_shortsword_blade. Leaving ~19% diffuse is
# what stops a vanilla texture's painted detail from vanishing into pure
# reflection, which is why those read so well in game.

SPEC_PRESETS = {
    # -- metals that keep their albedo readable (recommended for blades) ------
    "iron":            (206,  60, 132),   # the mod's own iron-spear-head recipe
    "steel":           (206,  52, 132),
    "silver":          (216,  62, 132),
    "ebony":           (212,  40, 132),
    "daedric":         (212,  40, 132),
    "orcish":          (212,  45, 132),   # orcish WEAPON (mod: 255,32 -- softened like the others)
    # Morrowind "glass" is volcanic glass, and Aesthetically Shiny Things treats
    # it as a metal rather than a dielectric: R=250 across its whole glass set.
    # Pair with [Alpha] on the material if the piece should also be see-through.
    "glass":           (250,  81, 132),

    # -- partial-coverage / plate: the mod's own values, albedo survives ------
    "orcish_plate":    (173,  85, 132),   # tx_a_shape_orcish -- your orcish bracket
    "plate":           (173,  85, 132),
    "rough_metal":     (255,  89, 132),   # tx_a_daedric_leather00 -- your daedric bracket
    "matte_metal":     (255, 170, 132),   # the mod's dullest full metal

    # -- full metal, most aggressive; albedo becomes pure reflection colour ---
    "mirror":          (255,  28, 132),
    "polished":        (255,  40, 132),
    "metal":           (255,  69, 132),
    "satin":           (255, 100, 132),
    "worn":            (255, 140, 132),

    # -- oxide films: partial coverage is physically correct here -------------
    "tarnished":       (180, 130, 132),
    "tarnished_heavy": (140, 165, 132),
    "patina":          (110, 180, 132),
    "rusted":          ( 45, 205, 132),

    # -- dielectrics ---------------------------------------------------------
    "chitin":          (  0, 130, 132),   # the mod's own value for all chitin
    "bone":            (  0, 120, 132),
    "leather":         (  0, 150, 132),
    "cloth":           (  0, 190, 132),
    "wood":            (  0, 142, 132),
    "stone":           (  0, 175, 132),
}

# --------------------------------------------------------------------------
# MATERIAL NAME TAGS
# --------------------------------------------------------------------------
# Put these in the MATERIAL name. They are only honoured when the OBJECT itself
# carries [Bake], so a material shared with non-baked objects is unaffected.
#
#   [Metal]       like the iron spear head   -- our most metallic metal
#   [RoughMetal]  like the daedric brackets  -- full metal, rough
#   [RoughPlate]  like the orcish bracket    -- partial coverage, rough
#   [NormGen]     albedo-derived relief for this material's area
#   [Bump]        the supplied tiling metal normal for this material's area
#
# [NormGen] and [Bump] are mutually exclusive. A material with no metal tag gets
# vanilla non-metal values, and one with neither normal tag stays flat.

MATERIAL_TAGS = {
    "[metal]":      "iron",           # (206, 60, 132)
    # both word orders accepted -- easy to type it either way
    "[roughmetal]": "rough_metal",    # (255, 89, 132)
    "[metalrough]": "rough_metal",
    "[roughplate]": "orcish_plate",   # (173, 85, 132)
    "[platerough]": "orcish_plate",
    "[glass]":      "glass",          # (250, 81, 132)
}
NORMGEN_TAG = "[normgen]"
BUMP_TAG = "[bump]"
NORMCOPY_TAG = "[normcopy]"
# Read by mw_export.py rather than here, but still legitimate on a material.
EXPORT_TAGS = {"[alpha]", "[alphaclip]"}
KNOWN_TAGS = set(MATERIAL_TAGS) | {NORMGEN_TAG, BUMP_TAG, NORMCOPY_TAG} | EXPORT_TAGS

CONFIG = {
    "bake_tag": "[bake]",
    "norm_tag": "[normgen]",

    # Output, relative to the .blend. Keep "textures" in the path: the exporter
    # turns ".../textures/katars/x.dds" into "textures\katars\x.dds".
    "out_dir": "textures/katars",
    "png_dir": "bake_source",

    # UV unwrap for the bake layer.
    "uv_layer": "BakeUV",
    "smart_angle": math.radians(66.0),
    "island_margin": 0.02,
    # Iterations of Blender's stretch minimiser after the projection. 0 = off.
    "minimize_stretch": 64,

    # Sizing. The packed layout is rescaled to fill 0-1 and the image gets a
    # matching non-square aspect -- blades unwrap to long thin islands, so a
    # square image would be mostly empty.
    # max_axis 256 matches this mod's textures: of 1195 of them, 97% top out at
    # 256 and only 34 reach 512.
    "auto_size": True,
    "non_square": True,
    "min_axis": 16,   # the mod itself ships 16px textures (tx_w_ebony_edging is 16x64)
    "max_axis": 256,
    "max_aspect": 8,
    "texel_multiplier": 2.0,
    "uv_border_texels": 2.0,
    "forced_size": None,
    "bake_margin_px": 8,

    "drop_source_uv": True,

    # --- spec map ---
    "make_spec": True,
    "spec_mode": "baked",         # "baked" = per-material; "flat" = one colour
    "spec_size_divisor": 2,
    "shiny_dir": None,            # None = auto-detect
    "spec_default": (0, 128, 132),
    # What a material with no metal tag gets. R=0 is "not metal at all", which
    # is what vanilla Morrowind effectively is. G/B still have to be written
    # because the presence of a _spec map disables OpenMW's roughness guess.
    "untagged_spec": (0, 128, 132),
    # "vanilla": untagged -> untagged_spec (what you asked for).
    # "guess":   fall back to the old keyword + Aesthetically Shiny Things lookup.
    "untagged_mode": "vanilla",
    # Prefer a preset over the Aesthetically Shiny Things lookup. The mod's
    # blade values are full-metal + near-mirror, which is what buries the albedo.
    "prefer_presets": True,
    "spec_fallbacks": [
        # Specific armour/plate textures first: the mod makes them markedly
        # duller than the weapon of the same material (tx_a_shape_orcish is
        # 173,85 where tx_w_orcish_waraxe is 255,32).
        ("shape_orcish", "orcish_plate"),
        ("daedric_leather", "rough_metal"),
        ("daedric", "daedric"), ("ebony", "ebony"), ("glass", "glass"),
        ("orcish", "orcish"), ("steel", "steel"), ("silver", "silver"),
        ("iron", "iron"), ("dwe", "iron"), ("dwarv", "iron"),
        ("leather", "leather"), ("chitin", "chitin"), ("bone", "bone"),
        ("wood", "wood"), ("handle", "wood"), ("grip", "wood"),
        ("shirt", "cloth"), ("cloth", "cloth"),
    ],

    # --- albedo ---
    # Left at 1.0 on purpose. The baked .dds IS the plain diffuse texture, used
    # by vanilla OpenMW shaders as much as by the PBR ones, so brightening it to
    # flatter a metal under PBR would make the mod look wrong for anyone without
    # those shaders. Fix dull metal with the spec map (metalness / roughness /
    # AO) instead -- that only exists when PBR is active.
    # mw_albedo_gain is still honoured per material if you deliberately want it.
    "albedo_gain": 1.0,

    # --- normal map ---
    "make_norm": True,
    "norm_suffix": "_n",
    # Relief is generated with Blender's own Bump node baked through Cycles'
    # NORMAL pass -- not a hand-rolled gradient.
    # Bump "Distance" is in world units and these weapons are ~0.1 units across,
    # so any fixed value saturates: at 0.05 the raw relief came out at p99 ~88
    # degrees with no dynamic range left, and the rescale then flattened the
    # whole map to a uniform ~3 degrees. Scaling it to the object keeps the
    # relief varied. bump_distance is the fallback if _rel is set to None.
    "bump_distance": 0.05,
    "bump_distance_rel": 0.01,    # fraction of the world bounding diagonal
    "bump_strength": 1.0,
    # Bump strength depends on object scale, so the result is rescaled to a
    # predictable maximum slope instead of being left to chance.
    "norm_slope_deg": 62.0,
    "norm_slope_percentile": 99.0,   # anchor; the median lands far below it
    # Height prep before the Bump node.
    "norm_highpass": True,
    "norm_highpass_sigma": 6.0,
    # [NormCopy]: where to look for an existing _nh / _n beside a source texture.
    # None = read OpenMW's own data paths from openmw.cfg (same VFS the game
    # uses), falling back to scanning the mods folder next to this .blend.
    "normal_search_dirs": None,
    "openmw_cfg": None,           # None = try the usual locations

    # Tiling detail normal. Relative to the .blend.
    "detail_normal": "Sources/Metal061B_1K-JPG_NormalGL.jpg",
    # One 512x512 quarter of the 1K source halves the grain frequency before any
    # tiling; 1.5 repeats instead of 4 drops it further (~5x coarser overall);
    # 11 degrees is 30% of the old 38. None crop = use the whole image.
    "detail_crop": "512x512+0+0",
    "detail_tiles": 1.5,
    "detail_slope_deg": 5.5,

    # OpenMW reads normal maps as OpenGL tangent space (green = +V).
    "norm_flip_green": False,

    "magick": "magick",
}


# --------------------------------------------------------------------------
# helpers
# --------------------------------------------------------------------------

def log(msg):
    print(f"[mw_bake] {msg}")


def slugify(name):
    name = re.sub(r"\[[^\]]*\]", " ", name)
    name = re.sub(r"[^0-9A-Za-z]+", "_", name).strip("_").lower()
    return name or "baked"


def next_pow2(n):
    return 1 << max(0, (int(n) - 1)).bit_length()


def blend_dir():
    if not bpy.data.filepath:
        raise RuntimeError("Save the .blend first -- output paths are relative to it.")
    return pathlib.Path(bpy.data.filepath).parent


def png_to_dds(png_path, dds_path):
    """Uncompressed 32-bit DDS with mipmaps, matching the mod's other textures."""
    dds_path.parent.mkdir(parents=True, exist_ok=True)
    subprocess.run([CONFIG["magick"], str(png_path), "-alpha", "set",
                    "-define", "dds:compression=none", str(dds_path)],
                   check=True, capture_output=True)
    return dds_path


def name_tags(name):
    """Every [tag] in a name, lowercased."""
    return set(re.findall(r"\[[^\]]*\]", (name or "").lower()))


def material_spec_preset(mat):
    tags = name_tags(mat.name if mat else "")
    for tag, preset in MATERIAL_TAGS.items():
        if tag in tags:
            return preset, tag
    return None, None


def warn_unknown_tags(mat):
    unknown = [t for t in name_tags(mat.name if mat else "")
               if t not in KNOWN_TAGS and not NORM_TAG_RE.fullmatch(t)]
    if unknown:
        log(f"  !! {mat.name!r} has unrecognised tag(s) {' '.join(unknown)} -- "
            f"known: {' '.join(sorted(KNOWN_TAGS))}")


NORM_TAG_RE = re.compile(r"\[(normgen|bump|normcopy)(\d+)?\]")


def material_norm_mode(mat):
    """(mode, strength) for one material.

    mode is 'normgen' | 'bump' | 'normcopy' | 'flat'. A number inside the tag is
    a percentage of full strength, so [NormGen50] is half as deep as [NormGen]
    and [NormGen] is the same as [NormGen100].
    """
    picked = []
    for tag in sorted(name_tags(mat.name if mat else "")):
        m = NORM_TAG_RE.fullmatch(tag)
        if m:
            picked.append((m.group(1), int(m.group(2)) / 100.0 if m.group(2) else 1.0))
    if len(picked) > 1:
        log(f"  !! {mat.name!r} carries {len(picked)} normal tags "
            f"{[p[0] for p in picked]} -- they are mutually exclusive, "
            f"using {picked[0][0]!r}")
    return picked[0] if picked else ("flat", 1.0)


def mw_prop(material, obj, key, default=None):
    """Custom property lookup: material wins, then object, then default."""
    for holder in (material, obj):
        if holder is not None and key in holder.keys():
            return holder[key]
    return default


# --------------------------------------------------------------------------
# reading the io_scene_mw material
# --------------------------------------------------------------------------

def mw_base_texture(mat):
    """(image, uv_layer, interpolation, extension), read from the node group.

    Deliberately not material.mw.base_texture: that bookkeeping is lost whenever
    a material is duplicated -- see repair_mw_material().
    """
    if not (mat and mat.use_nodes):
        return None, None, "Linear", "REPEAT"
    group = mat.node_tree.nodes.get("MW Inputs")
    if not (group and group.node_tree):
        return None, None, "Linear", "REPEAT"
    node = group.node_tree.nodes.get("Base Texture")
    if not (node and node.image):
        return None, None, "Linear", "REPEAT"
    return node.image, _walk_back_to_uv(node), node.interpolation, node.extension


def mw_diffuse_color(mat):
    try:
        return tuple(mat.node_tree.nodes["MW Shader"].inputs["Diffuse Color"].default_value)
    except Exception:
        return (1.0, 1.0, 1.0, 1.0)


def _walk_back_to_uv(node, depth=0, seen=None):
    if depth > 8:
        return None
    seen = seen if seen is not None else set()
    if node in seen:
        return None
    seen.add(node)
    if node.type == "UVMAP":
        return node.uv_map
    for socket in node.inputs:
        for link in socket.links:
            got = _walk_back_to_uv(link.from_node, depth + 1, seen)
            if got:
                return got
    return None


def repair_mw_material(mat):
    """Restore io_scene_mw bookkeeping that Blender drops when copying a material.

    Duplicating a MW material copies the node tree but not material.mw:
    mw.material (a self-pointer) comes back None and mw.texture_slots comes back
    empty. nif_export.py:953 wraps material.mw.validate() in
    `except TypeError: bl_prop = None`, and validate() opens with
    `if not (m and m.use_nodes): raise TypeError` -- so with the self-pointer
    gone the submesh exports with NO NiMaterialProperty and NO
    NiTexturingProperty, and OpenMW draws it plain white.
    """
    if not (mat and mat.use_nodes):
        return False
    group = mat.node_tree.nodes.get("MW Inputs")
    if not (group and group.node_tree):
        return False

    repaired = []
    if mat.mw.material != mat:
        mat.mw.material = mat
        repaired.append("self-pointer")

    slots = mat.mw.texture_slots
    tex_nodes = [n for n in group.node_tree.nodes if n.type == "TEX_IMAGE"]
    if not len(slots) and tex_nodes:
        for node in tex_nodes:
            slot = slots.add()
            slot.node_tree = group.node_tree
            slot.name = node.name
        for node in tex_nodes:
            slot = slots[node.name]
            if node.image:
                slot.image = node.image
                for link in node.inputs[0].links:
                    uv = _walk_back_to_uv(link.from_node)
                    if uv:
                        slot.layer = uv
                    break
        repaired.append("texture slots")

    if not repaired:
        return False
    log(f"  repaired {' + '.join(repaired)} on {mat.name!r}")
    return True


repair_mw_texture_slots = repair_mw_material          # old name, still used


def repair_all_materials():
    """Scene-wide sweep for the duplicated-material bug. Safe to run any time."""
    fixed = []
    for mat in bpy.data.materials:
        if repair_mw_material(mat):
            users = [o.name for o in bpy.data.objects
                     for s in o.material_slots if s.material == mat]
            fixed.append((mat.name, users))
    if fixed:
        log(f"repaired {len(fixed)} material(s) that would have exported untextured:")
        for name, users in fixed:
            log(f"    {name}  used by {users or '<nothing>'}")
    return fixed


# --------------------------------------------------------------------------
# spec colour resolution
# --------------------------------------------------------------------------

def find_shiny_dir():
    if CONFIG["shiny_dir"]:
        p = pathlib.Path(CONFIG["shiny_dir"])
        return p if p.is_dir() else None
    mods = blend_dir().parent
    if not mods.is_dir():
        return None
    for entry in sorted(mods.iterdir()):
        if entry.is_dir() and "shiny" in entry.name.lower():
            for candidate in entry.rglob("textures"):
                if any(candidate.glob("*_spec.dds")):
                    return candidate
    return None


_SHINY_CACHE = {}


def _parse_spec(value):
    """'tarnished' or '206,60,132' or (206,60,132) -> (r, g, b) bytes."""
    if value is None:
        return None
    if isinstance(value, (tuple, list)) and len(value) >= 3:
        return tuple(int(round(float(c))) for c in value[:3])
    text = str(value).strip()
    if text.lower() in SPEC_PRESETS:
        return SPEC_PRESETS[text.lower()]
    parts = re.split(r"[,\s]+", text)
    if len(parts) >= 3:
        try:
            return tuple(max(0, min(255, int(round(float(p))))) for p in parts[:3])
        except ValueError:
            pass
    log(f"  !! unrecognised mw_spec {value!r}; known presets: {', '.join(sorted(SPEC_PRESETS))}")
    return None


def _read_flat_color(path):
    """Representative colour of a DDS as raw bytes, ignoring colour management."""
    img = None
    try:
        img = bpy.data.images.load(str(path), check_existing=False)
        img.colorspace_settings.name = "Non-Color"
        px = np.array(img.pixels[:], dtype=np.float32).reshape(-1, 4)
        if not len(px):
            return None
        # Median, not mean: these ship as DXT1, so a mean drags the authored
        # byte off by a fraction (132 -> 132.4 -> 133).
        mid = np.median(px[:, :3], axis=0)
        return tuple(int(round(float(c) * 255.0)) for c in mid)
    except Exception as exc:
        log(f"  could not read {path.name}: {exc}")
        return None
    finally:
        if img is not None:
            bpy.data.images.remove(img)


def spec_color_for(material, obj, image, shiny_dir):
    """Resolve one material's (R, G, B) spec bytes.

    mw_spec custom property > [tag] in the material name > untagged default.
    """
    explicit = _parse_spec(mw_prop(material, obj, "mw_spec"))
    source = "mw_spec property"

    if explicit is None:
        preset, tag = material_spec_preset(material)
        if preset:
            explicit, source = SPEC_PRESETS[preset], f"{tag} -> {preset}"
        elif CONFIG["untagged_mode"] == "guess":
            explicit, source = _guess_spec(image, shiny_dir)
        else:
            explicit, source = CONFIG["untagged_spec"], "untagged -> non-metal"

    r, g, b = explicit
    over = []
    for key, idx in (("mw_metal", 0), ("mw_rough", 1), ("mw_ao", 2)):
        val = mw_prop(material, obj, key)
        if val is not None:
            v = max(0, min(255, int(round(float(val)))))
            r, g, b = (v if idx == 0 else r), (v if idx == 1 else g), (v if idx == 2 else b)
            over.append(f"{key}={v}")
    if over:
        source += " + " + ", ".join(over)
    return (r, g, b), source


def _guess_spec(image, shiny_dir):
    """Legacy keyword + Aesthetically Shiny Things lookup (untagged_mode='guess')."""
    stem = pathlib.Path(image.name).stem.lower() if image else ""
    preset = None
    for key, preset_name in CONFIG["spec_fallbacks"]:
        if key in stem:
            preset = preset_name
            break
    if CONFIG["prefer_presets"] and preset:
        return SPEC_PRESETS[preset], f"preset {preset!r}"
    if stem and stem in _SHINY_CACHE:
        return _SHINY_CACHE[stem], "Shiny Things (cached)"
    if stem and shiny_dir:
        for name in (f"{stem}_spec.dds", f"{stem}_SPEC.dds"):
            path = shiny_dir / name
            if path.is_file():
                got = _read_flat_color(path)
                if got:
                    _SHINY_CACHE[stem] = got
                    return got, "Aesthetically Shiny Things"
                break
    if preset:
        return SPEC_PRESETS[preset], f"preset {preset!r}"
    return CONFIG["spec_default"], "default"


# --------------------------------------------------------------------------
# UV work
# --------------------------------------------------------------------------

def _uv_stats(me, layer_name):
    uvs = me.uv_layers[layer_name].uv
    if not len(uvs):
        return (0.0, 0.0, 1.0, 1.0), 0.0
    pts = [tuple(uvs[i].vector) for i in range(len(uvs))]
    u0, u1 = min(p[0] for p in pts), max(p[0] for p in pts)
    v0, v1 = min(p[1] for p in pts), max(p[1] for p in pts)
    area = 0.0
    for poly in me.polygons:
        loop = [tuple(uvs[i].vector) for i in poly.loop_indices]
        acc = 0.0
        for k in range(len(loop)):
            x1, y1 = loop[k]
            x2, y2 = loop[(k + 1) % len(loop)]
            acc += x1 * y2 - x2 * y1
        area += abs(acc) * 0.5
    return (u0, v0, u1, v1), area


def count_source_texels(obj):
    """How many texels of the ORIGINAL textures this mesh actually samples."""
    me = obj.data
    source_uv = None
    for slot in obj.material_slots:
        _, uv_name, _, _ = mw_base_texture(slot.material)
        if uv_name and me.uv_layers.get(uv_name):
            source_uv = uv_name
            break
    layer = me.uv_layers.get(source_uv) if source_uv else me.uv_layers.active
    if layer is None:
        return 512.0 * 512.0

    sizes = {}
    for i, slot in enumerate(obj.material_slots):
        image, _, _, _ = mw_base_texture(slot.material)
        sizes[i] = (image.size[0], image.size[1]) if image and image.size[0] else (256, 256)

    uvs = layer.uv
    total = 0.0
    for poly in me.polygons:
        loop = [tuple(uvs[i].vector) for i in poly.loop_indices]
        acc = 0.0
        for k in range(len(loop)):
            x1, y1 = loop[k]
            x2, y2 = loop[(k + 1) % len(loop)]
            acc += x1 * y2 - x2 * y1
        w, h = sizes.get(poly.material_index, (256, 256))
        total += abs(acc) * 0.5 * w * h
    return total


def _evaluated_geometry(obj):
    """(vertex array, per-polygon material index array) with modifiers applied."""
    depsgraph = bpy.context.evaluated_depsgraph_get()
    eval_obj = obj.evaluated_get(depsgraph)
    me = eval_obj.to_mesh()
    try:
        verts = np.empty(len(me.vertices) * 3, dtype=np.float64)
        me.vertices.foreach_get("co", verts)
        mats = np.empty(len(me.polygons), dtype=np.int32)
        me.polygons.foreach_get("material_index", mats)
        return verts.reshape(-1, 3), mats
    finally:
        eval_obj.to_mesh_clear()


def clone_bucket(obj):
    """Cheap key for things that could possibly be clones."""
    base = re.sub(r"\.\d+$", "", obj.name).lower()
    mats = tuple(sorted((s.material.name if s.material else "") for s in obj.material_slots))
    scale = tuple(round(abs(v), 4) for v in obj.scale)
    return (base, len(obj.data.vertices), len(obj.data.polygons), mats, scale)


def group_clones(objects, tol=1e-5):
    """[(representative, [followers...]), ...] preserving input order.

    share_bake() REPLACES a follower's mesh with the representative's, so a
    false match silently corrupts geometry. Name and vertex count are nowhere
    near enough: two of these bladeknobs share both yet have different vertex
    positions and different modifier stacks.

    So candidates are bucketed cheaply and then compared on their EVALUATED
    geometry -- modifiers applied, actual coordinates -- with a tolerance.
    A tolerance rather than a hash because duplicates differ by ~3e-8 of float
    noise, which any rounding-then-hashing scheme turns into a spurious mismatch
    whenever a coordinate lands near a quantisation boundary.
    """
    buckets, order = {}, []
    for obj in objects:
        key = clone_bucket(obj)
        if key not in buckets:
            buckets[key] = []
            order.append(key)
        buckets[key].append(obj)

    groups = []
    for key in order:
        members = buckets[key]
        geom = {o.name: _evaluated_geometry(o) for o in members} if len(members) > 1 else {}
        reps = []                                  # [(obj, verts, mats, [followers])]
        for obj in members:
            if len(members) == 1:
                reps.append((obj, None, None, []))
                continue
            verts, mats = geom[obj.name]
            for rep_obj, rep_verts, rep_mats, followers in reps:
                if (verts.shape == rep_verts.shape and mats.shape == rep_mats.shape
                        and np.array_equal(mats, rep_mats)
                        and np.allclose(verts, rep_verts, atol=tol, rtol=0.0)):
                    followers.append(obj)
                    break
            else:
                reps.append((obj, verts, mats, []))
        groups.extend((r[0], r[3]) for r in reps)

    # keep the caller's ordering
    index = {o.name: i for i, o in enumerate(objects)}
    groups.sort(key=lambda g: index[g[0].name])
    return groups


def share_bake(rep, follower):
    """Point a clone at the representative's finished mesh, UVs and material."""
    # The representative's mesh may have had a non-uniform scale applied to it,
    # so the follower's own scale has to drop to matching magnitude or the mesh
    # would be scaled twice. Signs are kept, which is what preserves a mirror.
    follower.data = rep.data
    follower.scale = tuple(math.copysign(abs(r), f) if f != 0.0 else abs(r)
                           for r, f in zip(rep.scale, follower.scale))
    for i, slot in enumerate(follower.material_slots):
        slot.link = "OBJECT"
        slot.material = rep.material_slots[i].material if i < len(rep.material_slots) else None
    log(f"  shared with clone {follower.name!r} (no second bake)")


def apply_nonuniform_scale(obj):
    """Bake the object's scale into the mesh when it is non-uniform.

    UV unwrapping works in local space, but the bake -- and the exported NIF --
    are world space. With a scale like (-0.0109, -0.0109, -0.0016) the two
    disagree by 7x along one axis, so a layout that looks square in the UV
    editor lands badly stretched on the model.

    Applying scale leaves world-space geometry (and therefore the export)
    bit-identical, it just moves the scale from the transform into the vertices.
    Uniform scale, including uniform negative scale, is conformal and needs
    nothing.
    """
    s = [abs(v) for v in obj.scale]
    if max(s) <= min(s) * 1.02:
        return False

    bpy.ops.object.select_all(action="DESELECT")
    obj.select_set(True)
    bpy.context.view_layer.objects.active = obj
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    log(f"  applied non-uniform scale ({s[0]:.4g}, {s[1]:.4g}, {s[2]:.4g}) to the mesh")
    return True


def apply_modifiers_through_subsurf(obj):
    """Bake Mirror/Subsurf into the mesh so the UVs describe the real surface.

    UVs live on the cage, but both the bake and the NIF use the subdivided
    limit surface. On a dense mesh the two agree closely; on a 10-polygon
    bladeknob under two Mirrors and a Subsurf they do not, and the texture lands
    stretched by 2x on one axis. Applying the stack up to and including the last
    Subsurf makes the cage BE the shipped surface, so the unwrap is exact.

    Everything up to that point is applied in order, so the result matches the
    evaluated mesh rather than re-ordering the stack. WeightedNormal and
    anything after it is left alone: those change normals, not positions.
    """
    types = [m.type for m in obj.modifiers]
    if "SUBSURF" not in types:
        return False
    last = len(types) - 1 - types[::-1].index("SUBSURF")

    # Only collapse a stack made of modifiers that are safe to apply headless.
    # A geometry-nodes modifier can read scene state and evaluating one during
    # modifier_apply takes Blender down with no Python error to catch, so a
    # stack containing one is left alone -- slightly stretched texels beat a
    # crash that silently skips the save and leaves everything unbaked.
    safe = {"MIRROR", "SUBSURF", "BEVEL", "SOLIDIFY", "ARRAY", "WELD",
            "EDGE_SPLIT", "TRIANGULATE", "DECIMATE", "SIMPLE_DEFORM"}
    unsafe = sorted({t for t in types[:last + 1] if t not in safe})
    if unsafe:
        log(f"  not collapsing modifiers: {', '.join(unsafe)} cannot be applied safely "
            f"in background -- texels stay slightly non-square")
        return False

    bpy.ops.object.select_all(action="DESELECT")
    obj.select_set(True)
    bpy.context.view_layer.objects.active = obj

    applied = []
    for _ in range(last + 1):
        mod = obj.modifiers[0]
        name, kind = mod.name, mod.type
        try:
            bpy.ops.object.modifier_apply(modifier=name)
            applied.append(kind)
        except RuntimeError as exc:
            log(f"  !! could not apply {name!r}: {exc}")
            return bool(applied)
    log(f"  applied {' + '.join(applied)} so the unwrap matches the shipped surface "
        f"({len(obj.data.vertices)} verts)")
    return True


def unwrap_bake_uv(obj):
    """Fresh non-overlapping UV layer, rescaled to fill the image.

    Returns (aspect, coverage).
    """
    me = obj.data
    name = CONFIG["uv_layer"]

    existing = me.uv_layers.get(name)
    if existing:
        me.uv_layers.remove(existing)
    layer = me.uv_layers.new(name=name, do_init=True)
    me.uv_layers.active = layer
    layer.active_render = True

    bpy.ops.object.select_all(action="DESELECT")
    obj.select_set(True)
    bpy.context.view_layer.objects.active = obj

    bpy.ops.object.mode_set(mode="EDIT")
    bpy.ops.mesh.select_all(action="SELECT")
    bpy.ops.uv.select_all(action="SELECT")
    # correct_aspect MUST be off. It skews the unwrap by the aspect ratio of the
    # image currently assigned to the material -- and at this point that is still
    # the ORIGINAL vanilla texture, which is wildly non-square (tx_w_ebony_edging
    # is 16x64, tx_w_silver_blade is 32x256). That skew was landing verbatim in
    # the bake: texels came out 4x to 14x coarser in one direction. We are
    # generating a brand new texture and choose its aspect ourselves, so the
    # unwrap must stay faithful to the geometry.
    bpy.ops.uv.smart_project(angle_limit=CONFIG["smart_angle"],
                             island_margin=CONFIG["island_margin"],
                             area_weight=0.0, correct_aspect=False,
                             scale_to_bounds=False)
    # Smart UV Project is a planar projection, so a face tilted away from its
    # projection axis is foreshortened along one direction -- up to cos(66 deg)
    # at the default angle limit. That is anisotropy baked into the layout, and
    # no amount of reshaping the image undoes it. Blender's own stretch
    # minimiser relaxes it in place.
    if CONFIG["minimize_stretch"]:
        bpy.ops.uv.select_all(action="SELECT")
        try:
            bpy.ops.uv.minimize_stretch(iterations=CONFIG["minimize_stretch"], blend=0.0)
        except RuntimeError as exc:
            log(f"  !! minimize_stretch skipped: {exc}")

    bpy.ops.uv.select_all(action="SELECT")
    bpy.ops.uv.pack_islands(rotate=True, scale=True, margin=CONFIG["island_margin"],
                            rotate_method="ANY", shape_method="CONCAVE")
    bpy.ops.object.mode_set(mode="OBJECT")

    (u0, v0, u1, v1), area = _uv_stats(me, name)
    du = max(u1 - u0, 1e-6)
    dv = max(v1 - v0, 1e-6)

    aspect = du / dv
    if CONFIG["non_square"] and not CONFIG["forced_size"]:
        aspect = min(CONFIG["max_aspect"], max(1.0 / CONFIG["max_aspect"], aspect))
    else:
        aspect = 1.0

    coverage = min(1.0, max(0.02, area / (du * dv)))
    return ((u0, v0, du, dv), snapshot_uvs(obj)), aspect, coverage


def snapshot_uvs(obj):
    """The packed layout, kept so fit_uv_to_image can be re-applied safely."""
    uvs = obj.data.uv_layers[CONFIG["uv_layer"]].uv
    out = np.empty(len(uvs) * 2, dtype=np.float64)
    uvs.foreach_get("vector", out)
    return out.reshape(-1, 2)


def fit_uv_to_image(obj, layout, width, height):
    """Scale the packed layout into a width x height image with SQUARE texels.

    Packing is a uniform scale, so the layout's du:dv is its true shape. Writing
    u' = (u-u0)*a and v' = (v-v0)*b, the surface distance per texel is
    (k/a)/width along u and (k/b)/height along v, so texels are square exactly
    when a*width == b*height. Picking the largest such pair that still fits
    keeps the image as full as possible, and absorbs the error introduced by
    rounding width and height to powers of two.
    """
    (u0, v0, du, dv), packed = layout
    a = min(1.0 / du, (height / width) / dv)
    b = a * width / height

    # Always written from the packed snapshot, never from whatever is currently
    # in the layer, so calling this more than once is safe: mapping
    # already-fitted UVs through the original bbox again shrinks them each time
    # and pushes them negative. That once collapsed a 7000-vertex ornament onto
    # a 0.2 x 0.01 sliver of its texture, which read as an untextured white part
    # in game.
    fitted = np.empty_like(packed)
    fitted[:, 0] = (packed[:, 0] - u0) * a
    fitted[:, 1] = (packed[:, 1] - v0) * b
    obj.data.uv_layers[CONFIG["uv_layer"]].uv.foreach_set("vector", fitted.ravel())


def texel_anisotropy(obj, width, height):
    """How square the texels land on the actual surface.

    The image aspect is taken from the packed UV layout rather than from the
    object's bounding box, because packing is what decides the shape: a long
    blade whose two faces pack side by side wants a square-ish image, not a
    long thin one, even though the object is long and thin.

    This measures the result directly. For each triangle it solves the standard
    tangent frame -- how far you travel across the surface per unit of u and per
    unit of v -- divides by the pixel counts, and area-weights the ratio.
    1.0 means texels are square on the model; 2.0 means they are twice as
    coarse along u as along v.
    """
    # Measured on the EVALUATED mesh -- modifiers included. A 6-polygon cage
    # under two Mirrors and a Subsurf becomes a very different surface, and the
    # subdivided limit surface is what both the bake and the NIF actually use.
    depsgraph = bpy.context.evaluated_depsgraph_get()
    eval_obj = obj.evaluated_get(depsgraph)
    me = eval_obj.to_mesh()
    try:
        layer = me.uv_layers.get(CONFIG["uv_layer"])
        if layer is None:
            return 1.0
        uvs = layer.uv
        verts = me.vertices
        mat = obj.matrix_world      # world space: object scale is part of the answer
        su = sv = wsum = 0.0

        for poly in me.polygons:
            loops = list(poly.loop_indices)
            for k in range(1, len(loops) - 1):
                i0, i1, i2 = loops[0], loops[k], loops[k + 1]
                p0 = mat @ verts[me.loops[i0].vertex_index].co
                p1 = mat @ verts[me.loops[i1].vertex_index].co
                p2 = mat @ verts[me.loops[i2].vertex_index].co
                a0 = tuple(uvs[i0].vector)
                a1 = tuple(uvs[i1].vector)
                a2 = tuple(uvs[i2].vector)

                e1 = (p1[0] - p0[0], p1[1] - p0[1], p1[2] - p0[2])
                e2 = (p2[0] - p0[0], p2[1] - p0[1], p2[2] - p0[2])
                d1 = (a1[0] - a0[0], a1[1] - a0[1])
                d2 = (a2[0] - a0[0], a2[1] - a0[1])

                det = d1[0] * d2[1] - d2[0] * d1[1]
                if abs(det) < 1e-12:
                    continue
                inv = 1.0 / det
                dpdu = tuple((e1[c] * d2[1] - e2[c] * d1[1]) * inv for c in range(3))
                dpdv = tuple((e2[c] * d1[0] - e1[c] * d2[0]) * inv for c in range(3))

                lu = math.sqrt(sum(c * c for c in dpdu))
                lv = math.sqrt(sum(c * c for c in dpdv))
                w = abs(det) * 0.5
                su += lu * w
                sv += lv * w
                wsum += w
    finally:
        eval_obj.to_mesh_clear()

    if wsum <= 0 or sv <= 0:
        return 1.0
    # metres per texel along each axis
    return (su / wsum / max(width, 1)) / (sv / wsum / max(height, 1))


def inset_bake_uv(obj, width, height):
    pad_u = CONFIG["uv_border_texels"] / max(width, 1)
    pad_v = CONFIG["uv_border_texels"] / max(height, 1)
    uvs = obj.data.uv_layers[CONFIG["uv_layer"]].uv
    for i in range(len(uvs)):
        u, v = uvs[i].vector
        uvs[i].vector = (pad_u + u * (1.0 - 2.0 * pad_u),
                         pad_v + v * (1.0 - 2.0 * pad_v))


def choose_size(source_texels, aspect, coverage, max_axis):
    """Dimensions that preserve texel density, clamped without skewing texels."""
    if CONFIG["forced_size"]:
        n = int(CONFIG["forced_size"])
        return n, n
    if not CONFIG["auto_size"] or source_texels <= 0:
        return 256, 256

    needed = source_texels * CONFIG["texel_multiplier"] / coverage
    height = math.sqrt(needed / aspect)
    width = aspect * height

    w = max(CONFIG["min_axis"], next_pow2(width))
    h = max(CONFIG["min_axis"], next_pow2(height))
    # Halve both together so the aspect ratio -- and therefore square texels --
    # survives the clamp.
    while max(w, h) > max_axis and min(w, h) > CONFIG["min_axis"]:
        w, h = max(CONFIG["min_axis"], w // 2), max(CONFIG["min_axis"], h // 2)
    return int(min(w, max_axis)), int(min(h, max_axis))


# --------------------------------------------------------------------------
# bake plumbing
# --------------------------------------------------------------------------

def new_target_image(name, width, height, non_color, background):
    old = bpy.data.images.get(name)
    if old:
        bpy.data.images.remove(old)
    img = bpy.data.images.new(name, width=width, height=height, alpha=True, float_buffer=False)
    if non_color:
        img.colorspace_settings.name = "Non-Color"
    img.generated_color = background
    # Fill explicitly; bakes run with use_clear off so this survives in the gaps
    # between UV islands. For a spec map that is the difference between "still
    # metal at distance" and the mip chain fading metalness to black.
    img.pixels.foreach_set(np.tile(np.array(background, dtype=np.float32), width * height))
    return img


def build_emit_material(name, color=None, image=None, uv_name=None,
                        interpolation="Linear", extension="REPEAT", tint=None,
                        gain=1.0):
    """Pure emission: what Cycles' EMIT bake copies verbatim."""
    mat = bpy.data.materials.new(name)
    mat.use_nodes = True
    tree = mat.node_tree
    tree.nodes.clear()
    out = tree.nodes.new("ShaderNodeOutputMaterial")
    emit = tree.nodes.new("ShaderNodeEmission")
    emit.inputs["Strength"].default_value = 1.0
    tree.links.new(emit.outputs["Emission"], out.inputs["Surface"])

    if image is not None:
        tex = tree.nodes.new("ShaderNodeTexImage")
        tex.image = image
        tex.interpolation = interpolation
        tex.extension = extension
        if uv_name:
            uv = tree.nodes.new("ShaderNodeUVMap")
            uv.uv_map = uv_name
            tree.links.new(uv.outputs["UV"], tex.inputs["Vector"])

        source = tex.outputs["Color"]
        factor = [c * gain for c in (tint[:3] if tint else (1.0, 1.0, 1.0))]
        if any(abs(f - 1.0) > 1e-4 for f in factor):
            mix = tree.nodes.new("ShaderNodeMix")
            mix.data_type = "RGBA"
            mix.blend_type = "MULTIPLY"
            mix.inputs["Factor"].default_value = 1.0
            tree.links.new(source, mix.inputs[6])
            mix.inputs[7].default_value = (factor[0], factor[1], factor[2], 1.0)
            source = mix.outputs[2]
        tree.links.new(source, emit.inputs["Color"])
    else:
        emit.inputs["Color"].default_value = tuple(color or (0.0, 0.0, 0.0, 1.0))
    return mat


def add_bake_target(mat, image):
    node = mat.node_tree.nodes.new("ShaderNodeTexImage")
    node.image = image
    node.select = True
    mat.node_tree.nodes.active = node
    return node


def run_bake(obj, target_image, per_slot_materials, bake_type="EMIT", margin=None):
    """Swap in temporary materials, bake, restore the originals."""
    scene = bpy.context.scene
    original_engine = scene.render.engine
    original = [(slot.link, slot.material) for slot in obj.material_slots]
    try:
        scene.render.engine = "CYCLES"
        scene.cycles.device = "CPU"
        scene.cycles.samples = 1
        scene.cycles.use_denoising = False
        scene.render.bake.use_clear = False
        scene.render.bake.margin = CONFIG["bake_margin_px"] if margin is None else margin
        scene.render.bake.margin_type = "EXTEND"
        scene.render.bake.use_selected_to_active = False
        scene.render.bake.normal_space = "TANGENT"

        for i, slot in enumerate(obj.material_slots):
            slot.link = "OBJECT"
            slot.material = per_slot_materials[i]
            add_bake_target(per_slot_materials[i], target_image)

        obj.data.uv_layers.active = obj.data.uv_layers[CONFIG["uv_layer"]]
        obj.data.uv_layers[CONFIG["uv_layer"]].active_render = True

        bpy.ops.object.select_all(action="DESELECT")
        obj.select_set(True)
        bpy.context.view_layer.objects.active = obj
        bpy.ops.object.bake(type=bake_type)
    finally:
        for i, (link, mat) in enumerate(original):
            obj.material_slots[i].link = link
            obj.material_slots[i].material = mat
        scene.render.engine = original_engine


def save_image(image, png_path, dds_path):
    png_path.parent.mkdir(parents=True, exist_ok=True)
    image.file_format = "PNG"
    image.filepath_raw = str(png_path)
    image.save()
    png_to_dds(png_path, dds_path)
    return dds_path


def image_to_array(image):
    w, h = image.size
    return np.array(image.pixels[:], dtype=np.float32).reshape(h, w, 4)


def array_to_image(name, arr, non_color=True):
    h, w = arr.shape[:2]
    old = bpy.data.images.get(name)
    if old:
        bpy.data.images.remove(old)
    img = bpy.data.images.new(name, width=w, height=h, alpha=True, float_buffer=False)
    if non_color:
        img.colorspace_settings.name = "Non-Color"
    img.pixels = arr.ravel()
    return img


# --------------------------------------------------------------------------
# normal maps
# --------------------------------------------------------------------------

def _box_blur(arr, radius):
    if radius < 1:
        return arr
    k = 2 * radius + 1
    pad = np.pad(arr, ((radius, radius), (0, 0)), mode="edge")
    cs = np.cumsum(pad, axis=0)
    arr = (cs[k - 1:, :] - np.pad(cs[:-k, :], ((1, 0), (0, 0)))) / k
    pad = np.pad(arr, ((0, 0), (radius, radius)), mode="edge")
    cs = np.cumsum(pad, axis=1)
    arr = (cs[:, k - 1:] - np.pad(cs[:, :-k], ((0, 0), (1, 0)))) / k
    return arr


def gaussian_blur(arr, sigma):
    """Three box blurs approximate a gaussian closely enough for a height field."""
    if sigma <= 0:
        return arr
    radius = max(1, int(round(sigma * 0.9)))
    for _ in range(3):
        arr = _box_blur(arr, radius)
    return arr


def height_from_albedo(albedo_image):
    """Luminance, high-passed so broad shading does not become a dome."""
    px = image_to_array(albedo_image)
    lum = 0.2126 * px[:, :, 0] + 0.7152 * px[:, :, 1] + 0.0722 * px[:, :, 2]
    lum = np.sqrt(np.clip(lum, 0.0, 1.0))          # linear -> perceptual
    if CONFIG["norm_highpass"]:
        lum = lum - gaussian_blur(lum, CONFIG["norm_highpass_sigma"]) + 0.5
    height = np.clip(lum, 0.0, 1.0)
    out = np.empty(px.shape, dtype=np.float32)
    out[:, :, 0] = out[:, :, 1] = out[:, :, 2] = height
    out[:, :, 3] = 1.0
    return out


def bake_relief_normal(obj, height_image, width, height):
    """Blender's Bump node baked through Cycles' NORMAL pass, in tangent space."""
    mat = bpy.data.materials.new("__bake_relief")
    tree = mat.node_tree
    mat.use_nodes = True
    tree = mat.node_tree
    tree.nodes.clear()

    out = tree.nodes.new("ShaderNodeOutputMaterial")
    bsdf = tree.nodes.new("ShaderNodeBsdfDiffuse")
    bump = tree.nodes.new("ShaderNodeBump")
    tex = tree.nodes.new("ShaderNodeTexImage")
    uv = tree.nodes.new("ShaderNodeUVMap")

    tex.image = height_image
    tex.interpolation = "Cubic"
    tex.extension = "EXTEND"
    uv.uv_map = CONFIG["uv_layer"]
    corners = [obj.matrix_world @ mathutils.Vector(c) for c in obj.bound_box]
    diag = max((max(c[i] for c in corners) - min(c[i] for c in corners))
               for i in range(3)) or 1.0
    bump.inputs["Strength"].default_value = CONFIG["bump_strength"]
    bump.inputs["Distance"].default_value = (
        diag * CONFIG["bump_distance_rel"] if CONFIG.get("bump_distance_rel")
        else CONFIG["bump_distance"])

    tree.links.new(uv.outputs["UV"], tex.inputs["Vector"])
    tree.links.new(tex.outputs["Color"], bump.inputs["Height"])
    tree.links.new(bump.outputs["Normal"], bsdf.inputs["Normal"])
    tree.links.new(bsdf.outputs[0], out.inputs["Surface"])

    target = new_target_image("__relief", width, height, True, (0.5, 0.5, 1.0, 1.0))
    run_bake(obj, target, [mat] * len(obj.material_slots), bake_type="NORMAL")
    arr = image_to_array(target)[:, :, :3].copy()
    bpy.data.images.remove(target)
    bpy.data.materials.remove(mat)
    return arr


def openmw_data_dirs():
    """Every data= path in openmw.cfg -- the same VFS the game resolves against.

    Without this the search depends on where the .blend happens to sit, and a
    map living in another mod is missed silently.
    """
    candidates = [CONFIG.get("openmw_cfg")] if CONFIG.get("openmw_cfg") else []
    candidates += [
        pathlib.Path.home() / ".config/openmw/openmw.cfg",
        pathlib.Path.home() / ".local/share/openmw/openmw.cfg",
        pathlib.Path.home() / "Library/Preferences/openmw/openmw.cfg",
    ]
    for cfg in candidates:
        cfg = pathlib.Path(cfg)
        if not cfg.is_file():
            continue
        out = []
        for line in cfg.read_text(encoding="utf-8", errors="replace").splitlines():
            line = line.strip()
            if line.startswith("data="):
                out.append(pathlib.Path(line[5:].strip().strip('"')))
        if out:
            return out
    return []


_NORMAL_INDEX = None


def normal_index():
    """Lazy lowercase index of every *_nh / *_n texture in the mod tree.

    Built only when a [NormCopy] material is present.
    """
    global _NORMAL_INDEX
    if _NORMAL_INDEX is not None:
        return _NORMAL_INDEX

    dirs = CONFIG.get("normal_search_dirs")
    if dirs:
        roots = [pathlib.Path(d) for d in dirs]
    else:
        roots = [d / "textures" for d in openmw_data_dirs()]
        # fall back to the mods folder beside this .blend
        mods = blend_dir().parent
        if mods.is_dir():
            for entry in sorted(mods.iterdir()):
                if entry.is_dir():
                    roots.extend(entry.rglob("textures"))
        roots.append(blend_dir() / "textures")

    _NORMAL_INDEX = {}
    for root in roots:
        if not root.is_dir():
            continue
        for f in root.rglob("*"):
            if f.is_file() and re.search(r"_(nh|n)\.(dds|tga|png|bmp)$", f.name, re.I):
                _NORMAL_INDEX.setdefault(f.name.lower(), f)
    if not _NORMAL_INDEX:
        log("  !! [NormCopy]: found no existing normal maps -- set "
            "CONFIG['normal_search_dirs'] or CONFIG['openmw_cfg']")
    else:
        log(f"  indexed {len(_NORMAL_INDEX)} existing normal maps for [NormCopy]")
    return _NORMAL_INDEX


def find_source_normal(image):
    """The _nh (preferred, has parallax height) or _n beside a source texture."""
    if image is None:
        return None
    stem = pathlib.Path(image.name).stem.lower()
    index = normal_index()
    for suffix in ("_nh", "_n"):
        for ext in (".dds", ".tga", ".png", ".bmp"):
            hit = index.get(f"{stem}{suffix}{ext}")
            if hit:
                return hit
    return None


def bake_transfer_normal(obj, sources, width, height):
    """Resample each material's EXISTING normal map into the new UV layout.

    A straight pixel copy would be wrong: Smart UV Project reorients islands, so
    the old and new tangent frames disagree. Feeding the source map through a
    Normal Map node bound to the ORIGINAL UV layer and then baking Cycles'
    NORMAL pass over the new layer makes Cycles do the conversion -- it
    evaluates the perturbed normal in the old frame and writes it in the new one.
    """
    mats, used = [], []
    for i, src in enumerate(sources):
        mat = bpy.data.materials.new(f"__xfer_{i}")
        mat.use_nodes = True
        tree = mat.node_tree
        tree.nodes.clear()
        out = tree.nodes.new("ShaderNodeOutputMaterial")
        bsdf = tree.nodes.new("ShaderNodeBsdfDiffuse")
        tree.links.new(bsdf.outputs[0], out.inputs["Surface"])

        path = src.get("normal_path")
        if path and src.get("uv"):
            img = bpy.data.images.load(str(path), check_existing=True)
            img.colorspace_settings.name = "Non-Color"
            tex = tree.nodes.new("ShaderNodeTexImage")
            tex.image = img
            tex.interpolation = "Cubic"
            uv = tree.nodes.new("ShaderNodeUVMap")
            uv.uv_map = src["uv"]
            nmap = tree.nodes.new("ShaderNodeNormalMap")
            nmap.space = "TANGENT"
            nmap.uv_map = src["uv"]
            tree.links.new(uv.outputs["UV"], tex.inputs["Vector"])
            tree.links.new(tex.outputs["Color"], nmap.inputs["Color"])
            tree.links.new(nmap.outputs["Normal"], bsdf.inputs["Normal"])
            used.append(path.name)
        mats.append(mat)

    target = new_target_image("__xfer", width, height, True, (0.5, 0.5, 1.0, 1.0))
    try:
        run_bake(obj, target, mats, bake_type="NORMAL")
        arr = image_to_array(target)[:, :, :3].copy()
    finally:
        for m in mats:
            bpy.data.materials.remove(m)
        bpy.data.images.remove(target)
    if used:
        log(f"  transferred existing normal map(s): {', '.join(sorted(set(used)))}")
    return arr


def detail_normal_array(width, height, tiles, crop):
    """The tiling metal micro-surface, resampled to exactly width x height."""
    path = blend_dir() / CONFIG["detail_normal"]
    if not path.is_file():
        log(f"  !! detail normal not found: {path}")
        return None

    tw = max(8, int(round(width / max(tiles, 0.01))))
    th = max(8, int(round(height / max(tiles, 0.01))))
    tmp = blend_dir() / CONFIG["png_dir"] / "__detail_tmp.png"
    tmp.parent.mkdir(parents=True, exist_ok=True)
    cmd = [CONFIG["magick"], str(path)]
    if crop:
        cmd += ["-crop", crop, "+repage"]
    cmd += ["-resize", f"{tw}x{th}!",
            "-write", "mpr:tile", "+delete",
            "-size", f"{width}x{height}", "tile:mpr:tile", str(tmp)]
    subprocess.run(cmd, check=True, capture_output=True)

    img = bpy.data.images.load(str(tmp), check_existing=False)
    img.colorspace_settings.name = "Non-Color"
    arr = image_to_array(img)[:, :, :3].copy()
    bpy.data.images.remove(img)
    tmp.unlink(missing_ok=True)
    return arr


def decode_normal(rgb):
    n = rgb * 2.0 - 1.0
    length = np.sqrt(np.maximum((n * n).sum(axis=2, keepdims=True), 1e-12))
    return n / length


def encode_normal(n):
    length = np.sqrt(np.maximum((n * n).sum(axis=2, keepdims=True), 1e-12))
    return np.clip(n / length * 0.5 + 0.5, 0.0, 1.0)


def remove_dc(n):
    """Re-centre X/Y so the map has no net tilt.

    Essential before rescale_slope: a tangent-space detail map is nearly flat
    (Metal061B's 99th-percentile slope is 0.41 degrees), so reaching a useful
    strength needs ~45x amplification -- which would also multiply the source's
    tiny DC offset into a visible tilt across the entire surface.
    """
    out = n.copy()
    out[:, :, 0] -= out[:, :, 0].mean()
    out[:, :, 1] -= out[:, :, 1].mean()
    return out


def rescale_slope(n, target_deg, percentile):
    """Scale XY so the given percentile of slope hits target_deg.

    The Bump node's output depends on object scale, so without this the strength
    is whatever the mesh happens to make it.
    """
    n = remove_dc(n)
    xy = np.sqrt(n[:, :, 0] ** 2 + n[:, :, 1] ** 2)
    z = np.clip(np.abs(n[:, :, 2]), 1e-6, None)
    slope = np.degrees(np.arctan2(xy, z))
    current = float(np.percentile(slope, percentile))
    if current < 0.05:
        return n
    factor = math.tan(math.radians(target_deg)) / max(math.tan(math.radians(current)), 1e-6)
    out = n.copy()
    out[:, :, 0] *= factor
    out[:, :, 1] *= factor
    out[:, :, 2] = 1.0
    return out


def combine_normals(base, detail):
    """Whiteout blend -- the standard way to layer a detail normal."""
    out = np.empty_like(base)
    out[:, :, 0] = base[:, :, 0] + detail[:, :, 0]
    out[:, :, 1] = base[:, :, 1] + detail[:, :, 1]
    out[:, :, 2] = base[:, :, 2] * detail[:, :, 2]
    return out


def dilate_into_gaps(rgb, mask, passes):
    """Flatten the space between UV islands, then regrow island edges into it.

    Two islands' bake margins meet head-on in the gap; any gradient operator
    reads that as a cliff and leaves a bright ridge that bleeds in via mips.
    """
    filled = mask > 0.5
    out = rgb.copy()
    out[~filled] = (0.5, 0.5, 1.0)
    for _ in range(max(0, passes)):
        pad_v = np.pad(out, ((1, 1), (1, 1), (0, 0)), mode="edge")
        pad_m = np.pad(filled, 1, mode="constant", constant_values=False)
        acc = np.zeros_like(out)
        cnt = np.zeros(out.shape[:2], dtype=np.float32)
        for dy in (0, 1, 2):
            for dx in (0, 1, 2):
                if dy == 1 and dx == 1:
                    continue
                m = pad_m[dy:dy + out.shape[0], dx:dx + out.shape[1]]
                acc += pad_v[dy:dy + out.shape[0], dx:dx + out.shape[1]] * m[..., None]
                cnt += m
        grow = (~filled) & (cnt > 0)
        if not grow.any():
            break
        out[grow] = acc[grow] / cnt[grow][..., None]
        filled = filled | grow
    return out


def bake_material_masks(obj, width, height, n_slots):
    """One bake giving a boolean mask per material slot, plus overall coverage.

    Each slot emits a distinct byte value (i+1), so a single EMIT bake into a
    Non-Color image separates them. The bake margin extends each id outwards,
    which is what keeps a material's own normal treatment in its own margin.
    """
    img = new_target_image("__matid", width, height, True, (0, 0, 0, 1))
    mats = [build_emit_material(f"__matid_{i}",
                                color=((i + 1) / 255.0,) * 3 + (1.0,))
            for i in range(n_slots)]
    try:
        run_bake(obj, img, mats)
        ids = np.rint(image_to_array(img)[:, :, 0] * 255.0).astype(np.int32)
    finally:
        for m in mats:
            bpy.data.materials.remove(m)
        bpy.data.images.remove(img)

    masks = [ids == (i + 1) for i in range(n_slots)]
    coverage = ids > 0
    return masks, coverage


def bake_coverage_mask(obj, width, height, n_slots):
    """Zero-margin white bake = an exact UV coverage mask."""
    img = new_target_image("__mask", width, height, True, (0, 0, 0, 1))
    mats = [build_emit_material(f"__bake_mask_{i}", color=(1, 1, 1, 1))
            for i in range(n_slots)]
    try:
        run_bake(obj, img, mats, margin=0)
        mask = image_to_array(img)[:, :, 0].copy()
    finally:
        for m in mats:
            bpy.data.materials.remove(m)
        bpy.data.images.remove(img)
    return mask


def make_normal_map(obj, albedo_image, width, height, modes, settings, out_name,
                    sources=None):
    """Composite a normal map from per-material modes.

    modes is one of 'normgen' | 'bump' | 'flat' per material slot. Areas are
    separated by a material-id bake, so a single object can carry albedo relief
    on one material and the tiling metal grain on another -- they never blend,
    each material's area gets exactly one treatment.
    """
    strengths = [s for _m, s in modes]
    modes = [m for m, _s in modes]
    if all(m == "flat" for m in modes):
        return None

    relief = detail = None
    if "normgen" in modes:
        height_arr = height_from_albedo(albedo_image)
        height_img = array_to_image("__height", height_arr)
        try:
            raw = decode_normal(bake_relief_normal(obj, height_img, width, height))
        finally:
            bpy.data.images.remove(height_img)
        xy = np.sqrt(raw[:, :, 0] ** 2 + raw[:, :, 1] ** 2)
        p99 = float(np.percentile(np.degrees(np.arctan2(
            xy, np.clip(np.abs(raw[:, :, 2]), 1e-6, None))), 99))
        if p99 > 70.0:
            log(f"  !! relief bump saturated (p99 {p99:.0f} deg) -- lower bump_distance_rel")
        relief = rescale_slope(raw, settings["slope"], CONFIG["norm_slope_percentile"])

    transfer = None
    if "normcopy" in modes:
        transfer = decode_normal(bake_transfer_normal(obj, sources or [], width, height))

    if "bump" in modes:
        arr = detail_normal_array(width, height, settings["tiles"], settings["detail_crop"])
        if arr is not None:
            detail = rescale_slope(decode_normal(arr), settings["detail_slope"],
                                   CONFIG["norm_slope_percentile"])

    flat = np.zeros((height, width, 3), dtype=np.float32)
    flat[:, :, 2] = 1.0

    def scaled(src, strength):
        """A fraction of a normal map's depth: shrink XY, leave Z alone."""
        if src is None or abs(strength - 1.0) < 1e-6:
            return src
        out = src.copy()
        out[:, :, 0] *= strength
        out[:, :, 1] *= strength
        return out

    by_mode = {"normgen": relief, "bump": detail, "normcopy": transfer}
    distinct = set(zip(modes, strengths))
    if len(distinct) == 1:
        combined = scaled(by_mode.get(modes[0], flat), strengths[0])
        if combined is None:
            return None
        coverage = None
    else:
        masks, coverage = bake_material_masks(obj, width, height, len(modes))
        combined = flat.copy()
        for i, mode in enumerate(modes):
            src = scaled(by_mode.get(mode), strengths[i])
            if src is not None:
                combined[masks[i]] = src[masks[i]]

    rgb = encode_normal(combined)

    # Only albedo relief has island-edge artefacts; the tiling grain is
    # continuous noise and needs no masking.
    if "normgen" in modes:
        if coverage is None:
            coverage = bake_coverage_mask(obj, width, height, len(modes)) > 0.5
        rgb = dilate_into_gaps(rgb, coverage.astype(np.float32), CONFIG["bake_margin_px"])

    if CONFIG["norm_flip_green"]:
        rgb[:, :, 1] = 1.0 - rgb[:, :, 1]

    out = np.empty((height, width, 4), dtype=np.float32)
    out[:, :, :3] = np.clip(rgb, 0.0, 1.0)
    out[:, :, 3] = 1.0
    return array_to_image(out_name, out)


# --------------------------------------------------------------------------
# per-object driver
# --------------------------------------------------------------------------

def assign_baked_material(obj, image, name, carry_tags=()):
    """Collapse the object to a single MW material pointing at the baked texture.

    Tags the EXPORTER reads are carried onto the new material's name. Baking
    throws the source materials away, so without this a crystal tagged [Alpha]
    would come out opaque: the tag lived on a material that no longer exists by
    the time mw_export goes looking for it.
    """
    from io_scene_mw import nif_shader
    me = obj.data
    if carry_tags:
        name = "".join(f"[{t.strip('[]').title()}]" for t in sorted(carry_tags)) + " " + name
    mat = nif_shader.create_material(name)
    mat.mw.base_texture.image = image
    mat.mw.base_texture.layer = CONFIG["uv_layer"]
    mat.mw.base_texture.use_mipmaps = True
    mat.mw.base_texture.use_repeat = False
    me.materials.clear()
    me.materials.append(None)
    obj.material_slots[0].link = "OBJECT"
    obj.material_slots[0].material = mat
    for poly in me.polygons:
        poly.material_index = 0
    return mat


def process_object(obj, shiny_dir, do_spec, do_norm):
    log(f"--- {obj.name}")
    slug = slugify(obj.name)
    out_dir = blend_dir() / CONFIG["out_dir"]
    png_dir = blend_dir() / CONFIG["png_dir"]

    for slot in obj.material_slots:
        repair_mw_material(slot.material)
        warn_unknown_tags(slot.material)

    if obj.data.users > 1:
        obj.data = obj.data.copy()
        log("  mesh was multi-user, made a single-user copy")

    # ---- gather per-slot source info and spec colours ----
    sources, spec_colors = [], []
    for slot in obj.material_slots:
        mat = slot.material
        image, uv_name, interp, ext = mw_base_texture(mat)
        color, source = spec_color_for(mat, obj, image, shiny_dir)
        spec_colors.append(color)

        gain = float(mw_prop(mat, obj, "mw_albedo_gain", CONFIG["albedo_gain"]))
        sources.append({
            "image": image,
            "uv": uv_name or (obj.data.uv_layers.active.name if obj.data.uv_layers.active else None),
            "interp": interp, "ext": ext,
            "tint": mw_diffuse_color(mat), "gain": gain,
        })
        log(f"  slot {mat.name if mat else None!r}: tex={image.name if image else None!r} "
            f"spec=rgb{color} [{source}] norm={material_norm_mode(mat)[0]}" + (f" gain={gain:g}" if abs(gain - 1.0) > 1e-4 else ""))

    # ---- resolution ----
    max_axis = int(mw_prop(None, obj, "mw_max_res", CONFIG["max_axis"]))
    apply_nonuniform_scale(obj)
    source_texels = count_source_texels(obj)
    layout, aspect, coverage = unwrap_bake_uv(obj)
    width, height = choose_size(source_texels, aspect, coverage, max_axis)
    fit_uv_to_image(obj, layout, width, height)
    aniso = texel_anisotropy(obj, width, height)

    # Texel aspect is fixed by the UV layout, not by the image shape:
    # fit_uv_to_image already guarantees square texels for a uniformly packed
    # layout, whatever width and height it is given. So a bad value means the
    # layout itself is wrong -- usually because the UVs were made on a cage that
    # is not the surface that ships. Collapsing the modifiers and unwrapping the
    # real surface is the only thing that helps.
    if not (0.8 <= aniso <= 1.25) and apply_modifiers_through_subsurf(obj):
        before = aniso
        source_texels = count_source_texels(obj)
        layout, aspect, coverage = unwrap_bake_uv(obj)
        width, height = choose_size(source_texels, aspect, coverage, max_axis)
        fit_uv_to_image(obj, layout, width, height)
        aniso = texel_anisotropy(obj, width, height)
        log(f"  texel aspect {before:.2f} -> {aniso:.2f} after collapsing the modifiers")

    inset_bake_uv(obj, width, height)
    log(f"  resolution: {width}x{height}  (source texels {source_texels:.0f}, "
        f"layout aspect {aspect:.2f}, coverage {coverage:.0%}, max {max_axis})")
    flag = "" if 0.72 <= aniso <= 1.4 else "   <-- texels noticeably non-square"
    log(f"  texel aspect on the surface: {aniso:.2f} (1.00 = square){flag}")

    # ---- albedo ----
    albedo = new_target_image(slug, width, height, False, (0, 0, 0, 1))
    emit_mats = [
        build_emit_material(f"__bake_albedo_{slug}_{i}", color=s["tint"], image=s["image"],
                            uv_name=s["uv"], interpolation=s["interp"], extension=s["ext"],
                            tint=s["tint"], gain=s["gain"])
        for i, s in enumerate(sources)
    ]
    run_bake(obj, albedo, emit_mats)
    for m in emit_mats:
        bpy.data.materials.remove(m)
    albedo_dds = save_image(albedo, png_dir / f"{slug}.png", out_dir / f"{slug}.dds")
    log(f"  albedo -> {albedo_dds.relative_to(blend_dir())}")
    written = {"albedo": albedo_dds}

    # ---- spec ----
    if do_spec:
        d = CONFIG["spec_size_divisor"]
        sw = max(CONFIG["min_axis"], width // d)
        sh = max(CONFIG["min_axis"], height // d)
        if CONFIG["spec_mode"] == "flat" or len(set(spec_colors)) == 1:
            flat = spec_colors[0]
            spec_png = png_dir / f"{slug}_spec.png"
            spec_dds = out_dir / f"{slug}_spec.dds"
            spec_png.parent.mkdir(parents=True, exist_ok=True)
            subprocess.run([CONFIG["magick"], "-size", f"{sw}x{sh}",
                            f"xc:srgb({flat[0]},{flat[1]},{flat[2]})", str(spec_png)],
                           check=True, capture_output=True)
            png_to_dds(spec_png, spec_dds)
            log(f"  spec   -> {spec_dds.relative_to(blend_dir())}  flat rgb{flat}")
        else:
            bg = spec_colors[0]
            spec_img = new_target_image(f"{slug}_spec", sw, sh, True,
                                        (bg[0] / 255, bg[1] / 255, bg[2] / 255, 1.0))
            spec_mats = [build_emit_material(f"__bake_spec_{slug}_{i}",
                                             color=(c[0] / 255, c[1] / 255, c[2] / 255, 1.0))
                         for i, c in enumerate(spec_colors)]
            run_bake(obj, spec_img, spec_mats)
            for m in spec_mats:
                bpy.data.materials.remove(m)
            spec_dds = save_image(spec_img, png_dir / f"{slug}_spec.png",
                                  out_dir / f"{slug}_spec.dds")
            log(f"  spec   -> {spec_dds.relative_to(blend_dir())}  baked {spec_colors}")
        written["spec"] = spec_dds

    # ---- normal ----
    if do_norm:
        modes = [material_norm_mode(slot.material) for slot in obj.material_slots]
        settings = {
            "slope": float(mw_prop(None, obj, "mw_normal_slope", CONFIG["norm_slope_deg"])),
            "tiles": float(mw_prop(None, obj, "mw_detail_tiles", CONFIG["detail_tiles"])),
            "detail_slope": float(mw_prop(None, obj, "mw_detail_slope", CONFIG["detail_slope_deg"])),
            "detail_crop": mw_prop(None, obj, "mw_detail_crop", CONFIG["detail_crop"]),
        }
        mode_names = [m for m, _s in modes]
        if "normcopy" in mode_names:
            for i, src in enumerate(sources):
                src["normal_path"] = (find_source_normal(src["image"])
                                      if mode_names[i] == "normcopy" else None)
        norm_img = make_normal_map(obj, albedo, width, height, modes, settings,
                                   f"{slug}{CONFIG['norm_suffix']}", sources)
        if norm_img is not None:
            norm_dds = save_image(norm_img, png_dir / f"{slug}{CONFIG['norm_suffix']}.png",
                                  out_dir / f"{slug}{CONFIG['norm_suffix']}.dds")
            shown = [m if abs(st - 1.0) < 1e-6 else f"{m}@{st:.0%}" for m, st in modes]
            log(f"  normal -> {norm_dds.relative_to(blend_dir())}  modes={shown}")
            written["normal"] = norm_dds
        else:
            log("  normal -> none (no [NormGen] or [Bump] material)")

    # ---- relink ----
    baked = bpy.data.images.load(str(albedo_dds), check_existing=True)
    baked.name = f"{slug}.dds"
    baked.colorspace_settings.name = "sRGB"
    carry = set()
    for slot in obj.material_slots:
        if slot.material:
            carry |= name_tags(slot.material.name) & EXPORT_TAGS
    assign_baked_material(obj, baked, slug, carry)

    if CONFIG["drop_source_uv"]:
        me = obj.data
        for layer in [l for l in me.uv_layers if l.name != CONFIG["uv_layer"]]:
            me.uv_layers.remove(layer)
        me.uv_layers.active = me.uv_layers[0]
        me.uv_layers[0].active_render = True

    return written


# --------------------------------------------------------------------------
# entry point
# --------------------------------------------------------------------------

def log_banner():
    log("=" * 68)
    log("Bakes every mesh tagged [Bake] down to one albedo texture, plus a")
    log("matching _spec PBR map and a _n normal map.")
    log("Tag MATERIALS to control the result:")
    log("   [Metal] [MetalRough] [PlateRough] [Glass]   what it is made of")
    log("   [NormGen] | [Bump]                          where its relief comes from")
    log("An untagged material bakes as plain non-metal with no relief.")
    log("Run with --help for everything else.")
    log("=" * 68)


def die(message, detail=None):
    log("")
    log(f"ERROR: {message}")
    for line in detail or []:
        log(f"  {line}")
    log("")
    log("Run with --help for the full description.")
    raise SystemExit(1)


def parse_args(argv):
    args = {"save": False, "only": None, "spec": CONFIG["make_spec"],
            "norm": CONFIG["make_norm"], "res": CONFIG["forced_size"], "list": False}
    argv = argv[argv.index("--") + 1:] if "--" in argv else []

    i = 0
    while i < len(argv):
        a = argv[i]
        if a in ("--help", "-h"):
            print(__doc__)
            raise SystemExit(0)
        elif a == "--save":
            args["save"] = True
        elif a == "--list":
            args["list"] = True
        elif a == "--no-spec":
            args["spec"] = False
        elif a == "--no-norm":
            args["norm"] = False
        elif a == "--only":
            if i + 1 >= len(argv) or argv[i + 1].startswith("--"):
                die("--only needs a name after it", ["e.g. --only silver"])
            i += 1
            args["only"] = argv[i]
        elif a == "--res":
            if i + 1 >= len(argv) or argv[i + 1].startswith("--"):
                die("--res needs a number after it",
                    ["e.g. --res 256", "Omit it to size each texture automatically."])
            i += 1
            try:
                args["res"] = int(argv[i])
            except ValueError:
                die(f"--res wants a whole number, got {argv[i]!r}", ["e.g. --res 256"])
            if args["res"] < 8 or args["res"] > 4096:
                die(f"--res {args['res']} is out of range", ["Use something between 8 and 4096."])
        else:
            die(f"unknown option {a!r}",
                ["Valid options: --save --only NAME --res N --no-spec --no-norm "
                 "--list --help"])
        i += 1
    return args


def main():
    args = parse_args(list(sys.argv))
    log_banner()

    if not bpy.data.filepath:
        die("this .blend has never been saved",
            ["Output paths are worked out relative to the .blend file."])
    if args["res"]:
        CONFIG["forced_size"] = args["res"]

    targets = [o for o in bpy.context.scene.objects
               if o.type == "MESH" and CONFIG["bake_tag"] in o.name.lower()
               and (args["only"] is None or args["only"].lower() in o.name.lower())]
    if not targets:
        tagged = [o.name for o in bpy.context.scene.objects
                  if o.type == "MESH" and CONFIG["bake_tag"] in o.name.lower()]
        if args["only"]:
            die(f"no [Bake] object matches --only {args['only']!r}",
                ["Tagged objects: " + (", ".join(tagged) or "none in this file")])
        die("found no objects to bake",
            [f"Put {CONFIG['bake_tag']} in the OBJECT name of each mesh you want baked.",
             "The material tags then decide what it bakes as."])

    groups = group_clones(targets)
    dupes = sum(len(f) for _, f in groups)
    if dupes:
        log(f"{len(targets)} objects collapse to {len(groups)} unique bakes "
            f"({dupes} clone(s) will reuse a sibling's texture)")

    # OpenMW's VFS is case-insensitive, so two bakes differing only in case
    # would fight over one filename.
    seen = {}
    for rep, _followers in groups:
        base = _plain_slugify(rep.name)
        n = seen.get(base, 0)
        seen[base] = n + 1
        if n:
            rep["mw_bake_slug"] = f"{base}_{n + 1}"

    repair_all_materials()

    if args["list"]:
        log(f"would bake {len(groups)} texture(s) from {len(targets)} object(s):")
        for rep, followers in groups:
            mats = ", ".join(sorted({sl.material.name for sl in rep.material_slots
                                     if sl.material})) or "no materials"
            log(f"  {rep.name!r} -> {slugify(rep.name)}")
            log(f"      materials: {mats}")
            for f in followers:
                log(f"      clone: {f.name!r}")
        return

    shiny = find_shiny_dir()
    log(f"Aesthetically Shiny Things: {shiny}")
    log(f"detail normal: {blend_dir() / CONFIG['detail_normal']}")
    log(f"baking {len(targets)} object(s)")

    if bpy.context.object and bpy.context.object.mode != "OBJECT":
        bpy.ops.object.mode_set(mode="OBJECT")

    results = {}
    for rep, followers in groups:
        for obj in (rep, *followers):
            obj.hide_viewport = False
            obj.hide_render = False
        results[rep.name] = process_object(rep, shiny, args["spec"], args["norm"])
        for follower in followers:
            share_bake(rep, follower)
            results[rep.name].setdefault("clones", []).append(follower.name)

    log("=" * 60)
    for name, files in results.items():
        log(name)
        for kind, path in files.items():
            if kind == "clones":
                log(f"    {'clones':7s} {', '.join(path)}")
            else:
                log(f"    {kind:7s} {path.name}")

    if args["save"]:
        bpy.ops.wm.save_mainfile()
        log(f"saved {bpy.data.filepath}")


_plain_slugify = slugify


def slugify(name):  # noqa: F811
    obj = bpy.data.objects.get(name)
    if obj is not None and "mw_bake_slug" in obj.keys():
        return obj["mw_bake_slug"]
    return _plain_slugify(name)


if __name__ == "__main__":
    main()

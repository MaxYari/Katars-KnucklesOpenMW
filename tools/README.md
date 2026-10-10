# Katars build tools

Three Blender scripts that make the weapons' textures and meshes, all safe to
re-run, a file-manager helper, and the tools that make the release (below).
`mw_paint_prep.py` is meant to be run from Blender's Text Editor as well as
headless. The scripts for the plugins, animations and the off-hand bone are in
[Sources/Tools](../Sources/Tools/README.md). None of this ships with the mod.

```
BLENDER=<path to Blender 5.1>/blender

# 1. bake every "[Bake]" object down to one texture + PBR maps
"$BLENDER" -b Katars_bake_work.blend --python tools/mw_bake.py -- --save

# 2. export each weapon empty to "00 Core/meshes/<name>.nif"
"$BLENDER" -b Katars_bake_work.blend --python tools/mw_export.py -- --overwrite
```

Work on a **copy** of the source .blend. Blender's auto-running addons (Auto-Rig
Pro, Anvil, BlenderKit) can write to whatever file they open, so never point
these at the file you care about.

## mw_bake.py

Picks up any mesh object with `[Bake]` in its name and:

1. Makes a fresh non-overlapping `BakeUV` layer (Smart UV Project + pack), then
   rescales the packed layout to fill 0–1 and gives the image a matching
   **non-square aspect**. Blades unwrap to long thin islands, so a square
   texture would be >80% empty.
2. Bakes the albedo. Each source material is swapped for a pure Emission node
   fed by that material's own base texture through its *original* UVs, and
   Cycles' `EMIT` bake copies it verbatim — no lighting, no colour shift.
3. Writes `<name>_spec.dds`, the OpenMW-PBR map (**R = metalness, G = roughness,
   B = ambient occlusion**) — the same convention "Aesthetically Shiny Things"
   uses. Values are read straight out of that mod when the source texture has a
   counterpart there, otherwise from the keyword table in `CONFIG`.
4. For objects also tagged `[NormGen]`, derives `<name>_n.dds` from the baked
   albedo (local luminance → sobel → normal). This is *not* a high-to-low bake.
   The luminance is high-passed island by island, from each island's own texels,
   and grown outwards past its edge; a blur over the whole image pulled in the
   margin and background and raised a rim along every island border, which
   showed as a crease wherever two islands met on a rounded surface.

Every `_n` is written in the DirectX convention (green = down the image), which
is what OpenMW reads (its docs: texture-modding/texture-basics.rst). Blender
works in OpenGL, so `norm_flip_green` flips green on the way out, and on the way
in for `[NormCopy]` sources, which are OpenMW maps already.
5. Replaces the object's materials with a single MW material pointing at the
   baked DDS, and drops the old UV layer so `BakeUV` is UV set 0.

A material with no tag (`[Alpha]` aside) is left out of all of this: it keeps
its own texture, and its UV layer stays beside `BakeUV`. That is for thin
inlays whose look is their polygon edges — the adamantium blade's lining is
about one texel wide at any sensible bake size, and baked it reads as a
staircase. A bare `[Bake]` on a material bakes it as plain non-metal.

`[NoSpec]` on a material bakes it but writes no `_spec` map, so OpenMW's PBR
shaders guess metalness and roughness from the albedo themselves - a spec map's
mere presence switches that guess off. There is one map per texture, so it
takes every baked material of the object to say so; a stale `_spec` from an
earlier bake is deleted.

Output goes to `00 Core/textures/katars/` (shipping) and `bake_source/` (lossless PNG
masters, not shipped). Resolution is chosen to preserve the original texel
density; tune `texel_multiplier`, or force it with `--res N`.

OpenMW finds the extra maps by itself, given these in `settings.cfg`:

```
[Shaders]
auto use object specular maps = true
auto use object normal maps = true
```

It appends `_spec` / `_n` to the diffuse texture's path, which is why the maps
must sit next to the albedo in `00 Core/textures/katars/`.

## mw_paint_prep.py

Gets a mesh ready for texture painting: its vanilla textures baked onto a
non-overlapping layout of its own. Tag the object `[Paint]`, or select it and
run the script from the Text Editor (flags go in `RUN_OPTIONS` there).

The layout is a second UV map of yours if it is clean - inside 0-1, no
overlaps, not a copy of the first - and otherwise `PaintUV`, made from the
islands of the UV map the textures use. Islands are never re-unwrapped: each
is sized to the vanilla texels it covers, packed with 8 px between them (16 at
2048), and mirrored halves folded onto one seam are cut apart. Faces twisted in
the original UVs cannot be untwisted that way; they are reported and left
selected in Edit Mode.

The bake goes to `bake_source/paint/<name>.png` at twice vanilla's texel
density. Each material slot gets a new material reading it through the layout,
named after the old one with its tags, so `mw_bake.py` bakes the painted mesh
as it did the original. The old material stays in the file, the UV maps the
textures used are copied to `<name>_backup` first, and an object already
prepared is skipped unless `--overwrite` is given - the old texture is then
kept as `<name>_previous.png`. Image > Save (Alt+S) writes the painting.

## mw_export.py

Each weapon is one root EMPTY with its parts parented under it. For each one the
script moves the empty to the origin, exports the whole hierarchy through
io_scene_mw, and puts the empty back. By default it only touches weapons that
own a `[Bake]` object; `--all` does every root empty that has meshes.

Existing .nif files are skipped unless you pass `--overwrite`.

## The "everything is white in game" bug

Both scripts first run `repair_all_materials()`, and it is the reason the
exquisite-shirt texture on the ebony katar was rendering white.

Duplicating a MW material in Blender — Shift+D on an object, "New Material" from
an existing one, appending from another file — copies the node tree but **not**
the addon's custom properties on `material.mw`:

* `mw.material`, a self-pointer, comes back `None`
* `mw.texture_slots`, a CollectionProperty, comes back empty

The self-pointer is the fatal one. `nif_export.py:953` does

```python
try:    bl_prop = material.mw.validate()
except TypeError:  bl_prop = None
```

and `validate()` opens with `m = self.material; if not (m and m.use_nodes): raise
TypeError`. With the pointer gone it always raises, the exception is swallowed,
and that submesh exports with **no NiMaterialProperty and no
NiTexturingProperty at all** — OpenMW then draws it plain white.

Nothing is wrong with the file on disk, the UVs, or the mesh. To check a
suspect material in Blender's Python console:

```python
m = bpy.data.materials["Material.030"]
m.mw.material is m          # False  -> broken
len(m.mw.texture_slots)     # 0      -> broken
```

To fix the whole file:

```python
import sys; sys.path.insert(0, "tools")
import mw_bake; mw_bake.repair_all_materials()
```

## mw_thumbnails.py

Gives the `.dds` textures previews in Dolphin, or any other freedesktop file
manager, which has no DDS plugin on SteamOS: it writes the thumbnails into
`~/.cache/thumbnails` itself. Needs ImageMagick (`magick`).

```
python3 tools/mw_thumbnails.py                  # textures/katars
python3 tools/mw_thumbnails.py DIR [DIR ...]
python3 tools/mw_thumbnails.py --force DIR      # rebuild even if current
```

## The release

`build_nexus_zip.sh` packs the Nexus archive: every file committed to git,
minus what `.nexusignore` matches - the docs, images, sources and every tool
here and in `Sources/Tools`. It lays the archive out BAIN-style: the mod under
`00 Core/`, and each top-level `NN Name` folder of the repository (an optional
patch, such as `01 Glass Glowset Patch/`) and `fomod/` (the installer mod
organisers show, which explains the patches) as they are.

```
bash tools/build_nexus_zip.sh && unzip -l nexus-upload.zip
```

`readme_to_nexus.py` turns `README.md` into the Nexus page's BBCode,
`README.nexus.bbcode`, with image and link paths made into GitHub URLs. Text
between `<!-- nexus-skip-start -->` and `<!-- nexus-skip-end -->` is left out,
which is how the modders' section shrinks to a link on Nexus. The pre-commit
hook in `.githooks` keeps the file in step (`git config core.hooksPath .githooks`
once per clone):

```
python3 tools/readme_to_nexus.py -o README.nexus.bbcode
```

`.github/workflows/nexus-release.yml` runs the script tests on every push to
`main`, and uploads the archive to Nexus for a commit whose message starts with
`[nexus]`. Its own comments have the one-time setup and how the version and
changelog are picked.

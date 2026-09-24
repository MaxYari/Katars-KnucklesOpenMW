# Katars build tools

Two Blender scripts. Both are safe to re-run, and both work headless or from
Blender's Text Editor.

```
BLENDER=/run/media/deck/350243d8-.../programs/blender-5.1.0-linux-x64/blender

# 1. bake every "[Bake]" object down to one texture + PBR maps
"$BLENDER" -b Katars_bake_work.blend --python tools/mw_bake.py -- --save

# 2. export each weapon empty to meshes/<name>.nif
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
5. Replaces the object's materials with a single MW material pointing at the
   baked DDS, and drops the old UV layer so `BakeUV` is UV set 0.

Output goes to `textures/katars/` (shipping) and `bake_source/` (lossless PNG
masters, not shipped). Resolution is chosen to preserve the original texel
density; tune `texel_multiplier`, or force it with `--res N`.

OpenMW finds the extra maps by itself, given these in `settings.cfg`:

```
[Shaders]
auto use object specular maps = true
auto use object normal maps = true
```

It appends `_spec` / `_n` to the diffuse texture's path, which is why the maps
must sit next to the albedo in `textures/katars/`.

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

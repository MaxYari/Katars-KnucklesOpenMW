#!/usr/bin/env python3
"""Builds the Glass Glowset patch: the glass katar with Glass Glowset's glow maps.

Glass Glowset (https://www.nexusmods.com/morrowind/mods/42762) adds a glow map to each vanilla glass
mesh - the NiTexturingProperty's glow slot, which OpenMW draws as emissive light - and replaces the
glass textures with darker ones, the green moving into the glow. OpenMW only takes a glow map from
the mesh (normal and specular maps it can find by file name, glow maps never), so with Glowset
installed our glass katar would get the darker textures and none of the glow.

This writes a copy of the mesh with the glow slots filled into the patch folder, which loads after
the mod and replaces the mesh by its path. A glow map is painted on its texture's own layout, so each
shape gets the one Glowset pairs with its texture, and it lines up with whatever part of that texture
the shape shows. Shapes with any other texture keep none, and are listed. The blade stays solid, as
in Smooth Glass Weapons' Glowset patch (Glowset's own meshes swap in a see-through texture).

The glow maps are Glowset's and are not shipped: the patch needs Glowset installed.

Run it after every export of the glass katar:

    python3 glowset_patch.py                  (00 Core/meshes/glass_katar.nif)
    python3 glowset_patch.py meshes/a.nif ...
"""
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import mirror_weapon_track  # noqa: E402,F401  (puts the es3 library on the path)
from es3.nif import NiSourceTexture, NiStream, NiTexturingProperty, NiTexturingPropertyMap  # noqa: E402

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
PATCH_DIR = os.path.join(ROOT, "01 Glass Glowset Patch")
DEFAULT_MESHES = [os.path.join(ROOT, "00 Core", "meshes", "glass_katar.nif")]

# Texture -> the glow map Glowset's meshes give it. For the crystal blade, the one 11 of its 14
# blade shapes use, and Smooth Glass Weapons' patch too.
GLOWS = {
    "tx_w_crystal_blade": "tx_w_crystal_blade2_g.dds",
    "tx_w_knife_glass_00": "tx_w_knife_glass_00_g.dds",
    "tx_w_waraxe_glass_handle": "tx_w_waraxe_glass_handle_g.dds",
}


def stem(filename):
    return os.path.splitext(filename.replace("\\", "/").rsplit("/", 1)[-1])[0].lower()


def patch(path):
    stream = NiStream()
    stream.load(path)

    glowing, plain = [], []
    for shape in stream.objects():
        texturing = next((p for p in getattr(shape, "properties", None) or []
                          if isinstance(p, NiTexturingProperty)), None)
        if texturing is None or texturing.base_texture is None or texturing.base_texture.source is None:
            continue
        base = texturing.base_texture
        glow = GLOWS.get(stem(base.source.filename))
        if glow is None:
            plain.append("%s (%s)" % (shape.name, base.source.filename))
            continue
        # Shapes can share one property; filling it twice is harmless.
        texturing.glow_texture = NiTexturingPropertyMap(
            source=NiSourceTexture(filename=glow), clamp_mode=base.clamp_mode,
            filter_mode=base.filter_mode, uv_set=base.uv_set)
        glowing.append("%s (%s)" % (shape.name, glow))

    if not glowing:
        sys.exit("%s: no shape has a texture Glowset gives a glow to - nothing to patch" % path)

    out = os.path.join(PATCH_DIR, "meshes", os.path.basename(path))
    os.makedirs(os.path.dirname(out), exist_ok=True)
    stream.save(out)
    print(os.path.relpath(out, ROOT))
    print("  glow:    " + "\n           ".join(glowing))
    if plain:
        print("  no glow: " + "\n           ".join(plain))


def main():
    for path in sys.argv[1:] or DEFAULT_MESHES:
        patch(path)


if __name__ == "__main__":
    main()

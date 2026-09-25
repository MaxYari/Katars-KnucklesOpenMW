#!/usr/bin/env python3
"""Builds Ebony Rose's purple poison: the hit and area effects, their textures and the spell icon.

Every visual a magic effect has comes from its record - hit static, area static, particle texture,
icon - and the engine plays them for whatever effect is applied (spellcasting.cpp playEffects and
explodeSpell). So the venom's custom effect (scripts/MaxYari/H2HWeapons/content.lua) only has to
point at purple versions of the vanilla poison ones, and the engine does the rest: the burst on a
hit, the cloud that hangs on the victim while it lasts, the explosion.

Why copies of the meshes, and not just a purple particle texture: the particle texture only replaces
the *first* texture in an effect mesh (NifOsg marks that one "overrideFx" and TextureOverrideVisitor
touches nothing else), and the poison meshes carry five more, all of them green. Their materials are
grey, so the colour is entirely in the textures - which is why re-hueing those is enough.

The hue is replaced, not shifted: the vanilla set runs from yellow-green to blue-green, and a shift
would keep that spread. Lightness and saturation are kept, so every cloud keeps its detail, and the
result is brightened a little because purple reads darker than green at the same lightness.

Needs bsatool (ships with OpenMW), ImageMagick, and Greatness7's es3 library (see charge_fx.py).

    python3 venom_fx.py --data "<Morrowind>/Data Files" --bsatool <openmw>/bsatool
"""
import argparse
import os
import shutil
import subprocess
import sys
import tempfile

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import charge_fx  # noqa: E402,F401  (puts es3 on the path, and says so if it cannot)
from es3.nif import NiSourceTexture, NiStream  # noqa: E402

HUE = 0.79          # purple, as a fraction of the colour wheel
SATURATION = 1.10
BRIGHTNESS = 1.35
# Icons are opaque and seen at 16 pixels, where the textures' boost just burns them out.
ICON_BRIGHTNESS = 1.0

MESHES = {
    # vanilla mesh (in the BSA)       -> this mod's copy, relative to the mod root
    r"meshes\e\magic_hit_poison.nif": "meshes/katars/vfx_venom_hit.nif",
    r"meshes\e\magic_area_poison.nif": "meshes/katars/vfx_venom_area.nif",
}

# The venom's textures live in a folder of their own: textures/katars/ is where the weapon bake writes,
# and a re-bake clearing it took these with it once.
TEXTURE_FOLDER = "katars_vfx"

TEXTURES = {
    # vanilla texture name (no folder) -> this mod's, under textures/<TEXTURE_FOLDER>/
    "vfx_poison": "vfx_venom",               # the particle texture on the effect record itself
    "vfx_poison03": "vfx_venom03",
    "vfx_poisoncloud01": "vfx_venomcloud01",
    "vfx_poisoncloud03": "vfx_venomcloud03",
    "vfx_poisoncloud04": "vfx_venomcloud04",
    "vfx_greenalpha": "vfx_venomalpha",
}

ICONS = {
    # vanilla icon -> this mod's, under Icons/katars/. The big one is found by the engine from the
    # small one's name, so both have to be there.
    r"icons\s\tx_s_poison.dds": "tx_s_venom.dds",
    r"icons\s\b_tx_s_poison.dds": "b_tx_s_venom.dds",
}


def extract(bsatool, archive, member, out_dir):
    subprocess.run([bsatool, "extract", archive, member, out_dir],
                   check=True, stdout=subprocess.DEVNULL)
    path = os.path.join(out_dir, member.replace("\\", "/").split("/")[-1])
    if not os.path.exists(path):
        sys.exit("bsatool did not produce %s" % member)
    return path


def dds_compression(path):
    """DXT1 stays DXT1 (no alpha to keep); everything else goes out as DXT5."""
    with open(path, "rb") as fh:
        header = fh.read(88)
    return "dxt1" if header[84:88] == b"DXT1" else "dxt5"


def recolour(src, dst, brightness=BRIGHTNESS):
    os.makedirs(os.path.dirname(dst), exist_ok=True)
    subprocess.run([
        "magick", src,
        "-colorspace", "HSL",
        "-channel", "R", "-evaluate", "set", "%g%%" % (HUE * 100), "+channel",
        "-channel", "G", "-evaluate", "multiply", "%g" % SATURATION, "+channel",
        "-colorspace", "sRGB",
        "-channel", "RGB", "-evaluate", "multiply", "%g" % brightness, "+channel",
        "-define", "dds:compression=%s" % dds_compression(src),
        dst,
    ], check=True)


def retarget(src, dst):
    """Copy a mesh with every texture it names pointed at the purple set."""
    stream = NiStream()
    stream.load(src)
    changed = []
    for obj in stream.objects():
        if not isinstance(obj, NiSourceTexture):
            continue
        stem = os.path.splitext(os.path.basename(obj.filename.replace("\\", "/")))[0].lower()
        if stem not in TEXTURES:
            sys.exit("%s uses %s, which has no purple version - add it to TEXTURES"
                     % (os.path.basename(src), obj.filename))
        obj.filename = "%s\\%s.dds" % (TEXTURE_FOLDER, TEXTURES[stem])
        changed.append(stem)
    os.makedirs(os.path.dirname(dst), exist_ok=True)
    stream.save(dst)
    return changed


def main():
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--data", required=True, help="Morrowind's Data Files folder")
    ap.add_argument("--bsatool", default="bsatool", help="OpenMW's bsatool")
    ap.add_argument("--root", default=os.path.join(os.path.dirname(os.path.abspath(__file__)), "../.."),
                    help="the mod's root folder")
    args = ap.parse_args()

    archive = os.path.join(args.data, "Morrowind.bsa")
    root = os.path.abspath(args.root)
    work = tempfile.mkdtemp(prefix="venom_fx_")
    try:
        for member, out in MESHES.items():
            src = extract(args.bsatool, archive, member, work)
            used = retarget(src, os.path.join(root, out))
            print("%-34s -> %s (%s)" % (os.path.basename(member), out, ", ".join(sorted(set(used)))))

        for stem, new in TEXTURES.items():
            src = extract(args.bsatool, archive, "textures\\%s.dds" % stem, work)
            out = os.path.join(root, "textures", TEXTURE_FOLDER, new + ".dds")
            recolour(src, out)
            print("%-34s -> textures/%s/%s.dds" % (stem + ".dds", TEXTURE_FOLDER, new))

        for member, new in ICONS.items():
            src = extract(args.bsatool, archive, member, work)
            out = os.path.join(root, "Icons", "katars", new)
            recolour(src, out, ICON_BRIGHTNESS)
            print("%-34s -> Icons/katars/%s" % (os.path.basename(member), new))
    finally:
        shutil.rmtree(work, ignore_errors=True)


if __name__ == "__main__":
    main()

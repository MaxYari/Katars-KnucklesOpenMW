#!/usr/bin/env python3
"""
mw_thumbnails.py -- give DDS files previews in Dolphin (and any other
freedesktop file manager).

SteamOS ships no DDS image plugin, so Dolphin cannot generate previews for
.dds files at all. The previews you already see come from Blender: its File
Browser writes into the shared freedesktop thumbnail cache, and Dolphin simply
displays whatever it finds there. Textures that were never browsed in Blender
-- such as anything mw_bake.py writes -- therefore show a generic icon.

This writes spec-compliant thumbnails for them directly, no Blender needed:

    ~/.cache/thumbnails/normal/<md5 of uri>.png   (max 128px)
    ~/.cache/thumbnails/large/<md5 of uri>.png    (max 256px)

each carrying the Thumb::URI and Thumb::MTime tEXt chunks the spec requires, so
a file manager knows when the thumbnail has gone stale.

Usage:
    python3 tools/mw_thumbnails.py                  # defaults to textures/katars
    python3 tools/mw_thumbnails.py DIR [DIR ...]
    python3 tools/mw_thumbnails.py --force DIR      # rebuild even if current

Requires ImageMagick ("magick") on PATH. Deleting ~/.cache/thumbnails is always
safe -- the worst case is that previews are regenerated or simply absent.
"""

import binascii
import hashlib
import os
import pathlib
import struct
import subprocess
import sys
import urllib.parse

CACHE = pathlib.Path(os.environ.get("XDG_CACHE_HOME",
                                    os.path.expanduser("~/.cache"))) / "thumbnails"
SIZES = {"normal": 128, "large": 256}
EXTENSIONS = {".dds", ".tga", ".bmp"}


def thumb_path(uri, kind):
    return CACHE / kind / (hashlib.md5(uri.encode("utf-8")).hexdigest() + ".png")


def file_uri(path):
    # Matches what Blender/KDE produce: percent-encoded, path separators intact.
    return "file://" + urllib.parse.quote(str(path), safe="/")


PNG_MAGIC = b"\x89PNG\r\n\x1a\n"


def png_add_text(path, entries):
    """Insert tEXt chunks after IHDR.

    Done here rather than with ImageMagick's -set, which treats the value as a
    format string: a URI's %20 comes out the other side as "0".
    """
    raw = path.read_bytes()
    if not raw.startswith(PNG_MAGIC):
        raise ValueError(f"not a PNG: {path}")

    # walk to the end of IHDR
    pos = len(PNG_MAGIC)
    length, ctype = struct.unpack(">I4s", raw[pos:pos + 8])
    if ctype != b"IHDR":
        raise ValueError(f"first chunk is {ctype!r}, not IHDR: {path}")
    insert_at = pos + 8 + length + 4

    chunks = b""
    for key, value in entries.items():
        data = key.encode("latin-1") + b"\x00" + str(value).encode("latin-1")
        chunks += (struct.pack(">I", len(data)) + b"tEXt" + data
                   + struct.pack(">I", binascii.crc32(b"tEXt" + data) & 0xFFFFFFFF))

    path.write_bytes(raw[:insert_at] + chunks + raw[insert_at:])


def read_png_text(path):
    """Pull the tEXt chunks back out, so staleness can be checked."""
    out = {}
    try:
        raw = path.read_bytes()
    except OSError:
        return out
    if not raw.startswith(PNG_MAGIC):
        return out
    pos = len(PNG_MAGIC)
    while pos + 8 <= len(raw):
        length, ctype = struct.unpack(">I4s", raw[pos:pos + 8])
        if ctype == b"tEXt":
            key, _, value = raw[pos + 8:pos + 8 + length].partition(b"\x00")
            out[key.decode("latin-1")] = value.decode("latin-1")
        elif ctype == b"IEND":
            break
        pos += 8 + length + 4
    return out


def is_current(dest, uri, mtime):
    """A thumbnail is stale if its recorded URI/MTime no longer match."""
    if not dest.is_file():
        return False
    text = read_png_text(dest)
    return text.get("Thumb::URI") == uri and text.get("Thumb::MTime") == str(mtime)


def make_thumbnail(src, force=False):
    uri = file_uri(src)
    mtime = int(src.stat().st_mtime)
    made = []

    for kind, box in SIZES.items():
        dest = thumb_path(uri, kind)
        if not force and is_current(dest, uri, mtime):
            continue
        dest.parent.mkdir(parents=True, exist_ok=True)
        cmd = [
            "magick", f"{src}[0]",          # [0] = top mip level only
            "-alpha", "remove", "-alpha", "off",
            "-resize", f"{box}x{box}>",     # ">" = shrink only, never upscale
            str(dest),
        ]
        subprocess.run(cmd, check=True, capture_output=True)
        png_add_text(dest, {"Thumb::URI": uri, "Thumb::MTime": mtime})
        dest.chmod(0o600)                   # the spec requires owner-only
        made.append(kind)

    return made


def main():
    args = [a for a in sys.argv[1:] if not a.startswith("-")]
    force = "--force" in sys.argv

    if args:
        roots = [pathlib.Path(a).resolve() for a in args]
    else:
        roots = [pathlib.Path(__file__).resolve().parent.parent / "textures" / "katars"]

    total = skipped = 0
    for root in roots:
        if not root.is_dir():
            print(f"skip (not a directory): {root}")
            continue
        print(f"{root}")
        for src in sorted(root.rglob("*")):
            if not src.is_file() or src.suffix.lower() not in EXTENSIONS:
                continue
            made = make_thumbnail(src, force)
            if made:
                total += 1
                print(f"   {src.name:38s} -> {', '.join(made)}")
            else:
                skipped += 1
    print(f"\n{total} thumbnail set(s) written, {skipped} already current.")
    if total:
        print("Press F5 in Dolphin to pick them up.")


if __name__ == "__main__":
    main()

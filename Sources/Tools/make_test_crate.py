#!/usr/bin/env python3
"""Writes Katars_FOR_TESTING_ONLY_Crate_With_All_Items.omwaddon - FOR TESTING ONLY, never released.

One crate with one of everything this mod adds - every katar and knuckleduster, the uniques and the
Bound Fist weapons included, and the note - set on the ground beside the stump with the iron
shardaxe stuck in it, just west of the Seyda Neen lighthouse. The item list comes from
make_plugin.py, so the crate keeps up with the mod: run this again after adding anything.

The crate stands on the terrain itself: the heights are read from Morrowind.esm's landscape record
for the cell, and the spot is the highest ground on a ring around the stump that keeps clear of
the plants around it.

    python3 Sources/Tools/make_test_crate.py --master "<Data Files>/Morrowind.esm"

Enable it after Katar.omwaddon. It is left out of the release (.nexusignore).
"""
import argparse
import math
import os
import struct
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import make_plugin  # noqa: E402
from make_plugin import record, sub, zstr  # noqa: E402

OUT = "Katars_FOR_TESTING_ONLY_Crate_With_All_Items.omwaddon"
PLUGIN = "Katar.omwaddon"

CRATE_ID = "h2h_test_crate_all_items"
CRATE_NAME = "TEST: every Katars item"
CRATE_MODEL = "o\\Contain_crate_01.NIF"   # vanilla crate_01's, a 64-unit cube around its origin
CRATE_HALF_HEIGHT = 32.0

# The stump: flora_bc_tree_12 in Seyda Neen, cell (-2, -10), with an "iron shardaxe" in it.
CELL = (-2, -10)
STUMP = (-13086.7, -74870.8)
RING = (100.0, 150.0)          # how far from the stump the crate may stand
CLEARANCE = 60.0               # and how far from anything else
WATER_LEVEL = 0.0
CELL_SIZE = 8192
VERTICES = 65


def read_records(path):
    data = open(path, "rb").read()
    i = 0
    while i + 16 <= len(data):
        tag = data[i:i + 4].decode("latin-1")
        size = struct.unpack("<I", data[i + 4:i + 8])[0]
        yield tag, data[i + 16:i + 16 + size]
        i += 16 + size


def subrecords(body):
    j = 0
    while j + 8 <= len(body):
        tag = body[j:j + 4].decode("latin-1")
        size = struct.unpack("<I", body[j + 4:j + 8])[0]
        yield tag, body[j + 8:j + 8 + size]
        j += 8 + size


def find_cell_and_land(master):
    """The cell's own header subrecords, the positions of what is in it, and its terrain heights."""
    header, positions, heights = None, [], None
    for tag, body in read_records(master):
        if tag == "CELL" and header is None:
            subs = list(subrecords(body))
            data = next(b for t, b in subs if t == "DATA")
            flags, gx, gy = struct.unpack("<iii", data[:12])
            if flags & 1 or (gx, gy) != CELL:
                continue
            header = []
            for t, b in subs:
                if t == "FRMR":
                    break
                if t != "NAM0":  # the master's reference count, not this plugin's
                    header.append((t, b))
            for t, b in subs:
                if t == "DATA" and len(b) == 24:
                    positions.append(struct.unpack("<6f", b)[:3])
        elif tag == "LAND" and heights is None:
            subs = dict(subrecords(body))
            if struct.unpack("<ii", subs["INTV"][:8]) != CELL or "VHGT" not in subs:
                continue
            vhgt = subs["VHGT"]
            offset = struct.unpack("<f", vhgt[:4])[0]
            deltas = struct.unpack("<%db" % (VERTICES * VERTICES), vhgt[4:4 + VERTICES * VERTICES])
            heights = [[0.0] * VERTICES for _ in range(VERTICES)]
            row = offset
            for y in range(VERTICES):
                row += deltas[y * VERTICES]
                col = row
                heights[y][0] = row * 8
                for x in range(1, VERTICES):
                    col += deltas[y * VERTICES + x]
                    heights[y][x] = col * 8
    if header is None or heights is None:
        sys.exit("cell %s or its landscape is not in %s" % (CELL, master))
    return header, positions, heights


def terrain_height(heights, px, py):
    """Bilinear, between the landscape's vertices 128 units apart."""
    fx = (px - CELL[0] * CELL_SIZE) / (CELL_SIZE / (VERTICES - 1))
    fy = (py - CELL[1] * CELL_SIZE) / (CELL_SIZE / (VERTICES - 1))
    x0, y0 = int(math.floor(fx)), int(math.floor(fy))
    tx, ty = fx - x0, fy - y0
    h = heights
    top = h[y0][x0] * (1 - tx) + h[y0][x0 + 1] * tx
    bottom = h[y0 + 1][x0] * (1 - tx) + h[y0 + 1][x0 + 1] * tx
    return top * (1 - ty) + bottom * ty


def crate_spot(positions, heights):
    best = None
    for radius in RING:
        for step in range(32):
            angle = 2 * math.pi * step / 32
            px, py = STUMP[0] + radius * math.cos(angle), STUMP[1] + radius * math.sin(angle)
            if any(math.dist((px, py), p[:2]) < CLEARANCE for p in positions):
                continue
            ground = terrain_height(heights, px, py)
            if best is None or ground > best[2]:
                best = (px, py, ground)
    if best is None or best[2] <= WATER_LEVEL + 5:
        sys.exit("no dry ground clear of everything around the stump")
    # Facing the stump.
    facing = math.atan2(STUMP[0] - best[0], STUMP[1] - best[1])
    return best[0], best[1], best[2] + CRATE_HALF_HEIGHT, facing


def item_ids():
    ids = [item[0] for item in make_plugin.ITEMS]
    ids += [rid for rid, _base, _name in make_plugin.BOUND_WEAPONS]
    ids += list(make_plugin.NOTES)
    return ids


def crate_record(ids):
    body = sub("NAME", zstr(CRATE_ID)) + sub("MODL", zstr(CRATE_MODEL)) + sub("FNAM", zstr(CRATE_NAME))
    body += sub("CNDT", struct.pack("<f", 1000.0)) + sub("FLAG", struct.pack("<i", 8))
    for rid in ids:
        encoded = rid.encode("latin-1")
        assert len(encoded) <= 32, rid
        body += sub("NPCO", struct.pack("<i", 1) + encoded.ljust(32, b"\0"))
    return record("CONT", body)


def cell_record(header, spot):
    x, y, z, facing = spot
    body = b"".join(sub(t, b) for t, b in header)
    body += sub("FRMR", struct.pack("<I", 1)) + sub("NAME", zstr(CRATE_ID))
    body += sub("DATA", struct.pack("<6f", x, y, z, 0.0, 0.0, facing))
    return record("CELL", body)


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--master", required=True, help="path to Morrowind.esm")
    ap.add_argument("--plugin", default=PLUGIN, help="this mod's generated plugin, a master of the crate's")
    ap.add_argument("-o", "--out", default=OUT)
    args = ap.parse_args()

    header, positions, heights = find_cell_and_land(args.master)
    spot = crate_spot(positions, heights)
    ids = item_ids()

    author = b"Max Yari".ljust(32, b"\0")
    description = b"FOR TESTING ONLY: a crate of every Katars item by the Seyda Neen lighthouse.".ljust(256, b"\0")
    hedr = struct.pack("<fi", 1.3, 0) + author + description + struct.pack("<i", 2)
    tes3 = sub("HEDR", hedr)
    for master in (args.master, args.plugin):
        tes3 += sub("MAST", zstr(os.path.basename(master))) + sub("DATA", struct.pack("<Q", os.path.getsize(master)))

    with open(args.out, "wb") as fh:
        fh.write(record("TES3", tes3) + crate_record(ids) + cell_record(header, spot))
    print("wrote %s: a crate of %d items at (%.0f, %.0f, %.0f), %.0f units from the stump"
          % (args.out, len(ids), spot[0], spot[1], spot[2], math.dist(spot[:2], STUMP)))


if __name__ == "__main__":
    main()

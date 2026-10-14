"""Shop stock: which weapon merchants sell which katars and knuckledusters, and the records that put
them there. make_plugin.py runs it over vanilla's merchants, make_tr_plugin.py over Tamriel Rebuilt's.

The levelled lists alone leave the weapons rare in shops: most smiths sell a fixed stock - a few
weapons in their own inventory and in the chests they own, most of them restocking - and roll only a
little from the lists. So merchants who sell blunt weapons and short blades of their own get ours
beside them, in the materials they already sell:

* A merchant qualifies with two or more different fixed blunt weapons and short blades (levelled
  entries do not count, nor tools Tamriel Data types as weapons), plain and enchanted counted apart -
  an enchanted pool gets the shop-enchanted versions.
* Each material they sell rolls for its katar or knuckleduster: 30% at two such weapons, rising
  17.5 points a weapon to certain at six (CHANCE_AT_TWO, CHANCE_STEP). Where a material has both, the
  knuckles take the share the merchant's blunt weapons are of the pool and the katars the short
  blades'.
* A merchant gets at most half as many of ours as the weapons that qualified them (rounded down), one
  per material, and when that runs out first, the materials they sell most of come first.
* Every weapon has a target: what that roll gives on average without the cap, rounded up. Weapons the
  first roll leaves under it are dealt again, to merchants with room, until each is there or nobody
  has room left; weapons already there are not.
* A weapon restocks if the merchant's own weapons of its material do.

It is rolled once, here, with a fixed seed: every player finds the same shops stocked, and a rebuild
from the same data gives the same plugin. Ebony, glass and adamantium are left out of it (EXCLUDED):
they are rare in shops, and stocked by hand where they are (make_plugin.py's CONTAINER_ADDITIONS and
SHOP_ADDITIONS). Hand-stocked weapons count against a merchant's cap like dealt ones.

Merchants sell from their own inventory and from every container they own in the loaded cells
(World::getContainersOwnedBy, which skips containers that hold nothing). A merchant who owns a chest
of weapons that is in the world once gets ours in that chest: its record, read from the masters with
ours added. Anyone else - their stock in their own record, or in a chest the same as other shops' - gets
a hidden chest of their own instead: a new container, owned by them, far under their cell. No NPC
record is touched, so no mod that edits a merchant fights this one over them.
"""
import collections
import math
import random
import struct

import make_plugin as mp
from make_plugin import record, sub, zstr

SHORT_BLADE = 0
BLUNT = (3, 4, 5)  # one-handed, two-handed and staves

CHANCE_AT_TWO, CHANCE_STEP = 0.30, 0.175
SEED = 2026

# Weapons Tamriel Data types as short blades and blunt weapons that are a farmer's or a cook's tools.
NOT_WEAPONS = ("t_com_farm_", "t_com_var_")

# Test characters Morrowind.esm leaves in, who trade weapons and stand in a test cell.
TEST_NPCS = {"todd", "used clutter salesman"}

# A weapon's material, from words in its id or mesh, in this order - nordic silver before silver, and
# the plain metals last, since "iron" and "steel" turn up inside other names. Steel is what is left:
# vanilla names some steel weapons by their shape alone (tanto, wakizashi, the "dragon" dagger),
# Tamriel Data its Imperial and Nordic steel. Materials with no katar or knuckleduster (Dwemer,
# dreugh, wood - Driftwood Beaters are unique - gold, the Morag Tong's) deal none.
MATERIAL_WORDS = [
    ("adamant", "adamantium"), ("silver", "silver"), ("chitin", "chitin"), ("glass", "glass"),
    ("ebony", "ebony"), ("daedric", "daedric"), ("orcish", "orcish"), ("_orc_", "orcish"),
    ("dwemer", "dwemer"), ("dwarven", "dwemer"), ("dwrv", "dwemer"), ("t_dwe_", "dwemer"),
    ("dreugh", "dreugh"), ("bonemold", "bonemold"), ("wood", "wood"), ("corkbulb", "wood"),
    ("gold", "gold"), ("moragtong", "morag tong"), ("iron", "iron"), ("spiked club", "iron"),
]

# Ours, per material: the plain ones, and the shop-enchanted ones for an enchanted pool. Berserker
# Silver Knuckles are berserkers' gear, not shop stock (make_plugin.py, ENCHANTED_VERSIONS).
OURS = {
    False: {"iron": ["knuckle_iron"], "steel": ["katar_steel"], "silver": ["knuckle_silver", "katar_silver"],
            "chitin": ["knuckle_chitin"], "nordic silver": ["knuckle_nordic_silver"],
            "orcish": ["knuckle_orcish"], "daedric": ["knuckle_daedric", "katar_daedric"],
            "ebony": ["katar_ebony"], "glass": ["katar_glass"], "adamantium": ["katar_adamantium"]},
    True: {"iron": ["knuckle_iron_spark"], "steel": ["katar_steel_smoulder"],
           "silver": ["knuckle_silver_shard", "katar_silver_ice"], "chitin": ["knuckle_chitin_shard"],
           "orcish": ["knuckle_orcish_smoulder"], "ebony": ["katar_ebony_spark"], "glass": ["katar_glass_flame"]},
}
EXCLUDED = {"ebony", "glass", "adamantium"}

# The hidden chest: vanilla's small chest, under an id of its own, placed this far below the lowest
# thing in its cell - the lowest reference and, outdoors, the lowest point of the terrain. A reference's
# position is its origin, not the bottom of its mesh, and Morrowind's biggest interior pieces reach a
# couple of thousand units below theirs.
HIDDEN_CHEST = {"model": "o\\Contain_chest_small_01.NIF", "name": "Small Chest", "capacity": 25.0}
HIDDEN_DEPTH = 8192.0
HIDDEN_PREFIX = "h2h_shop_"


def material(rid, weapon):
    words = (rid + " " + weapon.get("model", "")).lower()
    if "nord" in words and "silver" in words:
        return "nordic silver"
    for word, mat in MATERIAL_WORDS:
        if word in words:
            return mat
    return "steel"


def material_of_ours(rid):
    """Which material one of ours is, from OURS."""
    for ench in (False, True):
        for mat, ids in OURS[ench].items():
            if rid in ids:
                return mat, ench
    raise KeyError(rid)


# --- Reading the world ---------------------------------------------------------------------------------

def _subrecords(body):
    out, pos = [], 0
    while pos + 8 <= len(body):
        name = body[pos:pos + 4].decode("latin-1")
        size = struct.unpack_from("<I", body, pos + 4)[0]
        out.append((name, body[pos + 8:pos + 8 + size]))
        pos += 8 + size
    return out


def _id(payload):
    return payload.split(b"\0")[0].decode("latin-1").lower()


def _records(path, tags):
    with open(path, "rb") as fh:
        data = fh.read()
    pos = 0
    while pos + 16 <= len(data):
        tag = data[pos:pos + 4]
        size, _unused, flags = struct.unpack_from("<III", data, pos + 4)
        body = data[pos + 16:pos + 16 + size]
        pos += 16 + size
        if tag in tags:
            yield tag, flags, body


class World:
    """What the merchant stock needs from a set of content files, read in load order: the merchants,
    containers and weapons as the last file leaves them, and every cell's references from all of them."""

    def __init__(self, paths):
        self.npcs, self.containers, self.weapons = {}, {}, {}
        self.origin = {}                        # NPC id -> the file that first has them
        self.cells = {}                         # cell key -> {name, grid, header, refs}
        self.placed = collections.defaultdict(list)   # base id -> [(cell key, position)]
        self.owned = collections.defaultdict(set)     # owner id -> container ids
        for path in paths:
            self._read(path)

    def _read(self, path):
        for tag, flags, body in _records(path, {b"NPC_", b"CREA", b"CONT", b"WEAP", b"CELL"}):
            subs = _subrecords(body)
            if tag == b"CELL":
                self._read_cell(subs)
                continue
            rid = _id(subs[0][1])
            if tag in (b"NPC_", b"CREA"):
                rec = {"name": "", "services": 0, "inventory": []}
                for name, payload in subs:
                    if name == "FNAM":
                        rec["name"] = payload.split(b"\0")[0].decode("latin-1")
                    elif name == "AIDT":
                        rec["services"] = struct.unpack_from("<i", payload, 8)[0]
                    elif name == "NPCO":
                        rec["inventory"].append((struct.unpack_from("<i", payload)[0], _id(payload[4:])))
                self.npcs[rid] = rec
                self.origin.setdefault(rid, path)
            elif tag == b"CONT":
                inventory = [(struct.unpack_from("<i", p)[0], _id(p[4:])) for n, p in subs if n == "NPCO"]
                self.containers[rid] = {"flags": flags, "body": body, "inventory": inventory}
            elif tag == b"WEAP":
                rec = {"enchanted": False}
                for name, payload in subs:
                    if name == "MODL":
                        rec["model"] = _id(payload)
                    elif name == "WPDT":
                        rec["type"] = struct.unpack_from("<h", payload, 8)[0]
                    elif name == "ENAM":
                        rec["enchanted"] = True
                self.weapons[rid] = rec

    def _read_cell(self, subs):
        first_ref = next((i for i, (n, _p) in enumerate(subs) if n in ("FRMR", "MVRF")), len(subs))
        name = next(p for n, p in subs[:first_ref] if n == "NAME").split(b"\0")[0].decode("latin-1")
        flags, gx, gy = struct.unpack_from("<iii", next(p for n, p in subs[:first_ref] if n == "DATA"))
        interior = bool(flags & 1)
        key = name.lower() if interior else (gx, gy)
        cell = self.cells.setdefault(key, {"name": name, "grid": None if interior else (gx, gy), "refs": []})
        # What a plugin adding to this cell has to write of the cell itself: its name and DATA, the one
        # field every CELL needs (Cell::loadNameAndData fails without it), as the last file to have it
        # leaves them. Nothing else: Store<ESM::Cell>::load merges a cell's references from every file,
        # and Cell::loadCell only overwrites the water level, light, region and map colour a file
        # actually has - leaving them out keeps whatever an earlier one set, so a mod that relights
        # or floods the cell keeps it whatever the load order. (The flags loadCell clears when they
        # are missing, mHasAmbi and mHasWaterHeightSub, only matter when a file is saved.)
        cell["header"] = b"".join(sub(n, p) for n, p in subs[:first_ref] if n in ("NAME", "DATA"))
        ref = None
        for n, payload in subs[first_ref:]:
            if n == "FRMR":
                ref = {"base": None, "owner": None, "pos": None, "deleted": False}
                cell["refs"].append(ref)
            elif ref is None:
                continue
            elif n == "NAME":
                ref["base"] = _id(payload)
            elif n == "ANAM":
                ref["owner"] = _id(payload)
            elif n == "DELE":
                ref["deleted"] = True
            elif n == "DATA" and len(payload) == 24:
                ref["pos"] = struct.unpack("<3f", payload[:12])
                if ref["base"] and not ref["deleted"]:
                    self.placed[ref["base"]].append((key, ref["pos"]))
                    if ref["owner"]:
                        self.owned[ref["owner"]].add(ref["base"])

    def lowest_point(self, key):
        """The lowest reference in a cell."""
        return min(r["pos"][2] for r in self.cells[key]["refs"] if r["pos"])


def terrain_floor(paths, grids):
    """{(x, y): the lowest point of that exterior cell's terrain}, from the last file to have its LAND.
    VHGT is an offset and 65 x 65 steps, each row starting from the one before it."""
    floors = {}
    for path in paths:
        for _tag, _flags, body in _records(path, {b"LAND"}):
            subs = dict(_subrecords(body))
            grid = struct.unpack_from("<ii", subs["INTV"])
            if grid not in grids or "VHGT" not in subs:
                continue
            vhgt = subs["VHGT"]
            offset = struct.unpack_from("<f", vhgt)[0]
            steps = struct.unpack_from("<4225b", vhgt, 4)
            row, lowest = offset, offset
            for r in range(65):
                row += steps[r * 65]
                height = row
                lowest = min(lowest, height)
                for c in range(1, 65):
                    height += steps[r * 65 + c]
                    lowest = min(lowest, height)
            floors[grid] = lowest * 8
    return floors


# --- Who gets what -------------------------------------------------------------------------------------

def chance(count):
    return min(1.0, CHANCE_AT_TWO + CHANCE_STEP * (count - 2))


def pools(world, merchants):
    """{(merchant, enchanted): pool} for every merchant that qualifies."""
    out = {}
    for mid in sorted(merchants):
        rec = world.npcs[mid]
        stock = list(rec["inventory"])
        for chest in sorted(world.owned.get(mid, ())):
            stock += world.containers.get(chest, {"inventory": []})["inventory"]
        for enchanted in (False, True):
            weapons = {}
            for count, rid in stock:
                w = world.weapons.get(rid)
                if not w or rid.startswith(NOT_WEAPONS) or w["enchanted"] != enchanted:
                    continue
                if w.get("type") == SHORT_BLADE or w.get("type") in BLUNT:
                    weapons[rid] = weapons.get(rid, False) or count < 0
            if len(weapons) < 2:
                continue
            blunt = sum(1 for rid in weapons if world.weapons[rid]["type"] in BLUNT)
            by_material = collections.Counter(material(rid, world.weapons[rid]) for rid in weapons)
            restocks = {material(rid, world.weapons[rid]) for rid, r in weapons.items() if r}
            options = {}
            for mat in by_material:
                ids = OURS[enchanted].get(mat)
                if ids and mat not in EXCLUDED:
                    options[mat] = [(i, blunt if i.startswith("knuckle") else len(weapons) - blunt) for i in ids]
            out[(mid, enchanted)] = {"count": len(weapons), "chance": chance(len(weapons)),
                                     "cap": len(weapons) // 2, "materials": by_material,
                                     "options": options, "restocks": restocks}
    return out


def _share(options, rid):
    if len(options) == 1:
        return 1.0
    total = sum(w for _i, w in options)
    return dict(options)[rid] / total if total else 1.0 / len(options)


def targets(pool_table):
    """Each weapon's target: what the roll deals on average with no cap, rounded up."""
    expected = collections.Counter()
    for pool in pool_table.values():
        for options in pool["options"].values():
            for rid, _w in options:
                expected[rid] += pool["chance"] * _share(options, rid)
    return {rid: math.ceil(value - 1e-9) for rid, value in expected.items() if value > 0}


def deal(pool_table, hand_stocked, seed=SEED):
    """{(merchant, enchanted): {material: weapon id}}: the hand-stocked ones, then the roll."""
    rng = random.Random(seed)
    have = collections.defaultdict(dict)
    for mid, rid in hand_stocked:
        mat, enchanted = material_of_ours(rid)
        have[(mid, enchanted)][mat] = rid

    def pick(options):
        weights = [w for _i, w in options]
        return options[0][0] if len(options) == 1 else \
            rng.choices([i for i, _w in options], weights=weights if sum(weights) else None)[0]

    for key in sorted(pool_table):
        pool = pool_table[key]
        mats = sorted(pool["options"])
        while mats:
            mat = rng.choices(mats, weights=[pool["materials"][m] for m in mats])[0]
            mats.remove(mat)
            if len(have[key]) >= pool["cap"]:
                break
            if mat not in have[key] and rng.random() < pool["chance"]:
                have[key][mat] = pick(pool["options"][mat])

    goal = targets(pool_table)

    def dealt():
        return collections.Counter(rid for got in have.values() for rid in got.values())

    while True:
        under = sorted(rid for rid, n in goal.items() if dealt()[rid] < n)
        rng.shuffle(under)
        progress = False
        for rid in under:
            mat, _enchanted = material_of_ours(rid)
            room = sorted(key for key, pool in pool_table.items()
                          if len(have[key]) < pool["cap"] and mat not in have[key]
                          and rid in dict(pool["options"].get(mat, [])))
            rng.shuffle(room)
            for key in room:
                if dealt()[rid] >= goal[rid]:
                    break
                progress = True
                pool = pool_table[key]
                if rng.random() < pool["chance"] * _share(pool["options"][mat], rid):
                    have[key][mat] = rid
        if not under or not progress:
            break
    return have, goal


def stock(world, merchants, hand_stocked):
    """{merchant: [(weapon id, count)]}: what the roll deals each merchant, a negative count
    restocking. hand_stocked is [(merchant, weapon id)], already stocked and counted against the cap."""
    table = pools(world, merchants)
    have, goal = deal(table, hand_stocked)
    out = collections.defaultdict(list)
    already = set(hand_stocked)
    for (mid, enchanted), got in sorted(have.items()):
        for mat, rid in sorted(got.items()):
            if (mid, rid) in already:
                continue
            out[mid].append((rid, -1 if mat in table[(mid, enchanted)]["restocks"] else 1))
    return dict(out), table, goal


def weapon_merchants(world, origins=None):
    """Every weapon merchant placed in the world - only those first defined in one of origins, if given."""
    return {mid for mid, rec in world.npcs.items()
            if rec["services"] & 1 and mid not in TEST_NPCS and world.placed.get(mid)
            and (origins is None or world.origin[mid] in origins)}


# --- Where it goes ---------------------------------------------------------------------------------

def shop_chest(world, mid):
    """The chest a merchant's stock goes in: one they own that holds weapons and is in the world once -
    the one with the most weapons - or None."""
    best = None
    for chest in sorted(world.owned.get(mid, ())):
        rec = world.containers.get(chest)
        if not rec or len(world.placed[chest]) != 1:
            continue
        weapons = sum(1 for _c, rid in rec["inventory"] if rid in world.weapons)
        if weapons and (best is None or weapons > best[0]):
            best = (weapons, chest)
    return best[1] if best else None


def hidden_chest_id(mid, taken):
    rid = HIDDEN_PREFIX + mid.replace(" ", "_")[:31 - len(HIDDEN_PREFIX)]
    n = 2
    while rid in taken:
        rid = rid[:29] + "%02d" % n
        n += 1
    taken.add(rid)
    return rid


def deliver(world, paths, by_merchant):
    """Turn {merchant: [(weapon id, count)]} into chests: {chest id: [(weapon id, count)]} for chests of
    their own, and [(merchant, chest id, cell key, position, items)] for hidden ones."""
    in_chests, hidden, taken = collections.defaultdict(list), [], set()
    outdoor = set()
    for mid in sorted(by_merchant):
        chest = shop_chest(world, mid)
        if chest:
            in_chests[chest] += by_merchant[mid]
            continue
        cell, pos = sorted(world.placed[mid], key=lambda p: (not isinstance(p[0], str), str(p[0])))[0]
        hidden.append([mid, hidden_chest_id(mid, taken), cell, pos, by_merchant[mid]])
        if not isinstance(cell, str):
            outdoor.add(cell)
    floors = terrain_floor(paths, outdoor) if outdoor else {}
    for entry in hidden:
        cell, pos = entry[2], entry[3]
        lowest = min(world.lowest_point(cell), floors.get(cell, float("inf")))
        entry[3] = (pos[0], pos[1], lowest - HIDDEN_DEPTH)
    return dict(in_chests), hidden


# --- Records ---------------------------------------------------------------------------------------

def hidden_container_record(rid, items):
    body = sub("NAME", zstr(rid)) + sub("MODL", zstr(HIDDEN_CHEST["model"])) \
        + sub("FNAM", zstr(HIDDEN_CHEST["name"])) + sub("CNDT", struct.pack("<f", HIDDEN_CHEST["capacity"])) \
        + sub("FLAG", struct.pack("<I", 8))
    return mp.container_record(0, body, items)


def cell_records(world, hidden):
    """A CELL record for each cell a hidden chest goes in: the cell's name and DATA as its master has
    them, then the chest, owned by its merchant. New references count up from 1, this file's own."""
    by_cell = collections.defaultdict(list)
    for mid, chest, cell, pos, _items in hidden:
        by_cell[cell].append((mid, chest, pos))
    out, refnum = [], 0
    for cell in sorted(by_cell, key=str):
        body = world.cells[cell]["header"]
        for mid, chest, pos in by_cell[cell]:
            refnum += 1
            body += sub("FRMR", struct.pack("<I", refnum)) + sub("NAME", zstr(chest)) \
                + sub("ANAM", zstr(mid)) + sub("DATA", struct.pack("<6f", *pos, 0.0, 0.0, 0.0))
        out.append(record("CELL", body))
    return out


def build(world, paths, by_merchant, extra_chests):
    """The records: chests of their own with ours added (extra_chests are hand-stocked, {chest id:
    [(weapon id, count)]}), the hidden chests and the cells they are in. Returns (records, [(chest id,
    items)] for the chests of their own, hidden)."""
    in_chests, hidden = deliver(world, paths, by_merchant)
    for chest, items in extra_chests.items():
        in_chests[chest] = list(items) + in_chests.get(chest, [])
    records = []
    for chest in sorted(in_chests):
        rec = world.containers[chest]
        records.append(mp.container_record(rec["flags"], rec["body"], in_chests[chest]))
    records += [hidden_container_record(chest, items) for _mid, chest, _c, _p, items in hidden]
    records += cell_records(world, hidden)
    return records, sorted(in_chests.items()), hidden

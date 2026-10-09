"""Fits the third-person rig's fingers to a first-person animation's hand. Used by
make_third_person_anims.py.

The two rigs have different hands. First person has five fingers of three joints. Third person has a
thumb (Finger0, Finger01), an index finger (Finger1, Finger11) and the other three as one (Finger2,
Finger21), two joints each, at their own lengths and rest angles - Finger1 rests 91 degrees from where
the first person's does. A first-person rotation copied onto a third-person bone bends a different
joint a different way, which twisted the thumbs.

Vanilla's first- and third-person hand meshes are one hand model rigged twice: the same shapes and
UVs, the palms in the same place on the hand bone. So this poses the first-person mesh with the
animation and solves the third-person finger rotations that put the same vertices where it has them.
It is ReAnimation's FBACompat/fba_fingers.py, which converts the other way, turned round; its vertex
map and fitting pieces are used as they are.
"""
import math

SIDES = ('L', 'R')
CHAINS = (('Finger0', 'Finger01'), ('Finger1', 'Finger11'), ('Finger2', 'Finger21'))
BONES = [b for chain in CHAINS for b in chain]
PARENT = {chain[1]: chain[0] for chain in CHAINS}
SUBTREE = {b: chain[i:] for chain in CHAINS for i, b in enumerate(chain)}
SKELETON = 'meshes\\xbase_anim.nif'
# Each pass fits every bone once, base joint first. Three, as fba_fingers does, left the answer
# depending on where it started - the attacks' last frames came out 7 degrees off the idle's first in
# the fingertips, the same first-person pose fitted twice - so it runs until nothing turns by more
# than this.
SETTLED_DEGREES = 0.01
MAX_PASSES = 80


class FingerFit:
    """The vertex map and the third-person skeleton's finger rest, ready to solve frames with."""

    def __init__(self, fba_fingers, kfeval, bsa):
        self.F, self.E = fba_fingers, kfeval
        self.map = fba_fingers.HandMap(fba_fingers.bsa_file(bsa, fba_fingers.MESH_1ST),
                                       fba_fingers.bsa_file(bsa, fba_fingers.MESH_3RD))
        rest = fba_fingers.skeleton_rest(fba_fingers.bsa_file(bsa, SKELETON))
        self.rest = {side: {b: rest['Bip01 %s %s' % (side, b)] for b in BONES} for side in SIDES}
        self.by_bone = {side: {b: [i for i, (_, w3) in enumerate(self.map.pairs[side])
                                   if sum(w for bone, w, _ in w3 if bone in SUBTREE[b]) >= fba_fingers.MIN_WEIGHT]
                               for b in BONES} for side in SIDES}
        self.previous = {}

    def offsets(self, side):
        return {b: self.rest[side][b][1] for b in BONES}

    def first_person_pose(self, kf, side, t):
        """Hand-space transforms of the first-person hand as the kf poses it at t."""
        F, E = self.F, self.E

        def local(short):
            d = kf.data('Bip01 %s %s' % (side, short))
            return E.rotation(d, t), E.translation(d, t)
        rots, offsets = {}, {}
        for b in F.FIT_BONES:
            rots[b], offsets[b] = local(b)
        forearm = F.inverse(local('Hand'))
        return F.first_person_transforms(rots, offsets, forearm), forearm

    def third_person_pose(self, rots, offsets, forearm):
        out = {'Hand': self.F.IDENTITY, 'Forearm': forearm}
        for chain in CHAINS:
            parent = self.F.IDENTITY
            for b in chain:
                parent = self.F.compose(parent, (rots[b], offsets[b]))
                out[b] = parent
        return out

    def solve(self, kf, side, t, key=None):
        """{third-person finger: rotation} for the kf's hand at t, and the mean distance (units) the
        fitted third-person vertices are from the first-person ones. key carries the last solve's
        rotations over as the next one's start; without one it starts from the rest."""
        F = self.F
        first, forearm = self.first_person_pose(kf, side, t)
        pairs = self.map.pairs[side]
        targets = [F.blend(first, w1) for w1, _ in pairs]
        offsets = self.offsets(side)
        rots = dict(self.previous.get(key) or {b: self.rest[side][b][0] for b in BONES})
        for _ in range(MAX_PASSES):
            before = dict(rots)
            for chain in CHAINS:
                for bone in chain:
                    pose = self.third_person_pose(rots, offsets, forearm)
                    parent = pose[PARENT[bone]] if bone in PARENT else F.IDENTITY
                    inv_parent = F.inverse(parent)
                    below = {bone: F.IDENTITY}
                    for c in SUBTREE[bone][1:]:
                        below[c] = F.compose(below[PARENT[c]], (rots[c], offsets[c]))
                    s = [[0.0] * 3 for _ in range(3)]
                    used = 0
                    for index in self.by_bone[side][bone]:
                        w3, target = pairs[index][1], targets[index]
                        # As fba_fingers.fit_frame: the vertex is known + wsub * parent(offset + R * src).
                        wsub, src, known = 0.0, [0.0, 0.0, 0.0], [0.0, 0.0, 0.0]
                        for b, w, gl in w3:
                            if b in below:
                                p = F.apply(below[b], gl)
                                src = [a + w * c for a, c in zip(src, p)]
                                wsub += w
                            else:
                                pk = F.apply(pose[b], gl)
                                known = [k + w * c for k, c in zip(known, pk)]
                        src = [c / wsub for c in src]
                        x = [(a - k) / wsub for a, k in zip(target, known)]
                        d = F.apply(inv_parent, x)
                        d = [c - o for c, o in zip(d, offsets[bone])]
                        omega = wsub * wsub
                        for i in range(3):
                            for j in range(3):
                                s[i][j] += omega * src[i] * d[j]
                        used += 1
                    if used >= 2:
                        q = F.horn(s)
                        if sum(a * b for a, b in zip(q, rots[bone])) < 0:
                            q = tuple(-c for c in q)
                        rots[bone] = q
            if max(self.E.qangle(before[b], rots[b]) for b in BONES) < SETTLED_DEGREES:
                break
        if key is not None:
            self.previous[key] = rots
        pose = self.third_person_pose(rots, offsets, forearm)
        error = sum(math.dist(F.blend(pose, w3), tg) for (_, w3), tg in zip(pairs, targets)) / len(pairs)
        return rots, error

    def copied_error(self, kf, side, t):
        """The same distance with the first-person rotations copied over, as the build used to."""
        F, E = self.F, self.E
        first, forearm = self.first_person_pose(kf, side, t)
        pairs = self.map.pairs[side]
        rots = {b: E.rotation(kf.data('Bip01 %s %s' % (side, b)), t) for b in BONES}
        pose = self.third_person_pose(rots, self.offsets(side), forearm)
        return sum(math.dist(F.blend(pose, w3), F.blend(first, w1)) for w1, w3 in pairs) / len(pairs)

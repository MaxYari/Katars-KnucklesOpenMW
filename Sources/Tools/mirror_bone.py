#!/usr/bin/env python3
"""How a right-hand bone transform becomes its left-hand counterpart, in one place.

Morrowind's rig does not give the two hands the same local frame, and it does not give them
reflected ones either. For any bone whose parent is itself half of a mirrored pair, the two sides
are related by a conjugation with a diagonal sign matrix:

    local_left = S . local_right . S

and for every vanilla actor skeleton S comes out as diag(1, 1, -1) - a flip of the bone's local Z.
Fitting it over the rig's own mirrored pairs (fit_signs below) beats the next best candidate by
5x on the posed first-person rig and 30x on the T-posed third-person one, so it is not a guess.

Getting this wrong is quiet rather than loud. Leaving S out entirely - treating the frames as
identical - puts the off-hand weapon about 2.8 units into the forearm on the first-person rig while
still letting the blade point more or less forwards, so a one-axis check does not catch it.

Used by patch_skeleton.py for the rest transform and by mirror_weapon_track.py for the keyframe
track. Both have to agree, which is why the rule lives here and not in either of them. Only the
track gets the half turn below: it is the katar's, not the bone's.
"""
import itertools

import numpy as np

# Bones whose parent is also half of a mirrored pair. Clavicles and the like are excluded: they hang
# off a bone on the midline, so the two sides are related by a reflection across the body rather
# than by a conjugation, and they would pull the fit around.
MIRRORED_BONES = [
    "UpperArm", "Forearm", "Hand",
    "Finger0", "Finger1", "Finger2", "Finger3", "Finger4",
    "Finger01", "Finger11", "Finger21", "Finger31", "Finger41",
    "Thigh", "Calf", "Foot", "Toe0",
]


# --- the half turn -------------------------------------------------------------------------------
# S . M . S is a similarity transform, so its determinant is det(M): the off-hand frame comes out a
# ROTATION of the main-hand one, never a reflection. The weapon is therefore rotated into place
# rather than mirrored, which leaves the face that should point away from the body pointing across
# it - the blade still aims forwards, but the weapon is on its wrong side.
#
# A true mirror is not available here: a NIF node carries one uniform float scale, and a negative
# one would invert triangle winding without OpenMW reversing the face culling to match. So the
# weapon gets a half turn about the axis it is long on instead, which puts the outward face back
# outwards. It also turns the weapon over, which is invisible on a weapon that is symmetric across
# that axis and is the trade this mod accepts.
#
# It is applied to the katar's animation tracks only (mirror_weapon_track.py), never to the bone's
# rest (patch_skeleton.py). The axis is the katar's: vanilla weapons are modelled blade up +Y, and
# this turn flips Y, so the same turn on the bone would hang any of them upside down. The plain
# conjugation flips Z instead, across which they are all symmetric.
SPIN_AXIS = 0  # X: the axis the blade runs along - see the extents of any katar .nif


def spin_matrix():
    """The half turn about SPIN_AXIS, as a 4x4."""
    signs = [-1.0, -1.0, -1.0]
    signs[SPIN_AXIS] = 1.0
    return np.diag(signs + [1.0])


def apply_spin(matrix):
    """Post-multiply, so the weapon spins in place and the bone's origin does not move."""
    return np.asarray(matrix, dtype=float) @ spin_matrix()


def spin_quaternion():
    """The same half turn as (w, x, y, z)."""
    q = np.zeros(4)
    q[1 + SPIN_AXIS] = 1.0
    return q


def quaternion_multiply(a, b):
    """Hamilton product of rows of (w, x, y, z) by a single quaternion."""
    a = np.atleast_2d(np.asarray(a, dtype=float))
    w1, x1, y1, z1 = a[:, 0], a[:, 1], a[:, 2], a[:, 3]
    w2, x2, y2, z2 = b
    return np.stack([
        w1 * w2 - x1 * x2 - y1 * y2 - z1 * z2,
        w1 * x2 + x1 * w2 + y1 * z2 - z1 * y2,
        w1 * y2 - x1 * z2 + y1 * w2 + z1 * x2,
        w1 * z2 + x1 * y2 - y1 * x2 + z1 * w2,
    ], axis=1)


def apply_spin_quaternion(quats):
    """The quaternion form of apply_spin: right-multiplication is post-multiplication."""
    return quaternion_multiply(quats, spin_quaternion())


def sign_matrix(signs):
    """A 4x4 diagonal sign matrix, for conjugating a local transform."""
    return np.diag(list(signs) + [1]).astype(float)


def fit_signs(local_matrices, prefix_left="Bip01 L ", prefix_right="Bip01 R "):
    """Work out which sign matrix this rig mirrors with, from the rig itself.

    Returns (signs, error, margin). `margin` is how much better the winner is than the runner-up -
    below about 2 the rig is not mirrored the way this assumes and the answer should not be trusted.
    """
    pairs = []
    for bone in MIRRORED_BONES:
        left, right = prefix_left + bone, prefix_right + bone
        if left in local_matrices and right in local_matrices:
            pairs.append((local_matrices[left], local_matrices[right]))
    if not pairs:
        raise ValueError("no mirrored bone pairs found; is this an actor skeleton?")

    scored = []
    for signs in itertools.product((1, -1), repeat=3):
        S = sign_matrix(signs)
        error = sum(np.abs(L - S @ R @ S).max() for L, R in pairs) / len(pairs)
        scored.append((error, signs))
    scored.sort()

    best_error, best_signs = scored[0]
    runner_up = scored[1][0]
    margin = runner_up / best_error if best_error > 1e-9 else float("inf")
    return best_signs, best_error, margin


def conjugate(matrix, signs):
    """local_left from local_right: S . M . S."""
    S = sign_matrix(signs)
    return S @ np.asarray(matrix, dtype=float) @ S


def conjugate_vectors(rows, signs):
    """Conjugate a block of row vectors - translations, or their tangents."""
    return np.asarray(rows, dtype=float) * np.asarray(signs, dtype=float)


def conjugate_quaternion(quats, signs):
    """Conjugate rotations stored as (w, x, y, z).

    Conjugating by a reflection maps the axis through S and negates the angle, so the vector part
    becomes -S.v; by a rotation it is just S.v. Both fall out of the determinant.
    """
    quats = np.asarray(quats, dtype=float)
    determinant = signs[0] * signs[1] * signs[2]
    out = quats.copy()
    out[:, 1:4] = quats[:, 1:4] * np.asarray(signs, dtype=float) * determinant
    return out


def self_test():
    """conjugate_quaternion has to agree with conjugating the matrix directly."""
    rng = np.random.default_rng(0)
    for signs in itertools.product((1, -1), repeat=3):
        for _ in range(8):
            q = rng.normal(size=4)
            q /= np.linalg.norm(q)
            w, x, y, z = q
            R = np.array([
                [1 - 2 * (y * y + z * z), 2 * (x * y - z * w), 2 * (x * z + y * w)],
                [2 * (x * y + z * w), 1 - 2 * (x * x + z * z), 2 * (y * z - x * w)],
                [2 * (x * z - y * w), 2 * (y * z + x * w), 1 - 2 * (x * x + y * y)],
            ])
            S3 = np.diag(signs).astype(float)
            expected = S3 @ R @ S3

            qc = conjugate_quaternion(q[None, :], signs)[0]
            w, x, y, z = qc
            got = np.array([
                [1 - 2 * (y * y + z * z), 2 * (x * y - z * w), 2 * (x * z + y * w)],
                [2 * (x * y + z * w), 1 - 2 * (x * x + z * z), 2 * (y * z - x * w)],
                [2 * (x * z - y * w), 2 * (y * z + x * w), 1 - 2 * (x * x + y * y)],
            ])
            assert np.allclose(got, expected, atol=1e-9), (signs, got, expected)

    # apply_spin_quaternion has to agree with apply_spin on the matrix.
    for _ in range(16):
        q = rng.normal(size=4)
        q /= np.linalg.norm(q)
        w, x, y, z = q
        R = np.eye(4)
        R[:3, :3] = [
            [1 - 2 * (y * y + z * z), 2 * (x * y - z * w), 2 * (x * z + y * w)],
            [2 * (x * y + z * w), 1 - 2 * (x * x + z * z), 2 * (y * z - x * w)],
            [2 * (x * z - y * w), 2 * (y * z + x * w), 1 - 2 * (x * x + y * y)],
        ]
        expected = apply_spin(R)[:3, :3]
        w, x, y, z = apply_spin_quaternion(q[None, :])[0]
        got = np.array([
            [1 - 2 * (y * y + z * z), 2 * (x * y - z * w), 2 * (x * z + y * w)],
            [2 * (x * y + z * w), 1 - 2 * (x * x + z * z), 2 * (y * z - x * w)],
            [2 * (x * z - y * w), 2 * (y * z + x * w), 1 - 2 * (x * x + y * y)],
        ])
        assert np.allclose(got, expected, atol=1e-9), (got, expected)

    # a half turn twice is the identity
    assert np.allclose(apply_spin(apply_spin(np.eye(4))), np.eye(4), atol=1e-12)
    return True


if __name__ == "__main__":
    self_test()
    print("mirror_bone: quaternion conjugation agrees with matrix conjugation for all 8 sign matrices")

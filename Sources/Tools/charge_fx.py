#!/usr/bin/env python3
"""Makes the mage knuckle's crystal translucent, and builds the charged-state effect that goes in it.

Two jobs, because they are two halves of one look:

1. `--alpha` adds a NiAlphaProperty to a shape in a weapon mesh. Morrowind will not blend a shape
   without one, whatever the material alpha or the texture's alpha channel say - the crystal as
   exported has only NiMaterialProperty and NiTexturingProperty, so it renders solid. The flags are
   0x00ed, which is what every vanilla translucent shape and particle system uses.

2. `--effect` writes a standalone particle .nif meant to be hung on "Weapon Bone" / "Weapon Bone.L"
   with animation.addVfx. It is authored in the weapon's own local space - grip at the origin, the
   same frame the weapon meshes are exported in - so it lands inside the crystal with no offsets to
   work out at runtime.

   The particle node carries ParticleFlag_LocalSpace (0x80) as well as ParticleFlag_AutoPlay (0x20).
   Local space matters: NifOsg::handleParticleSystem wraps a world-space system in a MatrixTransform
   with an InverseWorldMatrix callback, which fights the first-person projection and is the usual
   reason hand-attached particles look detached or wrongly ordered. Local-space particles stay in
   the emitter's frame and inherit the first-person render bin like any other geometry.

    python3 charge_fx.py --alpha meshes/mage_knuckle.nif --shape Crystal
    python3 charge_fx.py --effect meshes/mage_knuckle_charged.nif --centre 3.88,0,0 --extent 0.7,2.2,0.7
"""
import argparse
import os
import sys

import numpy as np

# NiAlphaProperty flags: bit 0 enables blending, (flags >> 1) & 0xF is the source factor and
# (flags >> 5) & 0xF the destination (components/nif/property.hpp:460).
#   0x00ED = SRC_ALPHA over ONE_MINUS_SRC_ALPHA - ordinary translucency, what vanilla uses.
#   0x000D = SRC_ALPHA over ONE           - additive, so the glow adds light instead of covering.
ALPHA_FLAGS = 0x00ED
ALPHA_FLAGS_ADDITIVE = 0x000D

# Nif::NiNode::BSParticleFlags, components/nif/node.hpp
PARTICLE_AUTOPLAY = 0x0020
PARTICLE_LOCALSPACE = 0x0080


def find_lib():
    for root in (
        os.environ.get("IO_SCENE_MW", ""),
        os.path.expanduser("~/.config/blender"),
        os.path.expanduser("~/Library/Application Support/Blender"),
        os.path.expanduser("~/AppData/Roaming/Blender Foundation/Blender"),
    ):
        if not root:
            continue
        if os.path.isdir(os.path.join(root, "es3")):
            return root
        for dirpath, dirnames, _ in os.walk(root):
            if os.path.basename(dirpath) == "lib" and "es3" in dirnames:
                return dirpath
    return None


lib = find_lib()
if lib and lib not in sys.path:
    sys.path.append(lib)
try:
    from es3.nif import (NiAlphaProperty, NiAutoNormalParticles, NiAutoNormalParticlesData,
                         NiBSParticleNode, NiColorData, NiMaterialProperty, NiNode,
                         NiParticleColorModifier, NiParticleGrowFade, NiParticleSystemController,
                         NiSourceTexture, NiStream, NiTexturingProperty, NiTexturingPropertyMap,
                         NiZBufferProperty)
except ImportError as exc:
    sys.exit("Could not find the es3 library (%s). Install Greatness7's io_scene_mw Blender add-on, "
             "or point IO_SCENE_MW at its 'lib' folder." % exc)


def walk(node):
    yield node
    for child in getattr(node, "children", None) or []:
        if child is not None:
            yield from walk(child)


def add_alpha(path, shape_name):
    stream = NiStream()
    stream.load(path)

    for node in walk(stream.roots[0]):
        if getattr(node, "name", "") != shape_name:
            continue
        props = list(node.properties or [])
        if any(isinstance(p, NiAlphaProperty) for p in props):
            return "%s already has a NiAlphaProperty" % shape_name
        alpha = NiAlphaProperty()
        alpha.flags = ALPHA_FLAGS
        node.properties = props + [alpha]
        stream.save(path)
        return "added NiAlphaProperty(0x%04x) to %r - it will blend now" % (ALPHA_FLAGS, shape_name)
    return "no shape called %r in this file" % shape_name


def make_particle_system(name, centre, extent, texture, size, birth_rate, lifespan, colour,
                         speed, additive):
    """One local-space particle system, confined to a box around `centre`."""
    emitter = NiNode()
    emitter.name = name + " Emitter"
    emitter.translation = np.array(centre, dtype=float)

    node = NiBSParticleNode()
    node.name = name
    # Local space keeps them inside the crystal as the hand moves; autoplay starts them with
    # nothing to trigger them.
    node.flags = PARTICLE_AUTOPLAY | PARTICLE_LOCALSPACE
    node.translation = np.array(centre, dtype=float)
    node.properties = [NiZBufferProperty()]

    particles = NiAutoNormalParticles()
    particles.name = name + " Particles"

    # NifOsg takes the quota from num_particles when the controller ships no preallocated array
    # (handleParticleInitialState); leave it at zero and the system is valid but emits nothing.
    quota = max(2, int(np.ceil(birth_rate * lifespan * 1.5)) + 2)
    data = NiAutoNormalParticlesData()
    data.num_particles = quota
    data.num_active = 0
    data.particle_radius = float(max(extent)) + size
    data.radius = float(np.linalg.norm(extent)) + size
    data.vertices = np.zeros((quota, 3), dtype=np.float32)
    data.sizes = np.full(quota, size, dtype=np.float32)
    particles.data = data

    source = NiSourceTexture()
    source.filename = texture
    base_map = NiTexturingPropertyMap()
    base_map.source = source
    texturing = NiTexturingProperty()
    texturing.base_texture = base_map

    material = NiMaterialProperty()
    material.ambient_color = np.array(colour, dtype=float)
    material.diffuse_color = np.array(colour, dtype=float)
    material.emissive_color = np.array(colour, dtype=float)  # self-lit, like every vanilla sparkle
    material.alpha = 1.0

    alpha = NiAlphaProperty()
    alpha.flags = ALPHA_FLAGS_ADDITIVE if additive else ALPHA_FLAGS
    particles.properties = [texturing, alpha, material]

    controller = NiParticleSystemController()
    controller.flags = 8
    controller.frequency = 1.0
    controller.start_time = 0.0
    controller.stop_time = 1e6          # runs until the effect is removed
    controller.emit_start_time = 0.0
    controller.emit_stop_time = 1e6
    controller.target = particles
    controller.emitter = emitter
    controller.speed = speed
    controller.speed_variation = speed
    # Emitted in every direction, so the drift is a shimmer rather than a plume.
    controller.declination_angle = 0.0
    controller.declination_variation = np.pi
    controller.planar_angle = 0.0
    controller.planar_angle_variation = np.pi
    controller.initial_normal = np.array([0.0, 0.0, 1.0])
    controller.initial_color = np.array(list(colour) + [1.0], dtype=float)
    controller.initial_size = size
    controller.birth_rate = birth_rate
    controller.use_birth_rate = 1
    controller.lifespan = lifespan
    controller.lifespan_variation = lifespan * 0.5
    controller.spawn_percentage = 1.0
    controller.num_active_particles = 0
    # Born throughout the box rather than at a point.
    controller.emitter_width = extent[0] * 2
    controller.emitter_height = extent[1] * 2
    controller.emitter_depth = extent[2] * 2

    grow_fade = NiParticleGrowFade()
    grow_fade.grow_time = lifespan * 0.35
    grow_fade.fade_time = lifespan * 0.45

    colour_data = NiColorData()
    colour_data.keys = np.array([
        [0.0, colour[0], colour[1], colour[2], 0.0],
        [lifespan * 0.5, colour[0], colour[1], colour[2], 1.0],
        [lifespan, colour[0], colour[1], colour[2], 0.0],
    ], dtype=float)
    colour_modifier = NiParticleColorModifier()
    colour_modifier.color_data = colour_data
    # NiParticleModifier chains through .next, and each points back at its controller.
    colour_modifier.next = grow_fade
    colour_modifier.controller = controller
    grow_fade.controller = controller

    controller.particle_modifier = colour_modifier
    particles.controller = controller
    node.children = [particles]
    return emitter, node, quota


def build_effect(path, centre, extent, texture, size, birth_rate, lifespan, colour,
                 glow_texture, glow_size):
    """A shimmer confined inside the crystal, plus a soft glow standing in for a light.

    OpenMW's NIF loader has no light records at all - no NiPointLight, NiLight, NiSpotLight or
    NiAmbientLight anywhere in its dispatch (components/nifosg/nifloader.cpp) - so a mesh cannot
    carry a light. The glow is a second particle system instead: a couple of big, stationary,
    additive sprites that breathe as they fade in and out. Particles are always camera-facing, so
    it reads as a light inside the stone from any angle, and it needs no machinery this file has
    not already validated.
    """
    root = NiNode()
    root.name = os.path.basename(path)

    # Drift has to stay inside the stone, so the emitter box is inset by as far as a particle can
    # travel in its lifetime.
    drift = speed_drift = 0.0
    sparkle_speed = 0.12
    drift = sparkle_speed * lifespan
    inset = tuple(max(0.05, e - drift) for e in extent)

    sparkle_emitter, sparkle_node, sparkle_quota = make_particle_system(
        "Charge", centre, inset, texture, size, birth_rate, lifespan, colour,
        sparkle_speed, additive=False)

    # The glow sits still at the centre; a long life and a low birth rate keep one or two alive.
    glow_emitter, glow_node, _ = make_particle_system(
        "Charge Glow", centre, (0.05, 0.05, 0.05), glow_texture, glow_size, 0.8, 2.5, colour,
        0.0, additive=True)

    root.children = [sparkle_emitter, sparkle_node, glow_emitter, glow_node]

    stream = NiStream()
    stream.roots = [root]
    os.makedirs(os.path.dirname(path) or ".", exist_ok=True)
    stream.save(path)
    return ("wrote %s\n   sparkle: size %.2f, %.1f/s, %.1fs life, drift %.2f, box %s\n"
            "   glow:    size %.2f, additive, breathing\n   both local-space, centred %s"
            % (os.path.basename(path), size, birth_rate, lifespan, drift,
               np.round(np.array(inset) * 2, 2).tolist(), glow_size, np.round(centre, 2).tolist()))


def triple(text):
    return tuple(float(v) for v in text.split(","))


def main():
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--alpha", help="weapon mesh to add a NiAlphaProperty to")
    ap.add_argument("--shape", default="Crystal", help="which shape in it")
    ap.add_argument("--effect", help="path of the particle .nif to write")
    ap.add_argument("--centre", type=triple, default=(3.88, 0.0, 0.0),
                    help="centre of the crystal, in the weapon's local space")
    ap.add_argument("--extent", type=triple, default=(0.7, 2.2, 0.7),
                    help="half-extents of the emitter box")
    ap.add_argument("--texture", default="vfx_myst_flare01.dds")
    ap.add_argument("--size", type=float, default=0.45)
    ap.add_argument("--birth-rate", type=float, default=11.0)
    ap.add_argument("--lifespan", type=float, default=1.2)
    ap.add_argument("--glow-texture", default="vfx_myst_glow.dds")
    ap.add_argument("--glow-size", type=float, default=2.6)
    ap.add_argument("--colour", type=triple, default=(0.45, 0.70, 1.0))
    args = ap.parse_args()

    if args.alpha:
        print(add_alpha(args.alpha, args.shape))
    if args.effect:
        print(build_effect(args.effect, args.centre, args.extent, args.texture,
                           args.size, args.birth_rate, args.lifespan, args.colour,
                           args.glow_texture, args.glow_size))
    if not args.alpha and not args.effect:
        ap.error("give --alpha, --effect, or both")


if __name__ == "__main__":
    main()

"""Adds an ARP custom controller 'Weapon Bone.L' to the `rig` armature, mirroring 'Weapon Bone',
and binds the vanilla 'Bip01' armature's existing 'Weapon Bone.L' to it the same way the other
bones are bound (Copy Transforms + Copy Scale)."""
import bpy
from mathutils import Matrix, Vector

SRC = 'Weapon Bone'      # the right-hand controller to copy from
NEW = 'Weapon Bone.L'    # the new controller
PARENT = 'hand.l'        # its ARP parent (mirror of hand.r)

rig = bpy.data.objects['rig']
bip = bpy.data.objects['Bip01']

assert NEW in bip.data.bones, "Bip01 has no %r bone" % NEW

# The deform rig's bones copy their controller's WORLD transform, so a controller's rest matrix has
# to match the deform bone's rest matrix exactly - that is how 'Weapon Bone' and 'Shield Bone' are
# set up (verified: identical world rest matrices).
bip_bone = bip.data.bones[NEW]
target_world = bip.matrix_world @ bip_bone.matrix_local
target_len = bip_bone.length
local = rig.matrix_world.inverted() @ target_world
local_head = local.to_translation()
local_dir = local.col[1].to_3d().normalized()    # a bone points along its own +Y
local_up = local.col[2].to_3d().normalized()     # ... and align_roll takes its +Z

# --- custom shape: ARP keeps one mesh object per controller, named cs_user_<bone> -----------------
src_pb = rig.pose.bones[SRC]
cs_name = 'cs_user_' + NEW
cs = bpy.data.objects.get(cs_name)
if cs is None and src_pb.custom_shape is not None:
    cs = src_pb.custom_shape.copy()
    cs.data = src_pb.custom_shape.data          # shared mesh, like ARP's own duplicates
    cs.name = cs_name
    for coll in src_pb.custom_shape.users_collection:
        coll.objects.link(cs)
    cs.parent = src_pb.custom_shape.parent
    cs.matrix_parent_inverse = src_pb.custom_shape.matrix_parent_inverse.copy()
    cs.hide_viewport = src_pb.custom_shape.hide_viewport
    cs.hide_render = src_pb.custom_shape.hide_render
    print("created custom shape", cs_name)

# --- the edit bone --------------------------------------------------------------------------------
bpy.context.view_layer.objects.active = rig
bpy.ops.object.mode_set(mode='EDIT')
arm = rig.data
mirror = arm.use_mirror_x
arm.use_mirror_x = False
try:
    eb = arm.edit_bones.get(NEW) or arm.edit_bones.new(NEW)
    src_eb = arm.edit_bones[SRC]
    eb.use_connect = False
    eb.parent = arm.edit_bones[PARENT]
    eb.head = local_head
    eb.tail = local_head + local_dir * target_len
    eb.align_roll(local_up)
    eb.use_deform = src_eb.use_deform
    eb.inherit_scale = src_eb.inherit_scale
    eb.use_inherit_rotation = src_eb.use_inherit_rotation
    eb.use_local_location = src_eb.use_local_location
    eb.envelope_distance = src_eb.envelope_distance
    eb.head_radius = src_eb.head_radius
    eb.tail_radius = src_eb.tail_radius
    eb['cc'] = 1                                  # ARP: marks a user-added custom controller
finally:
    arm.use_mirror_x = mirror
bpy.ops.object.mode_set(mode='OBJECT')

# Bone collections and colour, copied from the source controller.
src_b = arm.bones[SRC]
new_b = arm.bones[NEW]
for coll in src_b.collections:
    if new_b.name not in coll.bones:
        coll.assign(new_b)
new_b['cc'] = 1
new_b.color.palette = src_b.color.palette
if src_b.color.palette == 'CUSTOM':
    new_b.color.custom.normal = src_b.color.custom.normal
    new_b.color.custom.select = src_b.color.custom.select
    new_b.color.custom.active = src_b.color.custom.active

new_pb = rig.pose.bones[NEW]
new_pb['cc'] = 1
new_pb.rotation_mode = src_pb.rotation_mode
new_pb.custom_shape = cs
new_pb.custom_shape_scale_xyz = src_pb.custom_shape_scale_xyz
new_pb.custom_shape_translation = src_pb.custom_shape_translation
new_pb.custom_shape_rotation_euler = src_pb.custom_shape_rotation_euler
new_pb.custom_shape_wire_width = src_pb.custom_shape_wire_width
new_pb.use_custom_shape_bone_size = src_pb.use_custom_shape_bone_size

# --- bind the deform bone to it --------------------------------------------------------------------
bip_pb = bip.pose.bones[NEW]
src_bip_pb = bip.pose.bones[SRC]
for c in list(bip_pb.constraints):
    bip_pb.constraints.remove(c)
for src_c in src_bip_pb.constraints:
    c = bip_pb.constraints.new(src_c.type)
    c.name = src_c.name
    c.target = rig
    c.subtarget = NEW
    c.influence = src_c.influence
    c.mute = src_c.mute
    for attr in ('target_space', 'owner_space', 'mix_mode', 'head_tail', 'remove_target_shear',
                 'power', 'use_make_uniform', 'use_offset', 'use_add'):
        if hasattr(src_c, attr) and hasattr(c, attr):
            try:
                setattr(c, attr, getattr(src_c, attr))
            except Exception:
                pass
print("constraints on Bip01 %r: %s" % (NEW, [(c.type, c.name, c.subtarget) for c in bip_pb.constraints]))

# --- verify ------------------------------------------------------------------------------------------
got = rig.matrix_world @ arm.bones[NEW].matrix_local
for r in range(4):
    for c in range(4):
        assert abs(got[r][c] - target_world[r][c]) < 1e-4, ("rest matrix mismatch", r, c, got[r][c], target_world[r][c])
print("OK: rig %r rest matrix matches Bip01 %r" % (NEW, NEW))
print("   collections:", [c.name for c in new_b.collections], "cc:", new_b.get('cc'), "deform:", new_b.use_deform)

bpy.ops.wm.save_mainfile()
print("saved", bpy.data.filepath)

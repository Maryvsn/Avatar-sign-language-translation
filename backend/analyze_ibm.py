"""Analyze IBM correctness and local axes for arm bones in avatar_tpose.vrm"""
import struct, math
import numpy as np
from pygltflib import GLTF2

vrm_path = r'C:\grad_project\front-end\assets\avatar\avatar_tpose.vrm'
gltf = GLTF2().load_binary(vrm_path)

skin = gltf.skins[0]
accessor = gltf.accessors[skin.inverseBindMatrices]
bv = gltf.bufferViews[accessor.bufferView]
blob = gltf.binary_blob()
offset = bv.byteOffset + (accessor.byteOffset or 0)

arm_nodes = {
    45: 'L_Shoulder', 46: 'L_UpperArm', 47: 'L_LowerArm', 48: 'L_Hand',
    64: 'R_Shoulder', 65: 'R_UpperArm', 66: 'R_LowerArm', 67: 'R_Hand'
}

def quat_to_mat4(q):
    x, y, z, w = q
    return np.array([
        [1-2*(y*y+z*z), 2*(x*y-z*w),   2*(x*z+y*w),   0],
        [2*(x*y+z*w),   1-2*(x*x+z*z), 2*(y*z-x*w),   0],
        [2*(x*z-y*w),   2*(y*z+x*w),   1-2*(x*x+y*y), 0],
        [0,             0,             0,              1],
    ], dtype=np.float32)

def mat4_translate(t):
    m = np.eye(4, dtype=np.float32)
    m[0,3] = t[0]; m[1,3] = t[1]; m[2,3] = t[2]
    return m

parent_map = {}
for i, n in enumerate(gltf.nodes):
    if n.children:
        for c in n.children:
            parent_map[c] = i

def get_world_transform(node_idx):
    chain = []
    idx = node_idx
    while idx is not None:
        chain.append(idx)
        idx = parent_map.get(idx, None)
    chain.reverse()
    world = np.eye(4, dtype=np.float32)
    for nid in chain:
        node = gltf.nodes[nid]
        local = np.eye(4, dtype=np.float32)
        if node.rotation:
            local = quat_to_mat4(node.rotation)
        if node.translation:
            t = mat4_translate(node.translation)
            local = t @ local
        world = world @ local
    return world

# -------------------------------------------------------
# 1) Check IBM correctness
# -------------------------------------------------------
print("=" * 60)
print("  IBM CORRECTNESS CHECK")
print("=" * 60)
for node_idx in sorted(arm_nodes.keys()):
    name = arm_nodes[node_idx]
    world = get_world_transform(node_idx)
    expected_ibm = np.linalg.inv(world)
    
    ji = list(skin.joints).index(node_idx)
    mat_bytes = blob[offset + ji*64 : offset + (ji+1)*64]
    mat = struct.unpack('<16f', mat_bytes)
    stored_ibm = np.array(mat, dtype=np.float32).reshape(4, 4).T
    
    diff = np.abs(expected_ibm - stored_ibm).max()
    status = "OK" if diff < 0.001 else "MISMATCH!"
    print(f"  {name} (Node {node_idx}): max diff = {diff:.6f} [{status}]")

# -------------------------------------------------------
# 2) Show local axes in world space
# -------------------------------------------------------
print()
print("=" * 60)
print("  LOCAL AXES IN WORLD SPACE (from world transform)")
print("  For correct T-Pose:")
print("    L arm: local X -> model +X (towards hand)")
print("    R arm: local X -> model -X (towards hand)")
print("    local Z -> model +Z (forward, palm down)")
print("=" * 60)

for node_idx in sorted(arm_nodes.keys()):
    name = arm_nodes[node_idx]
    world = get_world_transform(node_idx)
    rot3 = world[:3, :3]
    local_x = rot3[:, 0]
    local_y = rot3[:, 1]
    local_z = rot3[:, 2]
    pos = world[:3, 3]
    
    print(f"\n  {name} (Node {node_idx}):")
    print(f"    World pos:  [{pos[0]:.4f}, {pos[1]:.4f}, {pos[2]:.4f}]")
    print(f"    Local X ->  [{local_x[0]:.4f}, {local_x[1]:.4f}, {local_x[2]:.4f}]")
    print(f"    Local Y ->  [{local_y[0]:.4f}, {local_y[1]:.4f}, {local_y[2]:.4f}]")
    print(f"    Local Z ->  [{local_z[0]:.4f}, {local_z[1]:.4f}, {local_z[2]:.4f}]")

# -------------------------------------------------------
# 3) Check bone-to-child direction vs local axes
# -------------------------------------------------------
print()
print("=" * 60)
print("  BONE DIRECTION (bone head -> child head) vs LOCAL AXES")
print("  This shows what axis the bone 'points along'")
print("=" * 60)

chain_pairs = [
    (45, 46, 'L_Shoulder -> L_UpperArm'),
    (46, 47, 'L_UpperArm -> L_LowerArm'),
    (47, 48, 'L_LowerArm -> L_Hand'),
    (64, 65, 'R_Shoulder -> R_UpperArm'),
    (65, 66, 'R_UpperArm -> R_LowerArm'),
    (66, 67, 'R_LowerArm -> R_Hand'),
]

for parent_idx, child_idx, label in chain_pairs:
    parent_world = get_world_transform(parent_idx)
    child_world = get_world_transform(child_idx)
    
    parent_pos = parent_world[:3, 3]
    child_pos = child_world[:3, 3]
    
    bone_dir = child_pos - parent_pos
    bone_len = np.linalg.norm(bone_dir)
    if bone_len > 1e-6:
        bone_dir_norm = bone_dir / bone_len
    else:
        bone_dir_norm = bone_dir
    
    # What is this direction in the parent's local space?
    parent_rot3 = parent_world[:3, :3]
    bone_dir_local = parent_rot3.T @ bone_dir_norm  # world -> local
    
    print(f"\n  {label}:")
    print(f"    World direction: [{bone_dir_norm[0]:.4f}, {bone_dir_norm[1]:.4f}, {bone_dir_norm[2]:.4f}]")
    print(f"    Local direction: [{bone_dir_local[0]:.4f}, {bone_dir_local[1]:.4f}, {bone_dir_local[2]:.4f}]")
    print(f"    Bone length:     {bone_len:.6f}")

# -------------------------------------------------------
# 4) Check original avatar.vrm for comparison
# -------------------------------------------------------
print()
print("=" * 60)
print("  ORIGINAL avatar.vrm LOCAL AXES (for comparison)")
print("=" * 60)

gltf_orig = GLTF2().load_binary(r'C:\grad_project\front-end\assets\avatar\avatar.vrm')
parent_map_orig = {}
for i, n in enumerate(gltf_orig.nodes):
    if n.children:
        for c in n.children:
            parent_map_orig[c] = i

def get_world_transform_orig(node_idx):
    chain = []
    idx = node_idx
    while idx is not None:
        chain.append(idx)
        idx = parent_map_orig.get(idx, None)
    chain.reverse()
    world = np.eye(4, dtype=np.float32)
    for nid in chain:
        node = gltf_orig.nodes[nid]
        local = np.eye(4, dtype=np.float32)
        if node.rotation:
            local = quat_to_mat4(node.rotation)
        if node.translation:
            t = mat4_translate(node.translation)
            local = t @ local
        world = world @ local
    return world

for node_idx in sorted(arm_nodes.keys()):
    name = arm_nodes[node_idx]
    world = get_world_transform_orig(node_idx)
    rot3 = world[:3, :3]
    local_x = rot3[:, 0]
    local_y = rot3[:, 1]
    local_z = rot3[:, 2]
    pos = world[:3, 3]
    
    print(f"\n  {name} (Node {node_idx}):")
    print(f"    World pos:  [{pos[0]:.4f}, {pos[1]:.4f}, {pos[2]:.4f}]")
    print(f"    Local X ->  [{local_x[0]:.4f}, {local_x[1]:.4f}, {local_x[2]:.4f}]")
    print(f"    Local Y ->  [{local_y[0]:.4f}, {local_y[1]:.4f}, {local_y[2]:.4f}]")
    print(f"    Local Z ->  [{local_z[0]:.4f}, {local_z[1]:.4f}, {local_z[2]:.4f}]")

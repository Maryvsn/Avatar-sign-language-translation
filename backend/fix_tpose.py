"""
Convert VRM avatar from A-Pose to T-Pose.

The avatar currently has shoulder+upper arm rotations that tilt the arms
downward (~16° from horizontal per side). This script:
1. Zeros out the Z-rotation on Shoulder and UpperArm bones (makes arms horizontal)
2. Keeps other rotation axes intact (forward tilt etc.)
3. Updates the inverse bind matrices in the skin so the mesh follows correctly
4. Saves a new VRM file with perfect T-Pose rest position
"""

import struct, copy, math, shutil
import numpy as np
from pygltflib import GLTF2

SRC = r'C:\grad_project\front-end\assets\avatar\avatar.vrm'
DST = r'C:\grad_project\front-end\assets\avatar\avatar_tpose.vrm'

print('[T-Pose Fix] Loading VRM...')
gltf = GLTF2().load_binary(SRC)

# ═══════════════════════════════════════════════════════════
#  Quaternion helpers
# ═══════════════════════════════════════════════════════════
def quat_from_euler_xyz(x, y, z):
    """Create quaternion from Euler angles (radians) in XYZ order."""
    cx, sx = math.cos(x/2), math.sin(x/2)
    cy, sy = math.cos(y/2), math.sin(y/2)
    cz, sz = math.cos(z/2), math.sin(z/2)
    return [
        sx*cy*cz + cx*sy*sz,  # qx
        cx*sy*cz - sx*cy*sz,  # qy
        cx*cy*sz + sx*sy*cz,  # qz
        cx*cy*cz - sx*sy*sz,  # qw
    ]

def quat_to_euler_xyz(q):
    """Convert quaternion [x,y,z,w] to Euler angles (radians) XYZ order."""
    qx, qy, qz, qw = q
    # Roll (X)
    sinr_cosp = 2*(qw*qx + qy*qz)
    cosr_cosp = 1 - 2*(qx*qx + qy*qy)
    x = math.atan2(sinr_cosp, cosr_cosp)
    # Pitch (Y)
    sinp = 2*(qw*qy - qz*qx)
    if abs(sinp) >= 1:
        y = math.copysign(math.pi/2, sinp)
    else:
        y = math.asin(sinp)
    # Yaw (Z)
    siny_cosp = 2*(qw*qz + qx*qy)
    cosy_cosp = 1 - 2*(qy*qy + qz*qz)
    z = math.atan2(siny_cosp, cosy_cosp)
    return x, y, z

def quat_multiply(a, b):
    """Multiply two quaternions [x,y,z,w]."""
    ax, ay, az, aw = a
    bx, by, bz, bw = b
    return [
        aw*bx + ax*bw + ay*bz - az*by,
        aw*by - ax*bz + ay*bw + az*bx,
        aw*bz + ax*by - ay*bx + az*bw,
        aw*bw - ax*bx - ay*by - az*bz,
    ]

def quat_inverse(q):
    """Inverse of a unit quaternion."""
    return [-q[0], -q[1], -q[2], q[3]]

def quat_to_mat4(q):
    """Quaternion [x,y,z,w] to 4x4 rotation matrix."""
    x, y, z, w = q
    return np.array([
        [1-2*(y*y+z*z), 2*(x*y-z*w),   2*(x*z+y*w),   0],
        [2*(x*y+z*w),   1-2*(x*x+z*z), 2*(y*z-x*w),   0],
        [2*(x*z-y*w),   2*(y*z+x*w),   1-2*(x*x+y*y), 0],
        [0,             0,             0,              1],
    ], dtype=np.float32)

def mat4_translate(t):
    """Translation matrix."""
    m = np.eye(4, dtype=np.float32)
    m[0,3] = t[0]; m[1,3] = t[1]; m[2,3] = t[2]
    return m

# ═══════════════════════════════════════════════════════════
#  Step 1: Identify the bones to fix
# ═══════════════════════════════════════════════════════════
bones_to_fix = {
    45: 'J_Bip_L_Shoulder',
    46: 'J_Bip_L_UpperArm',
    64: 'J_Bip_R_Shoulder',
    65: 'J_Bip_R_UpperArm',
}

print('\n[T-Pose Fix] Current rotations:')
for nid, name in bones_to_fix.items():
    node = gltf.nodes[nid]
    q = list(node.rotation) if node.rotation else [0,0,0,1]
    ex, ey, ez = quat_to_euler_xyz(q)
    print(f'  {name} (Node {nid}):')
    print(f'    Euler XYZ: ({math.degrees(ex):.2f}°, {math.degrees(ey):.2f}°, {math.degrees(ez):.2f}°)')

# ═══════════════════════════════════════════════════════════
#  Step 2: Zero out the Z rotation (keep X,Y for natural shoulder tilt)
# ═══════════════════════════════════════════════════════════
print('\n[T-Pose Fix] Fixing rotations (zeroing Z-axis)...')

# Store the OLD quaternions before modifying
old_quats = {}
for nid in bones_to_fix:
    node = gltf.nodes[nid]
    old_quats[nid] = list(node.rotation) if node.rotation else [0,0,0,1]

# Apply fix: zero Z rotation
for nid, name in bones_to_fix.items():
    node = gltf.nodes[nid]
    q = list(node.rotation) if node.rotation else [0,0,0,1]
    ex, ey, ez = quat_to_euler_xyz(q)
    
    # Zero out the Z rotation (this is what tilts arms down in A-Pose)
    new_q = quat_from_euler_xyz(ex, ey, 0.0)
    node.rotation = new_q
    
    new_ex, new_ey, new_ez = quat_to_euler_xyz(new_q)
    print(f'  {name}: Z {math.degrees(ez):.2f} -> 0.00')

# ═══════════════════════════════════════════════════════════
#  Step 3: Recompute inverse bind matrices
# ═══════════════════════════════════════════════════════════
print('\n[T-Pose Fix] Recomputing inverse bind matrices...')

# Build the full node tree to compute world transforms
def compute_world_transform(node_idx, gltf):
    """Compute the world transform of a node by walking up the parent chain."""
    # Build parent map
    parent_map = {}
    for i, n in enumerate(gltf.nodes):
        if n.children:
            for c in n.children:
                parent_map[c] = i
    
    # Collect chain from root to this node
    chain = []
    idx = node_idx
    while idx is not None:
        chain.append(idx)
        idx = parent_map.get(idx, None)
    chain.reverse()
    
    # Multiply transforms
    world = np.eye(4, dtype=np.float32)
    for nid in chain:
        node = gltf.nodes[nid]
        local = np.eye(4, dtype=np.float32)
        
        # Rotation
        if node.rotation:
            local = local @ quat_to_mat4(node.rotation)
        
        # Translation
        if node.translation:
            t = mat4_translate(node.translation)
            local = t @ local
        
        world = world @ local
    
    return world

# Update inverse bind matrices for all skins
for skin_idx, skin in enumerate(gltf.skins):
    if skin.inverseBindMatrices is None:
        continue
    
    accessor = gltf.accessors[skin.inverseBindMatrices]
    buffer_view = gltf.bufferViews[accessor.bufferView]
    
    # Read current inverse bind matrices from binary blob
    blob = gltf.binary_blob()
    offset = buffer_view.byteOffset + (accessor.byteOffset or 0)
    count = accessor.count
    mat_data = blob[offset:offset + count * 64]  # 4x4 float32 = 64 bytes
    
    matrices = []
    for i in range(count):
        mat = struct.unpack('<16f', mat_data[i*64:(i+1)*64])
        matrices.append(np.array(mat, dtype=np.float32).reshape(4, 4).T)  # column-major to row-major
    
    # Recompute for joints that changed
    updated_count = 0
    for j_idx, joint_node in enumerate(skin.joints):
        if joint_node in bones_to_fix or True:  # Recompute ALL (safer)
            world = compute_world_transform(joint_node, gltf)
            matrices[j_idx] = np.linalg.inv(world).astype(np.float32)
            updated_count += 1
    
    # Write back
    new_mat_data = bytearray()
    for mat in matrices:
        new_mat_data.extend(struct.pack('<16f', *mat.T.flatten()))  # row-major to column-major
    
    # Replace in binary blob
    new_blob = bytearray(blob)
    new_blob[offset:offset + count * 64] = new_mat_data
    gltf.set_binary_blob(bytes(new_blob))
    
    print(f'  Skin {skin_idx}: Updated {updated_count}/{count} inverse bind matrices')

# ═══════════════════════════════════════════════════════════
#  Step 4: Save
# ═══════════════════════════════════════════════════════════
print(f'\n[T-Pose Fix] Saving to {DST}...')
gltf.save_binary(DST)

# Verify
print('\n[T-Pose Fix] Verification - new rotations:')
gltf2 = GLTF2().load_binary(DST)
for nid, name in bones_to_fix.items():
    node = gltf2.nodes[nid]
    q = list(node.rotation) if node.rotation else [0,0,0,1]
    ex, ey, ez = quat_to_euler_xyz(q)
    print(f'  {name}: Euler XYZ = ({math.degrees(ex):.2f}°, {math.degrees(ey):.2f}°, {math.degrees(ez):.2f}°)')

print('\n✅ Done! T-Pose VRM saved successfully.')
print(f'   Old: {SRC}')
print(f'   New: {DST}')

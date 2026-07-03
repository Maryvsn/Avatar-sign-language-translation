"""
Fix VRM Avatar Bone Roll for Arm Chain.

Pipeline (order matters!):
  1. Load ORIGINAL avatar.vrm (clean axis-aligned bones)
  2. Apply T-Pose fix  (zero Shoulder/UpperArm Z-rotations)  ← BEFORE IBMs
  3. Rotate local axes for UpperArm → LowerArm → Hand (both sides)
       • Local Y  → along bone (towards child joint)
       • Local Z  → model-space +Z  (forward)
       • Local X  → Y×Z  (right-hand rule → down for left arm)
  4. Recompute ALL inverse-bind matrices for every skin
  5. Save avatar_fixed.vrm

No twist bones exist in this model (verified).
"""

import struct, math, copy
import numpy as np
from pygltflib import GLTF2
from scipy.spatial.transform import Rotation as R

# ── paths ──────────────────────────────────────────────────────
SRC = r"C:\grad_project\front-end\assets\avatar\avatar.vrm"
DST = r"C:\grad_project\front-end\assets\avatar\avatar_fixed.vrm"

print("[BoneRoll] Loading original avatar.vrm …")
gltf = GLTF2().load_binary(SRC)

# ═══════════════════════════════════════════════════════════════
#  Helpers
# ═══════════════════════════════════════════════════════════════

def quat_to_mat4(q):
    """Quaternion [x,y,z,w] → 4×4 rotation matrix (row-major)."""
    x, y, z, w = q
    return np.array([
        [1-2*(y*y+z*z), 2*(x*y-z*w),   2*(x*z+y*w),   0],
        [2*(x*y+z*w),   1-2*(x*x+z*z), 2*(y*z-x*w),   0],
        [2*(x*z-y*w),   2*(y*z+x*w),   1-2*(x*x+y*y), 0],
        [0,             0,             0,              1],
    ], dtype=np.float64)

def mat3_to_quat(m):
    """3×3 rotation matrix → quaternion [x,y,z,w]."""
    r = R.from_matrix(m)
    q = r.as_quat()  # [x,y,z,w]
    return q.tolist()

def mat4_translate(t):
    m = np.eye(4, dtype=np.float64)
    m[0, 3] = t[0]; m[1, 3] = t[1]; m[2, 3] = t[2]
    return m

def quat_from_euler_xyz(x, y, z):
    cx, sx = math.cos(x/2), math.sin(x/2)
    cy, sy = math.cos(y/2), math.sin(y/2)
    cz, sz = math.cos(z/2), math.sin(z/2)
    return [
        sx*cy*cz + cx*sy*sz,
        cx*sy*cz - sx*cy*sz,
        cx*cy*sz + sx*sy*cz,
        cx*cy*cz - sx*sy*sz,
    ]

def quat_to_euler_xyz(q):
    qx, qy, qz, qw = q
    sinr = 2*(qw*qx + qy*qz)
    cosr = 1 - 2*(qx*qx + qy*qy)
    ex = math.atan2(sinr, cosr)
    sinp = 2*(qw*qy - qz*qx)
    ey = math.asin(max(-1, min(1, sinp)))
    siny = 2*(qw*qz + qx*qy)
    cosy = 1 - 2*(qy*qy + qz*qz)
    ez = math.atan2(siny, cosy)
    return ex, ey, ez

# ── parent map ─────────────────────────────────────────────────
parent_map = {}
for i, n in enumerate(gltf.nodes):
    if n.children:
        for c in n.children:
            parent_map[c] = i

def get_local_matrix(node):
    rot = np.eye(4, dtype=np.float64)
    if node.rotation:
        rot = quat_to_mat4(node.rotation)
    trans = np.eye(4, dtype=np.float64)
    if node.translation:
        trans = mat4_translate(node.translation)
    return trans @ rot          # T * R  (no scale in this model)

def get_world_matrix(node_idx):
    chain = []
    idx = node_idx
    while idx is not None:
        chain.append(idx)
        idx = parent_map.get(idx)
    chain.reverse()
    w = np.eye(4, dtype=np.float64)
    for nid in chain:
        w = w @ get_local_matrix(gltf.nodes[nid])
    return w

# ═══════════════════════════════════════════════════════════════
#  STEP 1 — T-Pose fix  (zero Z-rotation on Shoulder + UpperArm)
# ═══════════════════════════════════════════════════════════════
tpose_bones = {
    45: "J_Bip_L_Shoulder",
    46: "J_Bip_L_UpperArm",
    64: "J_Bip_R_Shoulder",
    65: "J_Bip_R_UpperArm",
}

print("\n[Step 1] Zeroing Z-rotations for T-Pose …")
for nid, name in tpose_bones.items():
    node = gltf.nodes[nid]
    q = list(node.rotation) if node.rotation else [0, 0, 0, 1]
    ex, ey, ez = quat_to_euler_xyz(q)
    new_q = quat_from_euler_xyz(ex, ey, 0.0)
    node.rotation = new_q
    print(f"  {name}: Z {math.degrees(ez):.2f}° → 0°")

# ═══════════════════════════════════════════════════════════════
#  STEP 2 — Fix bone roll for arm chains
#
#  Convention:
#    Local Y = bone direction (head → child)
#    Local Z = model +Z  (forward)
#    Local X = Y × Z  (right-hand rule)
#
#  For LEFT  arm: X ends up ≈ [0,−1,0] (down) → palm down ✓
#  For RIGHT arm: X ends up ≈ [0,+1,0] (up)   → but the bone
#    is mirrored, so the palm-down normal is local −X, still
#    pointing [0,−1,0] in world.  Right-handed system preserved.
# ═══════════════════════════════════════════════════════════════

# Chains: (bone, child) — processed parent→child order
left_chain  = [(46, 47), (47, 48)]   # UpperArm→LowerArm, LowerArm→Hand
right_chain = [(65, 66), (66, 67)]
# Hand has fingers as children; pick first child for direction
hand_children = {48: 49, 67: 68}     # Hand → Index1 (first finger child)
# Add Hand bones
left_chain.append((48, 49))
right_chain.append((67, 68))

print("\n[Step 2] Fixing bone roll for arm chain …")

def desired_world_rot(bone_idx, child_idx):
    """Compute desired 3×3 world rotation: Y along bone, Z forward."""
    bone_pos = get_world_matrix(bone_idx)[:3, 3]
    child_pos = get_world_matrix(child_idx)[:3, 3]

    y_axis = child_pos - bone_pos
    y_axis /= np.linalg.norm(y_axis)

    z_temp = np.array([0.0, 0.0, 1.0])
    x_axis = np.cross(y_axis, z_temp)
    x_norm = np.linalg.norm(x_axis)
    if x_norm < 1e-6:
        # bone along Z — fallback
        z_temp = np.array([0.0, 1.0, 0.0])
        x_axis = np.cross(y_axis, z_temp)
    x_axis /= np.linalg.norm(x_axis)
    z_axis = np.cross(x_axis, y_axis)
    z_axis /= np.linalg.norm(z_axis)

    # Columns = local axes in world space
    rot = np.column_stack([x_axis, y_axis, z_axis])
    return rot

def apply_bone_roll(bone_idx, child_idx):
    """Set bone_idx's rotation so its local frame matches the desired roll.
    Then fix the DIRECT CHILDREN translations so they stay in place."""

    node = gltf.nodes[bone_idx]
    name = node.name or str(bone_idx)

    # Current world transform of bone and parent
    par_idx = parent_map.get(bone_idx)
    par_world = get_world_matrix(par_idx) if par_idx is not None else np.eye(4, dtype=np.float64)
    par_rot3 = par_world[:3, :3]

    # Desired world rotation
    des_rot3 = desired_world_rot(bone_idx, child_idx)

    # Local rotation = parent_rot_inv * desired_rot
    new_local_rot3 = par_rot3.T @ des_rot3

    # Old local rotation
    old_local_rot3 = np.eye(3, dtype=np.float64)
    if node.rotation:
        old_local_rot3 = quat_to_mat4(node.rotation)[:3, :3]

    # Correction in local space: C = old_inv * new  → child_t_new = C_inv * child_t_old
    correction = old_local_rot3.T @ new_local_rot3
    correction_inv = correction.T  # orthogonal matrix

    # Set new rotation
    new_q = mat3_to_quat(new_local_rot3)
    node.rotation = new_q

    # Fix translations of ALL direct children
    if node.children:
        for cid in node.children:
            cnode = gltf.nodes[cid]
            if cnode.translation:
                old_t = np.array(cnode.translation, dtype=np.float64)
                new_t = correction_inv @ old_t
                cnode.translation = new_t.tolist()

    # Show result
    y_world = des_rot3[:, 1]
    x_world = des_rot3[:, 0]
    z_world = des_rot3[:, 2]
    print(f"  {name}:")
    print(f"    Y (bone dir): [{y_world[0]:.4f}, {y_world[1]:.4f}, {y_world[2]:.4f}]")
    print(f"    Z (forward):  [{z_world[0]:.4f}, {z_world[1]:.4f}, {z_world[2]:.4f}]")
    print(f"    X (palm):     [{x_world[0]:.4f}, {x_world[1]:.4f}, {x_world[2]:.4f}]")

# Process chains in parent→child order
for bone_idx, child_idx in left_chain:
    apply_bone_roll(bone_idx, child_idx)

for bone_idx, child_idx in right_chain:
    apply_bone_roll(bone_idx, child_idx)

# ═══════════════════════════════════════════════════════════════
#  STEP 3 — Recompute ALL inverse bind matrices
#           (AFTER T-pose + bone roll are finalized)
# ═══════════════════════════════════════════════════════════════
print("\n[Step 3] Recomputing inverse bind matrices …")

for skin_idx, skin in enumerate(gltf.skins):
    if skin.inverseBindMatrices is None:
        continue

    accessor = gltf.accessors[skin.inverseBindMatrices]
    bv = gltf.bufferViews[accessor.bufferView]
    blob = gltf.binary_blob()
    offset = bv.byteOffset + (accessor.byteOffset or 0)
    count = accessor.count

    # Read existing
    matrices = []
    for i in range(count):
        raw = struct.unpack("<16f", blob[offset + i*64 : offset + (i+1)*64])
        matrices.append(np.array(raw, dtype=np.float64).reshape(4, 4).T)

    # Recompute ALL joints
    for j_idx, joint_node in enumerate(skin.joints):
        world = get_world_matrix(joint_node)
        matrices[j_idx] = np.linalg.inv(world)

    # Write back
    new_data = bytearray()
    for mat in matrices:
        mat32 = mat.astype(np.float32)
        new_data.extend(struct.pack("<16f", *mat32.T.flatten()))

    new_blob = bytearray(blob)
    new_blob[offset : offset + count * 64] = new_data
    gltf.set_binary_blob(bytes(new_blob))
    # Must re-read blob after set_binary_blob
    blob = gltf.binary_blob()

    print(f"  Skin {skin_idx}: {count} IBMs updated")

# ═══════════════════════════════════════════════════════════════
#  STEP 4 — Save
# ═══════════════════════════════════════════════════════════════
print(f"\n[Step 4] Saving → {DST}")
gltf.save_binary(DST)

# ═══════════════════════════════════════════════════════════════
#  Verification
# ═══════════════════════════════════════════════════════════════
print("\n[Verify] Loading saved file …")
gv = GLTF2().load_binary(DST)

# Rebuild helpers for verification
pm2 = {}
for i, n in enumerate(gv.nodes):
    if n.children:
        for c in n.children:
            pm2[c] = i

def gwm2(nidx):
    chain = []
    idx = nidx
    while idx is not None:
        chain.append(idx)
        idx = pm2.get(idx)
    chain.reverse()
    w = np.eye(4, dtype=np.float64)
    for nid in chain:
        nd = gv.nodes[nid]
        loc = np.eye(4, dtype=np.float64)
        if nd.rotation:
            loc = quat_to_mat4(nd.rotation)
        if nd.translation:
            loc = mat4_translate(nd.translation) @ loc
        w = w @ loc
    return w

arm_nodes = {46: "L_UpperArm", 47: "L_LowerArm", 48: "L_Hand",
             65: "R_UpperArm", 66: "R_LowerArm", 67: "R_Hand"}

print("\n  Local axes in world space:")
for nidx in sorted(arm_nodes):
    w = gwm2(nidx)
    r3 = w[:3, :3]
    print(f"  {arm_nodes[nidx]}:  X=[{r3[0,0]:.3f},{r3[1,0]:.3f},{r3[2,0]:.3f}]"
          f"  Y=[{r3[0,1]:.3f},{r3[1,1]:.3f},{r3[2,1]:.3f}]"
          f"  Z=[{r3[0,2]:.3f},{r3[1,2]:.3f},{r3[2,2]:.3f}]")

# IBM check
skin = gv.skins[0]
acc = gv.accessors[skin.inverseBindMatrices]
bv2 = gv.bufferViews[acc.bufferView]
bl2 = gv.binary_blob()
off2 = bv2.byteOffset + (acc.byteOffset or 0)

print("\n  IBM correctness:")
all_ok = True
for nidx in sorted(arm_nodes):
    ji = list(skin.joints).index(nidx)
    raw = struct.unpack("<16f", bl2[off2+ji*64:off2+(ji+1)*64])
    stored = np.array(raw, dtype=np.float64).reshape(4,4).T
    expected = np.linalg.inv(gwm2(nidx))
    diff = np.abs(stored - expected).max()
    ok = diff < 0.001
    if not ok:
        all_ok = False
    print(f"  {arm_nodes[nidx]}: diff={diff:.6f} {'OK' if ok else 'FAIL'}")

print(f"\n{'✅' if all_ok else '❌'} Done!  Saved to {DST}")

import json, struct, math
from pygltflib import GLTF2

vrm_path = r'C:\grad_project\front-end\assets\avatar\avatar.vrm'

# VRM is GLB (binary GLTF)
gltf = GLTF2().load_binary(vrm_path)

# Find UpperArm bones
print('=== Arm-related nodes ===')
for i, node in enumerate(gltf.nodes):
    name = node.name or ''
    if any(k in name for k in ['Shoulder', 'Arm', 'Hand', 'Upper', 'Lower']):
        rot = list(node.rotation) if node.rotation else [0,0,0,1]
        trans = list(node.translation) if node.translation else [0,0,0]
        
        # Convert quaternion to euler (Z angle in degrees)
        qx, qy, qz, qw = rot
        # Z-axis rotation (roll)
        z_angle = math.atan2(2*(qw*qz + qx*qy), 1 - 2*(qy*qy + qz*qz))
        
        print(f'  Node {i}: {name}')
        print(f'    rotation quat: [{qx:.6f}, {qy:.6f}, {qz:.6f}, {qw:.6f}]')
        print(f'    Z-angle: {math.degrees(z_angle):.2f}°')
        print(f'    translation: [{trans[0]:.4f}, {trans[1]:.4f}, {trans[2]:.4f}]')
        
        # Show children
        if node.children:
            child_names = [gltf.nodes[c].name for c in node.children if c < len(gltf.nodes)]
            print(f'    children: {child_names}')
        print()

# Check extensions
print('=== Extensions ===')
if gltf.extensions:
    for key in gltf.extensions.keys():
        print(f'  {key}')
else:
    print('  No extensions at GLTF root level')

# Check extensionsUsed
print(f'  extensionsUsed: {gltf.extensionsUsed}')
print(f'  extensionsRequired: {gltf.extensionsRequired}')

# Check VRM extension in the GLTF JSON (might be in extras)
vrm_ext = gltf.extensions.get('VRM', None) if gltf.extensions else None
if vrm_ext:
    humanoid = vrm_ext.get('humanoid', {})
    bones = humanoid.get('humanBones', [])
    print(f'\n=== VRM 0.x Humanoid ({len(bones)} bones) ===')
    for b in bones:
        bn = b.get('bone', '')
        nd = b.get('node', -1)
        if any(k in bn for k in ['shoulder', 'Shoulder', 'Arm', 'arm', 'Hand', 'hand']):
            node_name = gltf.nodes[nd].name if 0 <= nd < len(gltf.nodes) else '?'
            print(f'  {bn} -> node {nd} ({node_name})')

vrmc_ext = gltf.extensions.get('VRMC_vrm', None) if gltf.extensions else None
if vrmc_ext:
    humanoid = vrmc_ext.get('humanoid', {})
    hbones = humanoid.get('humanBones', {})
    print(f'\n=== VRM 1.0 Humanoid ({len(hbones)} bones) ===')
    for bn, info in hbones.items():
        nd = info.get('node', -1)
        if any(k in bn for k in ['shoulder', 'Shoulder', 'Arm', 'arm', 'Hand', 'hand']):
            node_name = gltf.nodes[nd].name if 0 <= nd < len(gltf.nodes) else '?'
            print(f'  {bn} -> node {nd} ({node_name})')

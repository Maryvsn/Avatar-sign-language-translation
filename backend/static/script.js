// ═══════════════════════════════════════════════════════════════
//  VRM Avatar — v15 (Anatomical Finger Constraints + OneEuro)
//
//  v15: Complete finger rewrite
//  - Anatomical curl-angle based rotation (no full IK twist)
//  - OneEuro filter for smooth jitter-free motion
//  - Pose library fallback for noisy ML data
//  - Per-joint anatomical limits (no backward bending)
// ═══════════════════════════════════════════════════════════════

import * as THREE from 'three';
import { GLTFLoader } from 'three/addons/loaders/GLTFLoader.js';
import { VRMLoaderPlugin, VRMHumanBoneName } from '@pixiv/three-vrm';

console.log('[VRM] v15 Anatomical Fingers');

// ── SCENE ──
const scene  = new THREE.Scene();
const camera = new THREE.PerspectiveCamera(28, innerWidth / innerHeight, 0.1, 100);
camera.position.set(0, 0.85, 3.5);
camera.lookAt(0, 0.85, 0);

const renderer = new THREE.WebGLRenderer({ alpha: true, antialias: true });
renderer.setSize(innerWidth, innerHeight);
renderer.setPixelRatio(Math.min(devicePixelRatio, 2));
renderer.toneMapping = THREE.ACESFilmicToneMapping;
document.getElementById('canvas-container').appendChild(renderer.domElement);

scene.add(new THREE.DirectionalLight(0xffffff, 1.2).translateZ(2).translateY(2));
scene.add(new THREE.AmbientLight(0x999999));
window.addEventListener('resize', () => {
    camera.aspect = innerWidth / innerHeight;
    camera.updateProjectionMatrix();
    renderer.setSize(innerWidth, innerHeight);
});

// ── VRM ──
let vrm = null;
const bonesMap = {};

// ── ANIMATION STATE ──
let animFrames = [], animStart = 0, isAnimating = false;
let isReturning = false, returnStart = 0;
const snapQuats = {};
const FRAME_MS  = 100;
const RETURN_MS = 700;

// ── Sentence Animation State ──
let isSentenceMode = false;
let sentenceWordBoundaries = [];  // [{startFrame, endFrame, wordIndex}]
let sentenceCurrentWord = -1;

// ── Wrist SLERP Smoothing ──
// Prevents sudden wrist flips/pops between poses
const WRIST_SMOOTH_ALPHA = 0.3;  // lower = smoother (0.3 = very smooth)
const smoothedWristQuats = {};   // boneName → THREE.Quaternion

// ═══════════════════════════════════════════════════════════════
//  OneEuro Filter — adaptive low-pass filter for smooth motion
//  Reduces jitter without adding lag (unlike simple EMA)
// ═══════════════════════════════════════════════════════════════
class OneEuroFilter {
    constructor(minCutoff = 1.0, beta = 0.5, dCutoff = 1.0) {
        this.minCutoff = minCutoff;
        this.beta = beta;
        this.dCutoff = dCutoff;
        this.xPrev = null;
        this.dxPrev = 0.0;
        this.tPrev = null;
    }
    _alpha(cutoff, dt) {
        const tau = 1.0 / (2 * Math.PI * cutoff);
        return 1.0 / (1.0 + tau / dt);
    }
    filter(x, t) {
        if (this.xPrev === null) {
            this.xPrev = x; this.dxPrev = 0.0; this.tPrev = t;
            return x;
        }
        const dt = Math.max(t - this.tPrev, 0.001);
        this.tPrev = t;
        const dx = (x - this.xPrev) / dt;
        const adx = this._alpha(this.dCutoff, dt);
        this.dxPrev = adx * dx + (1 - adx) * this.dxPrev;
        const cutoff = this.minCutoff + this.beta * Math.abs(this.dxPrev);
        const ax = this._alpha(cutoff, dt);
        this.xPrev = ax * x + (1 - ax) * this.xPrev;
        return this.xPrev;
    }
    reset() { this.xPrev = null; this.dxPrev = 0.0; this.tPrev = null; }
}

// ═══════════════════════════════════════════════════════════════
//  Anatomical Joint Limits (radians)
//  - No backward bending (min >= 0 for non-thumb)
//  - Limited side-to-side (splay only on proximal)
// ═══════════════════════════════════════════════════════════════
const JOINT_LIMITS = {
    proximal:      { min: -0.10, max: Math.PI * 0.50 },  // ~90°
    intermediate:  { min:  0.00, max: Math.PI * 0.55 },  // ~100°
    distal:        { min:  0.00, max: Math.PI * 0.40 },  // ~72°
    thumbProx:     { min: -0.20, max: Math.PI * 0.35 },  // ~63°
    thumbMid:      { min: -0.10, max: Math.PI * 0.35 },  // ~63°
    thumbDist:     { min: -0.10, max: Math.PI * 0.45 },  // ~81°
};

// ═══════════════════════════════════════════════════════════════
//  Pose Library — canonical handshapes for noisy-data fallback
//  Values are curl ratios: 0 = fully extended, 1 = fully curled
// ═══════════════════════════════════════════════════════════════
const HAND_POSES = {
    flat:    { thumb: 0.05, index: 0.0,  middle: 0.0,  ring: 0.0,  little: 0.0  },
    fist:    { thumb: 0.70, index: 0.95, middle: 0.95, ring: 0.95, little: 0.95 },
    point:   { thumb: 0.50, index: 0.0,  middle: 0.95, ring: 0.95, little: 0.95 },
    spread:  { thumb: 0.10, index: 0.0,  middle: 0.0,  ring: 0.0,  little: 0.0  },
    claw:    { thumb: 0.30, index: 0.45, middle: 0.45, ring: 0.45, little: 0.45 },
    peace:   { thumb: 0.50, index: 0.0,  middle: 0.0,  ring: 0.95, little: 0.95 },
    relaxed: { thumb: 0.15, index: 0.25, middle: 0.30, ring: 0.35, little: 0.40 },
};

// ── Filter storage: one filter per bone per axis ──
const curlFilters = {};  // key → OneEuroFilter
function getCurlFilter(key) {
    if (!curlFilters[key]) curlFilters[key] = new OneEuroFilter(0.8, 0.4, 1.0);
    return curlFilters[key];
}
function resetCurlFilters() {
    for (const k in curlFilters) delete curlFilters[k];
}

// ── Finger definitions per hand ──
function _buildFingerDefs(prefix) {
    return [
        { name: 'thumb',  pts: [1,2,3,4],     isThumb: true,
          bones: [
              VRMHumanBoneName[prefix+'ThumbProximal'],
              VRMHumanBoneName[prefix+'ThumbMetacarpal'],
              VRMHumanBoneName[prefix+'ThumbDistal'] ],
          limits: [JOINT_LIMITS.thumbProx, JOINT_LIMITS.thumbMid, JOINT_LIMITS.thumbDist] },
        { name: 'index',  pts: [5,6,7,8],     isThumb: false,
          bones: [
              VRMHumanBoneName[prefix+'IndexProximal'],
              VRMHumanBoneName[prefix+'IndexIntermediate'],
              VRMHumanBoneName[prefix+'IndexDistal'] ],
          limits: [JOINT_LIMITS.proximal, JOINT_LIMITS.intermediate, JOINT_LIMITS.distal] },
        { name: 'middle', pts: [9,10,11,12],  isThumb: false,
          bones: [
              VRMHumanBoneName[prefix+'MiddleProximal'],
              VRMHumanBoneName[prefix+'MiddleIntermediate'],
              VRMHumanBoneName[prefix+'MiddleDistal'] ],
          limits: [JOINT_LIMITS.proximal, JOINT_LIMITS.intermediate, JOINT_LIMITS.distal] },
        { name: 'ring',   pts: [13,14,15,16], isThumb: false,
          bones: [
              VRMHumanBoneName[prefix+'RingProximal'],
              VRMHumanBoneName[prefix+'RingIntermediate'],
              VRMHumanBoneName[prefix+'RingDistal'] ],
          limits: [JOINT_LIMITS.proximal, JOINT_LIMITS.intermediate, JOINT_LIMITS.distal] },
        { name: 'little', pts: [17,18,19,20], isThumb: false,
          bones: [
              VRMHumanBoneName[prefix+'LittleProximal'],
              VRMHumanBoneName[prefix+'LittleIntermediate'],
              VRMHumanBoneName[prefix+'LittleDistal'] ],
          limits: [JOINT_LIMITS.proximal, JOINT_LIMITS.intermediate, JOINT_LIMITS.distal] },
    ];
}
const LEFT_FINGERS  = _buildFingerDefs('Left');
const RIGHT_FINGERS = _buildFingerDefs('Right');

// All finger bone names (for snapshot/restore)
const ALL_FINGER_BONES = [
    ...LEFT_FINGERS.flatMap(f => f.bones),
    ...RIGHT_FINGERS.flatMap(f => f.bones),
];

// تحميل الأفاتار
const loader = new GLTFLoader();
loader.register(p => new VRMLoaderPlugin(p));
loader.load(
    new URL('avatar.vrm', location.href).href,
    gltf => {
        vrm = gltf.userData.vrm;
        if (!vrm) { console.error('[VRM] No VRM!'); return; }
        scene.add(vrm.scene);

        // تخزين العظام في Map وتجهيز userData
        for (const name of Object.values(VRMHumanBoneName)) {
            const node = vrm.humanoid.getNormalizedBoneNode(name);
            if (node) {
                bonesMap[name] = node;
                node.userData.initialQuat = node.quaternion.clone();
            }
        }
        
        // Log finger bones found
        let fingerCount = 0;
        for (const bname of ALL_FINGER_BONES) {
            if (bonesMap[bname]) fingerCount++;
        }
        console.log(`[VRM] ✅ ${Object.keys(bonesMap).length} bones (${fingerCount} finger bones)`);
        
        // إعداد وضعية التوقف (Idle Pose) كما في الويب
        setIdlePose();

        document.getElementById('loading').style.display = 'none';

        // ══ DEBUG CALIBRATION ══
        const _calibBones = {
            'leftShoulder': VRMHumanBoneName.LeftUpperArm,
            'rightShoulder': VRMHumanBoneName.RightUpperArm,
            'leftElbow': VRMHumanBoneName.LeftLowerArm,
            'rightElbow': VRMHumanBoneName.RightLowerArm,
            'leftWrist': VRMHumanBoneName.LeftHand,
            'rightWrist': VRMHumanBoneName.RightHand,
            'hips': VRMHumanBoneName.Hips,
            'spine': VRMHumanBoneName.Spine,
            'neck': VRMHumanBoneName.Neck,
            'head': VRMHumanBoneName.Head,
        };
        vrm.scene.updateMatrixWorld(true);
        const _pos = new THREE.Vector3();
        console.log('[CALIB] VRM bone world positions:');
        for (const [label, bname] of Object.entries(_calibBones)) {
            const b = bonesMap[bname];
            if (b) {
                b.getWorldPosition(_pos);
                console.log(`[CALIB]   ${label}: x=${_pos.x.toFixed(3)}, y=${_pos.y.toFixed(3)}, z=${_pos.z.toFixed(3)}`);
            }
        }
        const _testMP = mpToWorld([0.30, 0.33, 0.0]);
        console.log(`[CALIB] mpToWorld([0.30,0.33,0]) → x=${_testMP.x.toFixed(3)}, y=${_testMP.y.toFixed(3)}, z=${_testMP.z.toFixed(3)}`);
        // ══ END DEBUG ══

        if (window.chrome?.webview) window.chrome.webview.postMessage('VRM_LOADED');

    },
    undefined,
    err => console.error('[VRM] Error:', err)
);

// ── RENDER LOOP ──
const clock = new THREE.Clock();
(function loop() {
    requestAnimationFrame(loop);
    if (!vrm) { renderer.render(scene, camera); return; }

    if (isAnimating && animFrames.length > 0) {
        const raw   = (performance.now() - animStart) / FRAME_MS;
        const total = animFrames.length;
        if (raw >= total - 1) {
            _applyFrame(animFrames[total - 1]);
            _snapshot();
            isAnimating = false;
            isReturning = true;
            returnStart = performance.now();
            // Notify end of last word in sentence mode
            if (isSentenceMode && sentenceCurrentWord >= 0) {
                if (window.chrome?.webview) window.chrome.webview.postMessage(`WORD_END:${sentenceCurrentWord}`);
            }
            isSentenceMode = false;
            sentenceCurrentWord = -1;
            if (window.chrome?.webview) window.chrome.webview.postMessage('ANIMATION_DONE');
        } else {
            const iA = Math.floor(raw);
            _applyInterp(animFrames[iA], animFrames[Math.min(iA+1, total-1)], raw - iA);

            // ── Sentence word boundary tracking ──
            if (isSentenceMode && sentenceWordBoundaries.length > 0) {
                const frameIndex = Math.floor(raw);
                for (const wb of sentenceWordBoundaries) {
                    if (frameIndex >= wb.startFrame && frameIndex <= wb.endFrame && sentenceCurrentWord !== wb.wordIndex) {
                        // Notify end of previous word
                        if (sentenceCurrentWord >= 0) {
                            if (window.chrome?.webview) window.chrome.webview.postMessage(`WORD_END:${sentenceCurrentWord}`);
                        }
                        // Notify start of new word
                        sentenceCurrentWord = wb.wordIndex;
                        if (window.chrome?.webview) window.chrome.webview.postMessage(`WORD_START:${wb.wordIndex}`);
                        break;
                    }
                }
            }
        }
    }

    if (isReturning) {
        const t  = Math.min((performance.now() - returnStart) / RETURN_MS, 1.0);
        const st = t * t * (3 - 2 * t);
        for (const [name, from] of Object.entries(snapQuats)) {
            const bone = bonesMap[name];
            const to = bone?.userData.idleQuat || bone?.userData.initialQuat;
            if (bone && to) bone.quaternion.copy(from).slerp(to, st);
        }
        if (t >= 1.0) { isReturning = false; resetToIdle(); }
    }

    vrm.update(clock.getDelta());
    renderer.render(scene, camera);
})();

// ── Helpers من ملف الويب ──

function mpToWorld(point) {
    if (!point || point.length < 3) return new THREE.Vector3();
    const SCALE_X = 0.9;
    const SCALE_Y = 1.0;
    const CENTER_Y = 0.65;
    return new THREE.Vector3(
        (point[0] - 0.5) * SCALE_X,
        (0.5 - point[1]) * SCALE_Y + CENTER_Y,
        -point[2] * SCALE_X
    );
}

function findBoneChild(bone) {
    if (!bone) return null;
    for (let child of bone.children) {
        if (child.isBone || child.type === 'Bone' || child.type === 'Object3D') {
            return child;
        }
    }
    return bone.children[0];
}

function resetToIdle() {
    for (let name in bonesMap) {
        const bone = bonesMap[name];
        if (bone.userData.idleQuat) {
            bone.quaternion.copy(bone.userData.idleQuat);
        } else if (bone.userData.initialQuat) {
            bone.quaternion.copy(bone.userData.initialQuat);
        }
    }
    vrm.scene.updateMatrixWorld(true);
}

function setIdlePose() {
    if (!vrm) return;
    vrm.scene.updateMatrixWorld(true);

    const armConfigs = [
        { upper: VRMHumanBoneName.LeftUpperArm,  forearm: VRMHumanBoneName.LeftLowerArm,  sign: 1 },
        { upper: VRMHumanBoneName.RightUpperArm, forearm: VRMHumanBoneName.RightLowerArm, sign: -1 }
    ];

    for (const cfg of armConfigs) {
        const upperBone = bonesMap[cfg.upper];
        const forearmBone = bonesMap[cfg.forearm];
        if (!upperBone) continue;

        const upperChild = forearmBone || findBoneChild(upperBone);
        if (upperChild) {
            const bonePos = new THREE.Vector3();
            const childPos = new THREE.Vector3();
            upperBone.getWorldPosition(bonePos);
            upperChild.getWorldPosition(childPos);

            const currentDir = new THREE.Vector3().subVectors(childPos, bonePos).normalize();
            const targetDir = new THREE.Vector3(0, -1, 0).normalize();
            const rotQ = new THREE.Quaternion().setFromUnitVectors(currentDir, targetDir);

            const currentWorldQ = new THREE.Quaternion();
            upperBone.getWorldQuaternion(currentWorldQ);
            const newWorldQ = rotQ.multiply(currentWorldQ);

            if (upperBone.parent) {
                const parentWorldQ = new THREE.Quaternion();
                upperBone.parent.getWorldQuaternion(parentWorldQ);
                upperBone.quaternion.copy(parentWorldQ.invert().multiply(newWorldQ));
            } else {
                upperBone.quaternion.copy(newWorldQ);
            }
            upperBone.updateMatrixWorld(true);
            upperBone.userData.idleQuat = upperBone.quaternion.clone();
        }

        if (forearmBone) {
            forearmBone.quaternion.copy(forearmBone.userData.initialQuat);
            forearmBone.updateMatrixWorld(true);
            forearmBone.userData.idleQuat = forearmBone.quaternion.clone();
        }
    }

    // Store idle quats for all finger bones too
    for (const bname of ALL_FINGER_BONES) {
        const bone = bonesMap[bname];
        if (bone) {
            bone.userData.idleQuat = bone.quaternion.clone();
        }
    }
}

function alignBoneWorld(boneName, startPt, endPt) {
    const bone = bonesMap[boneName];
    if (!bone || !startPt || !endPt) return;

    const startPos = mpToWorld(startPt);
    const endPos = mpToWorld(endPt);
    const targetDir = new THREE.Vector3().subVectors(endPos, startPos);
    if (targetDir.lengthSq() < 0.0001) return;
    targetDir.normalize();

    bone.quaternion.copy(bone.userData.idleQuat || bone.userData.initialQuat);
    bone.updateMatrixWorld(true);

    let childBone = null;
    if (boneName === VRMHumanBoneName.LeftUpperArm) childBone = bonesMap[VRMHumanBoneName.LeftLowerArm];
    else if (boneName === VRMHumanBoneName.RightUpperArm) childBone = bonesMap[VRMHumanBoneName.RightLowerArm];
    else if (boneName === VRMHumanBoneName.LeftLowerArm) childBone = bonesMap[VRMHumanBoneName.LeftHand];
    else if (boneName === VRMHumanBoneName.RightLowerArm) childBone = bonesMap[VRMHumanBoneName.RightHand];

    if (!childBone) childBone = findBoneChild(bone);
    if (!childBone) return;

    const bonePos = new THREE.Vector3();
    const childPos = new THREE.Vector3();
    bone.getWorldPosition(bonePos);
    childBone.getWorldPosition(childPos);

    const currentDir = new THREE.Vector3().subVectors(childPos, bonePos).normalize();

    const swingQ = new THREE.Quaternion().setFromUnitVectors(currentDir, targetDir);

    const currentWorldQ = new THREE.Quaternion();
    bone.getWorldQuaternion(currentWorldQ);
    const newWorldQ = swingQ.multiply(currentWorldQ);

    let localQ;
    if (bone.parent) {
        const parentWorldQ = new THREE.Quaternion();
        bone.parent.getWorldQuaternion(parentWorldQ);
        localQ = parentWorldQ.clone().invert().multiply(newWorldQ);
    } else {
        localQ = newWorldQ;
    }

    // ── Wrist SLERP smoothing for LowerArm bones ──
    const isWrist = (boneName === VRMHumanBoneName.LeftLowerArm ||
                     boneName === VRMHumanBoneName.RightLowerArm);
    if (isWrist && smoothedWristQuats[boneName]) {
        smoothedWristQuats[boneName].slerp(localQ, WRIST_SMOOTH_ALPHA);
        bone.quaternion.copy(smoothedWristQuats[boneName]);
    } else {
        if (isWrist) smoothedWristQuats[boneName] = localQ.clone();
        bone.quaternion.copy(localQ);
    }

    bone.updateMatrixWorld(true);

    _removeTwist(bone, targetDir);
}

function _removeTwist(bone, boneAxis) {
    const boneWorldQ = new THREE.Quaternion();
    bone.getWorldQuaternion(boneWorldQ);

    const boneUp = new THREE.Vector3(0, 1, 0).applyQuaternion(boneWorldQ);

    const dot = boneUp.dot(boneAxis);
    boneUp.addScaledVector(boneAxis, -dot).normalize();
    if (boneUp.lengthSq() < 0.001) return;

    const worldUp = new THREE.Vector3(0, 0, 1);
    const dot2 = worldUp.dot(boneAxis);
    const desiredUp = worldUp.clone().addScaledVector(boneAxis, -dot2).normalize();
    if (desiredUp.lengthSq() < 0.001) return;

    const twistQ = new THREE.Quaternion().setFromUnitVectors(boneUp, desiredUp);
    const fixedWorldQ = twistQ.multiply(boneWorldQ);

    if (bone.parent) {
        const parentWorldQ = new THREE.Quaternion();
        bone.parent.getWorldQuaternion(parentWorldQ);
        bone.quaternion.copy(parentWorldQ.clone().invert().multiply(fixedWorldQ));
    } else {
        bone.quaternion.copy(fixedWorldQ);
    }
    bone.updateMatrixWorld(true);
}

// ═══════════════════════════════════════════════════════════════
//  FINGER ANIMATION v2 — Anatomical Curl Angles + OneEuro Filter
//
//  Instead of full 3D IK (which causes twist/melt artifacts),
//  we compute the CURL ANGLE at each joint from landmark geometry
//  and apply it as a single-axis local rotation.
//  Fingers can only bend along their natural flex axis.
// ═══════════════════════════════════════════════════════════════

/** Compute angle (radians) between two 3D vectors. Returns 0..PI. */
function _vec3Angle(ax, ay, az, bx, by, bz) {
    const la = Math.sqrt(ax*ax + ay*ay + az*az);
    const lb = Math.sqrt(bx*bx + by*by + bz*bz);
    if (la < 1e-7 || lb < 1e-7) return 0;
    const dot = (ax*bx + ay*by + az*bz) / (la * lb);
    return Math.acos(Math.max(-1, Math.min(1, dot)));
}

/**
 * Find the nearest canonical handshape from the pose library.
 * avgCurls: { thumb, index, middle, ring, little } - normalized 0..1
 */
function _findNearestPose(avgCurls) {
    let best = HAND_POSES.relaxed, bestDist = Infinity;
    for (const pose of Object.values(HAND_POSES)) {
        let dist = 0;
        for (const f of ['thumb','index','middle','ring','little']) {
            const d = (avgCurls[f] || 0) - pose[f];
            dist += d * d;
        }
        if (dist < bestDist) { bestDist = dist; best = pose; }
    }
    return best;
}

/**
 * Apply anatomically-constrained finger animation for one hand.
 *
 * @param {Array} joints  - 21 × [x,y,z] MediaPipe hand landmarks
 * @param {Array} fingerDefs - LEFT_FINGERS or RIGHT_FINGERS
 * @param {string} side - 'left' or 'right'
 */
function applyAnatomicalFingers(joints, fingerDefs, side) {
    if (!joints || joints.length < 21) return;
    // Skip all-zero hands
    if (!joints.some(p => Math.abs(p[0]) > 1e-6 || Math.abs(p[1]) > 1e-6)) return;

    const now = performance.now() / 1000.0;
    const wrist = joints[0];

    // ── Step 1: Compute curl angles for every finger/joint ──
    const fingerCurls = {};  // name → [proxAngle, midAngle, distAngle]
    const avgNorm = {};      // name → normalized 0..1 average curl
    let totalNoise = 0;

    for (const fdef of fingerDefs) {
        const [i0, i1, i2, i3] = fdef.pts;

        // Vectors between consecutive joints
        const vIn0  = [joints[i0][0]-wrist[0], joints[i0][1]-wrist[1], joints[i0][2]-wrist[2]];
        const vOut0 = [joints[i1][0]-joints[i0][0], joints[i1][1]-joints[i0][1], joints[i1][2]-joints[i0][2]];
        const vOut1 = [joints[i2][0]-joints[i1][0], joints[i2][1]-joints[i1][1], joints[i2][2]-joints[i1][2]];
        const vOut2 = [joints[i3][0]-joints[i2][0], joints[i3][1]-joints[i2][1], joints[i3][2]-joints[i2][2]];

        const a0 = _vec3Angle(...vIn0, ...vOut0);
        const a1 = _vec3Angle(...vOut0, ...vOut1);
        const a2 = _vec3Angle(...vOut1, ...vOut2);

        fingerCurls[fdef.name] = [a0, a1, a2];

        const maxC = fdef.limits[0].max;
        avgNorm[fdef.name] = Math.min(1.0, (a0 + a1 + a2) / (3 * (maxC || 1)));

        // Noise = variance between joint angles (good data has consistent curl)
        const avg = (a0 + a1 + a2) / 3;
        totalNoise += Math.abs(a0 - avg) + Math.abs(a1 - avg) + Math.abs(a2 - avg);
    }

    // ── Step 2: Pose-library blending for noisy data ──
    const noise = totalNoise / 5;
    let poseBlend = 0, nearestPose = null;
    if (noise > 1.0) {
        nearestPose = _findNearestPose(avgNorm);
        poseBlend = Math.min(0.7, (noise - 1.0) / 1.5);  // ramp 0→0.7
    }

    // ── Step 3: Apply rotation per bone using Euler Hard Clamp ──
    for (const fdef of fingerDefs) {
        const rawAngles = fingerCurls[fdef.name];

        for (let j = 0; j < 3; j++) {
            const boneName = fdef.bones[j];
            const bone = bonesMap[boneName];
            if (!bone) continue;

            const limits = fdef.limits[j];
            let curl = rawAngles[j];

            // Clamp to anatomical limits
            curl = Math.max(limits.min, Math.min(limits.max, curl));

            // STRICT: Non-thumb joints CANNOT bend backwards at all
            if (!fdef.isThumb) {
                curl = Math.max(0, curl);
            }

            // Blend with nearest pose if data is noisy
            if (poseBlend > 0 && nearestPose) {
                const poseCurl = nearestPose[fdef.name] * limits.max;
                curl = curl * (1 - poseBlend) + poseCurl * poseBlend;
            }

            // OneEuro filter (scalar — much more stable than quat filtering)
            const fKey = `${side}_${fdef.name}_${j}`;
            curl = getCurlFilter(fKey).filter(curl, now);

            // NaN guard
            if (isNaN(curl)) continue;

            // ── Euler-based Hard Clamp (X = bend axis) ──
            // Start from idle pose
            const idleQ = bone.userData.idleQuat || bone.userData.initialQuat;
            bone.quaternion.copy(idleQ);

            // Decompose idle to Euler, add curl to X (the bend axis)
            const euler = new THREE.Euler();
            euler.setFromQuaternion(bone.quaternion, 'XYZ');
            euler.x += curl;

            // Hard anatomical clamp — prevents ALL hyperextension
            _clampFingerEuler(euler, fdef.isThumb);

            // Apply clamped rotation
            bone.quaternion.setFromEuler(euler);
            bone.updateMatrixWorld(true);
        }
    }
}

/**
 * Hard anatomical clamp for finger Euler rotations.
 * X = bend axis (only forward, never backward)
 * Y = side-to-side (minimized to prevent jitter)
 * Z = twist (minimized to prevent jitter)
 */
function _clampFingerEuler(euler, isThumb) {
    if (isThumb) {
        // Thumb has wider range of motion
        euler.x = Math.max(-0.3, Math.min(1.4, euler.x));
        euler.y = Math.max(-0.5, Math.min(0.5, euler.y));
        euler.z *= 0.2;  // minimize twist
    } else {
        // Index, Middle, Ring, Little — strict forward-only bend
        euler.x = Math.max(0, Math.min(1.6, euler.x));  // 0 to ~90°
        euler.y *= 0.1;  // minimize side-to-side jitter
        euler.z *= 0.1;  // minimize twisting jitter
    }
}


function _snapshot() {
    // Snapshot arm bones
    const ARMS = [VRMHumanBoneName.LeftUpperArm, VRMHumanBoneName.RightUpperArm,
                  VRMHumanBoneName.LeftLowerArm,  VRMHumanBoneName.RightLowerArm];
    for (const name of ARMS) {
        const bone = bonesMap[name];
        if (bone) snapQuats[name] = bone.quaternion.clone();
    }
    // Snapshot finger bones too
    for (const name of ALL_FINGER_BONES) {
        const bone = bonesMap[name];
        if (bone) snapQuats[name] = bone.quaternion.clone();
    }
}

function _lerp(a, b, t) { return a + (b - a) * t; }

// ── تطبيق فريم واحد ──
function _applyFrame(d) {
    resetToIdle();
    // UpperArm: world-space 3D alignment
    if (d.lSh && d.lEl) alignBoneWorld(VRMHumanBoneName.LeftUpperArm, d.lSh, d.lEl);
    if (d.rSh && d.rEl) alignBoneWorld(VRMHumanBoneName.RightUpperArm, d.rSh, d.rEl);
    // LowerArm: world-space 3D alignment (بدون Hand عشان يمنع twist)
    if (d.lEl && d.lWr) alignBoneWorld(VRMHumanBoneName.LeftLowerArm, d.lEl, d.lWr);
    if (d.rEl && d.rWr) alignBoneWorld(VRMHumanBoneName.RightLowerArm, d.rEl, d.rWr);

    // ── Finger Animation (Anatomical v2) ──
    if (d.lHand) applyAnatomicalFingers(d.lHand, LEFT_FINGERS, 'left');
    if (d.rHand) applyAnatomicalFingers(d.rHand, RIGHT_FINGERS, 'right');
}

// ── الإنتربولاسيون بين فريمين ──
function _applyInterp(dA, dB, t) {
    const st = t * t * (3 - 2 * t);
    
    const interpPt = (ptA, ptB) => {
        if (!ptA || !ptB) return ptA || ptB;
        return [
            _lerp(ptA[0], ptB[0], st),
            _lerp(ptA[1], ptB[1], st),
            _lerp(ptA[2], ptB[2], st)
        ];
    };

    // Interpolate hand joints
    const interpHand = (handA, handB) => {
        if (!handA && !handB) return null;
        if (!handA) return handB;
        if (!handB) return handA;
        const result = [];
        for (let i = 0; i < 21; i++) {
            if (i < handA.length && i < handB.length) {
                result.push(interpPt(handA[i], handB[i]));
            } else if (i < handA.length) {
                result.push(handA[i]);
            } else if (i < handB.length) {
                result.push(handB[i]);
            }
        }
        return result;
    };

    _applyFrame({
        lSh: interpPt(dA.lSh, dB.lSh), lEl: interpPt(dA.lEl, dB.lEl), lWr: interpPt(dA.lWr, dB.lWr),
        rSh: interpPt(dA.rSh, dB.rSh), rEl: interpPt(dA.rEl, dB.rEl), rWr: interpPt(dA.rWr, dB.rWr),
        lHand: interpHand(dA.lHand, dB.lHand),
        rHand: interpHand(dA.rHand, dB.rHand),
    });
}

// ── PUBLIC API ──
window.playAnimation = function(jsonStr) {
    if (!vrm) { console.warn('[VRM] Not loaded'); return; }
    try {
        const frames = JSON.parse(jsonStr);
        if (!Array.isArray(frames) || !frames.length) return;
        
        // ── FULL RESET before new animation ──
        // 1. Stop any in-progress animation
        isAnimating = false;
        isReturning = false;
        // 2. Clear ALL previous animation data
        animFrames = [];
        // 3. Reset avatar to T-pose
        resetToIdle();
        // 4. Clear all filter/smoothing state
        resetCurlFilters();
        for (const k in smoothedWristQuats) delete smoothedWristQuats[k];
        
        // ── Load new animation ──
        animFrames  = frames;
        animStart   = performance.now();
        isAnimating = true;
        const hasFingers = frames.some(f => f.lHand || f.rHand);
        console.log(`[VRM] 🎬 ${frames.length} frames (v15 Anatomical${hasFingers ? ', finger data ✅' : ', no finger data'})`);

        // ── DEBUG: Print first 5 frames to verify word changes ──
        const debugCount = Math.min(5, frames.length);
        for (let i = 0; i < debugCount; i++) {
            const f = frames[i];
            const lSh = f.lSh ? `[${f.lSh.map(v=>v.toFixed(3)).join(',')}]` : 'null';
            const rSh = f.rSh ? `[${f.rSh.map(v=>v.toFixed(3)).join(',')}]` : 'null';
            const lH = f.lHand ? `${f.lHand.length}pts` : 'none';
            const rH = f.rHand ? `${f.rHand.length}pts` : 'none';
            console.log(`[DEBUG] Frame ${i}: lSh=${lSh} rSh=${rSh} lHand=${lH} rHand=${rH}`);
        }
    } catch (e) { console.error('[VRM]', e); }
};

window.applyRotations = function(jsonStr) {
    if (!vrm) return;
    try { _applyFrame(JSON.parse(jsonStr)); } catch (e) { console.error('[VRM]', e); }
};

window.stopAnimation = function() {
    isAnimating = false;
    isReturning = false;
    isSentenceMode = false;
    sentenceCurrentWord = -1;
    resetCurlFilters();
    if (vrm) resetToIdle();
};

// ═══════════════════════════════════════════════════════════════
//  SENTENCE ANIMATION — Cross-faded sequential word playback
//
//  Receives an array of word frame arrays, merges them with
//  5-frame SLERP overlap for smooth transitions, and plays
//  the combined sequence as one continuous animation.
// ═══════════════════════════════════════════════════════════════

const CROSSFADE_FRAMES = 5;  // number of overlap frames between words

/**
 * Blend two frames together for cross-fading.
 * @param {Object} frameA - Source frame (end of previous word)
 * @param {Object} frameB - Target frame (start of next word)
 * @param {number} t - Blend factor 0..1 (0 = all A, 1 = all B)
 * @returns {Object} Blended frame
 */
function _blendFrame(frameA, frameB, t) {
    if (!frameA) return frameB;
    if (!frameB) return frameA;

    const st = t * t * (3 - 2 * t);  // smoothstep for natural easing

    const interpPt = (ptA, ptB) => {
        if (!ptA) return ptB;
        if (!ptB) return ptA;
        return [
            _lerp(ptA[0], ptB[0], st),
            _lerp(ptA[1], ptB[1], st),
            _lerp(ptA[2], ptB[2], st)
        ];
    };

    const interpHand = (handA, handB) => {
        if (!handA) return handB;
        if (!handB) return handA;
        const result = [];
        for (let i = 0; i < 21; i++) {
            if (i < handA.length && i < handB.length) {
                result.push(interpPt(handA[i], handB[i]));
            } else {
                result.push(handA[i] || handB[i]);
            }
        }
        return result;
    };

    return {
        lSh: interpPt(frameA.lSh, frameB.lSh),
        lEl: interpPt(frameA.lEl, frameB.lEl),
        lWr: interpPt(frameA.lWr, frameB.lWr),
        rSh: interpPt(frameA.rSh, frameB.rSh),
        rEl: interpPt(frameA.rEl, frameB.rEl),
        rWr: interpPt(frameA.rWr, frameB.rWr),
        lHand: interpHand(frameA.lHand, frameB.lHand),
        rHand: interpHand(frameA.rHand, frameB.rHand),
    };
}

/**
 * Merge multiple word frame arrays with cross-fade overlap.
 * @param {Array<Array>} wordsFrames - Array of frame arrays, one per word
 * @returns {{merged: Array, boundaries: Array}} Merged frames + word boundary indices
 */
function _mergeWithCrossfade(wordsFrames) {
    let merged = [];
    const boundaries = [];

    for (let w = 0; w < wordsFrames.length; w++) {
        const wordFrames = wordsFrames[w];
        if (!wordFrames || !wordFrames.length) continue;

        if (merged.length === 0) {
            // First word — add all frames directly
            boundaries.push({ startFrame: 0, endFrame: wordFrames.length - 1, wordIndex: w });
            merged = [...wordFrames];
        } else {
            // Cross-fade: blend overlapping region
            const overlapCount = Math.min(CROSSFADE_FRAMES, merged.length, wordFrames.length);
            const blendStart = merged.length - overlapCount;

            // Blend the overlap region
            for (let i = 0; i < overlapCount; i++) {
                const t = (i + 1) / (overlapCount + 1);  // 0.17, 0.33, 0.50, 0.67, 0.83
                merged[blendStart + i] = _blendFrame(merged[blendStart + i], wordFrames[i], t);
            }

            // Append remaining frames from this word (after the overlap)
            const newStart = merged.length;
            const remaining = wordFrames.slice(overlapCount);
            merged.push(...remaining);

            boundaries.push({
                startFrame: blendStart,
                endFrame: merged.length - 1,
                wordIndex: w
            });
        }
    }

    return { merged, boundaries };
}

/**
 * Play a sentence animation: multiple words with smooth cross-fading.
 * Called from Flutter with a JSON string of word frame arrays.
 */
window.playSentenceAnimation = function(wordsJsonStr) {
    if (!vrm) { console.warn('[VRM] Not loaded'); return; }
    try {
        const wordsFrames = JSON.parse(wordsJsonStr);
        if (!Array.isArray(wordsFrames) || !wordsFrames.length) return;

        // ── FULL RESET ──
        isAnimating = false;
        isReturning = false;
        animFrames = [];
        resetToIdle();
        resetCurlFilters();
        for (const k in smoothedWristQuats) delete smoothedWristQuats[k];

        // ── Merge words with cross-fading ──
        const { merged, boundaries } = _mergeWithCrossfade(wordsFrames);

        if (merged.length === 0) {
            console.warn('[VRM] No frames after merge');
            return;
        }

        // ── Store word boundaries for render loop tracking ──
        sentenceWordBoundaries = boundaries;
        sentenceCurrentWord = -1;
        isSentenceMode = true;

        // ── Start playback ──
        animFrames = merged;
        animStart = performance.now();
        isAnimating = true;

        console.log(`[VRM] 🎬 Sentence: ${wordsFrames.length} words → ${merged.length} merged frames (${CROSSFADE_FRAMES}-frame crossfade)`);
        for (const wb of boundaries) {
            console.log(`[VRM]   Word ${wb.wordIndex}: frames ${wb.startFrame}–${wb.endFrame}`);
        }
    } catch (e) { console.error('[VRM] Sentence error:', e); }
};


// ═══════════════════════════════════════════════════════════════
//  VRM Avatar — v12 (Direct MediaPipe Alignment)
//
//  هذه النسخة مطابقة تماماً للمنطق الموجود في ملف الويب (HTML) والصور:
//  - تستخدم النقاط 3D الخام (lSh, lEl, lWr) مباشرة من الموديل
//  - تطبق دالة alignBoneWorld مع mpToWorld للتحويل من MediaPipe إلى Three.js
//  - تستخدم findBoneChild لإيجاد العظمة الفرعية تلقائياً
// ═══════════════════════════════════════════════════════════════

import * as THREE from 'three';
import { GLTFLoader } from 'three/addons/loaders/GLTFLoader.js';
import { VRMLoaderPlugin, VRMHumanBoneName } from '@pixiv/three-vrm';

console.log('[VRM] v12 Direct MP Alignment');

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
        
        console.log(`[VRM] ✅ ${Object.keys(bonesMap).length} bones`);
        
        // إعداد وضعية التوقف (Idle Pose) كما في الويب
        setIdlePose();

        document.getElementById('loading').style.display = 'none';

        // ══ DEBUG CALIBRATION ══
        // نطبع مكان العظام الحقيقية في الـ world space
        // عشان نقارنها بـ mpToWorld ونظبط AVATAR_SCALE و AVATAR_CENTER_Y
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
        // قارن مع mpToWorld للكتف الأيسر (MediaPipe baseline ~0.30, 0.33, 0)
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
            if (window.chrome?.webview) window.chrome.webview.postMessage('ANIMATION_DONE');
        } else {
            const iA = Math.floor(raw);
            _applyInterp(animFrames[iA], animFrames[Math.min(iA+1, total-1)], raw - iA);
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
    // بناءً على feedback المستخدم:
    // X كان عريض جداً → قلصناه لـ 0.9
    // Y كان عالي جداً → قلصناه لـ 1.0 + خفضنا المركز لـ 0.65
    const SCALE_X = 0.9;
    const SCALE_Y = 1.0;
    const CENTER_Y = 0.65; // was 0.85 → lower to bring hands to chest level
    return new THREE.Vector3(
        (point[0] - 0.5) * SCALE_X,
        (0.5 - point[1]) * SCALE_Y + CENTER_Y,
        -point[2] * SCALE_X
    );
}

function findBoneChild(bone) {
    if (!bone) return null;
    // ابحث عن أول طفل هو عظمة حقيقية في VRM
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

    // Swing-only rotation: الـ minimal arc بين currentDir و targetDir
    // هذا يمنع الـ twist حول محور العظمة
    const swingQ = new THREE.Quaternion().setFromUnitVectors(currentDir, targetDir);

    const currentWorldQ = new THREE.Quaternion();
    bone.getWorldQuaternion(currentWorldQ);
    const newWorldQ = swingQ.multiply(currentWorldQ);

    if (bone.parent) {
        const parentWorldQ = new THREE.Quaternion();
        bone.parent.getWorldQuaternion(parentWorldQ);
        bone.quaternion.copy(parentWorldQ.clone().invert().multiply(newWorldQ));
    } else {
        bone.quaternion.copy(newWorldQ);
    }
    bone.updateMatrixWorld(true);

    // ── Anti-Twist: إزالة الـ twist حول محور العظمة ──
    // نضمن إن محور الرفع (Y) للعظمة يبقى قريب من فوق
    _removeTwist(bone, targetDir);
}

// ── Anti-Twist: إزالة الـ Twist حول محور العظمة ──
// يضمن إن الـ palm تواجه الأمام وما فيش دوران مرسوم
function _removeTwist(bone, boneAxis) {
    const boneWorldQ = new THREE.Quaternion();
    bone.getWorldQuaternion(boneWorldQ);

    // الـ local Y axis بعد الدوران
    const boneUp = new THREE.Vector3(0, 1, 0).applyQuaternion(boneWorldQ);

    // نسقط boneUp على المستوى العمودي على boneAxis
    const dot = boneUp.dot(boneAxis);
    boneUp.addScaledVector(boneAxis, -dot).normalize();
    if (boneUp.lengthSq() < 0.001) return; // singularity

    // الـ desired up: عمودي على boneAxis في اتجاه العالم
    const worldUp = new THREE.Vector3(0, 0, 1); // ناحية الكاميرا = الأمام
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

function _snapshot() {
    const ARMS = [VRMHumanBoneName.LeftUpperArm, VRMHumanBoneName.RightUpperArm,
                  VRMHumanBoneName.LeftLowerArm,  VRMHumanBoneName.RightLowerArm];
    for (const name of ARMS) {
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

    _applyFrame({
        lSh: interpPt(dA.lSh, dB.lSh), lEl: interpPt(dA.lEl, dB.lEl), lWr: interpPt(dA.lWr, dB.lWr),
        rSh: interpPt(dA.rSh, dB.rSh), rEl: interpPt(dA.rEl, dB.rEl), rWr: interpPt(dA.rWr, dB.rWr)
    });
}

// ── PUBLIC API ──
window.playAnimation = function(jsonStr) {
    if (!vrm) { console.warn('[VRM] Not loaded'); return; }
    try {
        const frames = JSON.parse(jsonStr);
        if (!Array.isArray(frames) || !frames.length) return;
        isReturning = false;
        animFrames  = frames;
        animStart   = performance.now();
        isAnimating = true;
        console.log(`[VRM] 🎬 ${frames.length} frames (v12 Direct MP)`);
    } catch (e) { console.error('[VRM]', e); }
};

window.applyRotations = function(jsonStr) {
    if (!vrm) return;
    try { _applyFrame(JSON.parse(jsonStr)); } catch (e) { console.error('[VRM]', e); }
};

window.stopAnimation = function() {
    isAnimating = false;
    isReturning = false;
    if (vrm) resetToIdle();
};

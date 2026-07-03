import os
# تقليل رسائل TensorFlow - لازم يكون قبل أي import لـ TensorFlow
os.environ['TF_CPP_MIN_LOG_LEVEL'] = '3'

import io
import tempfile
import urllib.parse
import numpy as np
import pandas as pd
import tensorflow as tf
from PIL import Image, ImageSequence
from fastapi import FastAPI, File, UploadFile, Query
from fastapi.responses import StreamingResponse
from fastapi.middleware.cors import CORSMiddleware
import cv2

import mediapipe as mp
mp_holistic = mp.solutions.holistic

from fastapi.staticfiles import StaticFiles

app = FastAPI()

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_methods=["*"],
    allow_headers=["*"],
)

# ── خدمة ملفات الأفاتار ───────────────────────────────────────
if os.path.exists("static"):
    app.mount("/static", StaticFiles(directory="static", html=True), name="static")


# ── إعدادات ثابتة ──────────────────────────────────────────────
SEQUENCE_LENGTH = 30
NUM_FEATURES = 1662  # pose(33*4) + face(468*3) + lh(21*3) + rh(21*3)

# ── تحميل الموديلات والبيانات ────────────────────────────────────
sign_to_text_model = tf.keras.models.load_model("best_model.h5", compile=False)
text_to_sign_model = tf.keras.models.load_model("word_to_sign_model.h5", compile=False)
labels_df = pd.read_excel("KARSL-100_Labels (1).xlsx")
actions = np.array(labels_df['Sign-Arabic'].tolist())
NUM_CLASSES = len(actions)  # 100

print("[Startup] Models loaded successfully!")

# ═══════════════════════════════════════════════════════════════════
#  DIRECTION-VECTOR IK (axis-agnostic, no bone-roll issues)
#  
#  Instead of computing angles (Z-rotation only), we send normalized
#  2D direction vectors for each limb. The frontend uses
#  Quaternion.setFromUnitVectors() which works regardless of bone roll.
# ═══════════════════════════════════════════════════════════════════
import math

WORD_AMP  = 5.0
FRAME_AMP = 4.0

def _extract_dirs(frame):
    """
    Extract limb direction vectors from one frame.
    Upper arms: WORLD direction (shoulder→elbow)
    Lower arms: LOCAL direction relative to upper arm (so rotation is in parent space)
    """
    def pxy(idx): return float(frame[idx*4]), float(frame[idx*4+1])
    
    lsh = pxy(11); rsh = pxy(12)
    lel = pxy(13); rel = pxy(14)
    lwr = pxy(15); rwr = pxy(16)
    
    def norm2d(ax, ay, bx, by):
        dx, dy = bx - ax, -(by - ay)
        mag = math.sqrt(dx*dx + dy*dy) or 1e-6
        return dx/mag, dy/mag
    
    def rotate_by_inverse(dir_x, dir_y, ref_x, ref_y):
        """Rotate dir into ref's local frame (multiply by inverse of ref rotation)."""
        # ref rotation angle = atan2(ref_y, ref_x)
        # inverse rotation = -angle → cos(-a)=cos(a), sin(-a)=-sin(a)
        cos_a = ref_x   # cos(atan2(y,x)) = x/|v| = x (since normalized)
        sin_a = -ref_y   # -sin(atan2(y,x)) = -y
        lx = dir_x * cos_a - dir_y * sin_a
        ly = dir_x * sin_a + dir_y * cos_a
        return lx, ly
    
    # Upper arm world directions
    l_up = norm2d(*lsh, *lel)
    r_up = norm2d(*rsh, *rel)
    
    # Lower arm world directions
    l_lo_world = norm2d(*lel, *lwr)
    r_lo_world = norm2d(*rel, *rwr)
    
    # Convert lower arm to LOCAL space (relative to upper arm direction)
    # In T-Pose local space: (1,0) = straight extension, no bend
    l_lo_local = rotate_by_inverse(*l_lo_world, *l_up)
    r_lo_local = rotate_by_inverse(*r_lo_world, *r_up)
    
    return {
        'lUp': l_up, 'rUp': r_up,
        'lLo': l_lo_local, 'rLo': r_lo_local,
    }

# Pre-compute baseline directions AND baseline 3D points
print("[Startup] Computing baseline directions...")
_all_preds = []
for _i in range(NUM_CLASSES):
    _oh = np.zeros((1, NUM_CLASSES), dtype=np.float32)
    _oh[0, _i] = 1.0
    _all_preds.append(text_to_sign_model.predict(_oh, verbose=0)[0])
_all_preds = np.array(_all_preds)
_baseline_raw = _all_preds.mean(axis=0)
del _all_preds

BASELINE_DIRS = [_extract_dirs(_baseline_raw[f]) for f in range(30)]

# Baseline 3D positions for each key joint (per frame)
def _baseline_pt3(frame, idx):
    i = idx * 4
    return [float(frame[i]), float(frame[i+1]), float(frame[i+2])]

BASELINE_PTS = [
    {k: _baseline_pt3(_baseline_raw[f], idx)
     for k, idx in [('lSh',11),('rSh',12),('lEl',13),('rEl',14),('lWr',15),('rWr',16)]}
    for f in range(30)
]

# Per-axis amplification — based on user feedback:
# X too wide (1.6 instead of 3.5), Y too high (0.9 instead of 3.5)
POINT_AMP_X = 1.6   # horizontal spread
POINT_AMP_Y = 0.9   # vertical movement (keep small to prevent hands going to neck)
POINT_AMP_Z = 1.0   # depth

def _amplify_pt3(cur, base, amp=None):
    """Amplify per-axis deviation of cur from base."""
    return [
        base[0] + (cur[0] - base[0]) * POINT_AMP_X,
        base[1] + (cur[1] - base[1]) * POINT_AMP_Y,
        base[2] + (cur[2] - base[2]) * POINT_AMP_Z,
    ]

def _amplify_dir(cur_dx, cur_dy, base_dx, base_dy, amp):
    """Amplify the delta between cur and base direction."""
    ddx = cur_dx - base_dx
    ddy = cur_dy - base_dy
    new_dx = base_dx + ddx * amp
    new_dy = base_dy + ddy * amp
    mag = math.sqrt(new_dx*new_dx + new_dy*new_dy) or 1e-6
    return new_dx/mag, new_dy/mag

def _extract_hand_joints(frame, hand_offset):
    """
    Extract 21 hand joint 3D positions from keypoints.
    hand_offset: 1536 for left hand, 1599 for right hand.
    Returns list of 21 [x, y, z] points.
    """
    joints = []
    for j in range(21):
        base = hand_offset + j * 3
        x = float(frame[base])
        y = float(frame[base + 1])
        z = float(frame[base + 2])
        joints.append([x, y, z])
    return joints


def _hand_has_data(joints):
    """Check if hand landmarks contain actual data (not all zeros)."""
    for pt in joints:
        if abs(pt[0]) > 1e-6 or abs(pt[1]) > 1e-6 or abs(pt[2]) > 1e-6:
            return True
    return False


def _smooth_hand_sequence(all_frames_hands, key, window=5, sigma=1.0):
    """
    Temporal Gaussian smoothing for finger positions across frames.
    Reduces jerkiness while preserving distinct handshapes for finger-spelling.
    
    window: number of frames to consider (odd number preferred)
    sigma: Gaussian standard deviation (lower = sharper, higher = smoother)
    """
    n_frames = len(all_frames_hands)
    if n_frames < 2:
        return
    
    half = window // 2
    # Pre-compute Gaussian weights
    weights = []
    for i in range(-half, half + 1):
        w = math.exp(-0.5 * (i / sigma) ** 2)
        weights.append(w)
    
    # Smooth each joint independently
    for joint_idx in range(21):
        for coord in range(3):
            # Collect original values
            original = []
            for f in range(n_frames):
                hand_data = all_frames_hands[f].get(key)
                if hand_data and len(hand_data) > joint_idx:
                    original.append(hand_data[joint_idx][coord])
                else:
                    original.append(0.0)
            
            # Apply weighted average
            smoothed = []
            for f in range(n_frames):
                wsum = 0.0
                vsum = 0.0
                for k, w in enumerate(weights):
                    src = f + k - half
                    if 0 <= src < n_frames:
                        vsum += original[src] * w
                        wsum += w
                if wsum > 0:
                    smoothed.append(vsum / wsum)
                else:
                    smoothed.append(original[f])
            
            # Write back
            for f in range(n_frames):
                hand_data = all_frames_hands[f].get(key)
                if hand_data and len(hand_data) > joint_idx:
                    hand_data[joint_idx][coord] = smoothed[f]


def _apply_procedural_splay(joints):
    """
    Procedurally splays the fingers. Works for both hands.
    joints: list of 21 [x, y, z] representing hand landmarks.
    Modifies joints in place.
    """
    if not _hand_has_data(joints):
        return

    pts = np.array(joints, dtype=np.float32)
    
    p0 = pts[0]
    p5 = pts[5]
    p17 = pts[17]
    
    forward = ((p5 + p17) / 2.0) - p0
    n_forward = np.linalg.norm(forward)
    if n_forward < 1e-6:
        return
    forward /= n_forward
    
    # Vector pointing from Little to Index
    to_index = p5 - p17
    n_to_index = np.linalg.norm(to_index)
    if n_to_index < 1e-6:
        return
    to_index /= n_to_index
    
    up = np.cross(forward, to_index)
    n_up = np.linalg.norm(up)
    if n_up < 1e-6:
        return
    up /= n_up
    
    # Positive angle = moves towards Index. Negative angle = moves towards Little.
    angles = {
        'thumb': 25.0,
        'index': 15.0,
        'middle': 0.0,
        'ring': -15.0,
        'little': -30.0
    }
    
    def rotate_point_around_axis(point, origin, axis, theta_deg):
        theta = np.radians(theta_deg)
        axis = axis / np.linalg.norm(axis)
        v = point - origin
        v_rot = v * np.cos(theta) + np.cross(axis, v) * np.sin(theta) + axis * np.dot(axis, v) * (1 - np.cos(theta))
        return origin + v_rot

    chains = {
        'thumb': [1, 2, 3, 4],
        'index': [5, 6, 7, 8],
        'middle': [9, 10, 11, 12],
        'ring': [13, 14, 15, 16],
        'little': [17, 18, 19, 20]
    }
    
    for finger_name, indices in chains.items():
        angle = angles[finger_name]
        if angle == 0.0:
            continue
            
        # Rotate around the base joint of each finger
        base_idx = indices[0]
        origin = pts[base_idx] if finger_name != 'thumb' else pts[0]
        
        for idx in indices:
            pts[idx] = rotate_point_around_axis(pts[idx], origin, up, angle)
            
    for i in range(21):
        joints[i][0] = float(pts[i][0])
        joints[i][1] = float(pts[i][1])
        joints[i][2] = float(pts[i][2])


def compute_rotations(predicted_seq):
    """
    Compute direction vectors for each bone per frame.
    Upper arms: world direction (for setFromUnitVectors vs restDir)
    Lower arms: local direction relative to upper arm parent
    Also extracts hand joint positions for finger animation.
    """
    result = []
    
    for f_idx in range(len(predicted_seq)):
        frame = predicted_seq[f_idx]
        cur = _extract_dirs(frame)
        base = BASELINE_DIRS[min(f_idx, len(BASELINE_DIRS)-1)]
        
        # Upper arms: amplify word delta
        l_up = _amplify_dir(*cur['lUp'], *base['lUp'], WORD_AMP)
        r_up = _amplify_dir(*cur['rUp'], *base['rUp'], WORD_AMP)
        
        # Lower arms: already in local space, amplify slightly
        l_lo = _amplify_dir(*cur['lLo'], *base['lLo'], 2.0)
        r_lo = _amplify_dir(*cur['rLo'], *base['rLo'], 2.0)
        
        # 3D raw pose points → amplified around baseline
        def pt3(idx):
            i = idx * 4
            return [float(frame[i]), float(frame[i+1]), float(frame[i+2])]

        bpts = BASELINE_PTS[min(f_idx, len(BASELINE_PTS)-1)]

        # Extract hand joints (21 landmarks each)
        lh_joints = _extract_hand_joints(frame, 1536)  # left hand offset
        rh_joints = _extract_hand_joints(frame, 1599)  # right hand offset

        frame_data = {
            'lUpX': l_up[0], 'lUpY': l_up[1],
            'rUpX': r_up[0], 'rUpY': r_up[1],
            'lLoX': l_lo[0], 'lLoY': l_lo[1],
            'rLoX': r_lo[0], 'rLoY': r_lo[1],
            'lSh': _amplify_pt3(pt3(11), bpts['lSh']),
            'rSh': _amplify_pt3(pt3(12), bpts['rSh']),
            'lEl': _amplify_pt3(pt3(13), bpts['lEl']),
            'rEl': _amplify_pt3(pt3(14), bpts['rEl']),
            'lWr': _amplify_pt3(pt3(15), bpts['lWr']),
            'rWr': _amplify_pt3(pt3(16), bpts['rWr']),
        }
        
        # Include hand data only if it has actual content
        if _hand_has_data(lh_joints):
            frame_data['lHand'] = lh_joints
        if _hand_has_data(rh_joints):
            frame_data['rHand'] = rh_joints

        result.append(frame_data)

    
    # Frame-to-frame amplification for upper arms
    if len(result) > 1:
        first = result[0]
        for f_idx in range(1, len(result)):
            for prefix in ['lUp', 'rUp']:
                cx, cy = result[f_idx][prefix+'X'], result[f_idx][prefix+'Y']
                bx, by = first[prefix+'X'], first[prefix+'Y']
                ax, ay = _amplify_dir(cx, cy, bx, by, FRAME_AMP)
                result[f_idx][prefix+'X'] = ax
                result[f_idx][prefix+'Y'] = ay
    
    # Apply temporal smoothing to finger data
    # Uses Gaussian filter: window=5, sigma=1.2 for fluid motion
    # while still preserving distinct handshapes for finger-spelling
    _smooth_hand_sequence(result, 'lHand', window=5, sigma=1.2)
    _smooth_hand_sequence(result, 'rHand', window=5, sigma=1.2)
    
    return result

print("[Startup] Baseline computed! Ready.")


# ── استخراج الـ Keypoints (بنفس ترتيب التدريب بالظبط) ─────────
def extract_keypoints(results):
    """
    استخراج النقاط من MediaPipe Holistic بنفس الترتيب اللي اتدرب بيه الموديل:
    Pose (33×4=132) + Face (468×3=1404) + Left Hand (21×3=63) + Right Hand (21×3=63) = 1662
    """
    pose = np.array([[res.x, res.y, res.z, res.visibility]
                     for res in results.pose_landmarks.landmark]).flatten() \
        if results.pose_landmarks else np.zeros(33 * 4)

    face = np.array([[res.x, res.y, res.z]
                     for res in results.face_landmarks.landmark]).flatten() \
        if results.face_landmarks else np.zeros(468 * 3)

    lh = np.array([[res.x, res.y, res.z]
                   for res in results.left_hand_landmarks.landmark]).flatten() \
        if results.left_hand_landmarks else np.zeros(21 * 3)

    rh = np.array([[res.x, res.y, res.z]
                   for res in results.right_hand_landmarks.landmark]).flatten() \
        if results.right_hand_landmarks else np.zeros(21 * 3)

    return np.concatenate([pose, face, lh, rh])


def mediapipe_detect(image_rgb, holistic):
    """
    يعالج صورة RGB واحدة بـ MediaPipe Holistic
    بنفس الطريقة اللي في التدريب: writeable=False للأداء
    """
    image_rgb = np.ascontiguousarray(image_rgb)
    image_rgb.flags.writeable = False
    results = holistic.process(image_rgb)
    image_rgb.flags.writeable = True
    return results


def process_gif_frames(gif_bytes):
    """
    قراءة فريمات GIF باستخدام PIL ثم تحويلها لـ RGB numpy arrays
    ومعالجتها بـ MediaPipe Holistic
    """
    gif = Image.open(io.BytesIO(gif_bytes))
    sequence = []

    with mp_holistic.Holistic(
        min_detection_confidence=0.5,
        min_tracking_confidence=0.5
    ) as holistic:

        for i, frame in enumerate(ImageSequence.Iterator(gif)):
            if i >= SEQUENCE_LENGTH:
                break

            # تحويل لـ RGB (الفريمات ممكن تكون P, RGBA, L, etc.)
            frame_rgb = frame.convert("RGB")

            # تحويل لـ numpy array والتأكد إنه uint8 + contiguous
            frame_np = np.array(frame_rgb, dtype=np.uint8)

            # !! المفتاح: نفس المعالجة بتاعة التدريب
            results = mediapipe_detect(frame_np, holistic)
            keypoints = extract_keypoints(results)
            sequence.append(keypoints)

    return pad_or_trim_sequence(sequence)


def process_video_frames(video_path):
    """
    قراءة فريمات فيديو عادي بـ OpenCV
    ثم استخراج keypoints من كل فريم باستخدام MediaPipe Holistic
    """
    cap = cv2.VideoCapture(video_path)
    sequence = []

    with mp_holistic.Holistic(
        min_detection_confidence=0.5,
        min_tracking_confidence=0.5
    ) as holistic:

        frame_count = 0
        while cap.isOpened() and frame_count < SEQUENCE_LENGTH:
            ret, frame = cap.read()
            if not ret:
                break

            # تحويل BGR → RGB (OpenCV يقرأ BGR)
            frame_rgb = cv2.cvtColor(frame, cv2.COLOR_BGR2RGB)

            results = mediapipe_detect(frame_rgb, holistic)
            keypoints = extract_keypoints(results)
            sequence.append(keypoints)
            frame_count += 1

    cap.release()
    return pad_or_trim_sequence(sequence)


def pad_or_trim_sequence(sequence):
    """
    توحيد الطول لـ SEQUENCE_LENGTH فريم:
    - Padding بأصفار لو قصير
    - قص لو طويل
    """
    if len(sequence) == 0:
        sequence = [np.zeros(NUM_FEATURES)] * SEQUENCE_LENGTH
    elif len(sequence) < SEQUENCE_LENGTH:
        while len(sequence) < SEQUENCE_LENGTH:
            sequence.append(np.zeros(NUM_FEATURES))
    elif len(sequence) > SEQUENCE_LENGTH:
        sequence = sequence[:SEQUENCE_LENGTH]

    return np.array(sequence, dtype=np.float32)


# ══════════════════════════════════════════════════════════════════
#  API Endpoints
# ══════════════════════════════════════════════════════════════════

@app.get("/")
def home():
    return {"message": "Recognition API is Live on HF!"}


@app.post("/sign-to-text")
async def sign_to_text(file: UploadFile = File(...)):
    """
    يستقبل ملف GIF أو فيديو (mp4, avi, webm, mov)
    ويرجع الإشارة المتوقعة مع نسبة الثقة
    """
    try:
        contents = await file.read()
        filename = (file.filename or "").lower()

        # تحديد نوع الملف ومعالجته
        if filename.endswith(".gif"):
            sequence = process_gif_frames(contents)
        else:
            # فيديو عادي (mp4, avi, webm, mov, etc.)
            ext = os.path.splitext(filename)[1] or ".mp4"
            with tempfile.NamedTemporaryFile(suffix=ext, delete=False) as tmp:
                tmp.write(contents)
                tmp_path = tmp.name
            try:
                sequence = process_video_frames(tmp_path)
            finally:
                os.unlink(tmp_path)

        # عدد الفريمات الفعلية (مش الـ padding)
        non_zero_frames = int(np.count_nonzero(sequence.sum(axis=1)))

        # التحقق من الشكل
        assert sequence.shape == (SEQUENCE_LENGTH, NUM_FEATURES), \
            f"Shape mismatch: expected ({SEQUENCE_LENGTH}, {NUM_FEATURES}), got {sequence.shape}"

        # ── التوقع ──────────────────────────────────────────────
        input_data = np.expand_dims(sequence, axis=0)  # (1, 30, 1662)
        res = sign_to_text_model.predict(input_data, verbose=0)[0]

        predicted_idx = int(np.argmax(res))
        confidence = float(np.max(res))

        # ── أعلى 3 توقعات ────────────────────────────────────────
        top3_idx = np.argsort(res)[-3:][::-1]
        top3 = [
            {"word": str(actions[i]), "confidence": f"{float(res[i]) * 100:.2f}%"}
            for i in top3_idx
        ]

        return {
            "status": "success",
            "predicted_word": str(actions[predicted_idx]),
            "confidence": f"{confidence * 100:.2f}%",
            "top3_predictions": top3,
            "frames_processed": non_zero_frames,
            "total_frames": SEQUENCE_LENGTH,
        }

    except Exception as e:
        import traceback
        return {
            "status": "error",
            "message": str(e),
            "traceback": traceback.format_exc()
        }


# ══════════════════════════════════════════════════════════════════
#  Text-to-Sign: تحويل كلمة لـ GIF لغة إشارة
# ══════════════════════════════════════════════════════════════════

# ── MediaPipe Holistic connections للرسم ─────────────────────────
# ترتيب الـ keypoints في الـ 1662 features:
# [0:132]    = Pose   (33 نقطة × 4 قيم: x,y,z,visibility)
# [132:1536] = Face   (468 نقطة × 3 قيم: x,y,z)
# [1536:1599]= Left Hand  (21 نقطة × 3 قيم: x,y,z)
# [1599:1662]= Right Hand (21 نقطة × 3 قيم: x,y,z)

# وصلات الهيكل العظمي (Pose) - أرقام النقاط بتاعة MediaPipe
POSE_CONNECTIONS = [
    (11, 12), (11, 13), (13, 15), (12, 14), (14, 16),  # أكتاف وأذرع
    (11, 23), (12, 24), (23, 24),                        # جذع
    (23, 25), (25, 27), (24, 26), (26, 28),              # أرجل
]

# وصلات اليد (Hand)
HAND_CONNECTIONS = [
    (0, 1), (1, 2), (2, 3), (3, 4),       # إبهام
    (0, 5), (5, 6), (6, 7), (7, 8),       # سبابة
    (0, 9), (9, 10), (10, 11), (11, 12),  # وسطى
    (0, 13), (13, 14), (14, 15), (15, 16),# بنصر
    (0, 17), (17, 18), (18, 19), (19, 20),# خنصر
    (5, 9), (9, 13), (13, 17),            # راحة اليد
]


def parse_keypoints(keypoints_1662):
    """
    يفصل الـ 1662 feature لـ 4 مجموعات نقاط:
    pose, face, left_hand, right_hand
    كل نقطة بتكون (x, y) بين 0 و 1
    """
    # Pose: 33 نقطة × 4 (x, y, z, visibility)
    pose_flat = keypoints_1662[0:132]
    pose_points = pose_flat.reshape(33, 4)[:, :2]  # ناخذ x, y بس

    # Face: 468 نقطة × 3 (x, y, z)
    face_flat = keypoints_1662[132:1536]
    face_points = face_flat.reshape(468, 3)[:, :2]  # ناخذ x, y بس

    # Left Hand: 21 نقطة × 3 (x, y, z)
    lh_flat = keypoints_1662[1536:1599]
    lh_points = lh_flat.reshape(21, 3)[:, :2]

    # Right Hand: 21 نقطة × 3 (x, y, z)
    rh_flat = keypoints_1662[1599:1662]
    rh_points = rh_flat.reshape(21, 3)[:, :2]

    return pose_points, face_points, lh_points, rh_points


def draw_keypoints_frame(keypoints_1662, width=400, height=400):
    """
    يرسم الـ keypoints على صورة سوداء ويرجع numpy array (RGB)
    """
    frame = np.zeros((height, width, 3), dtype=np.uint8)
    pose, face, lh, rh = parse_keypoints(keypoints_1662)

    def to_pixel(point):
        """يحول نقطة (0-1) لبكسل"""
        x = int(point[0] * width)
        y = int(point[1] * height)
        return (x, y)

    def is_valid(point):
        """يتحقق إن النقطة مش صفر (يعني موجودة)"""
        return not (abs(point[0]) < 1e-6 and abs(point[1]) < 1e-6)

    # ── رسم الوجه (نقاط صغيرة بيضاء) ────────────────────────────
    for pt in face:
        if is_valid(pt):
            px = to_pixel(pt)
            cv2.circle(frame, px, 1, (200, 200, 200), -1)

    # ── رسم الهيكل العظمي (Pose) ─────────────────────────────────
    # رسم الخطوط
    for (i, j) in POSE_CONNECTIONS:
        if i < len(pose) and j < len(pose):
            if is_valid(pose[i]) and is_valid(pose[j]):
                cv2.line(frame, to_pixel(pose[i]), to_pixel(pose[j]),
                         (100, 255, 100), 2)
    # رسم النقاط
    for pt in pose:
        if is_valid(pt):
            cv2.circle(frame, to_pixel(pt), 4, (0, 255, 0), -1)

    # ── رسم اليد اليسرى (أزرق) ───────────────────────────────────
    for (i, j) in HAND_CONNECTIONS:
        if i < len(lh) and j < len(lh):
            if is_valid(lh[i]) and is_valid(lh[j]):
                cv2.line(frame, to_pixel(lh[i]), to_pixel(lh[j]),
                         (255, 150, 50), 2)
    for pt in lh:
        if is_valid(pt):
            cv2.circle(frame, to_pixel(pt), 3, (255, 200, 100), -1)

    # ── رسم اليد اليمنى (أحمر) ───────────────────────────────────
    for (i, j) in HAND_CONNECTIONS:
        if i < len(rh) and j < len(rh):
            if is_valid(rh[i]) and is_valid(rh[j]):
                cv2.line(frame, to_pixel(rh[i]), to_pixel(rh[j]),
                         (50, 150, 255), 2)
    for pt in rh:
        if is_valid(pt):
            cv2.circle(frame, to_pixel(pt), 3, (100, 200, 255), -1)

    return frame


def keypoints_to_gif(sequence, width=400, height=400, duration=100):
    """
    يحول sequence من keypoints (30, 1662) لـ GIF متحرك
    ويرجع bytes buffer
    """
    pil_frames = []
    for keypoints in sequence:
        frame_bgr = draw_keypoints_frame(keypoints, width, height)
        frame_rgb = cv2.cvtColor(frame_bgr, cv2.COLOR_BGR2RGB)
        pil_frames.append(Image.fromarray(frame_rgb))

    buf = io.BytesIO()
    pil_frames[0].save(
        buf, format='GIF', save_all=True,
        append_images=pil_frames[1:],
        duration=duration,  # مدة كل فريم بالمللي ثانية
        loop=0  # يتكرر للأبد
    )
    buf.seek(0)
    return buf


@app.post("/text-to-sign")
async def text_to_sign(word: str = Query(..., description="الكلمة العربية المراد تحويلها لإشارة")):
    """
    يستقبل كلمة عربية ويرجع GIF متحرك يوضح الإشارة
    """
    try:
        # ── البحث عن الكلمة في القائمة ────────────────────────────
        word_stripped = word.strip()
        word_idx = None

        for i, action in enumerate(actions):
            if action.strip() == word_stripped:
                word_idx = i
                break

        if word_idx is None:
            return {
                "status": "error",
                "message": f"الكلمة '{word}' مش موجودة في قائمة الإشارات المتاحة",
                "available_signs": [str(a) for a in actions],
            }

        # ── تجهيز الـ Input (One-Hot Vector) ──────────────────────
        one_hot = np.zeros((1, NUM_CLASSES), dtype=np.float32)
        one_hot[0, word_idx] = 1.0

        # ── توليد الـ Keypoints ───────────────────────────────────
        predicted_sequence = text_to_sign_model.predict(one_hot, verbose=0)[0]  # (30, 1662)

        # ── تحويل لـ GIF ─────────────────────────────────────────
        gif_buffer = keypoints_to_gif(predicted_sequence)

        # اسم الملف بـ URL encoding عشان يدعم العربي
        safe_name = urllib.parse.quote(word_stripped)
        return StreamingResponse(
            gif_buffer,
            media_type="image/gif",
            headers={
                "Content-Disposition": f"inline; filename*=UTF-8''{safe_name}.gif"
            }
        )

    except Exception as e:
        import traceback
        return {
            "status": "error",
            "message": str(e),
            "traceback": traceback.format_exc()
        }

@app.post("/text-to-sign-points")
async def text_to_sign_points(word: str = Query(...)):
    """
    يستقبل كلمة ويرجع النقاط الخاصة بحركة لغة الإشارة كـ JSON (30 فريم * 1662 نقطة)
    بدون تحويلها لـ GIF.
    """
    try:
        word_stripped = word.strip()
        if word_stripped not in actions:
            return {
                "status": "error",
                "message": f"الكلمة '{word}' مش موجودة في قائمة الإشارات المتاحة",
                "available_signs": [str(a) for a in actions],
            }

        word_idx = np.where(actions == word_stripped)[0][0]

        # ── تجهيز الـ Input (One-Hot Vector) ──────────────────────
        one_hot = np.zeros((1, NUM_CLASSES), dtype=np.float32)
        one_hot[0, word_idx] = 1.0

        # ── توليد الـ Keypoints ───────────────────────────────────
        predicted_sequence = text_to_sign_model.predict(one_hot, verbose=0)[0]  # (30, 1662)

        # تحويل المصفوفة لـ list عشان JSON (بدون تلاعب في الإحداثيات)
        points_list = predicted_sequence.tolist()
        
        # ── حساب زوايا العظام مسبقاً (Python-side IK) ──────────
        rotations = compute_rotations(predicted_sequence)

        # ── DEBUG: Print first 3 frames to verify data changes per word ──
        print(f"[DEBUG] Word: '{word_stripped}', Frames: {len(rotations)}")
        for i in range(min(3, len(rotations))):
            f = rotations[i]
            lsh = f.get('lSh', 'N/A')
            rsh = f.get('rSh', 'N/A')
            has_lh = 'lHand' in f
            has_rh = 'rHand' in f
            print(f"[DEBUG]   Frame {i}: lSh={lsh}, rSh={rsh}, lHand={has_lh}, rHand={has_rh}")
            # Check for NaN in hand data
            if has_lh:
                for j, pt in enumerate(f['lHand']):
                    if any(math.isnan(v) for v in pt):
                        print(f"[DEBUG]   ⚠️ NaN in lHand joint {j}: {pt}")
                        f['lHand'][j] = [0.0, 0.0, 0.0]
            if has_rh:
                for j, pt in enumerate(f['rHand']):
                    if any(math.isnan(v) for v in pt):
                        print(f"[DEBUG]   ⚠️ NaN in rHand joint {j}: {pt}")
                        f['rHand'][j] = [0.0, 0.0, 0.0]

        # ── تطبيق مباعدة الأصابع إجرائياً لإشارة "هيكل عظمي" ──
        if "هيكل" in word_stripped or "Skeleton" in word_stripped:
            for frame in rotations:
                if 'lHand' in frame:
                    _apply_procedural_splay(frame['lHand'])
                if 'rHand' in frame:
                    _apply_procedural_splay(frame['rHand'])

        return {
            "status": "success",
            "word": word_stripped,
            "points": points_list,
            "rotations": rotations
        }

    except Exception as e:
        import traceback
        return {
            "status": "error",
            "message": str(e),
            "traceback": traceback.format_exc()
        }

@app.get("/api/quiz/question")
async def get_quiz_question():
    """
    يرجع سؤال عشوائي لاختبار لغة الإشارة:
    - الكلمة الصحيحة
    - 4 خيارات عشوائية (مع الكلمة الصحيحة)
    - الإحداثيات/الدوران للـ Avatar (عشان يمثل الإشارة)
    """
    try:
        import random
        # 1. اختيار كلمة صحيحة عشوائياً
        correct_idx = random.randint(0, NUM_CLASSES - 1)
        correct_word = str(actions[correct_idx])

        # 2. اختيار 3 كلمات خاطئة عشوائياً
        wrong_indices = set()
        while len(wrong_indices) < 3:
            idx = random.randint(0, NUM_CLASSES - 1)
            if idx != correct_idx:
                wrong_indices.add(idx)
        
        choices = [correct_word] + [str(actions[i]) for i in wrong_indices]
        random.shuffle(choices)

        # 3. استخراج حركة الأفاتار للكلمة الصحيحة
        one_hot = np.zeros((1, NUM_CLASSES), dtype=np.float32)
        one_hot[0, correct_idx] = 1.0
        predicted_sequence = text_to_sign_model.predict(one_hot, verbose=0)[0]
        rotations = compute_rotations(predicted_sequence)

        return {
            "status": "success",
            "correct_word": correct_word,
            "choices": choices,
            "rotations": rotations
        }
    except Exception as e:
        import traceback
        return {
            "status": "error",
            "message": str(e),
            "traceback": traceback.format_exc()
        }

@app.get("/available-signs")
def available_signs():
    """
    يرجع قائمة بكل الإشارات المتاحة (100 إشارة)
    """
    return {
        "status": "success",
        "count": len(actions),
        "signs": [str(a) for a in actions],
    }


if __name__ == "__main__":
    import uvicorn
    uvicorn.run(app, host="0.0.0.0", port=7860)  # بورت 7860 هو الافتراضي لـ HF
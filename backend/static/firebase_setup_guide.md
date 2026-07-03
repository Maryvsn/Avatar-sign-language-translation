# 🔥 Cuppa — Firebase Setup Guide

## خطوات إعداد Firebase

### 1️⃣ إنشاء مشروع Firebase

1. افتح [Firebase Console](https://console.firebase.google.com/)
2. اضغط **Add Project** واسميه **Cuppa**
3. اختياري: فعّل Google Analytics

---

### 2️⃣ تفعيل Authentication

1. من القائمة اليسرى: **Authentication** → **Get Started**
2. اختار **Email/Password** → فعّله → **Save**

---

### 3️⃣ تفعيل Firestore Database

1. من القائمة: **Firestore Database** → **Create Database**
2. اختار **Start in test mode** (مؤقتًا للتطوير)
3. اختار أقرب Region

---

### 4️⃣ إضافة Android App

1. من Project Overview: اضغط Android icon
2. **Android package name**: `com.cuppa.cuppa`
3. **App nickname**: Cuppa
4. نزّل ملف `google-services.json`
5. حطه في: `android/app/google-services.json`

---

### 5️⃣ توليد `firebase_options.dart` (الطريقة الأسهل)

```powershell
# تثبيت FlutterFire CLI
dart pub global activate flutterfire_cli

# توليد ملف الإعداد تلقائيًا
cd C:\Cuppa
flutterfire configure
```

هذا الأمر سيولّد ملف `lib/firebase_options.dart` بشكل تلقائي بكل بياناتك.

---

### 6️⃣ تأكد من إعداد Android

#### `android/build.gradle` — أضف:
```gradle
classpath 'com.google.gms:google-services:4.4.2'
```

#### `android/app/build.gradle` — أضف في الأسفل:
```gradle
apply plugin: 'com.google.gms.google-services'
```

---

### 7️⃣ تشغيل التطبيق

```powershell
cd C:\Cuppa
flutter run
```

---

## 🔐 Firestore Security Rules (للـ Production)

```
rules_version = '2';
service cloud.firestore {
  match /databases/{database}/documents {
    match /users/{userId} {
      allow read, write: if request.auth != null && request.auth.uid == userId;
    }
  }
}
```

---

## 📁 هيكل المشروع

```
cuppa/
├── lib/
│   ├── core/
│   │   ├── theme/
│   │   │   └── app_theme.dart        ← ألوان وخطوط التطبيق
│   │   └── constants/
│   │       └── app_strings.dart      ← كل نصوص التطبيق
│   ├── services/
│   │   └── auth_service.dart         ← Firebase Auth + Firestore
│   ├── providers/
│   │   └── auth_provider.dart        ← State Management
│   ├── screens/
│   │   ├── splash_screen.dart        ← شاشة البداية المتحركة
│   │   ├── login_screen.dart         ← شاشة تسجيل الدخول
│   │   ├── signup_screen.dart        ← شاشة إنشاء الحساب
│   │   └── home_screen.dart          ← الصفحة الرئيسية المحمية
│   ├── widgets/
│   │   ├── cuppa_button.dart         ← زرار مخصص مع Animation
│   │   ├── cuppa_text_field.dart     ← حقل نص مخصص
│   │   └── error_banner.dart         ← عرض رسائل الخطأ
│   ├── firebase_options.dart         ← ⚠️ يتولد تلقائيًا بـ flutterfire
│   └── main.dart                     ← نقطة البداية
├── android/
│   └── app/
│       └── google-services.json      ← ⚠️ تنزيله من Firebase Console
└── pubspec.yaml
```

---

## ✅ Features المنجزة

| Feature | Status |
|---------|--------|
| Splash Screen مع Animation | ✅ |
| Login مع Firebase Auth | ✅ |
| Signup مع Firebase Auth | ✅ |
| Home Screen محمية | ✅ |
| Validation على كل الحقول | ✅ |
| رسائل خطأ Firebase واضحة | ✅ |
| حفظ بيانات المستخدم في Firestore | ✅ (Bonus) |
| عرض الاسم في Home Screen | ✅ (Bonus) |
| تذكر حالة تسجيل الدخول | ✅ |
| Logout مع تأكيد | ✅ |
| تصميم Coffee Theme احترافي | ✅ |
| Google Fonts (Playfair + Inter) | ✅ |
| Micro-animations | ✅ |

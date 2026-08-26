<div align="center">

<img src="assets/icon/icon.png" alt="SchoolWay logo: bus inside a heart-shaped route with a map pin" width="140" />

<br/>

# SchoolWay

**Live school bus visibility for families, drivers, and staff**

[![Flutter](https://img.shields.io/badge/Flutter-02569B?style=for-the-badge&logo=flutter&logoColor=white)](https://flutter.dev/)
[![Dart](https://img.shields.io/badge/Dart-0175C2?style=for-the-badge&logo=dart&logoColor=white)](https://dart.dev/)
[![Firebase](https://img.shields.io/badge/Firebase-039BE5?style=for-the-badge&logo=Firebase&logoColor=white)](https://firebase.google.com/)
[![Google Maps](https://img.shields.io/badge/Google%20Maps-4285F4?style=for-the-badge&logo=googlemaps&logoColor=white)](https://mapsplatform.google.com/)

*Cross‑platform app · Real‑time fleet map · Roles for parent, driver, and admin*

<br/>

</div>

---

## Highlights

| Feature | Description |
| --- | --- |
| **Three experiences, one product** | Tailored home screens for **Parent**, **Driver**, and **Admin** with role‑based routing after sign‑in. |
| **Live fleet & traffic ETAs** | Real-time map views, bus telemetry, live GPS tracking, and server-calculated traffic ETAs via Google Routes API. |
| **Firebase backbone** | Authentication (Email/Password, Google Sign‑In), Cloud Firestore, Realtime Database, and Cloud Messaging (FCM). |
| **NFC student boarding** | Driver‑side NFC tag scanning (Android) with offline caching and automatic attendance synchronization. |
| **Bulk data & CSV tools** | Built-in CSV import/export wizards for quick fleet, student, user, and route provisioning. |
| **Offline‑ready UX** | Local persistent storage via **Hive** and offline command queues for uninterrupted operation during network drops. |

---

## Quick Start (Direct Debug & Run)

After cloning the repository, you can immediately run and debug the app:

### 1. Clone the repository
```bash
git clone https://github.com/ChaiBoonHong/schoolway-0428.git
cd schoolway-0428
```

### 2. Install dependencies
```bash
flutter pub get
```

### 3. Run on your target platform
```bash
# Run on connected Android device / emulator
flutter run -d android

# Run on Chrome / Web
flutter run -d chrome

# Run on Windows Desktop
flutter run -d windows
```

> [!NOTE]
> The repository includes pre-configured client development credentials so you can debug immediately. Follow the guide below to connect your own Firebase project and Google Maps Platform API keys.

---

## Configuration & Secrets Guide

This section explains how to obtain and configure all API keys, credentials, and environment secrets for full development, backend deployment, and production release.

```
┌─────────────────────────────────────────────────────────────────────────┐
│                             SECRET INVENTORY                            │
├─────────────────────────┬─────────────────────────────┬─────────────────┤
│ Secret / Credential     │ Target Location             │ Required For    │
├─────────────────────────┼─────────────────────────────┼─────────────────┤
│ Firebase Client Config  │ lib/firebase_options.dart   │ Auth / Database │
│ Google Services JSON    │ android/app/google-services │ Android Firebase│
│ Google Service Info     │ ios/Runner/GoogleService    │ iOS Firebase    │
│ FCM Web VAPID Key       │ lib/core/config.dart        │ Web Push Alerts │
│ Google Maps Android Key │ android/local.properties    │ Android Native  │
│ Google Routes API Key   │ Cloud Functions Secret Mgr  │ Traffic ETAs    │
│ Google Maps Web Key     │ GitHub Actions / web index  │ Web Map / CI    │
│ Firebase Service Acct   │ functions/serviceAccountKey │ Admin Scripts   │
│ Android Keystore & Props│ android/key.properties      │ Release APK/AAB │
│ Cloudflare Token & ID   │ GitHub Actions Secrets      │ Web CI/CD Host  │
└─────────────────────────┴─────────────────────────────┴─────────────────┘
```

---

### 1. Firebase Configuration

#### A. Create a Firebase Project
1. Open the [Firebase Console](https://console.firebase.google.com/) and click **Add project**.
2. Enable **Authentication** in the console:
   - Go to **Build** → **Authentication** → **Sign-in method**.
   - Enable **Email/Password** and **Google**.
3. Enable **Cloud Firestore**:
   - Go to **Build** → **Firestore Database** → **Create database**.
   - Select production or test mode in your desired region (e.g. `asia-southeast1`).
4. Enable **Cloud Storage** and **Cloud Messaging (FCM)**.

#### B. Generate FlutterFire Configuration
Install the [FlutterFire CLI](https://firebase.flutter.dev/docs/cli/) and run:
```bash
dart pub global activate flutterfire_cli
flutterfire configure
```
This automatically updates [lib/firebase_options.dart](file:///d:/UTAR/schoolway/lib/firebase_options.dart) and places `google-services.json` in `android/app/`.

#### C. Web Push (FCM VAPID Key)
1. In Firebase Console, go to **Project settings** (gear icon) → **Cloud Messaging** tab.
2. Scroll to **Web configuration** → **Web Push certificates** → Click **Generate key pair**.
3. Copy the public key string and paste it into [`lib/core/config.dart`](file:///d:/UTAR/schoolway/lib/core/config.dart):
   ```dart
   class AppConfig {
     static const String fcmWebVapidKey = 'YOUR_GENERATED_PUBLIC_VAPID_KEY';
   }
   ```

#### D. Firebase Admin Service Account (for local management scripts)
To run administrative maintenance scripts (e.g. database seeders or wipe scripts):
1. In Firebase Console, go to **Project settings** → **Service accounts** tab.
2. Click **Generate new private key** and download the JSON file.
3. Save it as `functions/serviceAccountKey.json` (this file is automatically gitignored).

---

### 2. Google Maps Platform API Keys

SchoolWay uses Google Maps Platform for native Android maps, Web maps, and server-side traffic-aware route geometry calculation.

#### A. Obtain Maps API Keys
1. Go to the [Google Cloud Console](https://console.cloud.google.com/).
2. Select your Firebase project (or create a linked Google Cloud project).
3. Navigate to **APIs & Services** → **Library** and enable:
   - **Maps SDK for Android**
   - **Maps JavaScript API**
   - **Routes API**
4. Navigate to **APIs & Services** → **Credentials** → **Create Credentials** → **API Key**.

#### B. Configure Android Maps Key
Create or edit `android/local.properties` (never committed to git) and add your Android Maps API key:
```properties
sdk.dir=C:\\Users\\YourUser\\AppData\\Local\\Android\\sdk
flutter.sdk=C:\\src\\flutter
MAPS_API_KEY=AIzaSyYourAndroidMapsApiKeyHere
```
*(Best practice: In Google Cloud Console, restrict this key to **Android apps** using your package name `com.schoolway.app` and SHA-1 fingerprint).*

#### C. Configure Server-Side Routes API Key (Cloud Functions)
The backend Cloud Functions compute traffic-aware ETAs without exposing your API key to clients:
1. In Google Cloud Console, create an API key restricted to the **Routes API**.
2. Store the secret in Google Cloud Secret Manager via Firebase CLI:
   ```bash
   cd functions
   firebase functions:secrets:set GOOGLE_ROUTES_API_KEY
   # When prompted, paste your Routes API key
   ```

---

### 3. Deploying Cloud Functions & Security Rules

To deploy the backend functions, Firestore rules, and database indexes:

```bash
# Install backend dependencies
cd functions
npm install

# Deploy security rules and indexes
firebase deploy --only firestore:rules,firestore:indexes

# Deploy Cloud Functions
firebase deploy --only functions
```

---

### 4. CI/CD GitHub Actions Secrets (Automated Deployment)

The automated deployment pipeline in [`.github/workflows/deploy-web.yml`](file:///d:/UTAR/schoolway/.github/workflows/deploy-web.yml) requires the following repository secrets to deploy to Cloudflare Workers and GitHub Pages:

Go to your GitHub repo → **Settings** → **Secrets and variables** → **Actions** → **New repository secret**:

| Secret Name | Description | How to Obtain |
| --- | --- | --- |
| `GOOGLE_MAPS_WEB_API_KEY` | Public Google Maps JavaScript API key | Google Cloud Console → Credentials (HTTP referrer restricted) |
| `CLOUDFLARE_API_TOKEN` | API token with Cloudflare Workers Edit permissions | [Cloudflare Dashboard](https://dash.cloudflare.com/profile/api-tokens) → Create Custom Token (Workers Scripts:Edit) |
| `CLOUDFLARE_ACCOUNT_ID` | Cloudflare Account Identifier | Cloudflare Dashboard → Workers & Pages → Overview (Right sidebar) |

---

### 5. Android Release Signing (Optional)

To generate a signed release APK or App Bundle:

1. Generate a keystore:
   ```bash
   keytool -genkey -v -keystore android/upload-keystore.jks -keyalg RSA -keysize 2048 -validity 10000 -alias upload
   ```
2. Create `android/key.properties` (automatically gitignored):
   ```properties
   storePassword=your_keystore_password
   keyPassword=your_key_password
   keyAlias=upload
   storeFile=../upload-keystore.jks
   ```
3. Build release bundle:
   ```bash
   flutter build appbundle --release
   ```

---

## Testing & Standards Verification

SchoolWay adheres to strict engineering and security standards. Verify all standards locally before pushing:

```bash
# 1. Run Flutter unit and widget tests
flutter test

# 2. Run Cloud Functions backend tests
cd functions && npm test && cd ..

# 3. Verify project architecture and Agent Contract v1 standards
dart run tool/verify_project_standards.dart

# 4. Check Dart formatting
dart format --output=none --set-exit-if-changed lib test tool
```

---

## Repository Architecture

```
schoolway/
├── .github/workflows/       # CI/CD deployment pipelines (Cloudflare & GitHub Pages)
├── .gitleaks.toml           # Security scanner configuration for client-side keys
├── android/                 # Native Android project configuration & Gradle scripts
├── assets/                  # Application icons, images, and brand assets
├── functions/               # Firebase Cloud Functions (Routes API, notifications, admin)
│   ├── index.js             # Callable & background trigger definitions
│   ├── routes_client.js     # Google Routes API backend client
│   └── notification_policy.js # Push notification policy engine
├── lib/
│   ├── app.dart             # Application shell, routing & auth gates
│   ├── core/                # Theme, logging, map markers, preferences, diagnostics
│   ├── features/
│   │   ├── admin/           # Fleet management, route planner, user admin, CSV wizard
│   │   ├── driver/          # Driver dashboard, live trip navigation, NFC check-in
│   │   ├── parent/          # Parent map, live tracking, child roster, notifications
│   │   └── auth/            # Sign-in, Google authentication, profile completion
│   ├── models/              # Immutable domain entities (Bus, Student, Route, Session)
│   └── services/            # Firestore, GPS uploader, Geofencing, NFC, Push messaging
├── seed/                    # Demo and testing CSV templates for quick onboarding
├── test/                    # Comprehensive unit, widget, and contract tests
└── tool/                    # Project standards verification & migration scripts
```

---

<div align="center">

**SchoolWay** · Safer, clearer school transportation for everyone on the route.

</div>

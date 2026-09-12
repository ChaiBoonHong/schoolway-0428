<div align="center">

<img src="assets/icon/icon.png" alt="SchoolWay logo: bus inside a heart-shaped route with a map pin" width="130" />

# SchoolWay

### *Safer, Smarter, and Transparent School Transportation*

Live telemetry, automated NFC student attendance, and real-time traffic-aware ETAs designed for schools, drivers, and modern families.

<p align="center">
  <a href="https://flutter.dev/"><img src="https://img.shields.io/badge/Flutter-3.47+-02569B?style=for-the-badge&logo=flutter&logoColor=white" alt="Flutter" /></a>
  <a href="https://dart.dev/"><img src="https://img.shields.io/badge/Dart-3.10+-0175C2?style=for-the-badge&logo=dart&logoColor=white" alt="Dart" /></a>
  <a href="https://firebase.google.com/"><img src="https://img.shields.io/badge/Firebase-Auth%20|%20Firestore%20|%20Functions-FFCA28?style=for-the-badge&logo=firebase&logoColor=black" alt="Firebase" /></a>
  <a href="https://mapsplatform.google.com/"><img src="https://img.shields.io/badge/Google%20Maps-Routes%20API-4285F4?style=for-the-badge&logo=googlemaps&logoColor=white" alt="Google Maps" /></a>
  <a href="https://pages.cloudflare.com/"><img src="https://img.shields.io/badge/Cloudflare-Pages%20%26%20Workers-F38020?style=for-the-badge&logo=cloudflare&logoColor=white" alt="Cloudflare" /></a>
</p>

[Key Features](#-key-features) • [Three Experiences](#-three-tailored-experiences) • [Architecture](#-system-architecture) • [File Categories](#-repository-anatomy--file-categories) • [Centralized Secrets](#-centralized-secrets-architecture) • [Quick Start](#-quick-start) • [Testing](#-testing--quality-standards)

</div>

---

## 🌟 Why SchoolWay?

Every weekday morning, millions of parents wonder: *"Did my child make it onto the bus? Is the bus stuck in traffic? When should I head to the stop?"* Meanwhile, bus drivers juggle paper attendance sheets in morning rush hour, and school administrators manage frantic phone calls without live fleet visibility.

**SchoolWay changes the game.** Built with Flutter and serverless Cloud Architecture, SchoolWay combines real-time GPS telemetry, instant tap-and-go NFC student check-in, offline-resilient sync, and server-side Google Routes API calculations into one unified, cohesive platform.

---

## ✨ Key Features

| Capability | What It Does | Why It Matters |
| :--- | :--- | :--- |
| 🛰️ **Live Fleet Radar** | Interactive map rendering multi-bus positions, heading, and speed in real-time. | Total situational awareness for administrators and parents alike. |
| 🚦 **Traffic-Aware ETAs** | Serverless Cloud Functions calculate accurate arrival times via **Google Routes API**. | Eliminates waiting in the rain or missing the morning pickup. |
| 🪪 **NFC Tap-to-Board** | Drivers scan student cards directly from Android devices with instant sound and haptic feedback. | Replaces paper manifests with millisecond, verified boarding records. |
| 📶 **Offline-First Engine** | Built-in **Hive** local cache and retry queue that logs boarding events even when cellular signal drops. | Zero data loss in tunnels, basements, or remote rural routes. |
| 🚨 **Emergency Broadcasts** | Instant critical alerts for route disruptions, breakdowns, or delays with priority push notifications. | Keeps school staff and parents aligned during critical incidents. |
| 👥 **Multi-Profile Switcher** | Seamlessly switch between parent, driver, or admin profiles with zero-friction account management. | Perfect for parents with multiple children or staff serving dual roles. |

---

## 🎭 Three Tailored Experiences

SchoolWay uses role-based access control (RBAC) powered by Firebase Auth and custom Firestore security policies to provide three purpose-built interfaces from a single codebase:

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                           SCHOOLWAY UNIFIED APP                             │
└──────────────────────────────────────┬──────────────────────────────────────┘
                                       │
         ┌─────────────────────────────┼─────────────────────────────┐
         ▼                             ▼                             ▼
  👨‍👩‍👧 PARENT APP                 🚌 DRIVER CONSOLE             🏫 ADMIN COMMAND
  ─────────────────────────     ─────────────────────────     ─────────────────
  • Live bus map tracking       • Turn-by-turn route view     • Real-time fleet radar
  • Dynamic traffic ETAs        • 1-tap NFC boarding log      • Interactive route planner
  • Child boarding history      • Offline-cached rosters      • CSV student/bus import
  • Push alert preferences      • Incident quick-reporting    • Emergency broadcasts
```

### 1. 👨‍👩‍👧 The Parent Experience
- **Live Vehicle Tracking**: Track your child's exact bus live on the map with smooth animated marker interpolation.
- **Smart Stop ETAs**: View live minutes remaining based on current traffic conditions, not static schedules.
- **Boarding Timeline**: Receive instant push notifications the moment your child boards or alights from the bus.
- **Family Hub**: Monitor all your children across different buses and grades in one clean screen.

### 2. 🚌 The Driver Console
- **Hands-Free Trip Mode**: Clean, high-contrast display designed for quick glanceability while driving.
- **NFC Student Scanning**: Fast student check-ins with clear audio-visual confirmations.
- **Offline Reliability**: Automatically saves scans to local storage when offline and syncs in the background upon reconnection.
- **Roster Overview**: Instant list of who has boarded, who is still waiting, and which stop comes next.

### 3. 🏫 The School Administrator Command Center
- **Fleet-Wide Overview**: Monitor all active routes, delays, and driver sessions simultaneously.
- **Visual Route Planner**: Create and adjust bus stops with interactive map pins and automatic polyline routing.
- **Data Provisioning Wizards**: Onboard entire schools in minutes using bulk CSV importers for students, buses, and routes.
- **Audit & Compliance**: Searchable logs for attendance corrections, route deviation reports, and driver check-in histories.

---

## 🏗️ System Architecture

```mermaid
flowchart TD
    classDef client fill:#E0F2FE,stroke:#0284C7,stroke-width:2px,color:#0C4A6E;
    classDef gateway fill:#FEF3C7,stroke:#D97706,stroke-width:2px,color:#78350F;
    classDef backend fill:#FEE2E2,stroke:#DC2626,stroke-width:2px,color:#7F1D1D;
    classDef external fill:#F0FDF4,stroke:#16A34A,stroke-width:2px,color:#14532D;

    subgraph Tier1["📱 1. Client Applications (Cross-Platform Flutter)"]
        Driver["🚌 Driver Console<br/>(NFC Attendance & Telemetry)"]
        Parent["👨‍👩‍👧 Parent Mobile App<br/>(Live Map & Arrival ETAs)"]
        Admin["🏫 Admin Command Portal<br/>(Fleet Radar & Route Editor)"]
    end

    subgraph Tier2["🔐 2. Ingress & Security Gateway"]
        Auth["Firebase Authentication<br/>(Role-Based Access Control)"]
        CDN["Cloudflare Edge CDN<br/>(Global Web PWA Distribution)"]
    end

    subgraph Tier3["☁️ 3. Serverless Cloud Core (Firebase)"]
        Firestore[("🔥 Cloud Firestore<br/>(Real-Time Database & Telemetry)")]
        Functions["⚡ Cloud Functions (Node.js 22)<br/>(Trip Triggers & Access Control)"]
    end

    subgraph Tier4["🌐 4. External Services & Intelligence"]
        RoutesAPI["🗺️ Google Routes API<br/>(Live Traffic & Route Geometry)"]
        FCM["🔔 Firebase Cloud Messaging<br/>(Instant Push Notifications)"]
    end

    CDN --> Tier1
    Tier1 --> Auth
    Auth --> Firestore

    Driver -->|"Upload GPS (3s) & NFC Scans"| Firestore
    Firestore -->|"Real-Time Bus Telemetry"| Parent
    Firestore -->|"Multi-Bus Fleet Radar"| Admin

    Firestore -->|"Trip & Stop Event Triggers"| Functions
    Functions -->|"Compute Traffic-Aware ETAs"| RoutesAPI
    Functions -->|"Dispatch Priority Alerts"| FCM

    FCM -->|"Arrival & Departure Alerts"| Parent
    FCM -->|"Emergency Route Broadcasts"| Driver

    class Tier1,Driver,Parent,Admin client;
    class Tier2,Auth,CDN gateway;
    class Tier3,Firestore,Functions backend;
    class Tier4,RoutesAPI,FCM external;
```

---

## 📂 Repository Anatomy & File Categories

The SchoolWay codebase is organized using a clean, scalable **feature-first architecture**. Every folder and layer has a distinct responsibility:

```
schoolway/
├── .env.example             # Centralized configuration & secrets template
├── android/                 # Android native runner, Gradle configs, and NFC permissions
├── assets/                  # High-resolution icons, brand assets, and map markers
├── functions/               # Serverless Node.js backend (Routes API & notification engine)
├── ios/                     # iOS native runner, Xcode workspace, and entitlements
├── lib/                     # Main Flutter / Dart application source code
│   ├── app.dart             # Root application widget, theme provider, and route gates
│   ├── core/                # Shared foundational infrastructure & design system
│   ├── features/            # Feature modules divided by user role
│   ├── models/              # Immutable domain entities & serialization
│   ├── services/            # Hardware integrations & cloud service clients
│   └── l10n/                # Internationalization strings (ARB catalogs)
├── seed/                    # Ready-to-import demo CSV datasets for quick evaluation
├── test/                    # Unit, widget, and integration test suites
├── tool/                    # Standards verification, secret sync, and benchmarks
├── web/                     # Web platform runner, service workers, and PWA manifest
└── windows/                 # Windows desktop native host configuration
```

### 📑 Detailed File Categories Breakdown

| Category | Primary Directory | Description & Key Files |
| :--- | :--- | :--- |
| **🎨 UI Design System & Core** | [`lib/core/`](file:///d:/UTAR/schoolway/lib/core/) | Core design tokens, `SchoolWayTheme`, custom accessible widgets (`SlideToConfirm`, `ShimmerLoading`, `TrafficEtaChip`), AppLogger diagnostics, and `SchoolWayMap` controller. |
| **👨‍👩‍👧 Parent Experience** | [`lib/features/parent/`](file:///d:/UTAR/schoolway/lib/features/parent/) | Live vehicle tracking map (`LiveMapTab`), child roster (`ChildrenTab`), trip history viewer, and notification preferences. |
| **🚌 Driver Experience** | [`lib/features/driver/`](file:///d:/UTAR/schoolway/lib/features/driver/) | Active trip console (`DriverTripTab`), NFC boarding scanner (`DriverNfcTab`), driver navigation map, and student checklist. |
| **🏫 Admin Command Center** | [`lib/features/admin/`](file:///d:/UTAR/schoolway/lib/features/admin/) | Multi-bus fleet radar (`LiveFleetTab`), visual route builder (`RoutePlannerScreen`), geofence editor, and CSV onboarding wizard. |
| **🔐 Authentication & Shell** | [`lib/features/auth/`](file:///d:/UTAR/schoolway/lib/features/auth/) & [`lib/features/profile/`](file:///d:/UTAR/schoolway/lib/features/profile/) | Role-gated sign-in (`SignInScreen`), Google profile completion, startup recovery, and multi-profile switcher. |
| **📦 Domain Entities** | [`lib/models/`](file:///d:/UTAR/schoolway/lib/models/) | Strongly typed, immutable data models (`Bus`, `Student`, `PlannedRoute`, `RouteSession`, `BoardingEvent`, `EmergencyAlert`). |
| **⚡ Application Services** | [`lib/services/`](file:///d:/UTAR/schoolway/lib/services/) | `FirebaseService`, `LocationService`, `OfflineQueueService` (Hive-backed queue), `EtaGeofenceService`, and `NfcTagReader`. |
| **🌐 Localization** | [`lib/l10n/`](file:///d:/UTAR/schoolway/lib/l10n/) | Localized string catalog supporting multi-language environments (`app_en.arb`, generated localization classes). |
| **☁️ Cloud Functions** | [`functions/`](file:///d:/UTAR/schoolway/functions/) | Secure serverless backend (`index.js`), Google Routes API proxy (`routes_client.js`), and push notification policy engine (`notification_policy.js`). |
| **🧪 Quality & Testing** | [`test/`](file:///d:/UTAR/schoolway/test/) | 170+ unit and widget tests validating state changes, map marker bounds, offline queuing, and accessibility contrast. |
| **🌱 Onboarding Seeds** | [`seed/`](file:///d:/UTAR/schoolway/seed/) | Pre-configured template CSV files (`buses.csv`, `students.csv`, `users.csv`, `planned_routes.csv`) for instant import. |

---

## 🔐 Centralized Secrets Architecture

SchoolWay unifies all environment variables, API keys, and credentials into a **single source of truth** in the project root: **`.env`**. Developers configure their secrets once, and our automated tooling propagates them to native platforms and cloud functions.

### ⚡ 3-Step Setup
```bash
# 1. Copy the centralized environment template
cp .env.example .env

# 2. Open .env and insert your API keys

# 3. Synchronize secrets to Android, Web, and Cloud Functions automatically
dart run tool/sync_secrets.dart
```

### 📋 Centralized Secrets Reference Matrix

| Secret Variable | Target Subsystem | Function / Purpose | Propagation Method |
| :--- | :--- | :--- | :--- |
| `MAPS_API_KEY` | Android Native | Google Maps SDK for Android navigation | Direct read by `build.gradle.kts` & `local.properties` |
| `GOOGLE_MAPS_WEB_API_KEY` | Web Client | Google Maps JavaScript API for Web map | Injected into `web/index.html` via build/sync tool |
| `GOOGLE_ROUTES_API_KEY` | Cloud Functions | Traffic-aware ETA calculation & polylines | Synced to `functions/.env` & Secret Manager |
| `FCM_WEB_VAPID_KEY` | Flutter Client | Web Push notifications registration | Loaded via `--dart-define-from-file=.env` |
| `FIREBASE_PROJECT_ID` | Firebase SDK | Project identity, Firestore, Auth gates | Centralized client & backend initialization |
| `CLOUDFLARE_API_TOKEN` | CI/CD Pipeline | Cloudflare Workers & Pages Edge deployment | GitHub Actions Secret for automated release |

### 🔍 Automated Verification
Verify that every subsystem receives its required secret with zero missing credentials:
```bash
dart run tool/sync_secrets.dart --verify
```

---

## 🚀 Quick Start

Get SchoolWay running locally in under 3 minutes:

### Prerequisites
- [Flutter SDK](https://docs.flutter.dev/get-started/install) (`>= 3.47.1`)
- [Dart SDK](https://dart.dev/get-dart) (`>= 3.10.0`)
- Android Studio / Xcode / Chrome for target emulation

### 1. Clone & Enter Repository
```bash
git clone https://github.com/ChaiBoonHong/schoolway-0428.git
cd schoolway-0428
```

### 2. Fetch Dependencies & Sync Secrets
```bash
flutter pub get
dart run tool/sync_secrets.dart
```

### 3. Launch on Your Target Device
```bash
# Run on Chrome / Web (Instant Dev Preview)
flutter run -d chrome

# Run on connected Android phone or emulator
flutter run -d android

# Run on Windows Desktop
flutter run -d windows
```

> [!NOTE]
> Pre-configured development credentials are included for immediate UI exploration. Connect your own Firebase project and Google Maps API keys via `.env` for production deployment.

---

## 🧪 Testing & Quality Standards

SchoolWay adheres to rigorous software engineering, security, and accessibility standards:

```bash
# 1. Run full Flutter unit and widget test suite (170+ tests)
flutter test

# 2. Run Cloud Functions serverless backend tests (69 tests)
cd functions && npm test && cd ..

# 3. Verify static analysis and zero lints
flutter analyze

# 4. Verify code formatting
dart format --output=none --set-exit-if-changed lib test tool

# 5. Verify repository standards
dart run tool/verify_project_standards.dart

# 6. Verify centralized secrets
dart run tool/sync_secrets.dart --verify
```

---

## 🚢 CI/CD & Deployment

Automated multi-stage continuous delivery via [`.github/workflows/deploy-web.yml`](file:///d:/UTAR/schoolway/.github/workflows/deploy-web.yml):
1. **Standards Gate**: Executes Gitleaks secret detection, code formatting, and architecture verification.
2. **Quality Gates**: Runs concurrent Flutter test suites and Node.js Functions security audits (`npm audit`).
3. **Automated Production Build**: Compiles web bundles and deploys to **Cloudflare Pages & Workers** with global CDN caching.

---

<div align="center">

### Built with care for safe journeys home.

**SchoolWay** · Every child accounted for, every journey visible.

</div>

<div align="center">

<img src="assets/icon/icon.png" alt="SchoolWay logo: bus inside a heart-shaped route with a map pin" width="140" />

<br/>

# SchoolWay

**Live school bus visibility for families, drivers, and staff**

[![Flutter](https://img.shields.io/badge/Flutter-02569B?style=for-the-badge&logo=flutter&logoColor=white)](https://flutter.dev/)
[![Dart](https://img.shields.io/badge/Dart-0175C2?style=for-the-badge&logo=dart&logoColor=white)](https://dart.dev/)
[![Firebase](https://img.shields.io/badge/Firebase-039BE5?style=for-the-badge&logo=Firebase&logoColor=white)](https://firebase.google.com/)

*Cross‑platform app · Real‑time fleet map · Roles for parent, driver, and admin*

<br/>

</div>

---

## Why SchoolWay?

SchoolWay connects everyone who depends on the school run. Parents see where buses are and what matters for their children. Drivers run trips with maps, rosters, and NFC check‑ins where supported. Administrators operate the fleet: routes, users, imports, alerts, and reporting—backed by Firebase and a map built on OpenStreetMap tiles.

---

## Highlights

| | |
| --- | --- |
| **Three experiences, one product** | Tailored home screens for **Parent**, **Driver**, and **Admin** with role‑based routing after sign‑in. |
| **Live fleet & trips** | Map views with configurable tile sources, bus positions, and trip‑related flows for operations and families. |
| **Firebase backbone** | Authentication (including Google Sign‑In), Cloud Firestore, Realtime Database, and Cloud Messaging for push. |
| **NFC boarding** | Driver‑side NFC tooling (Android‑oriented) for fast, on‑bus record keeping. |
| **Bulk data** | CSV import paths for bringing students, routes, and related data into the system. |
| **Offline‑aware UX** | Local storage via **Hive** and connectivity awareness so the app degrades gracefully when the network dips. |

---

## Tech stack

- **Framework:** Flutter (Material 3, custom Lexend typography, brand palette around `#0077B6` / `#CAF0F8`)
- **State:** Riverpod
- **Backend & auth:** Firebase (Core, Auth, Firestore, Realtime Database, Messaging)
- **Maps:** `flutter_map` + **latlong2**, tile URL configurable (default OSM; optional Firestore override at `app_config/map`)
- **Device:** Geolocator, Connectivity Plus, NFC Manager (Android), File Picker
- **Utilities:** CSV, HTTP, Intl, URL Launcher, Archive

---

## Getting started

### Prerequisites

- [Flutter SDK](https://docs.flutter.dev/get-started/install) matching **`sdk: ^3.9.2`** (see `pubspec.yaml`)
- A [Firebase](https://console.firebase.google.com/) project with the platforms you intend to ship (Android, iOS, Web as applicable)
- For **Web Push**, configure FCM Web Push certificates and align `AppConfig.fcmWebVapidKey` in `lib/core/config.dart` with your project’s **public** VAPID key

### Clone & install

```bash
git clone https://github.com/ChaiBoonHong/schoolway-0428.git
cd schoolway-0428
flutter pub get
```

### Firebase in this repo

The app expects Firebase options generated for your project (e.g. `lib/firebase_options.dart` via FlutterFire). Replace placeholders with your own Firebase configuration and security rules before production use.

Run on a device or emulator:

```bash
flutter run
```

### App icons (optional)

Place a square source image at `assets/icon/icon.png` (1024×1024 recommended), then:

```bash
dart run flutter_launcher_icons
```

---

## Repository layout

```
lib/
├── app.dart                 # MaterialApp, routes, startup & auth gates
├── main.dart                # Firebase init, web Firestore persistence tuning
├── core/                    # Config, Firestore helpers, map tiles, permissions
├── features/
│   ├── admin/               # Fleet, routes, CSV import, users, emergencies
│   ├── driver/              # Trips, map, students, NFC
│   ├── parent/              # Children, live map, history, notifications
│   ├── auth/                # Sign-in, profile completion, email changes
│   └── shell/               # Onboarding & shared shell UI
├── models/                  # Domain types (bus, student, routes, alerts, …)
└── services/                # Firebase, GPS upload, CSV import, NFC, push, …
```

---

## Contributing

Issues and pull requests are welcome. Please keep changes focused and consistent with existing patterns (Riverpod providers, feature‑first folders, and Firebase access via shared helpers).

---

## Acknowledgements

Map imagery defaults to [**OpenStreetMap**](https://www.openstreetmap.org/) contributors via standard tile usage—respect their [tile usage policy](https://operations.osmfoundation.org/policies/tiles/) and configure alternative hosts if you operate at scale.

---

<div align="center">

**SchoolWay** · Safer, clearer school transportation for everyone on the route.

</div>

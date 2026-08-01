# EzeeBook

A **fully offline** shop-management app for Pakistani tailors (darzi), built with
Flutter for Android. It replaces paper registers with digital customer tracking,
order management, measurements, PDF receipts, and WhatsApp sharing.

## Model (v2.0.0)

EzeeBook is a **one-time-purchase** app installed directly on a tailor's phone:

- **No accounts, no login, no internet required.** All data is stored locally in
  SQLite. The app makes no network calls of its own.
- **Optional PIN lock.** A 4-digit app-lock can be enabled to protect data on a
  shared/lost phone (Settings → App lock). A forgotten PIN can only be cleared by
  erasing all data.
- **Backup & Restore.** Move to a new phone via Settings → Backup data (creates a
  JSON file you can send to yourself) and Restore data on the new device.

## First launch

Disclaimer (sold as-is) → Shop setup (appears on receipts) → optional PIN → Dashboard.

## Build

```bash
flutter pub get
flutter run                 # on a connected Android device/emulator
flutter build apk --release # release APK for direct install
```

Desktop testing (Windows/Linux) uses `sqflite_common_ffi` automatically.

## Tech

Flutter · Dart · sqflite (local DB) · easy_localization (en/ur) · pdf/printing ·
share_plus · file_picker · crypto (PIN hashing).

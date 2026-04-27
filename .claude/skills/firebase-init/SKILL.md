---
name: firebase-init
description: >-
  Use when setting up Firebase for the first time or adding a new Firebase
  service to the project. Triggered by 'set up Firebase', 'add Firestore',
  'add Firebase Auth', 'initialise Firebase', or 'connect Firebase'.
---

# Firebase Init Skill

This playbook sets up Firebase for Study Collab from zero.

## Step 1 — FlutterFire CLI

```bash
dart pub global activate flutterfire_cli
flutterfire configure --project=study-collab
```

This generates lib/firebase_options.dart (do not edit manually).

## Step 2 — pubspec.yaml dependencies

Add to dependencies:
```yaml
firebase_core: ^3.6.0
firebase_auth: ^5.3.0
cloud_firestore: ^5.4.0
firebase_storage: ^12.3.0
firebase_messaging: ^15.1.0
firebase_analytics: ^11.3.0
firebase_remote_config: ^5.1.0
```

Run: flutter pub get

## Step 3 — main.dart initialization

```dart
import 'package:firebase_core/firebase_core.dart';
import 'firebase_options.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );
  runApp(const ProviderScope(child: MyApp()));
}
```

## Step 4 — Deploy Security Rules

```bash
firebase deploy --only firestore:rules,storage
```

Always run rules tests first:
```bash
firebase emulators:exec --only firestore,storage 'flutter test test/rules/'
```

## Step 5 — Emulator setup for local dev

firebase.json (already scaffolded):
```json
{
  "emulators": {
    "auth": { "port": 9099 },
    "firestore": { "port": 8080 },
    "storage": { "port": 9199 },
    "ui": { "enabled": true }
  }
}
```

Start emulators: firebase emulators:start --only auth,firestore,storage

Point Flutter app at emulators (lib/infra/firebase_emulator.dart):
```dart
void useEmulators() {
  FirebaseAuth.instance.useAuthEmulator('localhost', 9099);
  FirebaseFirestore.instance.useFirestoreEmulator('localhost', 8080);
  FirebaseStorage.instance.useStorageEmulator('localhost', 9199);
}
```

Call useEmulators() in main.dart when kDebugMode is true.

## Checklist
- [ ] flutterfire configure run, firebase_options.dart generated
- [ ] google-services.json added to android/app/ (gitignored)
- [ ] GoogleService-Info.plist added to ios/Runner/ (gitignored)
- [ ] firebase_options.dart added to .gitignore
- [ ] Firestore rules deployed and tested
- [ ] Storage rules deployed and tested
- [ ] Emulators working locally
- [ ] main.dart initializes Firebase before runApp()

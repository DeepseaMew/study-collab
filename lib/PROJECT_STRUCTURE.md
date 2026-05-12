# Study Collab — Project Structure

This is the folder map agents read on every spawn. Keep it short and current.
For the *why* of any architectural decision, see `docs/decisions/`.

## Top level

```
study_collab/
├── CLAUDE.md                  ← project memory (rules, conventions)
├── PROJECT_STRUCTURE.md       ← this file
├── pubspec.yaml
├── analysis_options.yaml
├── firestore.rules            ← Firestore security rules
├── storage.rules              ← Firebase Storage security rules
├── .claude/
│   ├── settings.json          ← permissions (allow / deny)
│   └── agents/                ← subagent definitions
│       ├── flutter-engineer.md
│       ├── firebase-specialist.md
│       ├── code-reviewer.md
│       └── qa-engineer.md
├── docs/
│   ├── decisions/             ← architecture decision records (ADRs)
│   ├── firestore-indexes.md   ← required composite indexes
│   └── RATING_DESIGN.md       ← rating feature design doc
├── lib/                       ← Dart source
├── test/                      ← unit + widget tests
├── android/
└── ios/
```

## `lib/` — Dart source

Feature-first. Each feature is self-contained. Shared code in `core/`,
`models/`, `services/`.

```
lib/
├── main.dart
├── firebase_options.dart        ← AUTO-GENERATED, do not edit
│
├── core/                        ← cross-cutting code
│   ├── constants/
│   │   ├── auth_constants.dart       ← KMUTT email domain check
│   │   └── firestore_collections.dart ← collection name strings
│   ├── errors/
│   │   └── app_exceptions.dart       ← AppException, DataException, etc.
│   ├── router/
│   │   └── app_router.dart           ← GoRouter config + redirect logic
│   ├── theme/
│   │   └── app_theme.dart            ← AppColors + AppTheme (Poppins)
│   └── utils/
│       └── date_formatter.dart
│
├── models/                      ← plain Dart classes
│   ├── app_user.dart
│   ├── enums.dart                    ← Subject, AcademicLevel,
│   │                                   SessionStatus, SessionVisibility,
│   │                                   JoinStatus
│   ├── friend.dart                   ← Friend + FriendRequest models
│   ├── session.dart
│   ├── participant.dart
│   ├── join_request.dart
│   ├── chat.dart
│   ├── message.dart
│   ├── app_notification.dart
│   └── session_file.dart
│
├── services/                    ← Firebase access layer
│   ├── auth_service.dart             ← ✅ implemented
│   ├── user_service.dart             ← ✅ implemented (avatar upload, profile)
│   ├── friend_service.dart           ← ✅ implemented (send/accept/decline/unfriend)
│   ├── session_service.dart          ← ⚙️ stub (next major task)
│   ├── participation_service.dart    ← ⚙️ stub
│   ├── chat_service.dart             ← ⚙️ stub
│   └── notification_service.dart     ← ⚙️ stub
│
└── features/                    ← feature-first folders
    ├── auth/
    │   ├── providers/
    │   │   └── auth_providers.dart   ← authStateProvider, currentUserProvider
    │   └── screens/
    │       ├── splash_screen.dart
    │       ├── login_screen.dart
    │       ├── signup_screen.dart
    │       └── verify_email_screen.dart  ← email verification gate
    │
    ├── dashboard/                 ← home / discover feed
    │   ├── providers/
    │   │   └── dashboard_providers.dart  ← currently mock data
    │   ├── screens/
    │   │   └── dashboard_screen.dart
    │   └── widgets/
    │       ├── session_card.dart
    │       ├── search_bottom_sheet.dart
    │       ├── join_password_dialog.dart
    │       └── join_request_dialog.dart
    │
    ├── profile/                   ← own profile + other-user profile
    │   ├── providers/             ← (none yet — uses currentUserProvider)
    │   └── screens/
    │       ├── profile_screen.dart
    │       └── other_user_profile_screen.dart
    │
    ├── settings/
    │   └── screens/
    │       └── settings_screen.dart
    │
    ├── calendar/                  ← (skeleton, not migrated yet)
    ├── messaging/                 ← (skeleton, not migrated yet)
    ├── my_sessions/               ← (skeleton, not migrated yet)
    ├── notifications/             ← (skeleton, not migrated yet)
    └── session/                   ← create/edit/detail (skeleton)
```

## Conventions

- **Feature ownership:** screens, widgets, and feature-specific providers
  belong inside `lib/features/<name>/`. Don't put feature widgets in
  `lib/core/`.
- **Service-wrapper providers** (e.g. `userServiceProvider`) live at the
  bottom of each service file in `lib/services/`. We do not have a
  separate `core/providers/` folder.
- **Cross-feature imports** use `package:study_collab/...`. Within the
  same feature, relative imports are fine.
- **Models** are flat in `lib/models/` — no subfolders.

## Files that must not be edited

- `lib/firebase_options.dart` (FlutterFire CLI regenerates)
- `**/*.g.dart`, `**/*.freezed.dart` (codegen output — not used yet)
- `android/app/build/**`, `ios/Pods/**`, `.dart_tool/`, `build/`

These are also enforced via `.claude/settings.json` deny rules.

## Status legend
- ✅ implemented and tested
- ⚙️ stub or skeleton — not yet implemented
- (no marker) ordinary code, in normal use
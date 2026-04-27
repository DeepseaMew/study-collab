# Release Runbook — Study Collab

> Owned by: release-engineer agent + human lead
> Updated: 2026-04-27

## Prerequisites checklist (release-engineer verifies)

- [ ] `main` branch is green on CI (all tests pass).
- [ ] Security Rules tests pass: `firebase emulators:exec 'flutter test test/rules/'`
- [ ] security-reviewer report: severity_max < High.
- [ ] qa-engineer coverage report: all tiers green.
- [ ] No unresolved High/Critical findings from any agent.

## Step 1 — Deploy Firebase rules

```bash
# Dry run first
firebase deploy --only firestore:rules,storage --dry-run

# If clean, deploy
firebase deploy --only firestore:rules,storage
```

Human sign-off required before this step.

## Step 2 — Bump version

```bash
# In pubspec.yaml: version: X.Y.Z+buildNumber
# release-engineer agent handles this via conventional commit parsing
dart run tools/bump_version.dart
```

## Step 3 — Generate release notes

```bash
dart run tools/changelog.dart --since=$(git describe --tags --abbrev=0)
```

Output goes to CHANGELOG.md and docs/release-notes/vX.Y.Z.md.

## Step 4 — Cut tag

```bash
git add pubspec.yaml CHANGELOG.md
git commit -m "chore: release vX.Y.Z"
git tag vX.Y.Z
git push origin main --tags
```

## Step 5 — CI store submission

Triggered automatically by the tag. CI runs:
```bash
fastlane android beta    # Google Play internal track
fastlane ios beta        # TestFlight
```

## Rollback plan

Every risky code path is behind a Firebase Remote Config flag.

To roll back a feature without a new release:
1. Open Firebase Console → Remote Config.
2. Set the feature flag to `false` (default-off variant).
3. Publish. Takes effect within 1 minute for active users.

To roll back a full release:
1. Google Play: promote the previous version in Play Console.
2. App Store: use App Store Connect to revert to the previous build.
3. Firebase Rules: `git revert <rules commit>` + redeploy.

## Human touchpoints (non-negotiable)

- Rules deployment: human approves before `firebase deploy`.
- Store submission: human approves before fastlane runs.
- Any release touching Auth or payment flows: human reviews diff.

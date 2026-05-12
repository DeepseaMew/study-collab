# 0001 — Riverpod providers: hand-written, not code-generated

**Status:** accepted
**Date:** 2026-05 (decided retroactively, recorded after the fact)
**Owners:** flutter-engineer, project lead

## Context

Riverpod 2.x supports two ways to declare providers:

1. **Hand-written:** `final fooProvider = StreamProvider<...>((ref) { ... });`
2. **Code-generated:** Annotate a function with `@riverpod` and run
   `build_runner` to generate boilerplate.

Our existing auth code (`auth_providers.dart`) was already hand-written
when this project was inherited. New providers had to be added for the
profile, friends, and session features. We needed to pick one style and
stick with it.

## Decision

**Use hand-written providers project-wide.** Do not adopt
`riverpod_generator` or `@riverpod` annotations.

## Options considered

### Option A: Hand-written (chosen)
- Pro: matches existing `auth_providers.dart`. No mixed styles.
- Pro: no extra packages, no codegen step.
- Pro: what you see is what runs — easier to debug for beginners.
- Con: more boilerplate per provider.
- Con: less type safety on `family` parameters than codegen offers.

### Option B: Code-generated (`@riverpod` + `riverpod_generator`)
- Pro: less boilerplate per provider once setup is done.
- Pro: better type safety on family parameters (records vs positional).
- Pro: easier refactoring (rename a function and the provider follows).
- Con: requires 3 new packages (`riverpod_annotation`,
  `riverpod_generator`, `build_runner`).
- Con: every provider change requires running build_runner. Forgetting
  yields cryptic "missing .g.dart file" errors that confuse beginners.
- Con: would have meant migrating the existing auth providers too,
  for consistency.

## Why we chose A

For a college project with one main developer and ~20 providers total,
the codegen advantages don't outweigh the toolchain cost. The deciding
factor was consistency: mixing both styles in one project is worse than
either choice on its own, and the existing code was hand-written.

If the project grows past ~50 providers or onboards more developers,
the decision should be revisited.

## Reversal cost

**Low.** Each hand-written provider can be migrated to `@riverpod`
mechanically (add annotation, change function signature, run codegen).
A few hours of work for the whole codebase.

## See also
- `lib/features/auth/providers/auth_providers.dart` — example pattern.
- `lib/services/user_service.dart` (bottom) — service-wrapper provider
  pattern: `final userServiceProvider = Provider<UserService>(...)`.
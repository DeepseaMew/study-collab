# 0006 — Session visibility: 3 modes → 2 modes

**Date:** 2026-05
**Status:** Accepted
**Decided by:** Architect agent + human lead, in response to Sprint #3 feedback

## Problem

Sprint #3 review feedback included:

> "Private fully hide, Public must approve only from now"

The original `SessionVisibility` enum had three values:
- `public` — visible in browse, **instant join** (no approval).
- `approval` — visible in browse, **host approval required**.
- `private` — visible in browse, **password required**.

A separate `JoinApproval` enum (`none` / `hostApproval`) duplicated the
intent of `SessionVisibility.approval`. The model already noted in a
comment that the two enums overlapped and one was "kept for backward
compat."

The reviewer feedback essentially said two things:
1. Drop instant-join. Public sessions should always require approval.
2. Make private sessions invisible in browse.

## Options considered

### Option A: Keep 3 modes, just change behavior
- `public` would require approval (no longer instant).
- `private` would be filtered out of browse queries.
- `approval` would still exist as a separate mode — but functionally
  identical to the new `public`.

**Cons:** Two enum values for one behavior is confusing. The
redundancy that the model comment already flagged would only get worse.

### Option B: Reduce to 2 modes (chosen)
- `public` — visible in browse; joining always requires approval.
  (Absorbs the old `approval` semantics.)
- `private` — hidden from browse; joinable via password or shared link.
  (Old `private` was visible-with-password; now also hidden.)
- Drop `JoinApproval` enum entirely — was redundant under old model,
  fully redundant now.

**Cons:** Existing data with `visibility: 'approval'` needs migration
(or graceful fallback in `fromString`).

### Option C: Add a separate "discoverable" boolean
Split visibility (visible/hidden) from join-mode (approval/password).

- Pro: most flexible — any combination possible.
- Con: 4 logical states, only 2 of which are useful for users.
  Over-engineered for the actual product. Reviewer was clear about
  the 2-mode design they wanted.

## Decision

**Reduce to 2 modes (Option B).**

```dart
enum SessionVisibility {
  public,    // visible in browse, approval required to join
  private;   // hidden from browse, password required to join
}
```

Delete the `JoinApproval` enum. Simplify `Session.requiresApproval` to
`visibility == SessionVisibility.public`.

Handle legacy data via `fromString` fallback — any unknown value
(including the old `'approval'`) maps to `public`. Safe default since
public now means "needs approval" anyway, which was the old `approval`
mode's behavior.

## Why we chose Option B

The reviewer feedback was specific and the 2-mode design matches what
real apps in this space actually do. Keeping 3 modes (Option A) would
preserve technical debt the codebase already had a TODO comment about.
Option C added flexibility we don't need for any concrete user scenario.

The migration is free for us right now — we have no production session
data. The `fromString` fallback covers any dev/test data that does exist.

## Reversal cost

**Medium.** Re-introducing instant-join would mean:
1. Adding back a third enum value (or a new `instantJoin: bool` field).
2. Updating dashboard query filters and the session card switch.
3. Updating any future create/edit-session UI that lets host pick a mode.

A few hours of code change. Past data wouldn't need to migrate again.

## Constraints locked in by this decision

- **Browse / search queries** must filter to `where('visibility',
  isEqualTo: 'public')`. Private sessions never appear in discover or
  search. Already documented for the upcoming `session_service`.
- **Joining a private session** requires either:
  - Knowing the session ID (typed/pasted in a join form), or
  - Following a shared link (`/session/{id}`).
  Either way, the password gate at `participation_service.joinWithPassword`
  is the security boundary.
- **`Session.requiresApproval`** is now equivalent to "is this public?"
  — kept as a getter for readability; the two are interchangeable.
- **Dashboard mock data** updated to the new model — sessions previously
  marked `approval` are now `public`. See
  `lib/features/dashboard/providers/dashboard_providers.dart`.

## See also
- `lib/models/enums.dart` — new `SessionVisibility`, removed `JoinApproval`.
- `lib/models/session.dart` — removed `joinApproval` field, simplified
  `requiresApproval` getter, `fromString` fallback for legacy data.
- `lib/features/dashboard/widgets/session_card.dart` — `_NotJoinedButton`
  switch reduced from 3 cases to 2. Public sessions now show "Request
  to Join" outlined button (was "Join" filled button under old model).

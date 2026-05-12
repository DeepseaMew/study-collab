# 0011 — gmail.com as a temporary development-only allowed domain

**Date:** 2026-05-10
**Status:** Accepted (temporary — expires before first external beta or production release)
**Decided by:** Architect agent + human lead

## Problem

Firebase verification emails to `@kmutt.ac.th` addresses deliver inconsistently,
blocking developers from testing the full auth flow end-to-end. `@mail.kmutt.ac.th`
delivers fine but not all team members have those accounts during active development.
CLAUDE.md mandates KMUTT-only signup, so `gmail.com` in `kAllowedEmailDomains` is
currently undocumented and looks like a bug.

## Options considered

| Option | Pros | Cons |
|---|---|---|
| **A. Keep gmail.com permanently** | No future removal work. | Breaks the KMUTT-only policy. Non-students could sign up. Unacceptable for any public release. |
| **B. Require all devs to use @mail.kmutt.ac.th** | Policy stays clean today. | Blocks devs who do not have `@mail.kmutt.ac.th` accounts; slows down auth-flow testing immediately. |
| **C. Temporary exception with explicit removal trigger (chosen)** | Unblocks development now. Policy intent is documented. Removal is a single-line change. | Requires discipline to actually remove it before launch. |

## Decision

Retain `gmail.com` in `kAllowedEmailDomains` as an explicit, documented
development-only exception with a hard removal trigger.

## Why we chose option C

Option A permanently violates the KMUTT-only requirement and is ruled out.
Option B creates an immediate team workflow problem without solving the
unreliable `@kmutt.ac.th` delivery issue. Option C costs nothing extra and
converts a silent policy violation into a tracked, expiring exception.

## Reversal cost

**Low** — removing `gmail.com` is a single-line deletion in one constant file.

## Constraints locked in by this decision

- `gmail.com` is a dev tool, not a policy change. No user-facing messaging
  should suggest non-KMUTT emails are accepted.
- Remove `gmail.com` from `kAllowedEmailDomains` in
  `lib/core/constants/auth_constants.dart` before the first external beta
  or production release. Add to the launch checklist.
- This removal belongs alongside the Firestore rules-tightening items already
  listed in the "Before launch" block of CLAUDE.md's Security section.

## See also

- `lib/core/constants/auth_constants.dart` — `kAllowedEmailDomains` constant
  and `isAllowedUniversityEmail` function.
- CLAUDE.md Security section — "Before launch" block where this removal must
  be listed alongside Firestore rule hardening.

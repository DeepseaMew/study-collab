# 0001 — Firebase as the backend for Study Collab

**Date:** 2026-04-27
**Status:** Accepted
**Decided by:** Architect agent + human lead

## Problem

Study Collab needs: authentication, a real-time database, file storage, and push
notifications — and the team is four people with a tight deadline.

## Options considered

| Option | Pros | Cons |
|---|---|---|
| Firebase (Firestore + Auth + Storage + FCM) | Zero-ops, real-time sync built-in, generous free tier, Flutter SDK mature | Vendor lock-in, query limitations (no full-text search), cost at scale |
| Supabase (Postgres + Auth + Storage) | SQL queries, open-source, self-hostable | Flutter SDK less mature, real-time subscriptions need more setup |
| Custom backend (FastAPI + PostgreSQL) | Full control, any query shape | High build cost, team has to operate infra |

## Decision

Use Firebase. The team's velocity benefit and the maturity of the Flutter SDK
outweigh the lock-in risk at this stage. The app's query patterns (list sessions,
filter by subject, real-time chat) are well within Firestore's model.

## Reversal cost

Migrating away from Firestore would require: rewriting all repository classes,
replacing Security Rules with backend auth middleware, and migrating data. Estimate
4–6 weeks for a team of four. Acceptable if the product outgrows the free tier.

## Constraints locked in by this decision

- No full-text search (use Algolia MCP or Firebase Extensions if needed later).
- No complex JOIN-style queries — denormalize aggressively.
- Security Rules are the auth layer — client code must never assume permissions.
- member_count on sessions is a denormalized counter, updated atomically.

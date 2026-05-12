# 0007 — Rating system: thumbs up/down, not 1–5 stars

**Date:** 2026-05
**Status:** Accepted (design only — implementation pending)
**Decided by:** Architect agent + human lead, in response to Sprint #3 feedback

## Problem

Sprint #3 review feedback included a requirement to add ratings:

> "Rating"

The professor's framing was about **trust** — letting users check
"is this person trustworthy enough to study with?" before joining a
session. The default assumption when someone says "rating" is 1–5 stars,
since that's what most apps do.

We needed to decide what shape the rating system actually takes.

## Options considered

| Option | Pros | Cons |
|---|---|---|
| **1–5 stars** (Yelp-style) | Familiar UX. Granular signal. Standard expectation when someone says "rating." | At a small university (everyone sees everyone), 1-star ratings cause real social drama. Stars feel like grading. New users with one bad rating show "1.0 stars" forever, which is brutal. |
| **Thumbs up / down** (chosen) | Binary "would study again" framing is honest and low-drama. Easy to give. Trust signal computes cleanly to "X% recommended." Matches Airbnb / Uber etc. | Less granular signal than stars. Can't distinguish "amazing" from "fine." |
| **No rating, only reports** | Lowest friction. No social weight. | Doesn't satisfy prof's "rating" requirement. Reports alone don't help users *decide* before joining — only flag bad actors after the fact. |

## Decision

**Thumbs up / down** with the following rules:

- **Format:** thumbs up = "would study with them again"; thumbs down = "no thanks."
- **Who can rate whom:** only people who attended the same session can
  rate each other. One rating per (rater, ratee, session). Strangers
  cannot rate.
- **When:** soft prompt after session ends, easy to skip; also rate-able
  later from the user's profile if they skipped.
- **What's shown on profile:** "X% would study again (N ratings)".
  Only the positive percentage is displayed — never a raw downvote count
  (Airbnb-style).
- **New users:** show a "New member" badge instead of a percentage until
  they have ≥3 ratings. Protects newcomers from one bad day.
- **Anonymity:** the rated user sees their aggregate %, never who voted
  what. Removes social pressure from giving honest ratings.
- **Large sessions (50+ attendees):** prompt only asks about the host;
  a separate "Rate other members" button opens a search/select list.
  Avoids overwhelming users in big sessions.

## Why we chose thumbs over stars

Three reasons, in order:

1. **Stars hurt at a small university.** KMUTT is a finite community.
   Everyone sees everyone. A 1-star rating drags forever. Thumbs is
   binary — easier to read as "I personally didn't click with them"
   rather than a global judgment.

2. **Thumbs is still a rating system.** It satisfies the prof's
   requirement. We're not removing rating; we're choosing a less
   harmful version of it. A 100% / 92% / 75% trust score is just as
   informative as 5.0 / 4.5 / 3.5 stars for the actual question users
   are asking ("can I trust this person?").

3. **Lower friction = more participation.** A single tap per attendee
   completes the rating. Stars require thinking about gradations.
   More people complete the prompt = more reliable signal overall.

## Reversal cost

**Low** for the data layer; **medium** for the UI.

The Firestore document shape (`{raterId, ratedUserId, sessionId,
isThumbsUp}`) trivially extends to stars by adding a `stars` int field.
Aggregation on the user doc would need to add `starsTotal` /
`starsCount` alongside the existing thumbs counts.

The UI rework is bigger — replacing thumb buttons with a star control
on the prompt screen and the profile display.

If the team or prof later insists on stars, we can either run both
systems for a transition period or switch outright.

## Constraints locked in by this decision

- **Data model:** `ratings/{sessionId}_{raterId}_{ratedUserId}` with
  fields `{sessionId, raterId, ratedUserId, isThumbsUp, createdAt}`.
  Deterministic doc ID prevents duplicate ratings per pair per session
  (same pattern as ADR 0003).
- **Denormalization on user doc:** `thumbsUpCount`, `thumbsDownCount`.
  Trust % is computed in UI, not stored. Counts updated atomically in
  the same write that creates/changes/deletes a rating doc. Same
  pattern as `friendsCount` (see ADR 0004).
- **Dependencies:** rating system can't be implemented until
  `session_service` and `participation_service` exist — needed to
  define when a session ends and who attended.
- **Out of scope (intentionally):** comments / written reviews,
  multiple rating dimensions (punctual / helpful / etc.), public
  downvote counts, identifying who rated whom. The data model can
  support these later if added; the design intentionally doesn't
  surface them now.

## Open questions deferred to implementation

- **What counts as "session ended"?** Time-based (clock passes endTime)?
  Host marks done? Both?
- **Can users change a rating later?** Yes by default (they overwrite
  their own doc), but UX needs design.
- **Should old ratings expire?** A thumbs-down from 2 years ago
  shouldn't drag forever. Possibly: show only ratings from the last
  12 months in the public %.
- **Confirm with prof:** we changed stars → thumbs. Get explicit
  confirmation that this satisfies the rating requirement.

## See also
- `RATING_DESIGN.md` (project root or `/docs`) — fuller design doc
  shared with the team.
- ADR 0003 — deterministic IDs pattern reused for ratings collection.
- ADR 0004 — denormalized count pattern reused for thumbs counts.

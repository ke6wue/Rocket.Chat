# Skyward Qmlativ → Rocket.Chat Provisioning Connector

Syncs staff, students, and parents/guardians from Skyward Qmlativ into a custom
Rocket.Chat fork, and provisions per-class communication spaces, while treating
FERPA compliance as a first-class design constraint rather than an afterthought.

## Why the design looks like this (read before wiring up API paths)

**Skyward Qmlativ is confirmed** (URL contained `qmlativ.`), so this targets Qmlativ's
REST + OAuth2 "Integration Access" API, not the legacy SMS 2.0 Generic API.

Two things about Qmlativ access you (or your district's Skyward admin) must do
before this connector can run at all — Anthropic/Claude has no visibility into
your district's actual approved endpoints, so these are configured via env vars,
not hardcoded:

1. In Qmlativ: **Administrative Access → API → Integration** — your district
   must register (or approve a vendor registration of) an Integration, define
   which tables/fields it can read (Student, Staff, Guardian, Section,
   StudentSectionEnrollment, GuardianStudentRelationship — see field list
   below), and generate a Client ID/Secret for OAuth2 client-credentials auth.
2. Get the **district-specific base API URL** for your Qmlativ tenant (distinct
   from the login URL you shared) and the OAuth2 token endpoint — these come
   from the Integration Access record, not from public docs.

This connector is intentionally **read-only against Skyward**. It never writes
back to Skyward. Minimizing the blast radius of a misconfigured integration
matters a lot when the upstream system is a student record system.

## FERPA-driven design decisions

FERPA doesn't prohibit a tool like this — schools route "education records"
data to third-party tools constantly under the **"school official" exception**
(34 CFR § 99.31(a)(1)), provided the district maintains "direct control" over
the data and the vendor doesn't use it beyond the authorized purpose. That
means the compliance burden is mostly about *how you operate this connector*,
not whether you're allowed to build it. Concretely, this implementation:

- **Syncs the minimum field set needed for account + roster provisioning** —
  legal name, school-assigned/district email, role, section enrollment,
  guardian-student linkage. It never pulls grades, attendance, discipline,
  health, IEP/504, or SSN/state ID fields, even if your Integration Access
  grant technically exposes them. See `src/types.ts` for the exact allowed
  field set — treat expanding it as a deliberate, reviewed decision.
- **Honors Skyward's guardian restriction flags.** Skyward tracks a
  "Restrict from Family Access" / no-contact flag per guardian (for custody
  or protective-order situations). The sync **must** drop any guardian
  record with that flag set before creating an RC account or channel
  membership — see `shouldSyncGuardian()` in `src/sync/guardians.ts`. Treat
  this as a hard legal control, not a nice-to-have.
- **Separates student-peer space from parent-visible space.** Each class
  section provisions *two* Rocket.Chat Teams:
  - `#<section>-class` — teacher + enrolled students. Peer-to-peer student
    conversation happens here, out of parents' view (age-appropriate
    privacy), moderated by the teacher (added as Team owner/moderator).
  - `#<section>-family` — teacher + guardians of enrolled students only.
    Announcements and 1:1 teacher-family threads. Students are never
    members of this space.

  This mirrors how purpose-built K-12 comms tools (Bloomz, ClassDojo,
  Remind) structure things, and avoids the common FERPA/COPPA misstep of
  giving parents a raw feed of other students' messages about their kids.
- **Deactivates rather than deletes** on unenrollment/withdrawal. Most
  state student-record-retention laws require keeping an audit trail of who
  had access to what and when; hard-deleting a Rocket.Chat account destroys
  that. `active: false` + membership removal preserves history.
- **Full audit log** of every account/membership change the connector makes
  (`src/audit/log.ts`), append-only, with the Skyward source record ID, so
  you can answer "who could message my child, and since when" on request —
  parents have a FERPA right to this kind of accounting in spirit even
  where it's not literally an "education record" disclosure log.
- **No plaintext credential storage.** Skyward OAuth2 secret and Rocket.Chat
  admin token are read from environment/secret-manager only
  (`src/config.ts` throws if they're missing — it never has a hardcoded
  fallback).
- **Passwords are never chosen by this connector for students or staff.**
  It provisions accounts in a state that *requires* SSO or a forced
  reset-via-district-email flow — see the note in `src/rocketchat/client.ts`.
  If your fork doesn't yet support district SSO (Google Workspace for
  Education / Entra ID / Clever), that's a prerequisite worth solving before
  rostering students, not something to route around with generated
  passwords emailed in plaintext.

## What this doesn't solve (and you shouldn't expect a connector to)

- **Message-level moderation policy** (e.g., "students can't DM each other
  1:1 outside a class channel") is a Rocket.Chat *permissions/fork*
  question, not a provisioning question. Recommend locking down direct
  messages between users with the `student` role at the fork level.
- **A signed data-processing / vendor agreement with your district** — if
  this is a real deployment (not a personal fork experiment), your district
  almost certainly needs this reviewed by whoever handles FERPA compliance
  and vendor agreements before it touches real student data. That's a
  people/paperwork step, not a code step.
- **COPPA** if any enrolled students are under 13 and the "school official"
  exception's consent-delegation doesn't cover your specific data flows —
  worth a specific legal check, not assumed away here.

## Project layout

```
src/
  config.ts              env-based config, fails loudly if secrets missing
  types.ts                the *allowed* field set synced from Skyward
  skyward/client.ts        OAuth2 client-credentials + paginated resource fetch
  rocketchat/client.ts      admin REST wrapper: users, teams, membership
  store/db.ts               SQLite mapping table (Skyward ID <-> RC ID) + audit
  sync/staff.ts              staff -> RC user w/ `staff` role
  sync/students.ts           students -> RC user w/ `student` role
  sync/guardians.ts           guardians -> RC user w/ `parent` role, honors
                               restriction flags
  sync/classes.ts             sections -> paired class/family Teams + membership
  sync/engine.ts               orchestrates a full sync run, in dependency order
  audit/log.ts                  append-only audit trail
  index.ts                       entrypoint + optional cron scheduler
```

## Setup

```bash
cp .env.example .env    # fill in Skyward + Rocket.Chat + DB secrets
npm install
npm run migrate         # creates local SQLite mapping/audit DB
npm run sync            # one-off run
npm run sync:watch      # runs on a nightly cron (see CRON_SCHEDULE in .env)
```

## Extending to real-time

Qmlativ supports configurable event webhooks (new staff record, enrollment
change, etc.). Once you've run batch sync successfully for a while and are
comfortable with its behavior, `src/sync/engine.ts` exposes `syncOne(kind, id)`
so a webhook receiver can call the same reviewed logic for a single record
instead of re-deriving provisioning rules in a second code path.

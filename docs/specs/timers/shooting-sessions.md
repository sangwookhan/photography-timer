<!-- Copyright © 2026 Sangwook Han -->
<!-- SPDX-License-Identifier: Apache-2.0 -->

# Automatic Shooting Sessions

**Status: Proposed revision for initial approval.**

| Prefix | Owns |
| --- | --- |
| SESSION | Session identity, eligibility, and independence from timer execution |
| SESSION-LINK | Automatic membership and activity boundaries |
| SESSION-BROWSE | Session identification and navigation from History |
| SESSION-PERSIST | Membership durability and failure behavior |
| SESSION-DEBUG | Shortened session windows in iPhone debug builds |

## Purpose

A photographer uses timers normally and later reopens the records from the
same shooting activity together, without a mandatory session setup or end
procedure. A session represents inferred shooting context, not proof that
all exposures were made at one place or on one physical outing.

## Requirements

### Identity and scope

- **SESSION-001** — Starting an eligible timer shall automatically obtain a
  session membership without requiring the photographer to start or end a
  session separately.
- **SESSION-002** — A session shall have a stable identity. A timer shall
  belong to at most one session. An unfinished assignment shall be distinct
  from a confirmed membership.
- **SESSION-003** — Once assigned, a timer shall retain its membership
  across its running, paused, completed, canceled, and restored states.
- **SESSION-004** — Automatic pause cancellation shall preserve the record
  in its original session with its captured identity and remaining exposure
  time. Cancellation shall not constitute new shooting activity.
- **SESSION-005** — A rejected timer start shall create neither a new
  shooting activity nor a new session membership, and shall not change
  existing memberships.
- **SESSION-006** — Repeating a timer shall evaluate the new timer as a new
  start. It shall not inherit the source record's session merely because
  the source setup was copied. The source record retains its membership.
- **SESSION-007** — Camera identity and captured labels remain governed by
  `shooting/camera-slots.md` and `timers/lifecycle.md`. Display names,
  camera-list positions, and film labels shall not substitute for camera
  identity when identifying records for grouping.
- **SESSION-008** — A manual timer shall participate in the same time-only
  grouping as calculator-bound timers, without acquiring an inferred camera
  or film identity from the currently active camera.
- **SESSION-009** — Location denial, unavailability, or acquisition delay
  shall not prevent timer use or access to existing History.
- **SESSION-010** — Missing historical location shall not be fabricated
  from the current device location, camera name, or display text. This
  capability shall neither acquire location nor use its presence, absence,
  or value to change session membership.
- **SESSION-011** — Introducing sessions shall preserve pre-existing valid
  Timer records, their identities, captured metadata, and History ordering.
- **SESSION-012** — Pre-existing records without membership shall remain
  individually readable and explicitly unassigned. They shall not receive
  automatic retrospective membership. Missing membership alone shall not
  make a record corrupt or cause a current start to join legacy History.

### Time-only linking

The connection window W is one hour and the maximum admission span M is
eight hours. These windows govern successful starts, not timer duration or
completion. The debug-only alternative is defined below.

- **SESSION-LINK-001** — Only a successful new timer start shall count as
  activity for automatic assignment, using its original start time.
- **SESSION-LINK-002** — The candidate shall be the session of the most
  recent successful start. Assignment shall not search older sessions by
  camera, reactivate a historical session, or merge existing sessions.
- **SESSION-LINK-003** — A new start shall join that candidate only when
  its elapsed time since the most recent successful start is nonnegative
  and no greater than the one-hour connection window W, and its elapsed
  time since the candidate's first start is less than the eight-hour
  maximum admission span M. Otherwise it shall begin a distinct session.
- **SESSION-LINK-004** — M shall bound admission of new records, not timer
  execution or the final completion time of a member. A member timer may
  continue past M and retain its original session. A 25-hour timer started
  at 09:00 and another started at 09:50 shall therefore share a session;
  the long duration is not a separate reason to reject the second start.
  Repeated starts within W shall not extend admission beyond M.
- **SESSION-LINK-005** — The time rule shall apply across alternating
  cameras and overlapping timers, including starts before any earlier
  timer completes. Simultaneous starts shall resolve deterministically
  using stable creation order and timer identity rather than their input
  array order. The resulting membership shall remain the same when the
  same simultaneous records are presented in a different input order.
- **SESSION-LINK-006** — Pausing, resuming, continued running, completion,
  manual or automatic cancellation, viewing, and restoration shall not
  renew the connection activity or change an existing membership. A long
  running or abandoned paused timer shall not bridge otherwise separate
  shooting activity.
- **SESSION-LINK-007** — Midnight and a change of display time zone alone
  shall not split a session. A start earlier than the previous activity
  time shall begin a distinct session rather than count as a valid
  nonnegative gap.
- **SESSION-LINK-008** — Removing a timer shall not reassign surviving
  records or merge sessions. Deletion shall not rewind the already-established admission boundary. A session
  without any surviving records shall not appear as an openable empty
  result. This does not define later note or photo retention.

### Browsing

- **SESSION-BROWSE-001** — The default History shall retain its terminal
  time ordering and deterministic tie behavior under `timers/workspace.md`.
  Session presentation shall not reorder records into contiguous blocks.
- **SESSION-BROWSE-002** — A photographer shall be able to identify a
  record's session and open that session from History using a visible text
  cue and an accessible action. Color shall be supplementary only.
- **SESSION-BROWSE-003** — Session cues shall distinguish sessions on the
  same date and remain distinguishable from individual timer sequence
  numbers. Assistive technology shall identify the session and open action.
  Session cues remain subject to the existing timer-cell dimension and
  accessibility requirements in `timers/workspace.md`.
- **SESSION-BROWSE-004** — The session destination shall show its member
  Timer records and allow return to History without changing timer state,
  identity, membership, or History order. The destination shall include
  active and terminal members in separate groups. Terminal members shall follow the same ordering as History;
  active members shall follow the existing active ordering.
- **SESSION-BROWSE-005** — A readable record with no confirmed membership
  shall not offer a misleading confirmed-session link. Absence of
  assignment shall not hide the record or prevent its existing actions.

### Persistence and recovery

- **SESSION-PERSIST-001** — Timer identities, session identities, and
  confirmed memberships shall survive termination and relaunch, including
  while member timers are running or paused.
- **SESSION-PERSIST-002** — Timer restoration follows `timers/lifecycle.md`.
  Its original completion or pause-expiration times shall not become new
  session activity when discovered on restore.
- **SESSION-PERSIST-003** — Failure to save or load session assignment shall
  not delete, duplicate, or hide otherwise-readable Timer records or
  overwrite previously confirmed memberships. History remains usable.
- **SESSION-PERSIST-004** — Retrying an interrupted or failed assignment,
  including after relaunch, shall complete the same logical assignment for
  the existing timer rather than create another timer or conflicting
  memberships. An already confirmed assignment shall remain unchanged.
- **SESSION-PERSIST-005** — An assignment shall not be presented as durably
  confirmed until it can survive relaunch. A pending assignment shall be
  visibly distinguishable and shall not require starting the timer again
  to retry. Failure to save a new timer itself shall not be represented as
  a durably saved record.
- **SESSION-PERSIST-006** — Unreadable or partially recovered session data
  shall not invalidate independently readable timer data. Retry shall not
  replace known valid membership with an empty result merely because a read
  failed. Existing additive evolution, per-record decode isolation, and
  quarantine rules remain owned by `cross-cutting/persistence.md`.
- **SESSION-PERSIST-007** — If the new Timer record itself cannot be
  retained durably, starting it shall report failure with an explanation
  and shall not be acknowledged as a successful start or advance session
  activity. Existing records and memberships shall remain intact. A retry
  shall resolve the same logical start without duplicating a retained
  record. An assignment-only failure follows SESSION-PERSIST-003 through
  SESSION-PERSIST-005 and shall not be reported as loss of the Timer.

### iPhone debug timing

- **SESSION-DEBUG-001** — An iPhone debug build shall expose one toggle,
  `Shorten session intervals`, under the Settings debug tools. The toggle
  shall not be available in a production build.
- **SESSION-DEBUG-002** — With the toggle off, W is 3,600 seconds and M is
  28,800 seconds. With it on, W is 60 seconds and M is 480 seconds. All
  other admission rules remain identical, including gap ≤ W and span < M.
- **SESSION-DEBUG-003** — A mode shall apply from the first start in an
  independent timing comparison. For starts at 0 and 70 seconds, normal
  mode shall produce one session and shortened mode two sessions.
- **SESSION-DEBUG-004** — Starting at 0 seconds and every 50 seconds through
  450 seconds shall keep those records in one session in both modes.
  Independently adding a last start at 479 seconds shall retain that
  session in both modes. Adding it at 480 seconds shall retain the session
  in normal mode and create a new session in shortened mode. Previously
  assigned records shall retain their memberships.
- **SESSION-DEBUG-005** — Changing the toggle shall not recalculate existing
  memberships. Two starts 70 seconds apart that shared a session before
  normal-to-shortened switching shall keep their individual session
  identities. Two starts that belonged to distinct sessions before
  shortened-to-normal switching shall remain distinct. Each timer's
  identity and session identity shall survive relaunch unchanged.
- **SESSION-DEBUG-006** — The toggle shall not alter timer countdowns,
  exposure calculations, alerts, device time, or the fixed two-minute
  pause deadline. In both switch directions, without another timer start,
  a paused timer shall remain Paused at 119.999 seconds after pausing and
  become Canceled at exactly 120 seconds, preserving timer identity,
  session identity, and frozen remaining exposure at cancellation.
- **SESSION-DEBUG-007** — The debug surface shall provide interval shortening
  only. It shall not add scenario selection, automatic test execution,
  prepared-data loading, a separate test workspace, or guided test flows.

## Non-goals

- Changing calculation, timer transitions, the pause deadline, or alerts.
- Requiring location permission or a separate session setup to use timers.
- Notes, photos, manual Collection management, session merge or split,
  export, synchronization, or automatic record expiry.
- Replacing chronological History with a session-sorted default list.
- Inferring whether short-gap home tests and a later outing are different
  activities. They follow the same time-only rule; no optional manual
  session-start boundary is introduced in this increment.

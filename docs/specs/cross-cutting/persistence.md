<!-- Copyright © 2026 Sangwook Han -->
<!-- SPDX-License-Identifier: Apache-2.0 -->

# Persistence and Schema Evolution

| Prefix | Owns |
| --- | --- |
| PERSIST | Version gating and additive evolution |
| PERSIST-RECORD | Per-record decode isolation within a collection |
| PERSIST-QUARANTINE | Preserving a failed payload for later inspection |

## Purpose

Persisted shooting context and timers shall survive normal relaunches and
additive schema evolution, without one malformed record destroying
unrelated valid data.

## Current behavior

Every persisted collection whose records embed an evolving enum or a
sum-type discriminator — the custom film library, the timer-state
collection, the timer-metadata collection, and the timer workspace
snapshot — follows one uniform decode policy, applied identically on both
platforms. The camera-slot session follows a related but distinct policy
(see below) because it has its own legacy-migration path.

## Requirements

### Version gating and additive evolution

- **PERSIST-001** — `schemaVersion` is an equality gate: a payload whose
  version matches the current value decodes; a payload with any other
  version is rejected whole, with no records restored.
- **PERSIST-002** — A payload with no `schemaVersion` field is accepted as
  legacy version 1, so a payload written before the field existed continues
  to restore unchanged.
- **PERSIST-003** — Adding an Optional field is an additive change and
  never requires a version bump; an older payload that lacks the new field
  decodes with it treated as absent. A breaking change (renaming or
  removing a field, or changing what an existing field means) requires a
  coordinated version increment and a documented migration step.
- **PERSIST-004** — The camera-slot session uses its own version-and-
  fallback rule: an unrecognized session-schema version is rejected and the
  runtime falls back to the legacy single-context migration path (see
  `shooting/camera-slots.md`) rather than the uniform per-record policy
  below, because a slot session has no per-record structure to isolate.

### Per-record isolation

- **PERSIST-RECORD-001** — Within an accepted payload, each record decodes
  independently; a record that fails to decode (an unrecognized enum
  value, an unknown discriminator, a structurally malformed entry) is
  dropped, and the remaining valid records still restore.
- **PERSIST-RECORD-002** — Records are keyed by a stable id; a duplicate id
  resolves deterministically to the first valid occurrence.
- **PERSIST-RECORD-003** — Domain enum decoders themselves stay strict —
  the tolerance described here lives only in the persistence codec, so the
  bundled catalog loader and the calculation policy are unaffected by it.
- **PERSIST-RECORD-004** — The records array is required whenever a payload
  is present: an accepted payload whose records field is absent, or is not
  an array, is treated as malformed — not as a legitimately empty
  collection. A genuinely empty collection is the absence of the payload
  itself, which is a distinct, clean state from a payload present on disk
  but corrupt.

### Quarantine and signal

- **PERSIST-QUARANTINE-001** — When any decode failure occurs (a dropped
  record, a rejected version, a malformed root), the original raw payload
  is copied to a sibling quarantine key at load time, before a later save
  can overwrite the primary key.
- **PERSIST-QUARANTINE-002** — The quarantine preserves the latest failed
  payload as a whole (not per-record fragments): a later failed load
  replaces it, and any non-failing operation leaves it intact.
- **PERSIST-QUARANTINE-003** — Clearing a collection to empty — including
  when a restore recovers zero records — removes only the primary key and
  preserves the quarantine, so the very restore cycle that produced the
  quarantine cannot destroy it.
- **PERSIST-QUARANTINE-004** — A decode failure logs a diagnostic signal
  (at minimum: failure kind, dropped-record count, schema context) without
  ever logging the raw payload or user data.
- **PERSIST-QUARANTINE-005** — There is no automatic re-ingestion of a
  quarantined payload and no user-facing recovery workflow; the quarantine
  exists for later inspection only.
- **PERSIST-QUARANTINE-006** — A failure while writing the quarantine copy
  itself is isolated from the load result: it shall never turn an
  otherwise-successful degraded recovery into an empty or failed load. The
  records already recovered from the primary payload are still returned; a
  quarantine-write failure may be logged/signaled but never discards or
  hides them.

## Non-goals

- A general migration framework or versioned-dispatch table beyond the
  simple equality-gate-plus-fallback described above.
- Cross-platform byte-identical persistence formats.
- A user-facing recovery UI for quarantined or degraded data.

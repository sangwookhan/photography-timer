<!-- Copyright © 2026 Sangwook Han -->
<!-- SPDX-License-Identifier: Apache-2.0 -->

# Persistence and Schema Evolution

| Prefix | Owns |
| --- | --- |
| PERSIST | Version gating, release migration, and additive evolution |
| PERSIST-CAMERA-SEQUENCE | Independent camera automatic-name allocation |
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
platforms. The managed-camera session follows a related but distinct policy
(see below) because it retains the former camera-slot session's legacy-
migration path. Filter inventory
uses the saved-state exception below so empty or failed recovery cannot
be mistaken for first use.

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
- **PERSIST-004** — The managed-camera session uses its own documented
  version-and-migration rule (see `shooting/camera-slots.md`). A valid managed
  payload wins over every remaining legacy payload. Legacy migration runs only
  when no managed payload exists and keeps its source usable until the full
  managed state persists successfully, so retry is idempotent and cannot
  duplicate cameras. When stored content is read successfully but its version,
  camera collection, or whole managed payload cannot be decoded, one atomic
  write replaces it with fresh camera state using new opaque identities; the
  unreadable content is thereby deleted without exposing an absent-payload
  interval or running legacy migration. If the storage read supplies no content
  because it failed, camera persistence performs no delete or write, disables
  camera actions for that launch, and shows `Camera data couldn't be loaded.
  Restart the app.` on both platforms (or its localized equivalent).
  Initialization retries on the next launch. Timer persistence remains
  independent and unchanged.
- **PERSIST-005** — The current managed-camera release supports the fixed-slot
  storage shapes represented by the official 0.8.0 platform fixtures and the latest
  pre-PTIMER-234 official 0.9.1 platform fixtures identified by
  `docs/verification/Strategy.md`.
  Beginning with the first official release of a versioned managed-camera
  payload, each later official schema adds an ordered path to the current
  schema and activates it only after required companion state is ready.
  Development-only Draft and contaminated payloads are cleared from test
  installations instead of becoming product migration sources.
- **PERSIST-CAMERA-SEQUENCE-001** — The automatic `Camera N` sequence shall
  use a dedicated versioned store. The managed camera list, its names,
  identities, count, order, and timer records are not sources for its next
  value.
- **PERSIST-CAMERA-SEQUENCE-002** — Reserving an automatic number durably
  advances the sequence before the new camera record is committed. A crash may
  skip a reserved number but does not make it available again while the stored
  sequence remains readable. If it cannot be read, the fallback in
  PERSIST-CAMERA-SEQUENCE-003 may repeat a display number without reusing camera
  identity.
- **PERSIST-CAMERA-SEQUENCE-003** — Migration from either supported fixed-slot
  shape shall persist sequence value 5 before activating the migrated camera
  payload. Later official managed-camera migrations carry the stored next value
  forward before activation. When no next value can be read, the normal camera-
  addition allocator starts at 5, persists 6 before committing `Camera 5`, and
  continues from that stored value without inspecting camera or timer data.

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
  but corrupt. Filter inventory is an exception: a successfully saved empty
  inventory shall remain an explicit stored empty state, distinct from an
  inventory that has never been saved.

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
  quarantine cannot destroy it. For filter inventory, clearing all Sets shall
  store an explicit empty inventory instead of removing the primary payload.
  Malformed, unsupported or failed inventory reads shall not remove the primary
  payload or convert previously stored inventory into never-saved absence;
  preserve the failure evidence under the quarantine rules above. None of
  these states shall seed Samples under `calculator/filter-sets.md`.
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

- A general migration framework for domains outside managed-camera
  persistence. Managed cameras use the explicit release-to-release migration
  chain required by PERSIST-005.
- Cross-platform byte-identical persistence formats.
- A user-facing recovery UI for quarantined or degraded data.

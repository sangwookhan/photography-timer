# Task Spec: <TICKET_ID> <Short Title>

## Metadata

- Ticket: `<PTIMER-XXX>`
- Epic: `<PTIMER-EPIC-ID or N/A>`
- Feature Branch: `codex/PTIMER-<ID>-<short-slug>`
- Target Platform: `iPhone / SwiftUI / Xcode`
- Related Docs:
  - Jira: `<link or reference>`
  - Confluence: `<link or reference>`
  - Supporting Docs: `<Docs/... or other references>`

---

## 1. Goal

Describe the concrete outcome this task must achieve.

Keep this outcome-oriented.
State what should be true after the change is complete.

Example:

- Restore missing metadata display in a reciprocity result screen
- Preserve existing calculation behavior

---

## 2. Scope

List what is included in this task.

Example:

- update the affected presentation or view-model path
- render the missing value in the intended UI location
- add focused regression coverage for the affected behavior

---

## 3. Out of Scope

List what must not be done in this ticket.

Example:

- no exposure-engine policy changes
- no timer behavior changes
- no persistence schema changes
- no unrelated copy or layout cleanup

---

## 4. Protected / Do-Not-Change Areas

Name any protected files, modules, or behaviors.

Common examples in this repository:

- exposure calculation behavior
- reciprocity calculation rules
- confidence presentation mapping
- timer runtime semantics
- persistence and restore behavior

List specific files if needed.

---

## 5. Constraints and Policy

State rules the implementation must follow.

Examples:

- keep architecture boundaries intact
- do not duplicate business logic in SwiftUI views
- prefer the smallest change that satisfies the task
- preserve existing naming unless cleanup is explicitly requested

---

## 6. Expected Approach

Describe the intended implementation path at a high level.

Example:

1. identify where the required value is produced or dropped
2. restore propagation through the correct layer
3. render it without changing protected calculation behavior
4. add targeted regression tests

This should guide implementation, not prescribe exact code.

---

## 7. Test Requirements

### Required

- relevant existing tests pass
- new or updated focused regression coverage exists for changed behavior

### Suggested Commands

```bash
cd ios && xcodebuild -project PTimer.xcodeproj -scheme PTimer \
  -destination 'platform=iOS Simulator,name=iPhone 17' test
```

If needed, narrow to a relevant suite or test plan and record the exact
command used in the final report.

### Manual Checks

- `<manual check 1>`
- `<manual check 2>`

---

## 8. Definition of Done

The task is complete when all are true:

- the goal is achieved
- the change stayed inside scope
- protected behavior remains unchanged unless explicitly targeted
- relevant tests pass
- the diff is reviewable and intentional
- the final report includes summary, tests, and remaining risks

---

## 9. Review Checkpoints

Reviewers should verify:

1. Is the implementation aligned with the goal?
2. Did the change stay inside scope?
3. Were protected areas preserved?
4. Are architecture boundaries still clear?
5. Is the regression coverage sufficient?
6. Did any behavior expand silently?

---

## 10. Delivery Notes

Implementation output should include:

- files changed
- behavior summary
- tests run
- known limitations
- follow-up candidates if any

---

## 11. Open Questions

List unresolved points that must not be guessed.

Examples:

- exact copy not finalized
- policy source unclear between Jira and existing tests
- UI placement needs product confirmation

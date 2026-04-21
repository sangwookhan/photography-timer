# AGENTS.md

## Purpose

This repository uses a three-step execution workflow:

1. ChatGPT prepares the execution-ready task spec
2. Codex app coordinates implementation and review flow
3. Codex CLI implements, verifies, and reports results

For ticket work, the prepared task spec is the primary source of truth.
Raw Jira and Confluence pages are supporting references unless the user
explicitly says otherwise.

---

## Repository Context

- Product target: iPhone app
- Stack: Swift, SwiftUI, Xcode project
- Workspace entry point: `PTimer.xcodeproj`
- Main app scheme: `PTimer`
- Test target: `PTimerTests`
- Current automated tests use `XCTest`

Existing product documents live under `Docs/`.
Operational workflow documents may live at repository root, `Docs/tasks/`,
and `.codex/`.

---

## Source of Truth Order

Use this order when deciding what to implement:

1. Explicit user instruction in the current conversation
2. Prepared task spec for the ticket
3. Existing architecture, tests, and code contracts
4. Jira ticket
5. Confluence page
6. Existing implementation details not covered above

If Jira or Confluence wording conflicts with the task spec, follow the
prepared spec unless the user explicitly overrides it.

---

## Required Working Style

For each ticket:

1. Read the task spec first
2. Restate the goal, scope, and protected areas
3. Limit changes to the declared scope
4. Do not broaden the task through interpretation
5. Add or update focused tests where behavior changes
6. Run relevant verification before finishing
7. Report summary, tests, and remaining risks

When something is unclear, say what is ambiguous instead of guessing.

---

## Scope Discipline

- Do not change app behavior outside the prepared task scope
- Do not mix opportunistic cleanup into focused ticket work
- Do not rename, move, or restructure files without task-level approval
- Prefer the smallest change that satisfies the spec

Protected areas for many tickets:

- exposure calculation behavior
- reciprocity policy and domain rules
- confidence presentation mapping
- timer runtime semantics
- restore and persistence semantics

If a task is UI-only, do not change policy or calculation behavior.
If a task is policy-only, do not reshape unrelated UI or copy.

---

## Architecture Expectations

Respect separation of concerns between:

- app and composition
- domain and policy logic
- presentation and formatting
- state coordination / view model layers
- SwiftUI view rendering
- persistence and restore behavior

Avoid:

- business logic in SwiftUI views
- duplicate formatting or mapping paths
- weakening domain rules for UI convenience
- silent behavior expansion

---

## iOS Test and Verification Guidance

Prefer verification that matches the changed layer.

Typical commands:

```bash
xcodebuild -project PTimer.xcodeproj -scheme PTimer \
  -destination 'platform=iOS Simulator,name=iPhone 17' test
```

```bash
xcodebuild -project PTimer.xcodeproj -scheme PTimer \
  -testPlan PTimer \
  -destination 'platform=iOS Simulator,name=iPhone 17' test
```

Guidance:

- Domain or policy changes require unit/regression tests
- View model changes require state-oriented tests
- UI composition changes should include targeted verification where possible
- Documentation-only changes do not require app test changes, but the final
  report should say that no runtime behavior was modified

If a simulator name differs locally, choose an available iPhone simulator from
`xcodebuild -showdestinations`.

---

## Task Spec Location

Preferred path for prepared task specs:

- `Docs/tasks/<TICKET_ID>.md`

Use `Docs/tasks/TASK_TEMPLATE.md` as the starting point for new tickets.

Feature or verification reference material may remain in `Docs/`.

---

## Suggested Skills Layout

If project-scoped Codex skills are added later, prefer this structure:

```text
.codex/
  config.toml
  skills/
    README.md
    ios-xcode-build/
      SKILL.md
    swift-testing/
      SKILL.md
    ticket-delivery/
      SKILL.md
    code-review/
      SKILL.md
```

Recommended responsibilities:

- `ios-xcode-build`: build, simulator, scheme, and `xcodebuild` conventions
- `swift-testing`: unit test targeting, regression coverage, and test commands
- `ticket-delivery`: task-spec execution, scope control, and final reporting
- `code-review`: review checklist aligned with `code_review.md`

---

## Review and Delivery Expectations

Implementation output should always include:

1. What changed
2. Files changed
3. Tests run
4. Remaining risks or follow-up items
5. Notes for human review

Review should be done against the task spec, not personal preference alone.

---

## Commit Message Expectations

When creating or amending commits for this repository:

- follow standard Git subject/body formatting with a short imperative summary
- keep body paragraphs wrapped consistently
- when recording ticket context at the bottom, use `TICKET-ID Title` format
- ticket context lines must use a hanging indent on wrapped lines

Example:

```text
PTIMER-102 Extend quantified extrapolation policy for table-profile
           films beyond the current limit
```

Do not use a flush-left continuation line for wrapped ticket context.

---

## Escalation Triggers

Escalate instead of guessing when:

- the task spec is incomplete
- Jira or Confluence implies a different behavior
- protected calculation behavior may be affected
- architecture boundaries would need to expand
- the correct test target is unclear

When escalating, state:

- what is unclear
- what options exist
- which files or layers are affected
- which option is recommended

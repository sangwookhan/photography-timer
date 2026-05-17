# AGENTS.md

## Purpose

This repository uses a three-role execution workflow:

1. ChatGPT acts as product manager, app designer, and senior architect
2. Claude Code acts as working architect and development manager, and may
   implement when appropriate
3. Codex CLI acts as the primary developer and implements, verifies, and
   reports results

For ticket work, the execution-ready task spec approved by Claude Code is the
primary implementation source of truth. That task spec should reflect the
product intent, UX direction, and higher-level architectural guidance prepared
by ChatGPT. Raw Jira and Confluence pages are supporting references unless the
user explicitly says otherwise.

---

## Role Responsibilities

### ChatGPT

- Defines product intent, UX direction, and senior architectural constraints
- Clarifies goals, non-goals, and acceptance expectations
- Provides high-level tradeoff decisions when product or design intent matters

### Claude Code

- Converts ChatGPT guidance into execution-ready implementation tasks
- Defines implementation scope, sequencing, review checkpoints, and protected
  areas for the current task
- Acts as the escalation point for implementation ambiguity, delivery planning,
  and task management
- May implement directly when appropriate, but remains responsible for
  architectural coordination

### Codex CLI

- Treats Claude Code's execution-ready task spec as the immediate
  implementation guide
- Restates the goal, scope, and protected areas before changing code
- Implements with minimal scope, adds focused verification, and reports
  concrete outcomes
- Does not expand scope without escalation

---

## Repository Context

- Product target: iPhone app
- Stack: Swift, SwiftUI, Xcode project
- Workspace entry point: `ios/PTimer.xcodeproj`
- Main app scheme: `PTimer`
- Test target: `ios/PTimerTests`
- Current automated tests use `XCTest`

iOS sources live under `ios/`. Shared cross-platform fixtures live at
`shared/test-fixtures/`. Existing product documents live under `docs/`.
Operational workflow documents may live at repository root, `docs/tasks/`,
and `.codex/`.

---

## Source of Truth Order

Use this order when deciding what to implement:

1. Explicit user instruction in the current conversation
2. ChatGPT product intent, UX direction, and senior architectural guidance
3. Claude Code execution-ready task spec and delivery instructions
4. Existing architecture, tests, and code contracts
5. Jira ticket
6. Confluence page
7. Existing implementation details not covered above

If Jira or Confluence wording conflicts with ChatGPT or Claude Code guidance,
follow the higher-priority source unless the user explicitly overrides it.

---

## Required Working Style

For each ticket:

1. Read the Claude Code task spec first
2. Restate the goal, scope, and protected areas
3. Limit changes to the declared scope
4. Do not broaden the task through interpretation
5. Add or update focused tests where behavior changes
6. Run relevant verification before finishing
7. Report summary, tests, and remaining risks

Implementation should follow the product intent defined by ChatGPT and the
execution scope defined by Claude Code.

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

Typical commands, run from the repository root:

```bash
cd ios && xcodebuild -project PTimer.xcodeproj -scheme PTimer \
  -destination 'platform=iOS Simulator,name=iPhone 17' test
```

```bash
cd ios && xcodebuild -project PTimer.xcodeproj -scheme PTimer \
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

- `docs/tasks/<TICKET_ID>.md`

Use `docs/tasks/TASK_TEMPLATE.md` as the starting point for new tickets.

Feature or verification reference material may remain in `docs/`.

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

Review should be done against ChatGPT product intent and the Claude Code task
spec, not personal preference alone.

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

Escalation path:

- Escalate to ChatGPT when product intent, UX direction, or senior
  architecture guidance is unclear or conflicting
- Escalate to Claude Code when execution scope, task sequencing, ownership, or
  verification strategy is unclear

When escalating, state:

- what is unclear
- what options exist
- which files or layers are affected
- which option is recommended

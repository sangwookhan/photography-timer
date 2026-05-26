# AGENTS.md

This file is the canonical operating manual for any AI agent (Claude
Code, Codex CLI, or others) working in this repository. `CLAUDE.md`
is a symbolic link to this file so the two auto-loaded surfaces stay
in sync.

## Purpose

This repository uses a multi-role execution workflow with two
supported pipelines:

- **Three-role pipeline** — ChatGPT → Claude Code → Codex CLI
- **Two-role pipeline** — ChatGPT → Codex CLI (Codex CLI acts as
  both planner and implementer)

For ticket work, the **execution-ready task spec** is the primary
implementation source of truth. That spec MAY be authored by Claude
Code (three-role) or by Codex CLI itself (two-role). In either case
the spec should reflect the product intent, UX direction, and
higher-level architectural guidance prepared by ChatGPT. Raw Jira
and Confluence pages are supporting references unless the user
explicitly says otherwise.

---

## Role Responsibilities

Roles are described as **capabilities**, not fixed positions. In the
two-role pipeline, Codex CLI inherits the Claude Code capabilities
in addition to its own.

### ChatGPT

- Defines product intent, UX direction, and senior architectural
  constraints
- Clarifies goals, non-goals, and acceptance expectations
- Provides high-level tradeoff decisions when product or design
  intent matters

### Claude Code (when present in the chain)

- Converts ChatGPT guidance into execution-ready implementation tasks
- Defines implementation scope, sequencing, review checkpoints, and
  protected areas for the current task
- Acts as the escalation point for implementation ambiguity,
  delivery planning, and task management
- May implement directly when appropriate, but remains responsible
  for architectural coordination

### Codex CLI

- Treats the execution-ready task spec as the immediate
  implementation guide
- In the two-role pipeline, ALSO authors that spec from ChatGPT
  guidance before implementing
- Restates the goal, scope, and protected areas before changing code
- Implements with minimal scope, adds focused verification, and
  reports concrete outcomes
- Does not expand scope without escalation

---

## Repository Context

- Primary product target: iPhone app
- iOS stack: Swift, SwiftUI, Xcode project
- iOS workspace entry point: `ios/PTimer.xcodeproj`
- iOS main app scheme: `PTimer`
- iOS test target: `ios/PTimerTests`
- iOS automated tests use `XCTest`
- Secondary platform: native Android skeleton (`android/`,
  Kotlin + Jetpack Compose, Gradle). Android build entry point:
  `android/build.gradle.kts`; app module: `android/app`.

iOS sources live under `ios/`. Android sources live under `android/`.
Shared cross-platform fixtures live at `shared/test-fixtures/`.
Existing product documents live under `docs/`. Operational workflow
documents may live at repository root, `docs/tasks/`, and `.codex/`.

PTimer is a portrait-only iPhone app for film photography exposure
calculation and countdown timers. The architecture has strict layer
boundaries (one-way reads, single-owner state, dedicated coordinators
for external surfaces) and a small set of fitness rules enforced via
SwiftLint.

The current structure — layer-by-layer file ownership, dependency
direction, naming conventions, and source-of-truth ownership table —
lives in [`docs/architecture/Architecture.md`](docs/architecture/Architecture.md).
Read that document when you need to know which file owns which
responsibility.

---

## Source of Truth Order

Use this order when deciding what to implement:

1. Explicit user instruction in the current conversation
2. ChatGPT product intent, UX direction, and senior architectural
   guidance
3. Execution-ready task spec and delivery instructions (whether
   authored by Claude Code or by Codex CLI itself)
4. Existing architecture, tests, and code contracts
5. Jira ticket
6. Confluence page
7. Existing implementation details not covered above

If Jira or Confluence wording conflicts with ChatGPT guidance or the
execution-ready task spec, follow the higher-priority source unless
the user explicitly overrides it.

---

## Required Working Style

For each ticket:

1. Read the execution-ready task spec first
2. Restate the goal, scope, and protected areas
3. Limit changes to the declared scope
4. Do not broaden the task through interpretation
5. Add or update focused tests where behavior changes
6. Run relevant verification before finishing
7. Report summary, tests, and remaining risks

Implementation should follow the product intent defined by ChatGPT
and the execution scope captured in the task spec.

When something is unclear, say what is ambiguous instead of guessing.

---

## Scope Discipline

- Do not change app behavior outside the prepared task scope
- Do not mix opportunistic cleanup into focused ticket work
- Do not rename, move, or restructure files without task-level
  approval
- Prefer the smallest change that satisfies the spec

If a task is UI-only, do not touch policy, calculation, or
persistence code.
If a task is policy-only, do not reshape unrelated UI or copy.

Documentation-only changes do not require app test execution.

---

## Behavioral Guardrails

These guardrails apply across every ticket and complement the
Required Working Style and Scope Discipline sections. They exist
to reduce common LLM coding mistakes; for trivial tasks, use
judgment.

### Think before coding

- State assumptions explicitly before implementing. If a key input
  is uncertain, name it instead of guessing.
- When multiple reasonable interpretations exist, present them
  rather than silently picking one.
- When a simpler approach exists, say so — push back on
  overcomplication, even if the brief implies otherwise.
- If something is unclear, stop and name what is confusing. Do not
  hide confusion behind speculative code.

### Simplicity first

- Write the minimum code that satisfies the spec. No speculative
  features, configurability, or abstractions for single-use code.
- Do not add error handling for scenarios that cannot occur within
  the declared scope (see also `docs/conventions/ErrorModel.md`).
- If the change feels long for what it is, rewrite it shorter
  before reporting it. Ask: "Would a senior engineer call this
  overcomplicated?"

### Surgical changes

Reinforces the Scope Discipline section above:

- Match the surrounding style even if you would write it
  differently elsewhere.
- Do not "improve" adjacent code, comments, or formatting.
- Remove imports, helpers, and variables that YOUR change made
  unused. Do not delete pre-existing dead code that your change
  did not orphan — mention it in the final report instead.
- Every changed line should trace directly to the declared task
  scope.

### Goal-driven execution

- Convert each task into a verifiable success criterion before
  starting:
  - "Add validation" → "Write tests for invalid inputs, then make
    them pass"
  - "Fix the bug" → "Write a test that reproduces it, then make it
    pass"
  - "Refactor X" → "Tests pass before and after, behavior unchanged"
- For multi-step work, write the plan as `Step → verify: check`
  pairs so each step has a concrete checkpoint. This feeds the
  verification step in Required Working Style and the test-run
  expectations under Build and Test Commands.

---

## Protected Areas

The following behaviors must not be changed without explicit
task-level authorization:

- Exposure calculation rules (`ExposureCalculator.calculate`,
  snap-to-full-stop, `stabilityEpsilon`)
- Reciprocity policy evaluation order and result semantics
  (`ReciprocityCalculationPolicyEvaluator`)
- Confidence presentation mapping (`ReciprocityConfidencePresentation`)
- Timer runtime semantics (pause/resume/complete state machine,
  `TimerManager`)
- Persistence and restore contracts (snapshot schemas, UserDefaults
  keys)

Protected Areas carry a stronger form of the spec-precedence rule
(see below): a spec change requires an explicit ticket; do not
silently re-derive behavior from code.

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

## Build and Test Commands

Commands are run from the repository root. Cross-platform fixtures
stay at the repo root under `shared/test-fixtures/`.

### iOS

```bash
# Run all tests
cd ios && xcodebuild -project PTimer.xcodeproj -scheme PTimer \
  -testPlan PTimer \
  -destination 'platform=iOS Simulator,name=iPhone 17' test

# Run tests without a test plan (same scheme, ad-hoc)
cd ios && xcodebuild -project PTimer.xcodeproj -scheme PTimer \
  -destination 'platform=iOS Simulator,name=iPhone 17' test

# List available simulator destinations
cd ios && xcodebuild -showdestinations -project PTimer.xcodeproj -scheme PTimer
```

If `iPhone 17` is unavailable, choose any available iPhone simulator
from the destinations list.

To run a single test class, add `-only-testing PTimerTests/<ClassName>`
to the command.

iOS verification guidance:

- Domain or policy changes require unit/regression tests
- View model changes require state-oriented tests
- UI composition changes should include targeted verification where
  possible
- Documentation-only changes do not require app test changes, but
  the final report should say that no runtime behavior was modified

### Android

```bash
cd android && ./gradlew assembleDebug          # build debug APK
cd android && ./gradlew test                   # unit tests
cd android && ./gradlew lint                   # Android Lint
cd android && ./gradlew installDebug           # install on device/emulator
```

Requires JDK 17 or newer (Android Studio's bundled JBR is
sufficient; for CLI builds, point `JAVA_HOME` at a JDK 17+ install)
and `ANDROID_HOME` pointing at the Android SDK (or
`android/local.properties` with `sdk.dir=<path>`).
`connectedAndroidTest` is not part of skeleton DoD; gate it when
instrumented UI tests are introduced.

Prefer opening the repository root in Android Studio when reviewing
Git history across both platforms. If you open `android/` directly
and Git history is not visible, add the parent repository directory
as a Git root from *Preferences/Settings → Version Control →
Directory mappings*. Do not initialize a new Git repository inside
`android/`, and do not commit `android/.idea/`.

### Linting

A baseline `.swiftlint.yml` lives under `ios/`. The Phase 0 baseline
is intentionally relaxed to avoid churn; size and complexity
thresholds may be tightened as the codebase evolves. Run locally
from the repository root:

```bash
cd ios && swiftlint lint
```

CI integration is deferred until the platform decision (Bitbucket
Pipelines with self-hosted macOS runner, GitHub Actions, Xcode
Cloud, or local hooks only) is resolved.

---

## Task Spec Location

Preferred path for prepared task specs:

- `docs/tasks/<TICKET_ID>.md`

Use `docs/tasks/TASK_TEMPLATE.md` as the starting point for new
tickets. Feature or verification reference material may remain in
`docs/`.

---

## Companion Docs and Conventions

### Documentation map

Each document has a single role; cross-document references stay
single-rooted on the English paths.

- **`docs/requirements/Requirements.md`** — user-scenario-driven
  requirements layer between the user-need wiki and the behavior
  contracts. Personas, core scenarios with goals + steps + boundary
  conditions, functional requirements ("system shall …" with
  scenario back-references), non-functional requirements
  (determinism, type safety, architectural fitness, verification,
  performance, persistence stability), and explicit out-of-scope /
  reserved decisions. Read this first when answering "what does the
  app need to do, and why".
- **`docs/specs/{Calculator,Timer,UI,DomainSchema}.md`** — behavior
  contracts. Authoritative description of *what* the system does,
  written so the documents survive refactoring. Specs deliberately
  contain no code identifiers, file paths, or line numbers. Specs
  realize the requirements above at contract level.
- **`docs/architecture/Architecture.md`** — current code structure:
  layer stack, file-level responsibilities, dependency direction,
  source-of-truth ownership, naming conventions, and architectural
  fitness rules. Read this when you need to know which file owns
  which responsibility.
- **`docs/verification/Strategy.md`** — five-layer verification
  strategy. `docs/verification/{BackgroundNotificationDelivery,RelaunchRestore}.md`
  are rerunnable manual procedures.
- **`docs/conventions/ErrorModel.md`** — when to use `Optional`,
  `throws`, `Result`, and `precondition` in each layer.

### Korean translations

A Korean translation of Requirements and Specs lives under
`docs/translations/ko/` (same filenames). It is for human reference
only — this file and agent tooling reference the canonical English
paths above. Cross-references in any document shall point at the
English path (`docs/specs/Calculator.md`) so the citation graph
stays single-rooted.

### Spec precedence

When code under `ios/PTimer/` disagrees with a spec under
`docs/specs/`, treat it as either a bug or a spec drift, not as a
license to ignore the spec.

1. Follow the Source of Truth Order above.
2. If higher-priority guidance confirms a deliberate behavior
   change, update the spec.
3. Otherwise, change the code to match the spec.

The Protected Areas above carry a stronger form of this rule: a
spec change requires an explicit ticket; do not silently re-derive
behavior from code.

### Naming conventions

- **`*Storing` / `NoOp*` pair** — every persistence target exposes a
  `*Storing` protocol with a real implementation plus a `NoOp*`
  implementation that unit tests use.
- **`*Scheduling`** — same pair pattern for notification or
  live-activity adapters.
- **`Persistent*` prefix** — types that represent a serialized
  snapshot on disk; distinct from runtime state.
- **`*DisplayState` suffix** — transient view-model state struct
  that views consume read-only. Display state is computed, not
  stored. Files holding a single display-state type use the
  singular (`FilmSelectionDisplayState.swift`); files grouping
  several related display-state types use the plural
  (`FilmModeResultDisplayStates.swift`).
- **`*Coordinator` suffix** — types whose responsibility is to own
  the lifecycle of an external surface (Live Activity, dock,
  workspace) and reconcile its state. Coordinators are wiring; they
  do not hold business state. Example:
  `LockScreenTimerCoordinator`.
- **`*Presenter` suffix** — pure-value transforms from domain state
  into display state. Presenters take inputs as parameters (or an
  input struct), produce display-state output, and have no
  lifecycle or async dependency. Example:
  `FilmModeDetailsPresenter`.
- **`*Factory` suffix** — dependency-creation surface for the DI
  boundary. Provides `production()` / `test()` static factories
  that return a `*Dependencies` struct of collaborators. Example:
  `ViewModelDependencyFactory`.
- **Module-prefixed file groups** — when a directory contains
  several files for one structural area, share a common prefix
  (`BottomSheetWorkspace*` for the workspace shell breakdown,
  `ExposureCalculator*` for calculator-scoped types). Files outside
  that directory do not need the prefix.
- **`PTIMER-<n>-` filename prefix** — used only for ticket-scoped
  artifacts that are expected to disappear with the ticket.
  Permanent reference docs drop the prefix on rename.

---

## Suggested Skills Layout

If project-scoped Codex skills are added later, prefer this
structure:

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

- `ios-xcode-build`: build, simulator, scheme, and `xcodebuild`
  conventions
- `swift-testing`: unit test targeting, regression coverage, and
  test commands
- `ticket-delivery`: task-spec execution, scope control, and final
  reporting
- `code-review`: review checklist aligned with `code_review.md`

---

## Review and Delivery Expectations

Implementation output should always include:

1. What changed
2. Files changed
3. Tests run
4. Remaining risks or follow-up items
5. Notes for human review

Review should be done against ChatGPT product intent and the
execution-ready task spec, not personal preference alone.

---

## Commit Message Expectations

When creating or amending commits for this repository:

- follow standard Git subject/body formatting with a short
  imperative summary
- keep body paragraphs wrapped consistently
- when recording ticket context at the bottom, use `TICKET-ID Title`
  format
- ticket context lines must use a hanging indent on wrapped lines —
  not flush-left

Example:

```text
Short imperative summary

Body paragraphs wrapped consistently.

PTIMER-102 Extend quantified extrapolation policy for table-profile
           films beyond the current limit
```

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
- Escalate to Claude Code when execution scope, task sequencing,
  ownership, or verification strategy is unclear **and** Claude
  Code is part of the current pipeline
- In the two-role pipeline (no Claude Code in the chain), escalate
  all execution-scope ambiguity to ChatGPT

When escalating, state:

- what is unclear
- what options exist
- which files or layers are affected
- which option is recommended

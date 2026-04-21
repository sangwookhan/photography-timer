# Code Review Guide

## Purpose

This repository reviews implementation results against the approved task spec.
Raw Jira wording and reviewer preference are secondary to the prepared spec.

---

## Review Order

Review in this order:

1. goal alignment
2. scope control
3. protected-area compliance
4. architecture compliance
5. test sufficiency
6. regression risk
7. code clarity

---

## 1. Goal Alignment

Check whether the implementation actually satisfies the task goal.

Questions:

- Does the visible behavior match the spec?
- Is the required outcome complete?
- Is any important path still missing?

Request changes if:

- the solution addresses a different problem
- the goal is only partially satisfied without explanation

---

## 2. Scope Control

Check whether the change stayed inside the declared scope.

Questions:

- Were only the intended files and layers changed?
- Was unrelated cleanup mixed in?
- Did the implementation silently expand the task?

Request narrowing if:

- refactors unrelated to the ticket are mixed in
- opportunistic behavior changes reduce reviewability

---

## 3. Protected-Area Compliance

Many tickets must preserve sensitive behavior.

Common protected areas:

- exposure calculation rules
- reciprocity policy
- confidence mapping
- timer runtime semantics
- persistence and restore behavior

Questions:

- Did the ticket touch protected behavior without authorization?
- Did a UI task change calculation logic?
- Did policy work leak into presentation or view code?

---

## 4. Architecture Compliance

Check whether logic still lives in the correct layer.

Questions:

- Is business logic outside SwiftUI views?
- Are mapping and formatting concerns kept out of domain policy code?
- Is state ownership still clear?
- Is the smallest correct layer handling the change?

Request changes if:

- business logic moved into view code
- mapping logic is duplicated
- boundaries became harder to reason about

---

## 5. Test Sufficiency

Check both correctness and regression protection.

Questions:

- Were relevant tests run?
- Was changed behavior covered by focused tests?
- Do tests verify contracts rather than implementation trivia?
- Are edge cases or nearby regressions addressed?

Expected for app changes:

- relevant existing tests pass
- targeted regression tests exist for the behavior change
- no unexplained failures remain

For documentation-only tasks, verify that no runtime logic changed and note
that app tests were not required.

---

## 6. Regression Risk

Look for hidden side effects.

Questions:

- Could the change affect nearby workflows?
- Did shared view models, formatters, or policies change?
- Did persistence defaults or restore paths change?
- Did display-only work alter behavior semantics?

Call out medium or high risk areas explicitly.

---

## 7. Code Clarity

Evaluate maintainability after correctness.

Questions:

- Is the change easy to follow?
- Is naming coherent?
- Is the fix overly clever?
- Could a future maintainer understand why this exists?

Prefer:

- small, explicit code
- reviewable diffs
- comments only when they explain intent

---

## Review Output Format

Use the structure below when summarizing a review:

### Review Result

- Approved / Needs changes / Blocked

### What Matches the Spec

- `<item>`

### Issues Found

- `<issue>`

### Risks / Follow-ups

- `<risk or follow-up>`

### Test Assessment

- `<what was tested>`
- `<what is still missing>`

---

## Common Review Smells

Watch for:

- UI task that changed protected calculation behavior
- policy task that changed wording or layout unnecessarily
- duplicate formatter or mapper logic
- broad cleanup mixed into a focused fix
- tests updated only to fit incorrect implementation
- hidden persistence contract changes
- visually correct output without regression tests

---

## iOS / Xcode Checks

When relevant, reviewers should also confirm:

- the command used to test is appropriate for `PTimer.xcodeproj`
- the `PTimer` scheme or `PTimer` test plan was used intentionally
- simulator destination choice is documented when needed
- changed tests live in the expected `PTimerTests/...` area

---

## Approval Rule

A change is review-ready only if:

- it satisfies the task spec
- it respects scope
- it preserves protected behavior
- it includes sufficient verification
- it leaves clear notes for the human approver

Human approval still decides merge readiness.

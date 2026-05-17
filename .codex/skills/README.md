# Project Skills Proposal

This directory is reserved for project-scoped Codex skills used by future
ticket work. No executable skill is added yet. This file only proposes the
recommended structure.

## Proposed Layout

```text
.codex/
  config.toml
  skills/
    README.md
    ios-xcode-build/
      SKILL.md
      references/
    swift-testing/
      SKILL.md
      references/
    ticket-delivery/
      SKILL.md
      templates/
    code-review/
      SKILL.md
      checklists/
```

## Suggested Skill Responsibilities

### `ios-xcode-build`

- Xcode scheme discovery
- simulator destination selection
- `xcodebuild` build and test command patterns
- DerivedData and test troubleshooting notes

### `swift-testing`

- unit test targeting in `PTimerTests`
- regression test expectations by layer
- when to run full-suite vs focused tests
- common `XCTest` patterns used in this repository

### `ticket-delivery`

- execute prepared task specs faithfully
- keep scope tight
- report changed files, tests, and remaining risks
- align with `docs/tasks/TASK_TEMPLATE.md`

### `code-review`

- review against task spec
- use `code_review.md` checklist
- highlight scope, architecture, and regression risks

## Adoption Notes

- Add skills only when repeated ticket work shows a stable pattern
- Keep skill instructions repository-specific
- Prefer references and checklists over long prose
- Avoid adding product-policy rules here unless they are stable and approved

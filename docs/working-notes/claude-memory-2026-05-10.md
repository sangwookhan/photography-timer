# Claude Code memory backup — 2026-05-10

This is a snapshot of Claude Code's per-project auto-memory captured
before pausing PTIMER-25 work. The live memory lives under
`~/.claude/projects/-Users-sangwook-han-Playground-PTimerSpace-PTimerTryCodex/memory/`
on the original machine; this copy is committed so the same context
can be reconstructed after re-checking out the WIP commit on a fresh
session.

To restore on a new session: read the entries below, recreate the
files under `~/.claude/projects/<encoded-project-path>/memory/`, and
update `MEMORY.md` accordingly. Or just point the new Claude session
at this file.

---

## MEMORY.md (index)

```markdown
# Memory Index

- [Commit messages must include test procedure](feedback_commit_test_procedure.md) — Always add an English test procedure section to commit messages for PTimer
- [Structural improvement wiki tree](reference_structural_improvement_wiki.md) — Periodic code/architecture reviews accumulate under Confluence "구조 개선" hub (id 19070978)
- [Work efficiently, minimize tool calls](feedback_efficiency.md) — Avoid unnecessary tool calls and agent spawns to save tokens
- [Task specs are not committed](feedback_task_specs_excluded.md) — Exclude `docs/tasks/PTIMER-XX-*.md` files when staging ticket commits
- [Confirm before acting on context-unrelated requests](feedback_unrelated_request_confirmation.md) — Ask a short clarifying question when a new request looks like a topic switch from the active thread
```

---

## feedback_commit_test_procedure.md

```markdown
---
name: Commit messages must include test procedure
description: When writing commit messages for PTimer, always include the test procedure in English
type: feedback
originSessionId: 5f3e6aa7-1494-49ba-b569-cc037cbad740
---
Always include a test procedure (in English) in commit messages for this project.

**Why:** User explicitly requested this so that commit history is self-contained and reviewers can reproduce verification steps without needing external docs.

**How to apply:** Use this exact order:
1. Short imperative summary line
2. Body paragraphs
3. Test procedure: section (English, simulator steps — film, settings, badge, what to verify)
4. JIRA ticket context line (PTIMER-ID Title, hanging indent) — always last

Example structure:
```
Short imperative summary

Body explanation.

Test procedure:
1. Select Film X, set ND Y stops → badge Z → open details sheet.
   Confirm: ...
2. ...

PTIMER-100 Remove duplicated detail text in advisory and
           unsupported reciprocity states
```
```

---

## feedback_efficiency.md

```markdown
---
name: Work efficiently, minimize tool calls
description: Avoid unnecessary tool calls and agent spawns to save tokens
type: feedback
originSessionId: 5f3e6aa7-1494-49ba-b569-cc037cbad740
---
Work efficiently and minimize unnecessary tool calls and external agent spawns.

**Why:** User explicitly requested token-efficient work. Excessive tool calls waste context and slow down sessions.

**How to apply:** Plan steps mentally before calling tools. Batch related operations. Don't spawn subagents for tasks that can be done inline. Don't run evals or extra workflows unless the user asks for them.
```

---

## feedback_task_specs_excluded.md

```markdown
---
name: Task specs are not committed to the PTimer repo
description: Do not include docs/tasks/PTIMER-XX-*.md files in commits even if the task spec sits in the working tree
type: feedback
originSessionId: 7ea4f2a9-6a08-47c2-8fa1-461bf5e913cc
---
Do not commit task spec files (`docs/tasks/PTIMER-XX-*.md` or
`docs/tasks/PTIMER-XX-task-spec.md`) when committing implementation
work for a PTIMER ticket. The spec lives in Jira and as a local
working file; it is not a repo artifact.

**Why:** The user explicitly removed `docs/tasks/PTIMER-79-task-spec.md`
in commit 6c2af25 with the message "Task specs are kept out of the
repository per the working convention." A pre-existing
`PTIMER-88-color-correction-presentation-formatter.md` was a prior
mistake, not precedent.

**How to apply:** When staging files for a ticket commit on PTimer,
exclude any `docs/tasks/PTIMER-*` file even if it is in the working
tree. Stage `docs/tasks/TASK_TEMPLATE.md` only if the user
specifically asks for a template change. If the user later wants the
spec recorded somewhere, point them at Jira or ask before adding
anything to the repo.
```

---

## feedback_unrelated_request_confirmation.md

```markdown
---
name: Confirm before acting on context-unrelated requests
description: When a new request appears unrelated to the in-progress thread/context, ask a brief confirmation question before proceeding instead of executing immediately
type: feedback
originSessionId: 6a4802e9-abec-4e54-82ec-312b0b30c566
---
When a user request arrives that does not fit the current in-progress thread or context (e.g., implementing a different ticket while another is mid-work, switching topic abruptly), pause and ask a brief one-line clarifying question before acting.

**Why:** In this session, an implementation request for PTIMER-120 arrived embedded inside a larger PTIMER-121 management discussion. The request was acted on autonomously, but the user later said it was misrouted across threads. Asking first would have caught the misroute before code was written and a feature branch was created.

**How to apply:**
- Trigger when the new request's subject (ticket id, file area, task type) does not match the active thread's subject.
- Ask one short question, e.g. "현재 흐름과 별개의 요청 같은데, 맞나요?" before starting tool use.
- Auto-mode does not override this — auto-mode means execute decisively when intent is clear; an apparent topic shift is exactly the case where intent should be confirmed.
- Do not ask when the user is clearly continuing the current thread (e.g., "next story", "now do X under the same epic").
```

---

## reference_structural_improvement_wiki.md

```markdown
---
name: Structural improvement reviews live in Confluence "구조 개선" tree
description: Where periodic code/architecture/directory review reports are kept on Confluence for PTimer
type: reference
originSessionId: 14dc76ed-2e80-4ce0-8f52-f8431a4b145e
---
PTimer 코드·아키텍처·디렉토리 리뷰는 Confluence 위키의 "구조 개선" 트리에 누적된다.

- Confluence space: SD (Software Development), cloudId `sangwook.atlassian.net`, spaceId `229380`
- 프로젝트 루트 페이지: "사진가용 타이머 앱" (id `3440641`)
- 구조 개선 허브 페이지: id `19070978` — https://sangwook.atlassian.net/wiki/spaces/SD/pages/19070978
  - 운영 원칙(주기 점검, 즉시 착수 아님, 보호 영역 존중, Tier 1/2/3 우선순위)과 리뷰 항목 인덱스 보관.
- 첫 리뷰 항목: id `19103745` (2026-04-24 코드·아키텍처·디렉토리 리뷰 #1)

다음 점검 시:
1. 허브(`19070978`) 하위에 `YYYY-MM-DD 코드·아키텍처·디렉토리 리뷰 #N` 페이지를 새로 생성.
2. 허브의 "리뷰 항목" 섹션 목록에 날짜+제목 링크를 추가.
3. 이전 리뷰의 Tier 1/2/3 진행 여부, ViewModel LoC 추이, 테스트 커버리지 변화를 비교 기준으로 삼는다.

사용자는 개별 리뷰에서 즉시 개선을 진행하지 않으며, 누적된 결과를 바탕으로 **때가 되면 일괄 개선**을 수행한다.
```

---

## PTIMER-25 WIP context (recovery hints)

This commit is a temporary checkpoint of PTIMER-25 (Target Shutter
mode with stop-difference feedback). Not meant for review or merge.

Scope captured here:
- New `TargetShutterModel`, `TargetShutterPresenter`,
  `TargetShutterDisplayState`, `TargetShutterInputState`, and
  `TargetShutterSectionView`.
- `.targetShutter` exposure-source case + `TimerCardIdentityPresenter`
  routing.
- Per-camera-slot persistence of the target value
  (`CameraSlotCalculatorSnapshot`, `PersistentCameraSlotSession`,
  persistence controller).
- `ExposureCalculatorViewModel` facade methods (set/clear/start
  target, last-used memory) and `WorkspaceCoordinator` wiring.
- Minimal screen integration in `ExposureCalculatorScreen.swift`:
  TargetShutterSectionView render slot, layout style + section card
  visibility widening for cross-file rendering.
- Input sheet UX (C direction): horizontal Quick / Fine pager via
  `TabView(.page)`, draft-target single source of truth,
  Confirm/Cancel, frozen-inactive-wheel on stored fields,
  resync-on-mode-transition, continuous wheel observation via
  `WheelPickerContinuousObserver` for mid-scroll responsiveness.

Out of scope (split to PTIMER-126): dock / page-marker / layout
ownership changes. `ExposureCalculatorLayoutMetrics.swift` and
`PTimerTests/App/BottomSheetWorkspaceShellTests.swift` are at HEAD
in this commit.

Verification status at checkpoint: focused tests
(`TargetShutterInputStateTests`, `TargetShutterModelTests`,
`TargetShutterPresenterTests`,
`ExposureCalculatorViewModelTargetShutterTests`,
`CameraSlotSessionPersistenceTests`) pass. Full PTimer test plan
passes on iPhone 17 simulator.

# PTIMER-146 v3 — Work Log (Claude-led 3rd attempt)

> Chronological record of the user's prompts and Claude's reports for the
> Claude-led 3rd attempt, kept for later process analysis. Summarized, not
> verbatim; commit hashes link the narrative to the history. Appended as work
> proceeds.

## Phase 0 — Setup & alignment (2026-06-18)

1. **User:** Create a worktree based on origin/main.
   **Claude:** Fetched origin/main; asked branch vs detached.
2. **User:** It's the space for PTIMER-146's 3rd attempt.
   **Claude:** Created worktree `feature/PTIMER-146-android-mvp-v3` at
   `.claude/worktrees/PTIMER-146-android-mvp-v3` off origin/main (ec0e61b).
3. **User:** Start in the new space; understand PTIMER-146.
   **Claude:** Read prior round1/2/3 planning docs + git log; summarized scope.
4. **User:** No — "round3" is an iteration of the 2nd attempt.
   **Claude:** Corrected: round docs = 2nd-attempt planning iterations; this
   worktree is a distinct 3rd attempt. Saved memory.
5. **User:** (Strategy) 1st attempt = ChatGPT spec-extraction (failed, UI
   diverged); 2nd = ChatGPT test-restructuring-first (too heavy, paused). 3rd =
   Claude-led, driven by iOS git log feature-by-feature, commit at PR/ticket
   granularity, UI from injected iOS screenshots not a spec. Wanted Claude's
   opinion.
   **Claude:** Endorsed outcome-first approach; refined: treat git log as a
   feature map/oracle not a replay script (skip churn); screenshots = visual
   reference not pixel contract; keep `:core`/`:app` split + shared fixtures.
6. **User:** Want Android UI structure similar to iOS. timer-list full screen,
   reciprocity detail, custom-film edit must be identical (minus OS chrome);
   main-screen wheel + bottom-sheet timer list may adapt. Asked for ND/base
   shutter design. Don't rush; align first.
   **Claude:** Defined Tier 1 (clone) / Tier 2 (adapt) tiers; proposed a snap
   wheel for base shutter and stepper-or-wheel for ND.
7. **User:** Tiers OK. Like the snap wheel — build one reusable wheel; HARD
   requirement: emit value during fling so adjusted shutter/exposure update
   live (also target shutter). Accessibility secondary. When/how many captures?
   **Claude:** Gave a capture checklist; began iOS git-log analysis.
8. **User:** Pick the capture directory; commit docs + images?
   **Claude:** Recommended `docs/design/ios-screens/` in the worktree, commit +
   push (repo private).
9. **User:** Repo will be open-sourced later. Agree on docs/design.
   **Claude:** Created `docs/design/ios-screens/` + README; noted public-history
   caveat.
10. **User:** Give the capture list first; I'll capture while you analyze.
    **Claude:** Delivered the per-folder/per-state capture checklist; analyzed
    iOS git log (found product features in foundation commits + PRs #8–#15;
    #2–#7 = test/arch churn to skip); drafted the feature backlog.
11. **User (correction):** PRs were Bitbucket #1–#68 then migrated to GitHub;
    earliest commits had no PRs.
    **User (truth mode):** PTIMER-146 exists; fix Jira access first.
    **Claude:** Diagnosed the `mcp__jira` gateway was broken; switched to the
    `mcp__atlassian__*` MCP (cloudId beeab5c7…). Pulled all 189 PTIMER tickets;
    rebuilt the backlog JIRA-centric.
12. **User:** Agree — only Done tickets as reference; JIRA-centric. Commit
    messages should tag iOS tickets 완료/일부/참조.
    **Claude:** Rewrote `PTIMER-146-v3-backlog.md` (12 units + SnapWheel gate,
    each mapped to Done tickets); defined the commit convention.
13. **User:** Theme = dark only. Captures supplemented — gaps? Fix filename
    typos. When to validate the wheel?
    **Claude:** Recommended early SnapWheel spike + validate first (unit 2.5);
    flagged missing timer states.
14. **User:** Captures done; fix typos yourself; wheel validation as proposed;
    agree.
    **Claude:** Verified full capture coverage; fixed filename typos; inserted
    unit 2.5 into the backlog.
15. **User:** Worry — 30 MB committed. Need git LFS?
    **Claude:** Advised against LFS; pngquant-compressed captures 30 MB → 6.7 MB
    and amended the planning commit.

## Phase 1 — Implementation (2026-06-19)

16. **User:** Confirmed branch. Commit + push + Draft PR. Push every step +
    update PR. Commits must build + be testable; intentional build breaks
    recorded in the message; feature fixes amend (no commit piling).
    **Claude:** Committed planning baseline + captures; opened **Draft PR #17**.
    Recorded the working conventions in memory.
17. **User:** Proceed, go as far as possible. Stop condition need not be green;
    we'll meet at the wheel work.
    **Claude:** Unit 1 (`:core` module, 1a03b1b), Unit 2 (exposure core vs
    golden fixture, acba839), Unit 2.5 (SnapWheel + harness, committed). Paused
    at the wheel validation gate.
18. **User:** (1) Live update works, good enough; damping not quite iOS but
    passes. (2) Center band low-contrast → mask the edges, leave center clear.
    (3) ND is also a wheel — unify with iOS.
    **Claude:** Switched the wheel to an edge-mask gradient + clear center +
    hairline bounds; ND stays a wheel; amended unit 2.5 (5b13444); PTIMER-64 →
    완료.
19. **User:** Confirmed — gradient masking looks great. Go as far as possible.
    **Claude:** Began unit 3 (catalog + reciprocity core), split 3a–3d.
20. **User:** If it's not a part that needs UI testing, there is no "protected
    area" that forces a stop; revisable later. Only stop for genuine user UI
    tests. / "고고"
    **Claude:** Ported 3a domain+evaluators (8e6552a), 3b policy+confidence
    (cbe5a71), 3c catalog loader + bundled JSON + fixture validation (832f6d5),
    3d alternate models (eb37f69). 44 core tests green. Unit 3 complete.
21. **User:** Record all reports + prompts for later analysis. Keep going; from
    now on don't stop to report even if it runs long.
    **Claude:** Created this work log (commit added); continued without interim
    report pauses (still stopping only for genuine UI-feel tests).
22. **Claude (continued):** Unit 4 — timer lifecycle state machine
    (Running/Paused/Completed/Canceled + transitions + legacy factory; cf0594f).
    Unit 5a — timer-collection persistence schema + restore + codec
    (schemaVersion=1, fail-safe decode, legacy "stopped"→paused; 5ec1a7a).
    Core total 59 tests green. **Milestone: the entire non-UI core
    (exposure + reciprocity + catalog + timer + timer persistence) is ported
    and green.** Next is unit 6 (app layer: ViewModel + coordinator + timer UI,
    first runnable app).
23. **User (emphatic, repeated "고고"):** Don't stop at milestones / to report;
    only stop for a required decision or a UI-feel test. Continue.
    **Claude:** Recorded the directive in memory. Unit 6 — TimerWorkspace +
    ShootingViewModel (one-way intents) + AndroidTimerCoordinator + DataStore
    store (6a; 223e7d5) and the Tier-1 timer-list screen wired as the first
    runnable app (6b; 538fea1). Unit 7 — ShootingCalculator presenter (7a;
    e413fa0) and the shooting screen (wheels + film picker + alternate-model
    chips + result + Start, shooting↔timers navigation; 7b; 0fc1061).
    **Milestone: the app runs the full shooting → Start → timer loop end to
    end (61 core + 16 app unit tests green).** Continuing to units 8–12 without
    report pauses.

## Phase 2 — Camera slots (2026-06-20)

24. **User:** (after /compact) continue.
    **Claude:** Unit 8 — camera slots. Ported the iOS slot model to a pure
    `:core` `CameraSlotSession` (Camera 1–4, capture-on-switch of the active
    slot's calculator inputs, per-slot custom name with trim/reset). Made
    `CalculatorController` slot-aware (live state ↔ session snapshots) and added
    a slot pager + rename dialog to the shooting screen; timer identity now
    carries the active slot's display name + `C1`..`C4` short label. Slot-session
    persistence is deferred to unit 5b (slots are in-memory for now). 67 core +
    18 app unit tests green; `:app:assembleDebug` green. iOS PTIMER-120 일부
    (slot model + switch), PTIMER-123 완료 (rename/reset).

25. **Claude (continued, no pause):** Unit 10 — Target Shutter. Ported the pure
    `TargetShutterPresenter` to `:core` (stop-difference `log2(target/comparison)`
    with the third-snap match band, Unicode `⅓/⅔` + minus-sign formatting) and
    the display-state types. Added a per-slot `targetSeconds` to the slot
    snapshot so a target set on Camera 1 does not bleed into Camera 2; the
    controller exposes `setTargetShutter` / `startFromTarget` and a
    comparison-source selector (digital → Adjusted Shutter, film-quantified →
    Corrected Exposure, otherwise unavailable). Added a Target Shutter card +
    seconds input dialog to the shooting screen with a Start-from-target action.
    73 core + 19 app unit tests green; `:app:assembleDebug` green. iOS PTIMER-25
    일부 (comparison + start complete; input is a seconds field, not the wheel
    sheet; per-slot relaunch persistence pending unit 5b).

26. **Claude (continued, no pause):** Unit 11 — Reciprocity Details. Built a pure
    `ReciprocityDetailsPresenter` in `:core` (textual subset of the iOS Film
    Details sheet): confidence badge + summary, current Adjusted/Corrected/Status
    result, and Active model / Calculation basis (Modified-Schwarzschild equation
    text) / Guidance (metadata + supporting notes) / Sources sections. Added a
    scrolling `ReciprocityDetailsScreen` and a "Reciprocity details" entry on the
    shooting screen (film workflow only); the controller assembles the state from
    the active film/profile/result. The iOS formula-curve graph is intentionally
    deferred. 75 core + 19 app unit tests green; `:app:assembleDebug` green. iOS
    reciprocity-details tickets 일부 (all textual sections; curve graph deferred).

27. **Claude (continued, no pause):** Unit 5b (slots) — slot-session persistence.
    Made the slot types `@Serializable` and added a `PersistentSlotSession`
    snapshot + fail-safe codec + `SlotSessionStoring`/`NoOp` in `:core`
    (schemaVersion 1). The controller now restores from an injected session and
    can `exportSession()`; `ShootingApp` loads it once at construction and
    persists the latest export off the hot wheel-tick path (debounced 400 ms on
    IO). Closes the unit-8 / unit-10 "deferred to 5b" notes — camera names,
    per-slot wheel/film/model, and target now survive relaunch. 78 core + 20 app
    unit tests green; `:app:assembleDebug` green.

28. **Claude (continued, no pause):** Unit 9a — Custom film library (formula
    path). Ported to `:core`: `CustomFilmFormulaGuard` (the analytic
    non-shortening usable-range check, endpoints + interior critical point) and
    `CustomFilmDurationParser`; `CustomFilmBuilder` (builds a well-formed custom
    `FilmIdentity` with a single `.userDefined` formula profile, guard-gated);
    `CustomFilmLibrary` (sanitation, add/remove/lookup, store-backed); and the
    `PersistentCustomFilmLibrarySnapshot` + codec + `Storing`/`NoOp`. App side: a
    DataStore-backed library store, a "+ Create custom film" entry + formula form
    dialog in the film picker, and controller `setFilms` so a created film is
    immediately selectable and computes a corrected exposure; it persists and
    survives relaunch. Table editor, fitted preview, and create-formula-from-table
    are deferred to 9b–9d. 84 core + 21 app unit tests green; `:app:assembleDebug`
    green. iOS PTIMER-84/85 일부 (formula custom films; table path pending),
    PTIMER-179/180 참조.

31. **User device feedback (layout) + housekeeping.** See the conversation log for
    the verbatim rounds. Outcomes: shooting screen realigned to the iOS captures
    (per-result ▶ starts, Reciprocity ⓘ between Adjusted/Corrected, Target Shutter
    row, compact wheels, Reset, bottom dots + "N of M"), timers moved to a peeking
    bottom sheet, the redundant Timers button removed, the swipe ViewPager + ND
    weight fix, and notification device-test fixes. Conversation log + scratch dir
    gitignore + local backup-md protection added.

32. **Claude (continued):** Unit 9b — custom table films. Added `CustomTableFilmInput`
    + `CustomFilmBuilder.buildTableFilm` (≥2 strictly-increasing non-shortening
    anchors, 0 < knee < first anchor, source range = last anchor), sharing the
    assembly path with the formula builder. Added a "+ Create custom film (table)"
    picker entry + dialog (name/ISO/knee + 5 anchor rows, ≥2 filled). Created table
    films persist and compute via the existing log-log evaluator. 85 core + 26 app
    unit tests green; `:app:assembleDebug` green. iOS PTIMER-179 일부 (custom table
    films; fitted-preview graph + create-formula-from-table still pending 9c/9d).

33. **Claude (continued):** Unit 9d — create-formula-from-table. Ported
    `ReciprocityFormulaFitter` (log–log OLS power-law fit) and
    `CustomTableFittedFormula` (fit → guarded formula → per-anchor residuals +
    PTIMER-170 fit-quality thresholds) to `:core`. Controller exposes
    `fittedFormulaOutcome()` + `buildFormulaFilmFromActiveTable()`; the shooting
    screen offers "Create formula from table" for custom table films with a
    preview dialog and "Save as formula film". 87 core + 26 app unit tests green;
    `:app:assembleDebug` green. iOS PTIMER-179 완료 (table + fitted-formula
    create); the in-editor fitted-preview *graph* (9c) remains, deferred with the
    reciprocity curve graph.

29. **User:** Use AlarmManager AND an ongoing foreground service together —
    AlarmManager for the completion sound/alert, the foreground-service
    notification for a persistent visual + a way back into the app.
    **Claude:** Unit 12 — notifications, combined design. Pure `TimerAlertPlanner`
    (running timers → exact completion alarms + ongoing-notification content;
    re-synced only when the running set changes, not per tick). OS glue:
    `TimerNotifications` (silent ongoing channel + high-importance completion
    channel w/ sound), `TimerForegroundService` (specialUse FGS holding the
    ongoing notification), `TimerCompletionReceiver` (AlarmManager → completion
    alert), `AndroidTimerAlertCoordinator` (reconciles alarms + service, exact
    when permitted else inexact fallback). Manifest gains POST_NOTIFICATIONS /
    FOREGROUND_SERVICE(_SPECIAL_USE) / USE_EXACT_ALARM + service + receiver;
    ShootingApp ensures channels, requests POST_NOTIFICATIONS, and syncs the
    plan. 84 core + 23 app unit tests green; `:app:assembleDebug` green.
    **Needs on-device verification** (notification display, permission prompt,
    background/killed delivery, exact-alarm grant). iOS notification tickets
    일부 (completion alert + ongoing surface; on-device test pending).
    **Device test (user):** permission prompt + completion alert (with sound)
    confirmed working; Start gave no on-screen feedback; ongoing notification not
    found. Fixes (amended into the unit-12 commit): Start / Start-target now
    navigate to the timer list so the running timer is visible, and the
    foreground service uses `ServiceCompat.startForeground` with an explicit
    `specialUse` FGS type (API 34+) to avoid the silent start-foreground failure.
    Note: a No-film timer is 1/30 s (0.033 s) so it completes instantly — the
    ongoing notification only shows for multi-second timers.

30. **User (device feedback):** Start button hidden when a film is selected; ND
    wheel not visible (only base shutter); dislikes the Camera 1–4 chip buttons,
    wants a ViewPager.
    **Claude:** Shooting-screen UI fixes. (1) Start is pinned in a `Scaffold`
    bottomBar with the content scrollable, so it stays reachable when the film
    result + target cards exceed the screen. (2) ND wheel: each wheel column now
    takes `weight(1f)` — the base-shutter wheel's full-width dividers were eating
    the row and pushing ND off-screen. (3) Replaced the camera chip row with a
    swipeable `HorizontalPager` (one page per camera) + a dots indicator;
    settling on a page makes that camera the active slot (capture-on-switch),
    and an external slot change animates the pager back into alignment.
    `:app:assembleDebug` + tests green.

34. **User:** Timer list timers have a stable unique id on iOS; it was not
    ported. Implement it like the iOS structure.
    **Claude:** Ported iOS `RunningTimerItem.order` — a 1-based, monotonic
    (`max+1`) creation number on `WorkspaceTimer`, assigned in
    `TimerWorkspace.start` (so Start Again keeps climbing), persisted in
    `PersistentWorkspaceTimer`, carried through `TimerCardState`, and rendered as
    a bare monospaced number beside the slot badge in the full card (omitted on
    the compact mini card, like iOS). Folded into the timer workspace / list /
    planner commits. Verified on emulator; relaunch keeps order.

35. **User (device bug):** Reset is tappable from the timer list; starting a
    timer opens the list half-way (should be mini); tapping empty space in the
    half state does not close it.
    **Claude:** `BottomSheetScaffold` has no scrim, so the shooting surface stayed
    live behind the expanded list and outside taps did nothing; the peek height
    growing from 0 could settle the sheet to Expanded. Added a full-screen scrim
    while expanded (blocks + dims the surface, collapses on outside tap), forced
    the partial (mini) anchor when timers appear, and collapse-on-empty. Folded
    into the peeking-sheet commit; verified on emulator.

36. **User (device bug):** From the full list, Start New starts a timer but it is
    added at the top and stays hidden; the list scrolls back to the entered timer.
    **Claude:** Focus now follows a newly started active timer (keyed on the id
    list) so it scrolls into view + highlights. Verified (Start Again → new top
    timer focused). **User:** apply the same policy to iOS. **Claude:** ported —
    `startNewTimer`/`startTimerAgain` return the new id and the shell calls
    `focusTimer(newID)` (section-header scroll per PTIMER-126). 1305 iOS package
    tests + app build green.

37. **User:** Make the Reciprocity Details fully match the iOS screen (provided
    iOS captures). **Claude:** Replaced the (wrong) flat guidance list with the
    iOS **Source reference** table (metered exposure → +stops, color filter as an
    indented sub-line) + **Guidance boundary** rows + legend glossary; metered
    labels use compact seconds (`64s`, via `formatShutter`) like iOS; **status
    detail** sentence ported verbatim from `ReciprocityDetailsVocabularyPresenter`
    (manufacturer stop-signal lead); **App-derived guarded formula** calc label;
    round-duration **graph axis ticks**; **source-evidence markers** + the
    not-recommended boundary on the curve; full **legend chips**; and the
    **Sources** citation block. Each verified on emulator against the iOS Velvia
    50 screen; folded into the reciprocity presenter / graph / screen commits.

38. **User:** iOS classifies films into categories and treats each film as data
    only — is Android the same? **Claude:** Yes — both load the same 37-film JSON
    catalog into `FilmIdentity` data; no per-film code (generic policy/evaluator);
    grouped by `manufacturer`; reciprocity model categories are data-driven enums.
    Adding a film = one JSON entry, no code.

39. **User (device bug):** Back from Reciprocity Details exits the app; every
    screen's Back (and swipe-back) should return to main.
    **Claude:** The full-screen overlays (Reciprocity Details `Surface`, expanded
    Timers sheet) had no back handling. Added `BackHandler` for both (covers the
    swipe gesture too); modal sheets / dialogs already dismiss on Back. Verified
    every screen → main on emulator; folded into the shell commit. **User:** back
    verified on all screens — pass.

40. **User:** What is left for the MVP? Handle A, D, B in order, then merge; C
    later. **Claude+User:** A (notification action buttons) → **dropped** (the
    ongoing notification is a single aggregate; per-timer actions belong with the
    Live Activity / C); instead **tapping the notification opens the expanded
    timer list** (singleTop + SHOW_TIMERS extra). Also added the **iOS app icon**
    as a placeholder launcher icon. Two standalone commits.

41. **User (D):** Check all EN/KO docs; the spec should effectively have no
    difference. **Claude:** The branch changed no spec docs (MVP spec-clean); the
    EN↔KO divergence was pre-existing on main. **User:** sync now in this PR.
    **Claude:** synced all five KO translations to the English originals (EN
    untouched) — UI.md (4 missing film-selector subsections + drift), Requirements
    (custom-profile FRs), Calculator (table-interpolation step + Table-derived),
    DomainSchema (custom-profile section, selectorLabel, table log-log), Timer
    (canceled state). Heading/list counts now match EN exactly. Also refreshed the
    backlog status (units 11/12 done, action-buttons decision, device-fix log).

42. **User (B):** kill-state alarm works — with the app fully killed the sound +
    notification fire (quiet sound → separate ticket). **Claude:** verified the
    background ongoing notification + notification-tap-to-list on emulator; B
    confirmed (completion delivery while killed signed off on the user's device).

43. **User (device):** the placeholder icon renders wrong (a small square on a
    white circle); the splash is fine — leave it for later cleanup.
    **Claude:** the cause was a legacy square PNG with the adaptive icon removed,
    so launchers framed it on a white circle. Replaced with a proper **adaptive
    icon** (iOS art foreground at the 108dp densities over a solid dark
    background; legacy PNGs kept as the pre-API-26 fallback) so it masks
    edge-to-edge. Amended the icon commit; verified the masked iOS icon in the app
    drawer. Splash left untouched.

44. **User:** Time for the Live Activity (unit 12 / "C"). Scope: **enrich the
    alert — live count-down + iOS wording.** **Claude:** Branched
    `feature/PTIMER-146-android-live-activity` off the merged main and enriched
    the ongoing foreground-service notification to the iOS Live Activity analogue:
    representative (soonest) timer's name as title, "Expected completion {time}"
    line, and a live count-down chronometer (`setWhen(end)` +
    `chronometerCountDown`) — the ticking element iOS shows statically. Display
    only; per-timer Pause/Cancel stays omitted (single aggregate notification).
    Draft PR #20.

45. **User (device capture):** does the notification timer actually run / switch?
    **Claude:** Found the ongoing notification did not re-select the
    representative while backgrounded — the sync was keyed on
    `collectAsStateWithLifecycle`, which pauses collection when backgrounded, so
    after the soonest timer finished the notification stuck on it. Switched the
    alarm + ongoing sync to a direct (non-lifecycle) `ViewModel` flow collector so
    it keeps re-selecting while backgrounded. Verified on emulator: at the
    representative's completion the ongoing switched to the next timer and held a
    positive count (3→2 timers, end advanced).

46. **User (device capture):** the count-down momentarily shows -00:01 before it
    swaps. Why let it go negative — clamp at 0. **Claude:** The count-down is the
    OS chronometer (autonomous, can't be clamped mid-tick); it ticks one second
    past zero before the (background-throttled) in-app tick swaps it. Chosen fix
    (owner): **refresh from the end alarm.** The planner precomputes ordered
    ongoing "stages" (one per running timer), the coordinator publishes them, and
    the completion receiver re-posts the soonest still-future stage (or stops the
    service) at the exact alarm instant — filtering stages by current time so it
    advances even if its snapshot is stale. New `TimerAlertPlannerTest`
    stage-advancement case. **Lesson:** much of this turn was lost building the
    *main repo's* skeleton `android/` instead of the *worktree's* MVP `android/` —
    always build/install from the worktree path. **User:** verified on device, no
    -1 visible — pass.

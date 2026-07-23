<!-- Copyright © 2026 Sangwook Han -->
<!-- SPDX-License-Identifier: Apache-2.0 -->

# Timer Alerts and Lock-Screen Surface

| Prefix | Owns |
| --- | --- |
| ALERT | Staged completion alerts |
| ALERT-AUDIO | Audibility, stopping, and the silent-mode advisory |
| LOCKSCREEN | The lock-screen representative-timer surface |

## Purpose

A photographer may be looking through the camera, or have the phone in a
pocket, while an exposure runs. Completion needs staged awareness, not just
a visible countdown.

## Current behavior

A timer's completion is preceded, for longer timers, by one or two
pre-alerts that signal completion is approaching, then a terminal
completion alert.

## Requirements

### Alert stages

- **ALERT-001** — A timer's alert stages depend on its duration: 30s or
  less gets completion only; more than 30s and up to 60s gets one pre-alert
  before completion; more than 60s gets two pre-alerts before completion.
  This bucketing is the platform-neutral, foreground-tick schedule.
- **ALERT-002** — A background notification channel may use earlier lead
  times than the foreground schedule for the same duration buckets, to
  absorb platform notification delivery latency; the buckets themselves do
  not change.
- **ALERT-003** — The first (gentler) pre-alert is haptic-first where the
  platform supports it; a platform that cannot guarantee vibration-only
  background delivery implements it as best-effort rather than promising
  vibration-only behavior.
- **ALERT-004** — The second (stronger) pre-alert, where it exists, is
  delivered only when the app is not in the foreground; it never surfaces
  as a foreground-visible alert.
- **ALERT-005** — Pre-alert copy communicates remaining time and shall not
  imply the exposure should stop before completion.

### Audibility and control

- **ALERT-AUDIO-001** — Completion (and the stronger pre-alert, where it
  applies) shall be audible even when the device is in silent/vibrate mode,
  using the strongest alert path each platform allows.
- **ALERT-AUDIO-002** — A timer that completes while the app is
  backgrounded or locked shall not play its audible alarm belatedly when
  the user later returns to the foreground; on return, completion is
  reconciled silently. Only a genuinely live foreground completion plays
  the alarm.
- **ALERT-AUDIO-003** — The app-played completion alarm is bounded: it
  stops on its own after a short fixed window, and at most one timer's
  alarm sounds at a time.
- **ALERT-AUDIO-004** — While an alarm is sounding, the user can silence it
  from within the app via the affordance for that specific running timer.
  Silencing stops audio only — it does not change timer state, dismiss, or
  remove the timer.
- **ALERT-AUDIO-005** — A completion transition while the app is active and
  foregrounded plays exactly one audio cue and one haptic; a
  reactivation-triggered state update (§ below) never plays one.
- **ALERT-AUDIO-010** — The app may show a passive, best-effort advisory
  hinting the device might be muted, so the photographer can check before a
  long exposure. It never claims reliable silent-switch detection, never
  gates or delays starting a timer, requires no confirmation, and appears
  at most once per session, suppressed while an alarm is sounding.

### Background scheduling

- **ALERT-020** — For a timer running in the background or with the device
  locked, every applicable stage (pre-alerts and completion) is scheduled
  as a local notification keyed by timer identity and stage: creating a
  timer schedules every applicable stage; pausing or removing a timer
  cancels all its pending stages; resuming reschedules all stages against
  the new completion time; reaching a terminal state cancels any remaining
  pending stages. Duplicate scheduling for the same timer identity and
  stage shall not occur.

### Reactivation

- **ALERT-030** — When the app returns to the foreground, a running timer
  reconciles against wall clock; this reconciliation never itself triggers
  a completion sound or haptic — only the foreground tick does, and only
  while it can be perceived live.

## Lock-screen surface

- **LOCKSCREEN-001** — The system exposes at most one representative
  running timer to the lock screen at a time: the running timer with the
  earliest expected completion, ties broken deterministically so the same
  timer is selected across re-evaluations.
- **LOCKSCREEN-002** — When no timer is running, the lock-screen surface
  shows a "no active timer" presentation rather than stale data, and once
  every running/paused timer has stopped, the surface ends entirely.
- **LOCKSCREEN-003** — Becoming active resolves the existing lock-screen
  surface rather than recreating one; adding, completing, or relocking
  keeps the same surface instance updating rather than spawning a parallel
  one.
- **LOCKSCREEN-004** — The lock-screen surface refreshes its visible time
  frequently enough that the user perceives time advancing without
  unlocking (approximately once per second).

## Non-goals

- Parity with the platform's own system timer/clock alarm (e.g. iOS
  Critical Alerts) is not claimed.
- A defined policy for grouping multiple background completions within a
  short window, or varying the audio cue by timer kind, does not currently
  exist.

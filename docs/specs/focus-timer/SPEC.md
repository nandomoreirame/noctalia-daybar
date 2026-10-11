# Spec: Countdown timer and pomodoro commands in quick capture

## Problem Statement

The Focus tab only runs pomodoro phases with fixed durations. The user wants a simple
countdown timer of any length ("tea 5m") that ends with the same alarm and toast, living in
the Focus tab next to the pomodoro modes, and wants to start it, and to start, pause or stop
the pomodoro, straight from the quick-capture overlay.

## Goals

- A fourth chip, "Timer", in the Focus tab, with a circular progress ring around the clock.
- Free-form durations (`90s`, `10m`, `1h30`, `1:30`) typed in the panel or in quick capture.
- Quick-capture commands: `/t <duration> [label]` starts a timer, `/p ...` drives the pomodoro.
- Only one clock counts at a time: starting one pauses the other, keeping its remaining time.

## Context

- Pomodoro state and services live in `Main.qml` (`pomodoroRunning`, `pomodoroStarted`,
  `pomodoroMode`, `pomodoroRemaining`, a 1 s `Timer`, `pomodoroStart/Pause/Reset/Skip/SetMode`,
  `pomodoroFinished`). Nothing is persisted across shell restarts.
- The alarm is `alarm.mp3` through `SoundService.playSound(..., { repeat: true, volume: 0.3 })`,
  stopped after 5 s by `alarmLimitTimer`, gated by the `playSound` setting.
- `components/FocusView.qml` renders the mode chips (`Chip`), the clock as large `NText`, the
  controls (`PillButton`), the linked-task combo and the daily progress dots.
- `utils/capture/registry.js` resolves `=` (calculation), the prefixes `/e`, `/l`, `/n`, the
  Tab-forced type, a lone URL, then task. An empty body after a prefix is rejected with `empty`.
- `CaptureWindow.qml` treats `action: "copy"` as a non-saving action; every other action goes
  to `Main.executeCapture(result, done)` and shows a `capture.saved.<type>` toast.
- `BarWidget.qml` swaps the tab label for the pomodoro clock while `pomodoroRunning ||
  pomodoroSoundPlaying`; middle click starts or pauses the pomodoro.

## Verified Claims

| Claim | Source (file:line) | Verified |
|-------|--------------------|----------|
| Pomodoro state and phase functions are in Main.qml | `Main.qml:708-842` | yes |
| Alarm limited to 5 s by `alarmLimitTimer` | `Main.qml:745` | yes |
| Prefix list and empty-body rejection | `utils/capture/registry.js:18,34` | yes |
| `copy` is handled in CaptureWindow without executeCapture | `CaptureWindow.qml:113` | yes |
| Bar shows the clock while running or ringing | `BarWidget.qml:24` | yes |
| Focus tab icon is `hourglass` | `utils/tabs.js:7` | yes |
| `QtQuick.Shapes` is available in the shell runtime | `/etc/xdg/quickshell/noctalia-shell/Widgets/NSlider.qml` imports it | yes |
| i18n coverage test lists runtime-built keys in `DYNAMIC` | `tests/i18n.test.js:21` | yes |
| `/t` and `/p` are not used by any prefix | `utils/capture/registry.js:18` | yes |

## Requirements

### P1

1. **[REQ-001]** WHEN a duration text is parsed THEN the system SHALL accept `Ns`, `Nm`/`Nmin`,
   `Nh`, `NhM`/`NhMm`, `m:ss`, `h:mm:ss` and a bare number (minutes), ignoring case, and SHALL
   return the seconds plus the remaining words as the label; WHEN no duration is found it SHALL
   fail with `needs-duration`; WHEN the total is 0 or above 24 h it SHALL fail with
   `invalid-duration`.
2. **[REQ-002]** WHEN the Focus tab is shown THEN it SHALL offer four chips: Focus, Short break,
   Long break, Timer. Selecting Timer SHALL switch the view without touching the pomodoro state;
   selecting the current pomodoro mode while the Timer view is shown SHALL only switch back,
   without resetting it.
3. **[REQ-003]** WHEN the Timer view has no timer set THEN it SHALL show a duration field
   (Enter starts) and preset chips 1, 5, 10, 15 and 30 min that start at once; an invalid entry
   SHALL show the parse error under the field.
4. **[REQ-004]** WHEN a timer is set THEN the Timer view SHALL show a ring with the clock and the
   optional label in its center, a play/pause button, a reset button (back to the full duration,
   stopped) and a "new timer" button that clears it and returns to the entry state.
5. **[REQ-005]** WHEN the pomodoro view is shown THEN its clock SHALL be drawn inside the same
   ring, filled with remaining over the phase duration (clamped to 0..1).
6. **[REQ-006]** WHEN a timer reaches zero THEN the system SHALL stop it, keep its duration ready
   to run again, play the alarm under the same `playSound` setting and 5 s limit as the pomodoro,
   and show a toast titled "Timer" whose body is the label or "Time's up".
7. **[REQ-007]** WHEN the timer starts while the pomodoro is running THEN the pomodoro SHALL
   pause with its remaining time kept and a toast "Focus paused"; WHEN the pomodoro starts
   (button, bar, Today's play, capture) while the timer runs THEN the timer SHALL pause the same
   way with a toast "Timer paused". The two SHALL never count at the same time.
8. **[REQ-008]** WHEN the capture text is `/t <duration> [label]` THEN the preview SHALL show the
   clock and label (plus "replaces the current timer" when one is set) and Enter SHALL start it,
   close the overlay and select the Timer view; `/t` alone SHALL pause or resume the set timer
   (error `no-timer` when none) and `/t parar` (or `stop`) SHALL reset it.
9. **[REQ-009]** WHEN the capture text is `/p` THEN Enter SHALL start or pause the pomodoro;
   `/p foco`, `/p curta`, `/p longa` (aliases `focus`, `short`, `long`, `pausa curta`,
   `pausa longa`) SHALL switch to that phase if different and start it; `/p parar` (or `stop`)
   SHALL reset it; any other word SHALL fail with `unknown-command`. The preview SHALL name the
   action that Enter will run, and the Focus tab SHALL return to the pomodoro view.
10. **[REQ-010]** WHEN the Tab key cycles capture types THEN Timer SHALL be part of the cycle
    (after link); the pomodoro command SHALL only be reachable through `/p`, shown as a label
    like the calculation type.
11. **[REQ-011]** WHEN the timer runs or rings THEN the bar SHALL show its clock with an alarm
    icon instead of the pomodoro clock, and middle click SHALL pause or resume the clock shown
    (the pomodoro when none is shown).

### P2

12. **[REQ-012]** WHEN a timer runs THEN the Focus tab IconTab label stays "Focus"; no new tab,
    setting or IPC call is added.

## Architecture Decisions

| Decision | Choice | Rationale |
|----------|--------|-----------|
| Timer state | Separate properties in `Main.qml` (`timerTotal`, `timerRemaining`, `timerRunning`, `timerLabel`) | Independent durations; services keep running with the panel closed |
| Exclusivity | Starting one clock pauses the other (remaining kept) | User choice: only one counts at a time, nothing is lost |
| Alarm | One `alarmSource` ("", "pomodoro", "timer") shared by both; `pomodoroSoundPlaying` becomes derived | One sound, one limit timer, existing bar binding keeps working |
| Duration parsing | New `utils/duration.js` | Reused by the capture handler and the panel field; pure and testable |
| Capture handlers | `utils/capture/timer.js` (in the cycle) and `utils/capture/pomodoro.js` (prefix only, like `=`) | Registry pattern; one file per type |
| Empty body after a prefix | Allowed only for handlers that declare `ALLOW_EMPTY` and only when the prefix was typed | `/t` and `/p` alone are commands; an empty field on the Timer tab stays `empty` so a stray Enter does nothing |
| Ring | `components/ui/ProgressRing.qml` with `QtQuick.Shapes` (`PathAngleArc`), arc from 12 o'clock clockwise | No Canvas repaint per second; used by both views |
| Which view the Focus tab shows | `Main.focusPanel` ("pomodoro" or "timer") | Capture commands can switch it while the panel is closed |
| Bar source choice | Pure `utils/clock.js` `barSource(...)` | Testable; QML just binds |
| `1:30` meaning | minutes:seconds (`h:mm:ss` for hours) | Matches common timer apps; `1h30` covers hours and minutes |

## Grilling Log

| # | Question | Resolution |
|---|----------|------------|
| 1 | Timer independent of the pomodoro or the same clock? | Separate state |
| 2 | Can both count at once? | No. Starting one pauses the other, keeping its time |
| 3 | Capture syntax? | `/t <duration> [label]`, `/t`, `/t parar`; `/p`, `/p foco/curta/longa/parar` |
| 4 | Ring on the timer only or both? | Both views |
| 5 | Panel input? | Text field with the capture parser plus 1/5/10/15/30 min presets |
| 6 | One timer or many? | One; a new `/t` replaces it, and the preview says so |
| 7 | Alarm length? | 5 s, same as the pomodoro |
| 8 | What does `1:30` mean? | 1 min 30 s (default, recorded) |
| 9 | Does a preset chip start at once? | Yes (default, recorded) |
| 10 | Does the timer turn on the focus-mode command? | No; only a running focus phase does. Pausing the pomodoro for a timer turns focus mode off (consequence, accepted) |
| 11 | Timer survives a shell restart? | No, same as the pomodoro |
| 12 | After the timer rings? | Stopped at its full duration, ready to replay |

## Constraints

- `utils/` files: `.pragma library`, `.import`, top-level declarations at column 0, no ES modules.
- No `eval`/`Function`; the duration parser is regex plus integer math.
- All UI strings through i18n in `pt.json` and `en.json`; new runtime-built keys go into
  `DYNAMIC` in `tests/i18n.test.js`.
- QML keeps logic out: parsing, previews, bar choice and progress live in `utils/`.

## Out of Scope

- Several simultaneous timers, a stopwatch ("Cronômetro"), a fullscreen view.
- Persisting the timer across shell restarts.
- New IPC calls or settings.
- Logging timers in the focus history.

## Edge Cases

- **`/t 0`, `/t 25h`** → `invalid-duration`.
- **`/t chá`** (no duration) → `needs-duration`.
- **`/t 5m` with a timer paused at 2:10** → preview warns, Enter replaces it.
- **Timer rings while the pomodoro is paused** → pomodoro untouched; alarm source "timer".
- **Pomodoro finishes with auto-start while a timer is paused** → pomodoro auto-starts; the timer
  is already paused, nothing changes.
- **Config change mid-phase** makes `remaining > duration` → ring clamps to full.
- **`/p curta` while the short break is paused** → same phase, resume (no reset).
- **`/p` while the alarm rings** → `pomodoroStart` already stops the alarm.

## Test Strategy

- vitest: `tests/duration.test.js`, `tests/clock.test.js`, `tests/capture-timer.test.js`
  (timer + pomodoro handlers, previews), `tests/registry.test.js` (prefixes, cycle, `ALLOW_EMPTY`),
  `tests/i18n.test.js` (new keys).
- QML: shell reload with no daybar errors in the log, plus `docs/SMOKE.md` rows per REQ.

## Requirement Traceability

| REQ | Status | Task | Evidence |
|-----|--------|------|----------|
| REQ-001 | Done | T1 | `tests/duration.test.js` (20 cases, incl. review additions) |
| REQ-002 | Pending (smoke 53) | T2, T8 | `chipAction` unit-tested; view switch not clicked |
| REQ-003 | Pending (smoke 52, 54) | T9 | parser unit-tested; panel entry not clicked |
| REQ-004 | Pending (smoke 55) | T7, T9 | loads with no log error; not clicked |
| REQ-005 | Pending (smoke 56) | T2, T7, T8 | `progress` unit-tested; ring not seen |
| REQ-006 | Pending (smoke 57) | T6 | code reviewed; alarm not heard |
| REQ-007 | Pending (smoke 58) | T6 | every start path traced in review |
| REQ-008 | Pending (smoke 59) | T3, T4, T10 | handlers and registry unit-tested |
| REQ-009 | Pending (smoke 60) | T3, T4, T10 | `plan`/`previewKey` unit-tested |
| REQ-010 | Pending (smoke 61) | T4, T10 | cycle unit-tested |
| REQ-011 | Pending (smoke 62) | T2, T11 | `barSource`/`middleClickTarget` unit-tested |
| REQ-012 | Done | T12 | no tab, setting or IPC added |

## Implementation Notes

- Duration parsing grew past the original list after review: consecutive unit words add up
  (`1h 30m`), unit words win over clock forms (`reunião às 14:30 5m` is 5 min), `1h30min` is
  accepted, a bare number counts only as the first word, and oversized numbers give
  `invalid-duration`.
- While the timer alarm rings, `/t` and a bar middle click only silence it (preview
  "Silence the alarm"); pausing or resetting one clock no longer stops the other clock's alarm.
- The ring shrinks with the panel height (80 to 160 px) and the clock text fits inside it.

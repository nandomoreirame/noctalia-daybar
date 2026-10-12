# Spec: Detached focus clock (floating window and corner overlay)

## Problem Statement

The pomodoro and timer clocks are visible only inside the toolbar panel, or as a small
text in the bar. The user wants to keep the countdown on screen while working, in two
forms opened with one click from the Focus tab: a real Niri window that can be moved and
resized, and a small overlay pinned to a screen corner.

## Goals

- One click in the Focus tab opens or closes each form; both can be open at once.
- Both show the active clock: progress ring and numbers only. Play/pause and reset appear
  on mouse hover.
- The overlay corner and size are configurable; both forms reopen after a shell restart.

## Context

- `ProgressRing` (`components/ui/ProgressRing.qml`) and the clock text already exist in
  `components/FocusView.qml` and `components/TimerPane.qml`.
- Noctalia opens its settings as a `FloatingWindow` (Quickshell xdg toplevel), so that type
  is available in the runtime. The capture and note overlays are `PanelWindow` layer-shell
  surfaces in this repo.
- `Main.qml` holds the clock state (`pomodoro*`, `timer*`, `alarmSource`, `focusPanel`,
  `barClock`) and the alarm/exclusivity rules; the bar picks its clock with
  `Clock.barSource`.
- `data.json` keeps UI state under `ui` (`lastTab`), normalized by `utils/store.js`.
- Plugin settings are edited in `Settings.qml` with defaults in `manifest.json`.

## Verified Claims

| Claim | Source (file:line) | Verified |
|-------|--------------------|----------|
| Noctalia uses `FloatingWindow` for its settings window | `/etc/xdg/quickshell/noctalia-shell/Modules/Panels/Settings/SettingsPanelWindow.qml:10` | yes |
| Layer-shell overlays use `WlrLayershell.layer/keyboardFocus/namespace/exclusionMode` | `CaptureWindow.qml:45-48` | yes |
| `ui` is normalized to `{ lastTab }` only | `utils/store.js:44-47` | yes |
| `createEmpty()` shape is asserted exactly in tests | `tests/store.test.js:7` | yes |
| The bar clock source rule is `Clock.barSource` | `utils/clock.js` | yes |
| Settings read defaults from `manifest.metadata.defaultSettings` | `Settings.qml:32-36` | yes |
| A Quickshell `FloatingWindow` reaches Niri with app-id `org.quickshell` | n/a | assumption, check with `niri msg --json windows` |

## Requirements

### P1

1. **[REQ-001]** WHEN the Focus tab is shown THEN its header SHALL have two icon buttons next
   to the daily progress and the gear, "Open in a window" and "Pin to corner", in both the
   pomodoro and the Timer view. Each SHALL toggle its form, show a selected state while it is
   open, have a tooltip and accessible name, and be reachable with Tab.
2. **[REQ-002]** WHEN the window is opened THEN the system SHALL show a `FloatingWindow` titled
   "Daybar timer" (default 280x280, minimum 160x160, resizable) whose ring and numbers scale
   with the window size. Closing it from the compositor SHALL update the open state.
3. **[REQ-003]** WHEN the overlay is opened THEN the system SHALL show a layer-shell surface on
   the Top layer of the focused screen, anchored to the configured corner with a fixed margin,
   with no keyboard focus, reserving no space and staying clear of the bar's exclusive zone.
4. **[REQ-004]** WHEN either form is shown THEN it SHALL display the active clock: the running
   or ringing clock (same rule as the bar); when none runs or rings, the clock of the view
   selected in the Focus tab. It SHALL switch on its own when the other clock starts.
5. **[REQ-005]** WHEN the pointer is outside a form THEN it SHALL show only the ring and the
   numbers; WHEN the pointer is over it THEN play/pause and reset SHALL appear (the overlay
   also a close button). Play/pause SHALL follow the bar rules (a ringing timer is only
   silenced); reset SHALL reset the shown clock.
6. **[REQ-006]** WHEN the overlay size setting is small, medium or large THEN the ring SHALL be
   90, 130 or 180 px (times the UI scale); WHEN the corner setting is top-left, top-right,
   bottom-left or bottom-right THEN the overlay SHALL anchor there (default top-right, medium).
7. **[REQ-007]** WHEN a form is opened or closed THEN `data.json` `ui.clockWindow` /
   `ui.clockOverlay` SHALL record it; WHEN the store loads THEN open forms SHALL reopen
   (the overlay on the focused screen). Non-boolean values SHALL load as false.

### P2

8. **[REQ-008]** WHEN the README is read THEN it SHALL show a niri `window-rule` that opens the
   window floating in a corner, matched by its title.

## Architecture Decisions

| Decision | Choice | Rationale |
|----------|--------|-----------|
| Shared face | New `components/ClockFace.qml` (ring + numbers + hover controls), used by both forms | One drawing, two hosts |
| Active clock rule | `Clock.shownClock(state)` in `utils/clock.js`, exposed as `Main.shownClock` | Testable; same priority as the bar plus the Focus view fallback |
| Shown clock data | `Main` exposes `shownRemaining`, `shownTotal`, `shownRunning` and `shownToggle()`, `shownReset()` | Hosts stay thin; the bar's ringing-timer rule is reused |
| Window | `ClockWindow.qml` (`FloatingWindow`) | Real Niri window: move, resize, other monitor |
| Overlay | `ClockOverlay.qml` (`PanelWindow`, `WlrLayer.Top`, `KeyboardFocus.None`, `ExclusionMode.Normal` with `exclusiveZone: 0`) | Visible on every workspace, never steals focus; full-screen apps cover it |
| Corner and size | Settings `clockCorner`, `clockSize` validated by `Clock.cornerAnchors` and `Clock.ringSize` | Bad values fall back to defaults |
| Persistence | `ui.clockWindow`, `ui.clockOverlay` in `data.json` via `Store.normalizeUi` and `Store.setUiFlag` | `pluginSettings` holds configuration only |
| Hover controls | `HoverHandler` on the face; controls fade in | Matches the "numbers only" request |
| Niri placement | Documented `window-rule` matched by title | Placement belongs to the compositor |

## Grilling Log

| # | Question | Resolution |
|---|----------|------------|
| 1 | Which clock is shown? | The active one (bar rule), else the Focus view's clock |
| 2 | Where is the click? | Two buttons in the Focus header; clicking again closes |
| 3 | Overlay position and layer? | Configurable corner, Top layer, focused screen |
| 4 | Remember open state? | Yes, in `data.json` `ui` |
| 5 | Controls? | Play/pause and reset, only on hover; otherwise ring and numbers only |
| 6 | Overlay size? | Configurable: small, medium, large |
| 7 | Both open at once? | Yes, independent (default, recorded) |
| 8 | Overlay close? | Close button on hover, or the Focus button (default) |
| 9 | Which screen on restore? | The focused screen at load (default; screen identity not stored) |
| 10 | IPC or right-click menu? | Not now (user chose the Focus buttons only) |

## Constraints

- `utils/` rules: `.pragma library`, column-0 declarations, no ES modules, unit-tested.
- UI strings through i18n in both languages.
- Keyboard: header buttons are focusable; the forms are pointer-first (the panel stays the
  keyboard path) and expose an accessible name with the clock.

## Out of Scope

- IPC calls and the bar right-click menu for these forms.
- Persisting the window position or size (Niri owns it; the window rule covers placement).
- Showing the timer label or pomodoro cycle in the forms.

## Edge Cases

- **No timer set and Timer view selected** → shows `00:00` with an empty ring.
- **Window closed with Mod+Q** → `visible` false → `ui.clockWindow` false.
- **Overlay open, monitor unplugged** → the surface is destroyed with its screen; state stays
  true and it reopens on the next load (accepted).
- **`clockCorner: "middle"` hand-edited** → top-right; **`clockSize: 999`** → medium.
- **Store written by an older version** (no flags) → both false.

## Test Strategy

- vitest: `tests/clock.test.js` (`shownClock`, `cornerAnchors`, `ringSize`),
  `tests/store.test.js` (`normalizeUi` flags, `setUiFlag`), `tests/i18n.test.js`.
- QML: shell reload with no daybar errors, plus `docs/SMOKE.md` rows.

## Requirement Traceability

| REQ | Status | Task | Evidence |
|-----|--------|------|----------|
| REQ-001 | Pending (smoke 63) | T8 | buttons added; not clicked |
| REQ-002 | Partial | T6 | window restored from data.json, niri title "Daybar timer", app_id `dev.noctalia.noctalia-qs`; closing via niri wrote `clockWindow: false`; resize not seen |
| REQ-003 | Partial | T7 | layer `noctalia-daybar-clock`, keyboard interactivity none, restored on load; position vs bar not seen |
| REQ-004 | Done (logic) | T1, T5 | `shownClock` unit-tested |
| REQ-005 | Pending (smoke 67) | T4, T5 | hover not exercised |
| REQ-006 | Done (logic) | T1, T7, T9 | `cornerAnchors`/`ringSize` unit-tested; settings not clicked |
| REQ-007 | Done | T2, T5 | store flags unit-tested; both forms reopened after a restart |
| REQ-008 | Done | T10 | README rule with the verified app_id and title |

## Implementation Notes

- Each host wraps `ClockFace` in a `Loader` active only while visible: creating the faces
  with `Main` evaluated `pomodoroConfig` inside the ring's `progress` binding and logged a
  binding loop.
- While the timer rings, the face's play button reads "Silence the alarm".
- The overlay open callback re-checks the pin, so a late screen callback cannot reopen it.

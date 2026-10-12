# Plan: Detached focus clock (floating window and corner overlay)

> **Spec:** docs/specs/focus-clock-detach/SPEC.md
> **Depends on:** `focus-timer` (done). The working tree holds uncommitted Focus-tab sizing
> changes (`Panel.qml`, `components/FocusView.qml`, `components/TimerPane.qml`) and the
> user's `import QtQuick 6.11` edits across QML files; commit them before Task 5/8 touch
> `Main.qml` and `FocusView.qml`.

**Goal:** One click in the Focus tab opens the active clock as a Niri floating window and/or a corner overlay, showing only ring and numbers, with play/pause and reset on hover; open state survives restarts.
**Architecture:** Pure rules in `utils/clock.js` (`shownClock`, `cornerAnchors`, `ringSize`) and `utils/store.js` (`ui.clockWindow`/`ui.clockOverlay`, `setUiFlag`). `Main.qml` exposes the shown clock and open/close/restore functions. New QML: `components/ClockFace.qml` (shared face), `ClockWindow.qml` (`FloatingWindow`), `ClockOverlay.qml` (`PanelWindow`, Top layer). Focus header buttons and two settings.
**Tech Stack:** QML (noctalia-shell 4.7.x, Qt 6.11, Quickshell), ES2018 QML JavaScript libraries, vitest 2.
**Total Tasks:** 10
**Estimated Complexity:** medium (Standard: 8 REQs)

---

## Conventions for every task

- Repo root: `~/dev/projects/noctalia-daybar`. `npm test -- <file>` for one file, `npm test` for the suite; read the `Tests  N passed` line.
- `utils/**/*.js`: `.pragma library`, `.import` for deps, top-level declarations at column 0, no ES modules.
- QML files start with `import QtQuick 6.11` (repo convention).
- QML runtime check: `qs -c noctalia-shell kill`, wait until `pgrep -x qs` is empty, `setsid -f qs -c noctalia-shell -d`, then `grep -iE "daybar|binding loop" "$(ls -t /run/user/1000/quickshell/by-id/*/log.log | head -1)" | grep -vE "INFO|QColor|overrides a member"` prints nothing, plus the task's visual check.
- Commit after every task with `/git commit`. Implementers DO NOT run any git command.
- Do NOT reference any previous or source project in code, comments, docs or commits.

## Dependency graph

```
T1 clock rules ─┐
T2 store flags ─┼── T5 Main services ──┬── T6 ClockWindow ──┐
T3 i18n+manifest┤                      ├── T7 ClockOverlay ─┼── T8 Focus buttons ── T10 docs
T4 ClockFace ───┘                      └── T9 Settings ─────┘
```

Parallel batches: {T1, T2, T3, T4} → T5 → {T6, T7, T9} → T8 → T10.

---

### Task 1: Clock rules: shown clock, corner anchors, ring size

**Requirement:** REQ-004, REQ-006
**Files:**
- Modify: `utils/clock.js`
- Test: `tests/clock.test.js`

**Team:**
- Track: backend
- Implementer: backend-engineer (skills: test-driven-development)
- Reviewers: business-logic-reviewer, test-reviewer

**Step 1: Write the failing test**

In `tests/clock.test.js`, extend the import with `shownClock, cornerAnchors, ringSize, CORNERS, RING_SIZES` and append:
```js
describe("shownClock", () => {
  const base = { pomodoroRunning: false, timerRunning: false, alarmSource: "", focusPanel: "pomodoro" };

  it("follows the bar rule while a clock runs or rings", () => {
    expect(shownClock({ ...base, timerRunning: true })).toBe("timer");
    expect(shownClock({ ...base, pomodoroRunning: true, focusPanel: "timer" })).toBe("pomodoro");
    expect(shownClock({ ...base, alarmSource: "timer" })).toBe("timer");
  });

  it("falls back to the Focus view when nothing runs", () => {
    expect(shownClock(base)).toBe("pomodoro");
    expect(shownClock({ ...base, focusPanel: "timer" })).toBe("timer");
    expect(shownClock({ ...base, focusPanel: "junk" })).toBe("pomodoro");
  });
});

describe("cornerAnchors", () => {
  it("anchors two edges per corner", () => {
    expect(cornerAnchors("top-left")).toEqual({ top: true, bottom: false, left: true, right: false });
    expect(cornerAnchors("top-right")).toEqual({ top: true, bottom: false, left: false, right: true });
    expect(cornerAnchors("bottom-left")).toEqual({ top: false, bottom: true, left: true, right: false });
    expect(cornerAnchors("bottom-right")).toEqual({ top: false, bottom: true, left: false, right: true });
  });

  it("falls back to top-right", () => {
    for (const c of ["middle", "", undefined, null, 3]) expect(cornerAnchors(c)).toEqual(cornerAnchors("top-right"));
    expect(CORNERS).toEqual(["top-left", "top-right", "bottom-left", "bottom-right"]);
  });
});

describe("ringSize", () => {
  it("maps the size setting to the ring in px, medium by default", () => {
    expect(["small", "medium", "large"].map(ringSize)).toEqual([90, 130, 180]);
    for (const s of ["huge", 999, undefined, "constructor"]) expect(ringSize(s)).toBe(130);
    expect(Object.keys(RING_SIZES)).toEqual(["small", "medium", "large"]);
  });
});
```

**Step 2: Run test to verify it fails**
Run: `npm test -- tests/clock.test.js`
Expected: FAIL (`shownClock is not a function`).

**Step 3: Write minimal implementation**

Append to `utils/clock.js`:
```js
// Detached clock (window and corner overlay): the bar's clock while one runs or rings,
// else the clock of the view selected in the Focus tab. Never "".
function shownClock(state) {
  const source = barSource(state);
  if (source) return source;
  return state.focusPanel === "timer" ? "timer" : "pomodoro";
}

var CORNERS = ["top-left", "top-right", "bottom-left", "bottom-right"];
var DEFAULT_CORNER = "top-right";

// Overlay corner setting -> PanelWindow anchors; unknown values use the default.
function cornerAnchors(corner) {
  const c = CORNERS.indexOf(corner) >= 0 ? corner : DEFAULT_CORNER;
  return { top: c.indexOf("top") === 0, bottom: c.indexOf("bottom") === 0, left: c.endsWith("left"), right: c.endsWith("right") };
}

// Overlay size setting -> ring diameter in px (before UI scale).
var RING_SIZES = { small: 90, medium: 130, large: 180 };
var DEFAULT_SIZE = "medium";

function ringSize(size) {
  return Object.prototype.hasOwnProperty.call(RING_SIZES, size) ? RING_SIZES[size] : RING_SIZES[DEFAULT_SIZE];
}
```

**Step 4: Run test to verify it passes**
Run: `npm test -- tests/clock.test.js`
Expected: PASS.

**Step 5: Commit**
Run: `/git commit`

---

### Task 2: Store: clock open flags in `ui`

**Requirement:** REQ-007
**Files:**
- Modify: `utils/store.js`
- Test: `tests/store.test.js`

**Team:**
- Track: backend
- Implementer: backend-engineer (skills: test-driven-development)
- Reviewers: business-logic-reviewer, consequences-reviewer

**Step 1: Write the failing test**

In `tests/store.test.js`:
- Line 7: expected `ui` becomes `{ lastTab: "", clockWindow: false, clockOverlay: false }`.
- Replace the "keeps a known last tab" test with:
```js
  it("normalizes ui: known last tab, boolean clock flags", () => {
    const ui = (raw) => parse(JSON.stringify({ ui: raw })).data.ui;
    expect(ui({ lastTab: "focus", clockWindow: true })).toEqual({ lastTab: "focus", clockWindow: true, clockOverlay: false });
    expect(ui({ lastTab: "nope", clockWindow: "yes", clockOverlay: 1 })).toEqual({ lastTab: "", clockWindow: false, clockOverlay: false });
    expect(ui("x")).toEqual({ lastTab: "", clockWindow: false, clockOverlay: false });
  });
```
- Add (import `setUiFlag`):
```js
describe("setUiFlag", () => {
  it("sets a known flag and keeps the rest of ui", () => {
    const data = createEmpty();
    data.ui.lastTab = "focus";
    const next = setUiFlag(data, "clockOverlay", true);
    expect(next.ui).toEqual({ lastTab: "focus", clockWindow: false, clockOverlay: true });
    expect(data.ui.clockOverlay).toBe(false);
  });

  it("returns the same object when nothing changes or the key is unknown", () => {
    const data = createEmpty();
    expect(setUiFlag(data, "clockWindow", false)).toBe(data);
    expect(setUiFlag(data, "lastTab", true)).toBe(data);
    const older = { ...data, ui: { lastTab: "" } };
    expect(setUiFlag(older, "clockWindow", false)).toBe(older);
  });
});
```

**Step 2: Run test to verify it fails**
Run: `npm test -- tests/store.test.js`
Expected: FAIL (ui shape and `setUiFlag is not a function`).

**Step 3: Write minimal implementation**

In `utils/store.js`:
```js
function createEmpty() {
  return { version: VERSION, tasks: [], eventChecks: {}, reminders: [], bookmarks: [], notes: [], focusLog: {}, ui: { lastTab: "", clockWindow: false, clockOverlay: false } };
}
```
```js
// Detached clock forms that reopen after a restart.
var UI_FLAGS = ["clockWindow", "clockOverlay"];

function normalizeUi(ui) {
  const src = ui && typeof ui === "object" ? ui : {};
  const out = { lastTab: Tabs.isTab(src.lastTab) ? src.lastTab : "" };
  for (const key of UI_FLAGS) out[key] = src[key] === true;
  return out;
}

// Same object back when nothing changes, so toggling to the current state does not
// schedule a write. A missing flag counts as false.
function setUiFlag(data, key, value) {
  if (UI_FLAGS.indexOf(key) < 0) return data;
  const ui = data.ui || {};
  const v = !!value;
  if (!!ui[key] === v) return data;
  const patch = {};
  patch[key] = v;
  return Object.assign({}, data, { ui: Object.assign({}, ui, patch) });
}
```
No `VERSION` bump: new fields are optional and default to false.

**Step 4: Run test to verify it passes**
Run: `npm test -- tests/store.test.js tests/tabs.test.js`, then `npm test`
Expected: PASS (tabs tests unchanged; `setLastTab` keeps the other ui fields).

**Step 5: Commit**
Run: `/git commit`

---

### Task 3: i18n keys and manifest defaults

**Requirement:** REQ-001, REQ-005, REQ-006
**Files:**
- Modify: `i18n/pt.json`, `i18n/en.json`, `manifest.json`
- Test: `tests/i18n.test.js`, `tests/manifest.test.js`

**Team:**
- Track: frontend
- Implementer: frontend-engineer (skills: test-driven-development)
- Reviewers: test-reviewer

**Step 1: Write the failing test**
- `tests/i18n.test.js` `DYNAMIC`, append:
```js
  ...["top-left", "top-right", "bottom-left", "bottom-right"].map((c) => "settings.clock-corners." + c),
  ...["small", "medium", "large"].map((s) => "settings.clock-sizes." + s),
```
- `tests/manifest.test.js`: the sorted default-settings list gains `"clockCorner"` and `"clockSize"` (keep it sorted: `"autoStartBreaks", "autoStartWork", "clockCorner", "clockSize", "dailyPomodoroGoal", ...`).

**Step 2: Run test to verify it fails**
Run: `npm test -- tests/i18n.test.js tests/manifest.test.js`
Expected: FAIL (missing keys, missing defaults).

**Step 3: Write minimal implementation**
- `manifest.json` `defaultSettings`: add `"clockCorner": "top-right"`, `"clockSize": "medium"`.
- `i18n/pt.json`, merged into existing objects (keep order; append):
```json
"focus": {
  "clock-window-open": "Abrir em janela",
  "clock-window-close": "Fechar a janela",
  "clock-overlay-open": "Fixar no canto",
  "clock-overlay-close": "Desafixar do canto"
},
"settings": {
  "clock-corner": "Canto do relógio fixado",
  "clock-size": "Tamanho do relógio fixado",
  "clock-corners": { "top-left": "Superior esquerdo", "top-right": "Superior direito", "bottom-left": "Inferior esquerdo", "bottom-right": "Inferior direito" },
  "clock-sizes": { "small": "Pequeno", "medium": "Médio", "large": "Grande" }
}
```
- `i18n/en.json`, same keys:
```json
"focus": {
  "clock-window-open": "Open in a window",
  "clock-window-close": "Close the window",
  "clock-overlay-open": "Pin to corner",
  "clock-overlay-close": "Unpin from corner"
},
"settings": {
  "clock-corner": "Pinned clock corner",
  "clock-size": "Pinned clock size",
  "clock-corners": { "top-left": "Top left", "top-right": "Top right", "bottom-left": "Bottom left", "bottom-right": "Bottom right" },
  "clock-sizes": { "small": "Small", "medium": "Medium", "large": "Large" }
}
```
Merge with a script that refuses to overwrite existing keys, and write back with `JSON.stringify(_, null, 2)` + newline (the files round-trip byte-identical through it).

**Step 4: Run test to verify it passes**
Run: `npm test -- tests/i18n.test.js tests/manifest.test.js`
Expected: PASS.

**Step 5: Commit**
Run: `/git commit`

---

### Task 4: ClockFace component

**Requirement:** REQ-004, REQ-005
**Files:**
- Create: `components/ClockFace.qml`

**Team:**
- Track: frontend
- Implementer: frontend-engineer (skills: accessibility-guardrails)
- Reviewers: business-logic-reviewer, consequences-reviewer

**Step 1: Write the failing test**
Runtime check deferred to Task 6 (first host). Static check: `/usr/lib/qt6/bin/qmllint components/ClockFace.qml` (only `qs.*` import/unqualified warnings allowed).

**Step 2: Run test to verify it fails**
Expected: FAIL (file does not exist).

**Step 3: Write minimal implementation**

`components/ClockFace.qml`:
```qml
import QtQuick 6.11
import QtQuick.Layouts
import qs.Commons
import qs.Widgets
import "ui"
import "../utils/pomodoro.js" as Pomodoro
import "../utils/clock.js" as Clock

// Detached clock face: the active clock's ring and numbers, sized by the host.
// Play/pause, reset (and close, when the host asks) fade in while the pointer is over it.
Item {
  id: root

  property var pluginApi: null
  property var mainInstance: null
  property bool showClose: false
  property string closeText: ""
  signal closeRequested

  readonly property bool running: mainInstance?.shownRunning ?? false
  readonly property int remaining: mainInstance?.shownRemaining ?? 0
  readonly property bool hovered: hover.hovered
  // Buttons scale with the ring, so the small overlay keeps them inside it.
  readonly property int buttonSize: Math.max(18, Math.round(ring.width * 0.17))

  function tr(key) {
    return pluginApi ? pluginApi.tr(key) : key;
  }

  HoverHandler {
    id: hover
  }

  ProgressRing {
    id: ring
    anchors.centerIn: parent
    width: Math.min(root.width, root.height)
    height: width
    thickness: Math.max(3, Math.round(width * 0.04))
    progress: Clock.progress(root.remaining, root.mainInstance?.shownTotal ?? 0)
    arcColor: root.running ? Color.mPrimary : Qt.alpha(Color.mPrimary, 0.5)
    accessibleName: Pomodoro.formatClock(root.remaining)

    NText {
      anchors.centerIn: parent
      // Moves up while the controls show, so they never cover the numbers.
      anchors.verticalCenterOffset: root.hovered ? -Math.round(ring.height * 0.1) : 0
      width: Math.round(ring.width * 0.66)
      horizontalAlignment: Text.AlignHCenter
      fontSizeMode: Text.HorizontalFit
      minimumPointSize: Style.fontSizeXS
      elide: Text.ElideNone
      text: Pomodoro.formatClock(root.remaining)
      family: Settings.data.ui.fontFixed
      // Upper bound only: HorizontalFit shrinks it to the ring width.
      pointSize: Style.fontSizeXXXL * 4
      font.weight: Style.fontWeightBold
      color: root.running ? Color.mPrimary : Color.mOnSurface

      Behavior on anchors.verticalCenterOffset {
        NumberAnimation {
          duration: 150
        }
      }
    }

    RowLayout {
      anchors.horizontalCenter: parent.horizontalCenter
      anchors.bottom: parent.bottom
      anchors.bottomMargin: Math.round(ring.height * 0.17)
      spacing: Math.round(4 * Style.uiScaleRatio)
      opacity: root.hovered ? 1 : 0
      visible: opacity > 0

      Behavior on opacity {
        NumberAnimation {
          duration: 150
        }
      }

      PillButton {
        implicitHeight: root.buttonSize
        icon: root.running ? "player-pause" : "player-play"
        tooltipText: root.running ? root.tr("focus.pause") : root.tr("focus.start")
        onClicked: root.mainInstance.shownToggle()
      }

      PillButton {
        implicitHeight: root.buttonSize
        icon: "refresh"
        tooltipText: root.tr("focus.reset")
        onClicked: root.mainInstance.shownReset()
      }

      PillButton {
        visible: root.showClose
        implicitHeight: root.buttonSize
        icon: "x"
        tooltipText: root.closeText
        onClicked: root.closeRequested()
      }
    }
  }
}
```
If `PillButton`'s icon does not shrink with `implicitHeight`, leave it: the button stays round and the icon may look large on "small"; note it for the smoke row.

**Step 4: Run test to verify it passes**
Run: `/usr/lib/qt6/bin/qmllint components/ClockFace.qml` (no syntax errors) and `npm test` (i18n scan finds `focus.pause`, `focus.start`, `focus.reset`, all existing).
Expected: PASS.

**Step 5: Commit**
Run: `/git commit`

---

### Task 5: Main services: shown clock, open/close, restore

**Requirement:** REQ-004, REQ-005, REQ-007
**Files:**
- Modify: `Main.qml`

**Team:**
- Track: frontend
- Implementer: frontend-engineer (skills: none)
- Reviewers: business-logic-reviewer, consequences-reviewer

**Step 1: Write the failing test**
Runtime check: after Task 6, `ClockWindow` reads `mainInstance.shownRemaining`; before this task it is undefined.

**Step 2: Run test to verify it fails**
Expected: FAIL (`shownRemaining`, `setClockWindow` undefined).

**Step 3: Write minimal implementation**

Add after the timer section (before `Component.onCompleted`):
```qml
  // ---------------------------------------------------------------- detached clock
  // Window and corner overlay show one clock: the bar's while one runs or rings,
  // else the Focus view's. Their open state lives in data.ui and reopens on load.

  readonly property string shownClock: Clock.shownClock({ pomodoroRunning: pomodoroRunning, timerRunning: timerRunning, alarmSource: alarmSource, focusPanel: focusPanel })
  readonly property int shownRemaining: shownClock === "timer" ? timerRemaining : pomodoroRemaining
  readonly property int shownTotal: shownClock === "timer" ? timerTotal : Pomodoro.durationFor(pomodoroMode, pomodoroConfig)
  readonly property bool shownRunning: shownClock === "timer" ? timerRunning : pomodoroRunning
  readonly property bool clockWindowOpen: data?.ui?.clockWindow === true
  readonly property bool clockOverlayOpen: data?.ui?.clockOverlay === true

  // Same rules as the bar's middle click: a ringing timer is only silenced.
  function shownToggle() {
    if (shownClock === "timer") {
      if (timerSoundPlaying)
        stopAlarm("timer");
      else if (timerRunning)
        timerPause();
      else
        timerStart();
    } else if (pomodoroRunning) {
      pomodoroPause();
    } else {
      pomodoroStart();
    }
  }

  function shownReset() {
    if (shownClock === "timer")
      timerReset();
    else
      pomodoroReset();
  }

  function setUiFlag(key, value) {
    const next = Store.setUiFlag(data, key, value);
    if (next !== data)
      commit(next);
  }

  function setClockWindow(open) {
    setUiFlag("clockWindow", open);
    if (clockWindow.visible !== open)
      clockWindow.visible = open;
  }

  function setClockOverlay(open) {
    setUiFlag("clockOverlay", open);
    if (!open)
      clockOverlay.visible = false;
    else if (!clockOverlay.visible && pluginApi)
      pluginApi.withCurrentScreen(screen => clockOverlay.openOn(screen));
  }

  function restoreClockForms() {
    if (clockWindowOpen)
      clockWindow.visible = true;
    if (clockOverlayOpen && pluginApi && !clockOverlay.visible)
      pluginApi.withCurrentScreen(screen => clockOverlay.openOn(screen));
  }

  ClockWindow {
    id: clockWindow
    pluginApi: root.pluginApi
    mainInstance: root
  }

  ClockOverlay {
    id: clockOverlay
    pluginApi: root.pluginApi
    mainInstance: root
  }
```
- In `applyLoaded(text)`, after `root.loaded = true;`: `Qt.callLater(root.restoreClockForms);`
- Add `onPluginApiChanged: if (pluginApi && loaded) restoreClockForms()` (the store may load before the plugin API arrives).
- `Store` is already imported as `Store` (check the import line; add `import "utils/store.js" as Store` only if missing).

`ClockWindow`/`ClockOverlay` are created in Tasks 6 and 7. Until then, comment out the two blocks and the `clockWindow`/`clockOverlay` references so the file loads; Tasks 6 and 7 uncomment them.

**Step 4: Run test to verify it passes**
Restart the shell (Conventions): no daybar errors. `npm test` green.

**Step 5: Commit**
Run: `/git commit`

---

### Task 6: ClockWindow (floating window)

**Requirement:** REQ-002
**Files:**
- Create: `ClockWindow.qml`
- Modify: `Main.qml` (uncomment the `ClockWindow` block and its references)

**Team:**
- Track: frontend
- Implementer: frontend-engineer (skills: accessibility-guardrails)
- Reviewers: consequences-reviewer

**Step 1: Write the failing test**
Runtime check: `qs -c noctalia-shell ipc call plugin:daybar open focus`, then from a scratch `Qt.callLater(() => setClockWindow(true))` in `restoreClockForms` (remove after) or wait for Task 8's button.

**Step 2: Run test to verify it fails**
Expected: FAIL (`ClockWindow is not a type`).

**Step 3: Write minimal implementation**

`ClockWindow.qml`:
```qml
import QtQuick 6.11
import Quickshell
import qs.Commons
import "components"

// Detached clock as a real Niri window titled "Daybar timer": move, resize, other
// monitor. Placement belongs to a niri window-rule matched by the title (README).
FloatingWindow {
  id: root

  property var pluginApi: null
  property var mainInstance: null

  title: "Daybar timer"
  implicitWidth: Math.round(280 * Style.uiScaleRatio)
  implicitHeight: Math.round(280 * Style.uiScaleRatio)
  minimumSize: Qt.size(Math.round(160 * Style.uiScaleRatio), Math.round(160 * Style.uiScaleRatio))
  visible: false
  color: Color.mSurface

  // Closed by the compositor (Mod+Q) or the Focus button: record it once.
  onVisibleChanged: {
    if (!visible && mainInstance?.clockWindowOpen)
      mainInstance.setClockWindow(false);
  }

  ClockFace {
    anchors.fill: parent
    anchors.margins: Math.round(16 * Style.uiScaleRatio)
    pluginApi: root.pluginApi
    mainInstance: root.mainInstance
  }
}
```

**Step 4: Run test to verify it passes**
Restart the shell; open the window (scratch call or Task 8):
1. A window titled "Daybar timer" appears; `niri msg --json windows | grep -A3 "Daybar timer"` shows its `app_id` (record it in the README task).
2. Resize it: the ring and numbers scale.
3. Hover: play/pause and reset appear; play starts the shown clock.
4. Mod+Q closes it; `grep -o '"clockWindow":[a-z]*' ~/.local/share/noctalia-daybar/data.json` prints `false`.
Remove any scratch call. No daybar errors.

**Step 5: Commit**
Run: `/git commit`

---

### Task 7: ClockOverlay (corner overlay)

**Requirement:** REQ-003, REQ-006
**Files:**
- Create: `ClockOverlay.qml`
- Modify: `Main.qml` (uncomment the `ClockOverlay` block and its references)

**Team:**
- Track: frontend
- Implementer: frontend-engineer (skills: accessibility-guardrails)
- Reviewers: consequences-reviewer

**Step 1: Write the failing test**
Runtime check: open the overlay (scratch call or Task 8's button).

**Step 2: Run test to verify it fails**
Expected: FAIL (`ClockOverlay is not a type`).

**Step 3: Write minimal implementation**

`ClockOverlay.qml`:
```qml
import QtQuick 6.11
import Quickshell
import Quickshell.Wayland
import qs.Commons
import "components"
import "utils/clock.js" as Clock

// Detached clock pinned to a screen corner. Top layer (full-screen apps cover it),
// never takes keyboard focus, reserves no space but stays clear of the bar.
PanelWindow {
  id: root

  property var pluginApi: null
  property var mainInstance: null
  readonly property var corner: Clock.cornerAnchors(mainInstance?.setting("clockCorner"))
  readonly property int ringPx: Math.round(Clock.ringSize(mainInstance?.setting("clockSize")) * Style.uiScaleRatio)
  readonly property int pad: Math.round(8 * Style.uiScaleRatio)

  anchors.top: corner.top
  anchors.bottom: corner.bottom
  anchors.left: corner.left
  anchors.right: corner.right
  margins.top: Style.marginL
  margins.bottom: Style.marginL
  margins.left: Style.marginL
  margins.right: Style.marginL
  implicitWidth: ringPx + pad * 2
  implicitHeight: implicitWidth
  visible: false
  color: "transparent"

  WlrLayershell.layer: WlrLayer.Top
  WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
  WlrLayershell.namespace: "noctalia-daybar-clock"
  WlrLayershell.exclusionMode: ExclusionMode.Normal
  exclusiveZone: 0

  function openOn(targetScreen) {
    screen = targetScreen;
    visible = true;
  }

  Rectangle {
    anchors.fill: parent
    radius: width / 2
    color: Qt.alpha(Color.mSurface, 0.88)
    border.color: Qt.alpha(Color.mOnSurface, 0.08)
    border.width: Style.borderS
  }

  ClockFace {
    anchors.fill: parent
    anchors.margins: root.pad
    pluginApi: root.pluginApi
    mainInstance: root.mainInstance
    showClose: true
    closeText: root.pluginApi ? root.pluginApi.tr("focus.clock-overlay-close") : ""
    onCloseRequested: root.mainInstance.setClockOverlay(false)
  }
}
```
If `ExclusionMode.Normal` still overlaps the bar at runtime, switch to `ExclusionMode.Ignore` and add the bar height to the margin on the bar's edge; record which one landed.

**Step 4: Run test to verify it passes**
Restart the shell; open the overlay:
1. Card in the top-right, clear of the bar, on every workspace; typing in a window still goes to that window.
2. Change the corner and size in Settings (Task 9): it moves and resizes at once.
3. Hover: play/pause, reset, close; close hides it and `ui.clockOverlay` turns `false`.
4. Restart the shell with it open: it comes back.
No daybar errors.

**Step 5: Commit**
Run: `/git commit`

---

### Task 8: Focus header buttons

**Requirement:** REQ-001
**Files:**
- Modify: `components/FocusView.qml`

**Team:**
- Track: frontend
- Implementer: frontend-engineer (skills: accessibility-guardrails)
- Reviewers: consequences-reviewer

**Step 1: Write the failing test**
Runtime check: open Focus.

**Step 2: Run test to verify it fails**
Expected: FAIL (no window/pin buttons in the header).

**Step 3: Write minimal implementation**

In the header `RowLayout`, between the progress `NText` and the gear `PillButton`, add (visible in both views):
```qml
      PillButton {
        icon: "picture-in-picture"
        primary: root.mainInstance?.clockWindowOpen ?? false
        tooltipText: root.tr(primary ? "focus.clock-window-close" : "focus.clock-window-open")
        onClicked: root.mainInstance.setClockWindow(!root.mainInstance.clockWindowOpen)
      }

      PillButton {
        icon: root.mainInstance?.clockOverlayOpen ? "pinned" : "pin"
        primary: root.mainInstance?.clockOverlayOpen ?? false
        tooltipText: root.tr(primary ? "focus.clock-overlay-close" : "focus.clock-overlay-open")
        onClicked: root.mainInstance.setClockOverlay(!root.mainInstance.clockOverlayOpen)
      }
```
The gear keeps `visible: !root.timerView`.

**Step 4: Run test to verify it passes**
Restart the shell, open Focus:
1. Two buttons next to the progress text in the pomodoro view and in the Timer view.
2. Click each: the form opens and the button turns primary; click again: it closes.
3. Tab reaches both; Space toggles; tooltips read open/close.
No daybar errors; `npm test` green (i18n scan).

**Step 5: Commit**
Run: `/git commit`

---

### Task 9: Settings: overlay corner and size

**Requirement:** REQ-006
**Files:**
- Modify: `Settings.qml`

**Team:**
- Track: frontend
- Implementer: frontend-engineer (skills: accessibility-guardrails)
- Reviewers: consequences-reviewer

**Step 1: Write the failing test**
Runtime check: open the plugin settings.

**Step 2: Run test to verify it fails**
Expected: FAIL (no corner/size options).

**Step 3: Write minimal implementation**

In `Settings.qml`:
- Properties: `property string clockCorner: "top-right"`, `property string clockSize: "medium"`.
- `loadSettings()`: `clockCorner = value("clockCorner"); clockSize = value("clockSize");`
- `saveSettings()`: `s.clockCorner = clockCorner; s.clockSize = clockSize;`
- Import `"utils/clock.js" as Clock`. After the play-sound toggle in the Focus section:
```qml
  NComboBox {
    label: root.tr("settings.clock-corner")
    model: Clock.CORNERS.map(k => ({ key: k, name: root.tr("settings.clock-corners." + k) }))
    currentKey: root.clockCorner
    onSelected: key => root.clockCorner = key
  }

  NComboBox {
    label: root.tr("settings.clock-size")
    model: Object.keys(Clock.RING_SIZES).map(k => ({ key: k, name: root.tr("settings.clock-sizes." + k) }))
    currentKey: root.clockSize
    onSelected: key => root.clockSize = key
  }
```

**Step 4: Run test to verify it passes**
Restart the shell, open the plugin settings: both combos with translated names; saving moves/resizes an open overlay (it binds to `setting()`). `npm test` green.

**Step 5: Commit**
Run: `/git commit`

---

### Task 10: Docs, smoke rows and verification

**Requirement:** REQ-008 and all (verification)
**Files:**
- Modify: `README.md`, `CLAUDE.md`, `docs/SMOKE.md`, `docs/specs/focus-clock-detach/SPEC.md`, `docs/specs/focus-clock-detach/STATE.md`

**Team:**
- Track: docs
- Implementer: frontend-engineer (skills: verification-before-completion)
- Reviewers: test-reviewer

**Step 1: Write the failing test**
Run: `grep -n "Daybar timer" README.md docs/SMOKE.md`
Expected: no match.

**Step 2: Run test to verify it fails**
Expected: FAIL.

**Step 3: Write minimal implementation**
- `README.md` Focus section: the two header buttons, hover controls, corner/size settings, restore on restart, and the niri rule (use the `app_id` recorded in Task 6; keep the title match either way):
~~~kdl
window-rule {
    match title="^Daybar timer$"
    open-floating true
    default-column-width { fixed 280; }
    default-window-height { fixed 280; }
    default-floating-position x=24 y=24 relative-to="top-right"
}
~~~
- `CLAUDE.md`: in "Services live in Main.qml" mention the detached clock forms; in Architecture add one line: "`ClockWindow.qml` (FloatingWindow) and `ClockOverlay.qml` (Top-layer PanelWindow) share `components/ClockFace.qml`".
- `docs/SMOKE.md`: `## Detached clock` rows 63 onward, one per REQ (buttons, window resize/close, overlay corner/layer/focus, active clock switch, hover controls, corner/size settings, restore after restart, niri rule).
- `SPEC.md` traceability statuses from what was verified; `STATE.md` `phase: none`, plan_path, Verified / Not walked.

**Step 4: Run test to verify it passes**
```bash
npm test > /tmp/daybar-test.log 2>&1; echo "EXIT=$?"; grep -E "Tests +[0-9]+ passed|failed" /tmp/daybar-test.log
grep -rniE "n[i]ko" --exclude-dir=node_modules --exclude-dir=.git --exclude-dir=coverage . && echo "FOUND REFERENCE" || echo "clean"
```
Expected: `EXIT=0`, `Tests  N passed`, `clean`. Restart the shell and walk the new smoke rows.

**Step 5: Commit**
Run: `/git commit`

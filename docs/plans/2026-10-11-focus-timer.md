# Plan: Countdown timer and pomodoro commands in quick capture

> **Spec:** docs/specs/focus-timer/SPEC.md
> **Depends on:** none (no active plan touches these files). `README.md` has an uncommitted
> change in the working tree; Task 12 edits it, so commit or stash that change first.

**Goal:** Add a free-form countdown timer as a fourth chip of the Focus tab (circular ring, alarm, toast), mutually exclusive with the pomodoro, plus `/t` and `/p` quick-capture commands.
**Architecture:** Pure helpers in `utils/duration.js` (parser), `utils/clock.js` (bar source, ring progress, chip action) and two capture handlers (`utils/capture/timer.js` in the Tab cycle, `utils/capture/pomodoro.js` behind `/p`). `Main.qml` gains timer state, a shared alarm (`alarmSource`) and the exclusivity rule. UI: `components/ui/ProgressRing.qml` (QtQuick.Shapes), `components/TimerPane.qml`, `FocusView.qml`, `CaptureWindow.qml`, `BarWidget.qml`.
**Tech Stack:** QML (noctalia-shell 4.7.x, Qt 6.11), ES2018 JavaScript as QML libraries, vitest 2.
**Total Tasks:** 12
**Estimated Complexity:** medium (Deep: 11 P1 REQs)

---

## Conventions for every task

- Repo root: `~/dev/projects/noctalia-daybar`. `npm test -- <file>` for one file, `npm test` for the suite; read the `Tests  N passed` line, never a piped exit code.
- `utils/**/*.js`: `.pragma library`, `.import` for deps, top-level declarations at column 0, no ES modules, no `eval`/`Function`.
- QML runtime check: `qs -c noctalia-shell kill`, wait until `pgrep -x qs` is empty, start it detached (`qs -c noctalia-shell -d`), then `grep -iE "ReferenceError|TypeError|is not a type|non-existent|daybar" "$(ls -t /run/user/1000/quickshell/by-id/*/log.log | head -1)"` shows no daybar error, plus the task's visual check.
- Use short durations for runtime checks (`/t 5s`, focus duration 1 min).
- Commit after every task with `/git commit`. Implementers DO NOT run any git command and DO NOT invoke the git-commit skill.
- Do NOT reference any previous or source project in code, comments, docs or commits.

## Dependency graph

```
T1 duration ──┬── T3 capture handlers ── T4 registry ── T10 CaptureWindow
T2 clock ─────┤                                          │
T5 i18n ──────┼── T6 Main services ── T8 FocusView ── T9 TimerPane
T7 ProgressRing ┘                     T11 BarWidget
T12 docs, smoke, verification (all)
```

Parallel batches: {T1, T2, T5, T7} → {T3, T6} → {T4, T8, T11} → {T9, T10} → T12.

---

### Task 1: Duration parser

**Requirement:** REQ-001
**Files:**
- Create: `utils/duration.js`
- Test: `tests/duration.test.js`

**Team:**
- Track: backend
- Implementer: backend-engineer (skills: test-driven-development)
- Reviewers: business-logic-reviewer, test-reviewer

**Step 1: Write the failing test**

`tests/duration.test.js`:
```js
import { describe, it, expect } from "vitest";
import { parseDuration, MAX_SECONDS } from "../utils/duration.js";

describe("parseDuration", () => {
  it.each([
    ["90s", 90],
    ["10m", 600],
    ["10min", 600],
    ["10MIN", 600],
    ["1h", 3600],
    ["1h30", 5400],
    ["1h30m", 5400],
    ["1:30", 90],
    ["1:02:03", 3723],
    ["25", 1500]
  ])("%s -> %i s", (text, seconds) => {
    expect(parseDuration(text)).toEqual({ ok: true, seconds, label: "" });
  });

  it("keeps the other words as the label, wherever the duration is", () => {
    expect(parseDuration("chá 5m")).toEqual({ ok: true, seconds: 300, label: "chá" });
    expect(parseDuration("10m tirar o bolo")).toEqual({ ok: true, seconds: 600, label: "tirar o bolo" });
  });

  it("prefers a token with a unit over a bare number", () => {
    expect(parseDuration("2 ovos 7m")).toEqual({ ok: true, seconds: 420, label: "2 ovos" });
  });

  it("fails without a duration", () => {
    expect(parseDuration("chá")).toEqual({ ok: false, error: "needs-duration" });
    expect(parseDuration("")).toEqual({ ok: false, error: "needs-duration" });
    expect(parseDuration(null)).toEqual({ ok: false, error: "needs-duration" });
  });

  it("rejects zero, more than 24 h and out-of-range fields", () => {
    for (const t of ["0", "0s", "25h", "1441m", "1:75", "1h75", "86401s"]) {
      expect(parseDuration(t)).toEqual({ ok: false, error: "invalid-duration" });
    }
    expect(parseDuration("24h")).toEqual({ ok: true, seconds: MAX_SECONDS, label: "" });
  });
});
```

**Step 2: Run test to verify it fails**
Run: `npm test -- tests/duration.test.js`
Expected: FAIL (cannot resolve `../utils/duration.js`).

**Step 3: Write minimal implementation**

`utils/duration.js`:
```js
.pragma library

// Free-form countdown durations for the timer: "90s", "10m", "10min", "1h", "1h30",
// "1h30m", "1:30" (m:ss), "1:02:03" (h:mm:ss) or a bare number of minutes.
// A field out of range (seconds or minutes above 59) yields -1, read as invalid.
var MAX_SECONDS = 24 * 3600;

var UNIT_PATTERNS = [
  [/^(\d{1,2}):(\d{2}):(\d{2})$/, (m) => (+m[2] > 59 || +m[3] > 59 ? -1 : +m[1] * 3600 + +m[2] * 60 + +m[3])],
  [/^(\d{1,4}):(\d{2})$/, (m) => (+m[2] > 59 ? -1 : +m[1] * 60 + +m[2])],
  [/^(\d{1,2})h(?:(\d{1,2})m?)?$/, (m) => (m[2] && +m[2] > 59 ? -1 : +m[1] * 3600 + (m[2] ? +m[2] * 60 : 0))],
  [/^(\d{1,4})(?:m|min)$/, (m) => +m[1] * 60],
  [/^(\d{1,5})s$/, (m) => +m[1]]
];
var BARE_MINUTES = /^(\d{1,4})$/;

function tokenSeconds(token, allowBare) {
  for (const [re, toSeconds] of UNIT_PATTERNS) {
    const m = re.exec(token);
    if (m) return toSeconds(m);
  }
  const bare = allowBare ? BARE_MINUTES.exec(token) : null;
  return bare ? +bare[1] * 60 : null;
}

// -> { ok: true, seconds, label } | { ok: false, error: "needs-duration" | "invalid-duration" }
// The first word with a unit wins, else the first bare number; the other words form the label.
function parseDuration(text) {
  const words = String(text || "").trim().split(/\s+/).filter((w) => w);
  for (const allowBare of [false, true]) {
    for (let i = 0; i < words.length; i++) {
      const seconds = tokenSeconds(words[i].toLowerCase(), allowBare);
      if (seconds === null) continue;
      if (seconds <= 0 || seconds > MAX_SECONDS) return { ok: false, error: "invalid-duration" };
      return { ok: true, seconds: seconds, label: words.slice(0, i).concat(words.slice(i + 1)).join(" ") };
    }
  }
  return { ok: false, error: "needs-duration" };
}
```

**Step 4: Run test to verify it passes**
Run: `npm test -- tests/duration.test.js`
Expected: PASS (all cases).

**Step 5: Commit**
Run: `/git commit`

---

### Task 2: Clock helpers (bar source, ring progress, chip action)

**Requirement:** REQ-002, REQ-005, REQ-011
**Files:**
- Create: `utils/clock.js`
- Test: `tests/clock.test.js`

**Team:**
- Track: backend
- Implementer: backend-engineer (skills: test-driven-development)
- Reviewers: business-logic-reviewer, test-reviewer

**Step 1: Write the failing test**

`tests/clock.test.js`:
```js
import { describe, it, expect } from "vitest";
import { barSource, progress, middleClickTarget, chipAction, TIMER_CHIP, TIMER_ICON } from "../utils/clock.js";

describe("barSource", () => {
  const base = { pomodoroRunning: false, timerRunning: false, alarmSource: "" };

  it("shows the running clock first", () => {
    expect(barSource({ ...base, timerRunning: true })).toBe("timer");
    expect(barSource({ ...base, pomodoroRunning: true, alarmSource: "timer" })).toBe("pomodoro");
  });

  it("falls back to the clock whose alarm rings, else nothing", () => {
    expect(barSource({ ...base, alarmSource: "timer" })).toBe("timer");
    expect(barSource({ ...base, alarmSource: "pomodoro" })).toBe("pomodoro");
    expect(barSource(base)).toBe("");
    expect(barSource({ ...base, alarmSource: "junk" })).toBe("");
  });
});

describe("progress", () => {
  it("is remaining over total, clamped to [0, 1]", () => {
    expect(progress(150, 300)).toBe(0.5);
    expect(progress(400, 300)).toBe(1);
    expect(progress(-2, 300)).toBe(0);
  });

  it("is 0 without a positive total", () => {
    expect(progress(10, 0)).toBe(0);
    expect(progress(10, undefined)).toBe(0);
  });
});

describe("middleClickTarget", () => {
  it("drives the clock shown, else the pomodoro", () => {
    expect(middleClickTarget("timer")).toBe("timer");
    expect(middleClickTarget("pomodoro")).toBe("pomodoro");
    expect(middleClickTarget("")).toBe("pomodoro");
  });
});

describe("chipAction", () => {
  // modes: WORK 0, SHORT 1, LONG 2
  it("the Timer chip only switches the view", () => {
    expect(chipAction(TIMER_CHIP, "pomodoro", 0)).toBe("show-timer");
    expect(chipAction(TIMER_CHIP, "timer", 0)).toBe("show-timer");
  });

  it("the current pomodoro mode seen from the Timer view switches back without a reset", () => {
    expect(chipAction(1, "timer", 1)).toBe("show-pomodoro");
  });

  it("any other pomodoro chip sets the mode, as before", () => {
    expect(chipAction(2, "timer", 1)).toBe("set-mode");
    expect(chipAction(1, "pomodoro", 1)).toBe("set-mode");
  });

  it("names the timer icon", () => {
    expect(TIMER_ICON).toBe("alarm");
  });
});
```

**Step 2: Run test to verify it fails**
Run: `npm test -- tests/clock.test.js`
Expected: FAIL (cannot resolve `../utils/clock.js`).

**Step 3: Write minimal implementation**

`utils/clock.js`:
```js
.pragma library

// Shared rules for the two countdowns (pomodoro and timer). Only one counts at a
// time: starting one pauses the other.

var TIMER_ICON = "alarm";
// Chip value of the Timer chip in the Focus tab (pomodoro modes are 0..2).
var TIMER_CHIP = -1;

// Which clock the bar shows: the running one, else the one whose alarm rings.
// state: { pomodoroRunning, timerRunning, alarmSource } -> "timer" | "pomodoro" | ""
function barSource(state) {
  if (state.timerRunning) return "timer";
  if (state.pomodoroRunning) return "pomodoro";
  return state.alarmSource === "timer" || state.alarmSource === "pomodoro" ? state.alarmSource : "";
}

// Ring fill: remaining over total, clamped to [0, 1]; 0 without a positive total.
function progress(remaining, total) {
  if (!(total > 0)) return 0;
  return Math.min(1, Math.max(0, remaining / total));
}

// Middle click on the bar pauses or resumes the clock shown, else the pomodoro.
function middleClickTarget(source) {
  return source === "timer" ? "timer" : "pomodoro";
}

// Focus tab chip click -> "show-timer" | "show-pomodoro" | "set-mode".
// Coming back from the Timer view to the current pomodoro mode must not reset it.
function chipAction(chip, view, mode) {
  if (chip === TIMER_CHIP) return "show-timer";
  if (view === "timer" && chip === mode) return "show-pomodoro";
  return "set-mode";
}
```

**Step 4: Run test to verify it passes**
Run: `npm test -- tests/clock.test.js`
Expected: PASS.

**Step 5: Commit**
Run: `/git commit`

---

### Task 3: Capture handlers for timer and pomodoro commands

**Requirement:** REQ-008, REQ-009
**Files:**
- Create: `utils/capture/timer.js`, `utils/capture/pomodoro.js`
- Test: `tests/capture-timer.test.js`

**Team:**
- Track: backend
- Implementer: backend-engineer (skills: test-driven-development)
- Reviewers: business-logic-reviewer, test-reviewer

**Step 1: Write the failing test**

`tests/capture-timer.test.js`:
```js
import { describe, it, expect } from "vitest";
import * as Timer from "../utils/capture/timer.js";
import * as PomodoroCommand from "../utils/capture/pomodoro.js";

describe("timer capture", () => {
  it("starts a timer with a duration and label", () => {
    expect(Timer.build("chá 5m")).toEqual({ ok: true, type: "timer", action: "startTimer", payload: { seconds: 300, label: "chá" } });
  });

  it("toggles with an empty body and resets with parar/stop", () => {
    expect(Timer.build("")).toMatchObject({ ok: true, action: "timerToggle" });
    expect(Timer.build("PARAR")).toMatchObject({ ok: true, action: "timerStop" });
    expect(Timer.build("stop")).toMatchObject({ ok: true, action: "timerStop" });
  });

  it("passes the parser error through", () => {
    expect(Timer.build("chá")).toEqual({ ok: false, type: "timer", error: "needs-duration" });
    expect(Timer.build("25h")).toEqual({ ok: false, type: "timer", error: "invalid-duration" });
  });

  it("allows an empty body only through its prefix", () => {
    expect(Timer.ALLOW_EMPTY).toBe(true);
  });

  it("names the preview line from the timer state", () => {
    const none = { set: false, running: false };
    const paused = { set: true, running: false };
    const running = { set: true, running: true };
    expect(Timer.previewKey("startTimer", none)).toBe("");
    expect(Timer.previewKey("startTimer", paused)).toBe("capture.timer.replaces");
    expect(Timer.previewKey("timerToggle", none)).toBe("capture.error.no-timer");
    expect(Timer.previewKey("timerToggle", paused)).toBe("capture.timer.resume");
    expect(Timer.previewKey("timerToggle", running)).toBe("capture.timer.pause");
    expect(Timer.previewKey("timerStop", running)).toBe("capture.timer.stop");
  });
});

describe("pomodoro command capture", () => {
  it.each([
    ["", "toggle"],
    ["foco", "work"],
    ["Focus", "work"],
    ["curta", "short"],
    ["pausa  curta", "short"],
    ["short", "short"],
    ["longa", "long"],
    ["pausa longa", "long"],
    ["parar", "stop"],
    ["stop", "stop"]
  ])("'%s' -> %s", (text, command) => {
    expect(PomodoroCommand.build(text)).toEqual({ ok: true, type: "pomodoro", action: "pomodoro", payload: { command } });
  });

  it("rejects anything else", () => {
    expect(PomodoroCommand.build("agora")).toEqual({ ok: false, type: "pomodoro", error: "unknown-command" });
    expect(PomodoroCommand.build("constructor")).toEqual({ ok: false, type: "pomodoro", error: "unknown-command" });
  });

  // modes: WORK 0, SHORT 1, LONG 2
  it("plans what Enter does from the pomodoro state", () => {
    expect(PomodoroCommand.plan("toggle", { running: true, mode: 0 })).toEqual({ op: "pause", switchTo: -1 });
    expect(PomodoroCommand.plan("toggle", { running: false, mode: 0 })).toEqual({ op: "start", switchTo: -1 });
    expect(PomodoroCommand.plan("short", { running: false, mode: 1 })).toEqual({ op: "start", switchTo: -1 });
    expect(PomodoroCommand.plan("long", { running: true, mode: 0 })).toEqual({ op: "start", switchTo: 2 });
    expect(PomodoroCommand.plan("stop", { running: true, mode: 2 })).toEqual({ op: "reset", switchTo: -1 });
  });

  it("names the preview line", () => {
    expect(PomodoroCommand.previewKey("toggle", { running: true, mode: 0 })).toBe("capture.pomodoro.pause");
    expect(PomodoroCommand.previewKey("toggle", { running: false, mode: 1 })).toBe("capture.pomodoro.start-short");
    expect(PomodoroCommand.previewKey("work", { running: false, mode: 2 })).toBe("capture.pomodoro.start-work");
    expect(PomodoroCommand.previewKey("stop", { running: false, mode: 0 })).toBe("capture.pomodoro.stop");
  });
});
```

**Step 2: Run test to verify it fails**
Run: `npm test -- tests/capture-timer.test.js`
Expected: FAIL (cannot resolve `../utils/capture/timer.js`).

**Step 3: Write minimal implementation**

`utils/capture/timer.js`:
```js
.pragma library
.import "../duration.js" as Duration

// Timer capture: "/t 10m chá" starts a countdown (replacing the one set), "/t" alone
// pauses or resumes the timer that is set, "/t parar" (or "stop") resets it.
var TYPE = "timer";
// "/t" with nothing after it is a command, not an empty capture.
var ALLOW_EMPTY = true;
var STOP_WORDS = ["parar", "stop"];

function build(text) {
  const body = String(text || "").trim();
  if (!body) return { ok: true, type: TYPE, action: "timerToggle", payload: {} };
  if (STOP_WORDS.indexOf(body.toLowerCase()) >= 0) return { ok: true, type: TYPE, action: "timerStop", payload: {} };
  const d = Duration.parseDuration(body);
  if (!d.ok) return { ok: false, type: TYPE, error: d.error };
  return { ok: true, type: TYPE, action: "startTimer", payload: { seconds: d.seconds, label: d.label } };
}

// i18n key of the preview line, given the timer state { set, running }. For
// startTimer the overlay shows the clock and label and appends this key when non-empty.
function previewKey(action, timer) {
  if (action === "timerStop") return "capture.timer.stop";
  if (action === "timerToggle") return !timer.set ? "capture.error.no-timer" : (timer.running ? "capture.timer.pause" : "capture.timer.resume");
  return timer.set ? "capture.timer.replaces" : "";
}
```

`utils/capture/pomodoro.js`:
```js
.pragma library
.import "../pomodoro.js" as Pomodoro

// Pomodoro commands, reachable only through "/p": "/p" starts or pauses, "/p foco",
// "/p curta", "/p longa" switch to that phase (if different) and start it, "/p parar" resets.
var TYPE = "pomodoro";
var ALLOW_EMPTY = true;
var COMMANDS = {
  "": "toggle",
  "foco": "work",
  "focus": "work",
  "curta": "short",
  "pausa curta": "short",
  "short": "short",
  "longa": "long",
  "pausa longa": "long",
  "long": "long",
  "parar": "stop",
  "stop": "stop"
};
var MODES = { work: Pomodoro.WORK, short: Pomodoro.SHORT, long: Pomodoro.LONG };
var MODE_NAMES = ["work", "short", "long"];

function build(text) {
  const key = String(text || "").trim().toLowerCase().replace(/\s+/g, " ");
  if (!Object.prototype.hasOwnProperty.call(COMMANDS, key)) return { ok: false, type: TYPE, error: "unknown-command" };
  return { ok: true, type: TYPE, action: "pomodoro", payload: { command: COMMANDS[key] } };
}

// What Enter does, given { running, mode }: { op: "start" | "pause" | "reset", switchTo }.
// switchTo is the phase to set first, or -1 to keep the current one (a paused phase resumes).
function plan(command, state) {
  if (command === "stop") return { op: "reset", switchTo: -1 };
  if (command === "toggle") return { op: state.running ? "pause" : "start", switchTo: -1 };
  const mode = MODES[command];
  return { op: "start", switchTo: mode === state.mode ? -1 : mode };
}

// i18n key of the preview line.
function previewKey(command, state) {
  const p = plan(command, state);
  if (p.op === "reset") return "capture.pomodoro.stop";
  if (p.op === "pause") return "capture.pomodoro.pause";
  return "capture.pomodoro.start-" + MODE_NAMES[p.switchTo >= 0 ? p.switchTo : state.mode];
}
```

**Step 4: Run test to verify it passes**
Run: `npm test -- tests/capture-timer.test.js`
Expected: PASS.

**Step 5: Commit**
Run: `/git commit`

---

### Task 4: Registry: `/t`, `/p`, timer in the Tab cycle, prefix-only empty commands

**Requirement:** REQ-008, REQ-009, REQ-010
**Files:**
- Modify: `utils/capture/registry.js`
- Test: `tests/registry.test.js`

**Team:**
- Track: backend
- Implementer: backend-engineer (skills: test-driven-development)
- Reviewers: business-logic-reviewer, consequences-reviewer

**Step 1: Write the failing test**

In `tests/registry.test.js`, replace the two cycle tests and add a new block:
```js
  it("cycles types with Tab", () => {
    expect(CYCLE).toEqual(["task", "event", "reminder", "note", "link", "timer"]);
    expect(nextType("task")).toBe("event");
    expect(nextType("link")).toBe("timer");
    expect(nextType("timer")).toBe("task");
    expect(nextType("calculation")).toBe("task");
    expect(nextType("pomodoro")).toBe("task");
  });

  it("cycles backwards with prevType (Shift+Tab)", () => {
    expect(prevType("event")).toBe("task");
    expect(prevType("task")).toBe("timer");
    expect(prevType("calculation")).toBe("timer");
    expect(CYCLE.map((t) => nextType(prevType(t)))).toEqual(CYCLE);
  });
```
```js
describe("timer and pomodoro commands", () => {
  it("/t starts, toggles and stops the timer", () => {
    expect(resolve("/t 5m chá", null, NOW)).toMatchObject({ ok: true, type: "timer", action: "startTimer", payload: { seconds: 300, label: "chá" } });
    expect(resolve("/t", null, NOW)).toMatchObject({ ok: true, action: "timerToggle" });
    expect(resolve("/t parar", null, NOW)).toMatchObject({ ok: true, action: "timerStop" });
  });

  it("an empty field on the Timer tab stays empty, so a stray Enter does nothing", () => {
    expect(resolve("", "timer", NOW)).toEqual({ ok: false, type: "timer", error: "empty" });
    expect(resolve("10m", "timer", NOW)).toMatchObject({ ok: true, action: "startTimer" });
  });

  it("/p is a pomodoro command whatever type Tab forced", () => {
    expect(resolve("/p", null, NOW)).toMatchObject({ ok: true, type: "pomodoro", payload: { command: "toggle" } });
    expect(resolve("/p curta", "note", NOW)).toMatchObject({ type: "pomodoro", payload: { command: "short" } });
    expect(resolve("/p xyz", null, NOW)).toEqual({ ok: false, type: "pomodoro", error: "unknown-command" });
  });

  it("does not read /px or /tx as commands", () => {
    expect(resolve("/px", null, NOW).type).toBe("task");
    expect(resolve("/tx", null, NOW).type).toBe("task");
  });

  it("other prefixes still reject an empty body", () => {
    expect(resolve("/e", null, NOW)).toEqual({ ok: false, type: "event", error: "empty" });
  });
});
```

**Step 2: Run test to verify it fails**
Run: `npm test -- tests/registry.test.js`
Expected: FAIL (CYCLE has 5 entries; `/t 5m chá` resolves as task).

**Step 3: Write minimal implementation**

`utils/capture/registry.js`: add the imports, update the header comment, lists and `resolve`:
```js
.pragma library
.import "task.js" as Task
.import "event.js" as Event
.import "reminder.js" as Reminder
.import "note.js" as Note
.import "link.js" as Link
.import "calculation.js" as Calculation
.import "timer.js" as Timer
.import "pomodoro.js" as PomodoroCommand

// Capture type resolution. Inference order:
//   1. "=" -> calculation (always)
//   2. "/p" -> pomodoro command (always; not in the Tab cycle)
//   3. prefix "/e" event, "/l" reminder, "/n" note, "/t" timer
//   4. type forced with Tab
//   5. a lone http(s) URL -> link
//   6. task (default)
// An empty body is rejected, except after a typed prefix whose handler sets
// ALLOW_EMPTY ("/t" alone is a command; an empty field on the Timer tab is not).
// To add a type: create capture/<type>.js with TYPE and build(text, now), then
// register it in HANDLERS, CYCLE and (optionally) PREFIXES.

var CYCLE = ["task", "event", "reminder", "note", "link", "timer"];
var PREFIXES = [["/e", "event"], ["/l", "reminder"], ["/n", "note"], ["/t", "timer"]];
var HANDLERS = { task: Task, event: Event, reminder: Reminder, note: Note, link: Link, timer: Timer };

function hasPrefix(text, prefix) {
  return text === prefix || text.indexOf(prefix + " ") === 0;
}

function resolve(text, forcedType, now) {
  const trimmed = String(text || "").trim();
  if (trimmed.charAt(0) === "=") return Calculation.build(trimmed.slice(1));
  if (hasPrefix(trimmed, "/p")) return PomodoroCommand.build(trimmed.slice(2));

  let type = null;
  let body = trimmed;
  for (const [prefix, prefixType] of PREFIXES) {
    if (hasPrefix(trimmed, prefix)) {
      type = prefixType;
      body = trimmed.slice(prefix.length).trim();
      break;
    }
  }
  const prefixed = type !== null;
  if (!type) type = HANDLERS[forcedType] ? forcedType : (Link.isLink(trimmed) ? "link" : "task");
  if (!body && !(prefixed && HANDLERS[type].ALLOW_EMPTY)) return { ok: false, type: type, error: "empty" };
  return HANDLERS[type].build(body, now);
}
```
`nextType`/`prevType` stay unchanged (they already wrap types outside the cycle).

**Step 4: Run test to verify it passes**
Run: `npm test -- tests/registry.test.js tests/capture.test.js`
Expected: PASS (existing capture tests unchanged).

**Step 5: Commit**
Run: `/git commit`

---

### Task 5: i18n keys

**Requirement:** REQ-002 to REQ-011 (strings)
**Files:**
- Modify: `i18n/pt.json`, `i18n/en.json`
- Test: `tests/i18n.test.js`

**Team:**
- Track: frontend
- Implementer: frontend-engineer (skills: test-driven-development)
- Reviewers: test-reviewer

**Step 1: Write the failing test**

In `tests/i18n.test.js`, extend `DYNAMIC` (keys built at runtime):
```js
  ...["needs-duration", "invalid-duration", "unknown-command", "no-timer"].map((c) => "capture.error." + c),
  ...["timer", "pomodoro"].map((t) => "capture.type." + t),
  "capture.placeholders.timer",
  ...["pause", "resume", "stop", "replaces"].map((k) => "capture.timer." + k),
  ...["pause", "stop", "start-work", "start-short", "start-long"].map((k) => "capture.pomodoro." + k),
  "focus.mode.timer",
```

**Step 2: Run test to verify it fails**
Run: `npm test -- tests/i18n.test.js`
Expected: FAIL (`missing` lists the new keys).

**Step 3: Write minimal implementation**

`i18n/pt.json` (merge into the existing objects):
```json
"capture": {
  "keys": "Enter salva · Shift+Enter salva e continua · Tab/Shift+Tab tipo · /t timer · /p pomodoro · Esc fecha",
  "run": "Executar",
  "type": { "timer": "Timer", "pomodoro": "Pomodoro" },
  "error": {
    "needs-duration": "Timer precisa de duração (ex.: 10m, 1h30, 1:30)",
    "invalid-duration": "Duração entre 1 segundo e 24 horas",
    "unknown-command": "Comando desconhecido. Use /p, /p foco, /p curta, /p longa ou /p parar",
    "no-timer": "Nenhum timer definido. Use /t 10m"
  },
  "placeholders": { "timer": "10m chá, 1h30 ou 1:30 (precisa de duração)" },
  "timer": {
    "pause": "Pausar o timer",
    "resume": "Retomar o timer",
    "stop": "Parar e reiniciar o timer",
    "replaces": "substitui o timer atual ({clock})"
  },
  "pomodoro": {
    "pause": "Pausar o pomodoro",
    "stop": "Parar e reiniciar o pomodoro",
    "start-work": "Iniciar foco",
    "start-short": "Iniciar pausa curta",
    "start-long": "Iniciar pausa longa"
  }
},
"focus": { "mode": { "timer": "Timer" } },
"timer": {
  "placeholder": "Ex.: 5m, 1h30, 1:30 chá",
  "preset": "{n} min",
  "new": "Novo timer",
  "entry-help": "Enter inicia. Pela captura rápida: /t 10m chá",
  "toast-title": "Timer",
  "toast-done": "Tempo esgotado",
  "paused-pomodoro": "Foco pausado para o timer",
  "paused-timer": "Timer pausado para o foco"
}
```

`i18n/en.json` (same keys):
```json
"capture": {
  "keys": "Enter saves · Shift+Enter saves and stays · Tab/Shift+Tab type · /t timer · /p pomodoro · Esc closes",
  "run": "Run",
  "type": { "timer": "Timer", "pomodoro": "Pomodoro" },
  "error": {
    "needs-duration": "A timer needs a duration (e.g. 10m, 1h30, 1:30)",
    "invalid-duration": "Duration between 1 second and 24 hours",
    "unknown-command": "Unknown command. Use /p, /p focus, /p short, /p long or /p stop",
    "no-timer": "No timer set. Use /t 10m"
  },
  "placeholders": { "timer": "10m tea, 1h30 or 1:30 (needs a duration)" },
  "timer": {
    "pause": "Pause the timer",
    "resume": "Resume the timer",
    "stop": "Stop and reset the timer",
    "replaces": "replaces the current timer ({clock})"
  },
  "pomodoro": {
    "pause": "Pause the pomodoro",
    "stop": "Stop and reset the pomodoro",
    "start-work": "Start focus",
    "start-short": "Start short break",
    "start-long": "Start long break"
  }
},
"focus": { "mode": { "timer": "Timer" } },
"timer": {
  "placeholder": "E.g. 5m, 1h30, 1:30 tea",
  "preset": "{n} min",
  "new": "New timer",
  "entry-help": "Enter starts. From quick capture: /t 10m tea",
  "toast-title": "Timer",
  "toast-done": "Time's up",
  "paused-pomodoro": "Focus paused for the timer",
  "paused-timer": "Timer paused for focus"
}
```
Keep the existing `capture.keys` key (value replaced), and every other existing key.

**Step 4: Run test to verify it passes**
Run: `npm test -- tests/i18n.test.js`
Expected: PASS (both files in sync, every key defined).

**Step 5: Commit**
Run: `/git commit`

---

### Task 6: Main services: timer state, shared alarm, exclusivity, capture actions

**Requirement:** REQ-006, REQ-007, REQ-008, REQ-009
**Files:**
- Modify: `Main.qml`

**Team:**
- Track: frontend
- Implementer: frontend-engineer (skills: none)
- Reviewers: business-logic-reviewer, consequences-reviewer

**Step 1: Write the failing test**
Runtime check: `qs -c noctalia-shell ipc call plugin:daybar capture`, type `/t 5s chá`, Enter.

**Step 2: Run test to verify it fails**
Expected: FAIL. `executeCapture` has no `startTimer` branch: the overlay stays busy and nothing rings.

**Step 3: Write minimal implementation**

Imports (next to the existing ones):
```qml
import "utils/clock.js" as Clock
import "utils/capture/pomodoro.js" as PomodoroCommand
```

Shared alarm. Replace `property bool pomodoroSoundPlaying: false`, `pomodoroStopAlarm()` and the sound block of `pomodoroFinished()`:
```qml
  // Which countdown's alarm is ringing: "", "pomodoro" or "timer". One sound, one 5 s limit.
  property string alarmSource: ""
  readonly property bool pomodoroSoundPlaying: alarmSource === "pomodoro"
  readonly property bool timerSoundPlaying: alarmSource === "timer"

  function playAlarm(source) {
    if (setting("playSound") === false)
      return;
    if (alarmSource === "")
      SoundService.playSound(alarmSoundFile, { repeat: true, volume: 0.3 });
    alarmSource = source;
    alarmLimitTimer.restart();
  }

  function stopAlarm() {
    if (alarmSource === "")
      return;
    SoundService.stopSound(alarmSoundFile);
    alarmSource = "";
    alarmLimitTimer.stop();
  }
```
- `alarmLimitTimer.onTriggered: root.stopAlarm()`.
- Rename every `pomodoroStopAlarm()` call in `Main.qml` to `stopAlarm()` (`grep -n pomodoroStopAlarm Main.qml` must print nothing afterwards; no other file uses it).
- In `pomodoroFinished()`, replace the `if (setting("playSound") !== false) { ... }` block with `playAlarm("pomodoro");`.

Exclusivity in `pomodoroStart()` (right after `stopAlarm();`):
```qml
    if (timerRunning) {
      timerRunning = false;
      ToastService.showNotice(pluginApi?.tr("timer.toast-title"), pluginApi?.tr("timer.paused-timer"), "player-pause");
    }
```
The auto-start in `pomodoroFinished()` keeps setting `pomodoroRunning = true` directly (calling `pomodoroStart()` would cut the alarm at once); the timer cannot be running there, since the pomodoro was.

In `focusTask(id)`, add `focusPanel = "pomodoro";` before `requestedTab = "focus";`.

Timer section (after the pomodoro section, before `Component.onCompleted`):
```qml
  // ---------------------------------------------------------------- timer
  // One free-form countdown. Only one clock counts at a time: starting the timer
  // pauses the pomodoro and vice versa, both keeping their remaining time.

  // Seconds; 0 means no timer is set.
  property int timerTotal: 0
  property int timerRemaining: 0
  property bool timerRunning: false
  property string timerLabel: ""
  // Which view the Focus tab shows: "pomodoro" or "timer".
  property string focusPanel: "pomodoro"
  readonly property string barClock: Clock.barSource({ pomodoroRunning: pomodoroRunning, timerRunning: timerRunning, alarmSource: alarmSource })

  Timer {
    interval: 1000
    repeat: true
    running: root.timerRunning
    onTriggered: {
      root.timerRemaining -= 1;
      if (root.timerRemaining <= 0)
        root.timerFinished();
    }
  }

  function timerSet(seconds, label) {
    timerRunning = false;
    timerTotal = seconds;
    timerRemaining = seconds;
    timerLabel = label || "";
    focusPanel = "timer";
  }

  function timerStart() {
    if (timerTotal <= 0)
      return;
    stopAlarm();
    if (pomodoroRunning) {
      pomodoroRunning = false;
      ToastService.showNotice(pluginApi?.tr("timer.toast-title"), pluginApi?.tr("timer.paused-pomodoro"), "player-pause");
    }
    if (timerRemaining <= 0)
      timerRemaining = timerTotal;
    timerRunning = true;
  }

  function timerStartNew(seconds, label) {
    timerSet(seconds, label);
    timerStart();
  }

  function timerPause() {
    timerRunning = false;
    stopAlarm();
  }

  // Back to the full duration, stopped.
  function timerReset() {
    timerRunning = false;
    timerRemaining = timerTotal;
    stopAlarm();
  }

  // "New timer": back to the entry state.
  function timerClear() {
    timerRunning = false;
    timerTotal = 0;
    timerRemaining = 0;
    timerLabel = "";
    stopAlarm();
  }

  // Rings, then waits at its full duration, ready to run again.
  function timerFinished() {
    timerRunning = false;
    timerRemaining = timerTotal;
    playAlarm("timer");
    ToastService.showNotice(pluginApi?.tr("timer.toast-title"), timerLabel || pluginApi?.tr("timer.toast-done"), Clock.TIMER_ICON);
  }

  function runPomodoroCommand(command) {
    const step = PomodoroCommand.plan(command, { running: pomodoroRunning, mode: pomodoroMode });
    focusPanel = "pomodoro";
    if (step.switchTo >= 0)
      pomodoroSetMode(step.switchTo);
    if (step.op === "start")
      pomodoroStart();
    else if (step.op === "pause")
      pomodoroPause();
    else
      pomodoroReset();
  }
```

In `executeCapture(result, done)`, append these branches after `createReminder`:
```qml
    } else if (result.action === "startTimer") {
      timerStartNew(p.seconds, p.label);
      done(true, "");
    } else if (result.action === "timerToggle" || result.action === "timerStop") {
      if (timerTotal <= 0)
        return done(false, "no-timer");
      focusPanel = "timer";
      if (result.action === "timerStop")
        timerReset();
      else if (timerRunning)
        timerPause();
      else
        timerStart();
      done(true, "");
    } else if (result.action === "pomodoro") {
      runPomodoroCommand(p.command);
      done(true, "");
    }
```

**Step 4: Run test to verify it passes**
Restart the shell (Conventions). Then:
1. Capture `/t 5s chá` → after about 5 s a toast "Timer: chá" and the alarm for about 5 s.
2. Start a 1-minute focus in the Focus tab, capture `/t 1m` → toast "Foco pausado para o timer"; the Focus clock stays where it was.
3. Capture `/p` → toast "Timer pausado para o foco"; the focus resumes from its kept time.
4. Capture `/p parar` → focus reset; `/t parar` → timer back to 1:00, stopped.
No daybar errors in the log.

**Step 5: Commit**
Run: `/git commit`

---

### Task 7: ProgressRing component

**Requirement:** REQ-004, REQ-005
**Files:**
- Create: `components/ui/ProgressRing.qml`

**Team:**
- Track: frontend
- Implementer: frontend-engineer (skills: accessibility-guardrails)
- Reviewers: consequences-reviewer

**Step 1: Write the failing test**
Runtime check: in `components/FocusView.qml`, temporarily wrap the clock `NText` in `ProgressRing { progress: 0.66 }`.

**Step 2: Run test to verify it fails**
Expected: FAIL. The log shows `ProgressRing is not a type`.

**Step 3: Write minimal implementation**

`components/ui/ProgressRing.qml`:
```qml
import QtQuick
import QtQuick.Shapes
import qs.Commons

// Circular countdown ring: a faint full track and an arc for `progress` (0..1),
// drawn clockwise from 12 o'clock. Children are placed in a full-size center item.
Item {
  id: root

  property real progress: 0
  property real thickness: Math.round(6 * Style.uiScaleRatio)
  property color trackColor: Qt.alpha(Color.mOnSurface, 0.12)
  property color arcColor: Color.mPrimary
  property string accessibleName: ""
  default property alias content: center.data

  readonly property real ringRadius: Math.min(width, height) / 2 - thickness / 2
  readonly property real clamped: Math.min(1, Math.max(0, progress))

  implicitWidth: Math.round(160 * Style.uiScaleRatio)
  implicitHeight: implicitWidth

  Accessible.role: Accessible.ProgressBar
  Accessible.name: accessibleName

  // Smooths the one-second steps and the jump back to full on reset.
  Behavior on clamped {
    NumberAnimation {
      duration: 250
    }
  }

  Shape {
    anchors.fill: parent
    preferredRendererType: Shape.CurveRenderer

    ShapePath {
      strokeColor: root.trackColor
      strokeWidth: root.thickness
      fillColor: "transparent"
      capStyle: ShapePath.RoundCap

      PathAngleArc {
        centerX: root.width / 2
        centerY: root.height / 2
        radiusX: root.ringRadius
        radiusY: root.ringRadius
        startAngle: 0
        sweepAngle: 360
      }
    }

    ShapePath {
      strokeColor: root.clamped > 0 ? root.arcColor : "transparent"
      strokeWidth: root.thickness
      fillColor: "transparent"
      capStyle: ShapePath.RoundCap

      PathAngleArc {
        centerX: root.width / 2
        centerY: root.height / 2
        radiusX: root.ringRadius
        radiusY: root.ringRadius
        startAngle: -90
        sweepAngle: 360 * root.clamped
      }
    }
  }

  Item {
    id: center
    anchors.fill: parent
  }
}
```
If `Behavior on clamped` is rejected for a readonly property, move the Behavior to a plain `property real shown: clamped` and bind the sweep to `shown`.

**Step 4: Run test to verify it passes**
Restart the shell, open the Focus tab: ring with about two thirds of the arc from 12 o'clock clockwise, clock centered, smooth edges. Remove the scratch wrapper. No daybar errors.

**Step 5: Commit**
Run: `/git commit`

---

### Task 8: FocusView: Timer chip, view switch, pomodoro clock in the ring

**Requirement:** REQ-002, REQ-005
**Files:**
- Modify: `components/FocusView.qml`

**Team:**
- Track: frontend
- Implementer: frontend-engineer (skills: accessibility-guardrails)
- Reviewers: business-logic-reviewer, consequences-reviewer

**Step 1: Write the failing test**
Runtime check: open the toolbar on Focus (`qs -c noctalia-shell ipc call plugin:daybar open focus`).

**Step 2: Run test to verify it fails**
Expected: FAIL. Only three chips, no ring.

**Step 3: Write minimal implementation**

In `components/FocusView.qml`:
- Import `"../utils/clock.js" as Clock`.
- `readonly property var modes: [["work", Pomodoro.WORK], ["short", Pomodoro.SHORT], ["long", Pomodoro.LONG], ["timer", Clock.TIMER_CHIP]]`
- `readonly property bool timerView: mainInstance?.focusPanel === "timer"`
- Chip click handler:
```qml
  function selectChip(chip) {
    const action = Clock.chipAction(chip, mainInstance.focusPanel, mainInstance.pomodoroMode);
    mainInstance.focusPanel = action === "show-timer" ? "timer" : "pomodoro";
    if (action === "set-mode")
      mainInstance.pomodoroSetMode(chip);
  }
```
- In the chip `Repeater`: `selected: root.timerView ? modelData[1] === Clock.TIMER_CHIP : root.mainInstance?.pomodoroMode === modelData[1]` and `onClicked: root.selectChip(modelData[1])`.
- The gear `PillButton`: `visible: !root.timerView`.
- Restructure the first `ColumnLayout` so the header row stays at the top and everything below it (from the first spacer `Item { Layout.fillHeight: true }` to the progress-dots `RowLayout`) moves into a content area:
```qml
    Item {
      Layout.fillWidth: true
      Layout.fillHeight: true

      ColumnLayout {
        id: pomodoroPane
        anchors.fill: parent
        spacing: Math.round(8 * Style.uiScaleRatio)
        visible: !root.timerView

        // ...the existing spacer, clock, cycle text, controls, task combo, spacer and dots,
        // with the clock and cycle text replaced by the ring below
      }

      TimerPane {
        anchors.fill: parent
        visible: root.timerView
        pluginApi: root.pluginApi
        mainInstance: root.mainInstance
      }
    }
```
- Replace the clock `NText` and the cycle `NText` with:
```qml
        ProgressRing {
          Layout.alignment: Qt.AlignHCenter
          progress: Clock.progress(root.mainInstance?.pomodoroRemaining ?? 0, root.mainInstance ? Pomodoro.durationFor(root.mainInstance.pomodoroMode, root.mainInstance.pomodoroConfig) : 0)
          arcColor: root.running ? Color.mPrimary : Qt.alpha(Color.mPrimary, 0.5)
          accessibleName: root.tr("focus.mode." + root.modes[root.mainInstance?.pomodoroMode ?? 0][0]) + " " + Pomodoro.formatClock(root.mainInstance?.pomodoroRemaining ?? 0)

          ColumnLayout {
            anchors.centerIn: parent
            spacing: 0

            NText {
              Layout.alignment: Qt.AlignHCenter
              text: Pomodoro.formatClock(root.mainInstance?.pomodoroRemaining ?? 0)
              family: Settings.data.ui.fontFixed
              pointSize: Style.fontSizeXXXL * 1.6
              font.weight: Style.fontWeightBold
              color: root.running ? Color.mPrimary : Color.mOnSurface
            }

            NText {
              Layout.alignment: Qt.AlignHCenter
              text: root.tr("focus.cycle").replace("{n}", (root.mainInstance?.pomodoroCompleted ?? 0) + 1).replace("{total}", root.mainInstance?.pomodoroConfig.sessionsBeforeLong ?? 4)
              pointSize: Style.fontSizeS
              color: Qt.alpha(Color.mOnSurface, 0.56)
            }
          }
        }
```
`TimerPane` does not exist until Task 9. Until then, a `Item {}` placeholder with the same `visible` binding keeps this task loadable. Task 9 swaps it in.

**Step 4: Run test to verify it passes**
Restart the shell, open Focus:
1. Four chips: Foco, Pausa curta, Pausa longa, Timer. Ring around the clock, cycle text inside it.
2. Start the focus, click Timer, then click Foco → the clock is still counting (no reset).
3. From the Timer view, click Pausa curta → mode changes and resets, as before.
4. Tab reaches the four chips; Space selects.
5. Everything fits the panel with no clipping. If the dots clip, lower the ring `implicitWidth` (140) in this file only.
No daybar errors.

**Step 5: Commit**
Run: `/git commit`

---

### Task 9: TimerPane: entry state and ring state

**Requirement:** REQ-003, REQ-004
**Files:**
- Create: `components/TimerPane.qml`
- Modify: `components/FocusView.qml` (swap the placeholder for `TimerPane`)

**Team:**
- Track: frontend
- Implementer: frontend-engineer (skills: accessibility-guardrails)
- Reviewers: business-logic-reviewer, consequences-reviewer

**Step 1: Write the failing test**
Runtime check: open Focus, click the Timer chip.

**Step 2: Run test to verify it fails**
Expected: FAIL. The Timer view is empty (placeholder).

**Step 3: Write minimal implementation**

`components/TimerPane.qml`:
```qml
import QtQuick
import QtQuick.Layouts
import qs.Commons
import qs.Widgets
import "ui"
import "../utils/pomodoro.js" as Pomodoro
import "../utils/duration.js" as Duration
import "../utils/clock.js" as Clock

// Timer view of the Focus tab: a duration entry (field + presets) while no timer
// is set, then the ring with play/pause, reset and "new timer".
Item {
  id: root

  property var pluginApi: null
  property var mainInstance: null
  property string error: ""
  readonly property bool hasTimer: (mainInstance?.timerTotal ?? 0) > 0
  readonly property bool running: mainInstance?.timerRunning ?? false
  readonly property int remaining: mainInstance?.timerRemaining ?? 0
  readonly property var presets: [1, 5, 10, 15, 30]

  function tr(key) {
    return pluginApi ? pluginApi.tr(key) : key;
  }

  function startFromField() {
    const d = Duration.parseDuration(entry.text);
    if (!d.ok) {
      error = tr("capture.error." + d.error);
      return;
    }
    error = "";
    entry.text = "";
    mainInstance.timerStartNew(d.seconds, d.label);
  }

  onVisibleChanged: if (visible && !hasTimer) entry.forceActiveFocus()

  ColumnLayout {
    anchors.centerIn: parent
    width: Math.min(parent.width, Math.round(360 * Style.uiScaleRatio))
    spacing: Math.round(10 * Style.uiScaleRatio)
    visible: !root.hasTimer

    Field {
      id: entry
      Layout.fillWidth: true
      placeholderText: root.tr("timer.placeholder")
      maximumLength: 120
      error: root.error !== ""
      Accessible.name: root.tr("timer.placeholder")
      onTextChanged: root.error = ""
      Keys.onReturnPressed: root.startFromField()
      Keys.onEnterPressed: root.startFromField()
    }

    NText {
      Layout.fillWidth: true
      visible: root.error !== ""
      wrapMode: Text.WordWrap
      text: root.error
      pointSize: Style.fontSizeS
      color: Color.mError
    }

    RowLayout {
      Layout.alignment: Qt.AlignHCenter
      spacing: Math.round(4 * Style.uiScaleRatio)

      Repeater {
        model: root.presets

        Chip {
          required property int modelData
          text: root.tr("timer.preset").replace("{n}", modelData)
          onClicked: root.mainInstance.timerStartNew(modelData * 60, "")
        }
      }
    }

    PillButton {
      Layout.alignment: Qt.AlignHCenter
      primary: true
      implicitHeight: Math.round(34 * Style.uiScaleRatio)
      icon: "player-play"
      text: root.tr("focus.start")
      onClicked: root.startFromField()
    }

    NText {
      Layout.fillWidth: true
      horizontalAlignment: Text.AlignHCenter
      wrapMode: Text.WordWrap
      text: root.tr("timer.entry-help")
      pointSize: Style.fontSizeXS
      color: Qt.alpha(Color.mOnSurface, 0.56)
    }
  }

  ColumnLayout {
    anchors.fill: parent
    spacing: Math.round(8 * Style.uiScaleRatio)
    visible: root.hasTimer

    Item {
      Layout.fillHeight: true
    }

    ProgressRing {
      id: ring
      Layout.alignment: Qt.AlignHCenter
      progress: Clock.progress(root.remaining, root.mainInstance?.timerTotal ?? 0)
      arcColor: root.running ? Color.mPrimary : Qt.alpha(Color.mPrimary, 0.5)
      accessibleName: root.tr("focus.mode.timer") + " " + Pomodoro.formatClock(root.remaining)

      ColumnLayout {
        anchors.centerIn: parent
        spacing: 0

        NText {
          Layout.alignment: Qt.AlignHCenter
          text: Pomodoro.formatClock(root.remaining)
          family: Settings.data.ui.fontFixed
          pointSize: Style.fontSizeXXXL * 1.6
          font.weight: Style.fontWeightBold
          color: root.running ? Color.mPrimary : Color.mOnSurface
        }

        NText {
          Layout.alignment: Qt.AlignHCenter
          Layout.maximumWidth: ring.width * 0.7
          visible: text !== ""
          elide: Text.ElideRight
          text: root.mainInstance?.timerLabel ?? ""
          pointSize: Style.fontSizeS
          color: Qt.alpha(Color.mOnSurface, 0.56)
        }
      }
    }

    RowLayout {
      Layout.alignment: Qt.AlignHCenter
      Layout.topMargin: Math.round(4 * Style.uiScaleRatio)
      spacing: Math.round(8 * Style.uiScaleRatio)

      PillButton {
        icon: "refresh"
        tooltipText: root.tr("focus.reset")
        onClicked: root.mainInstance.timerReset()
      }

      PillButton {
        primary: true
        implicitHeight: Math.round(34 * Style.uiScaleRatio)
        icon: root.running ? "player-pause" : "player-play"
        text: root.running ? root.tr("focus.pause") : root.tr("focus.start")
        onClicked: root.running ? root.mainInstance.timerPause() : root.mainInstance.timerStart()
      }

      PillButton {
        icon: "plus"
        tooltipText: root.tr("timer.new")
        onClicked: {
          root.mainInstance.timerClear();
          entry.forceActiveFocus();
        }
      }
    }

    Item {
      Layout.fillHeight: true
    }
  }
}
```
In `components/FocusView.qml`, replace the Task 8 placeholder `Item` with the `TimerPane { ... }` block shown in Task 8.

**Step 4: Run test to verify it passes**
Restart the shell, open Focus, click Timer:
1. Field focused, five presets, Start, help line.
2. Type `chá` + Enter → "Timer precisa de duração (ex.: 10m, 1h30, 1:30)" under the field; typing clears it.
3. Type `5s ovo` + Enter → ring with `00:05` and "ovo", counting down; the arc shrinks each second; it rings and returns to `00:05` stopped.
4. Click 1 min → starts at once. Pause, reset (back to 01:00 stopped), "Novo timer" (entry state, field focused).
No daybar errors.

**Step 5: Commit**
Run: `/git commit`

---

### Task 10: CaptureWindow: timer and pomodoro previews, label, run button, toasts

**Requirement:** REQ-008, REQ-009, REQ-010
**Files:**
- Modify: `CaptureWindow.qml`

**Team:**
- Track: frontend
- Implementer: frontend-engineer (skills: accessibility-guardrails)
- Reviewers: business-logic-reviewer, consequences-reviewer

**Step 1: Write the failing test**
Runtime check: open capture, type `/p`, then `/t 10m chá`.

**Step 2: Run test to verify it fails**
Expected: FAIL. `/p` shows no type label and its preview is blank. `/t` shows no clock preview. Enter on either shows the toast title as a raw key (`capture.saved.pomodoro`).

**Step 3: Write minimal implementation**

In `CaptureWindow.qml`:
- Imports: `"utils/capture/timer.js" as TimerCapture`, `"utils/capture/pomodoro.js" as PomodoroCapture`, `"utils/pomodoro.js" as Pomodoro`, `"utils/clock.js" as Clock`, `"utils/tabs.js" as Tabs`.
- `readonly property var typeIcons: ({ task: "checkbox", event: "calendar-event", reminder: "bell", note: "note", link: "link", calculation: "calculator", timer: Clock.TIMER_ICON, pomodoro: Tabs.ICONS.focus })`
- `readonly property bool offCycle: Registry.CYCLE.indexOf(result.type) < 0` (calculation and pomodoro).
- `readonly property bool isCommand: result.type === "timer" || result.type === "pomodoro"`
- `cycleType(step)`: replace `if (result.type === "calculation") return;` with `if (offCycle) return;`.
- The header label `RowLayout` (currently calculation only): `visible: root.offCycle`, its `NIcon.icon: root.typeIcons[root.result.type] ?? ""`, its `NText.text: root.tr("capture.type." + root.result.type)`.
- Field placeholder: `root.tr("capture.placeholders." + (root.offCycle ? "task" : root.result.type))`.
- Save button text: `root.result.type === "calculation" ? root.tr("capture.copy") : (root.isCommand ? root.tr("capture.run") : root.tr("capture.save"))`.
- `previewText(r)`, add before the `calculation` branch:
```js
    if (r.type === "timer") {
      const timer = { set: mainInstance.timerTotal > 0, running: mainInstance.timerRunning };
      const key = TimerCapture.previewKey(r.action, timer);
      if (r.action !== "startTimer")
        return tr(key);
      const head = [Pomodoro.formatClock(p.seconds), p.label].filter(s => s).join("  ·  ");
      return key ? head + "  ·  " + tr(key).replace("{clock}", Pomodoro.formatClock(mainInstance.timerRemaining)) : head;
    }
    if (r.type === "pomodoro")
      return tr(PomodoroCapture.previewKey(p.command, { running: mainInstance.pomodoroRunning, mode: mainInstance.pomodoroMode }));
```
- Toast title helper:
```js
  // Commands have no "saved" wording; their toast is titled with the type.
  function savedTitle(r) {
    return isCommandType(r.type) ? tr("capture.type." + r.type) : tr("capture.saved." + r.type);
  }

  function isCommandType(type) {
    return type === "timer" || type === "pomodoro";
  }
```
- `submit(keepOpen)`: compute `const shown = previewText(r);` right after `const typedText = field.text;` (commands describe the state BEFORE they run), and in both success toasts use `ToastService.showNotice(savedTitle(r), shown, "check")` instead of `tr("capture.saved." + r.type)` / `previewText(r)`.

**Step 4: Run test to verify it passes**
Restart the shell, open capture:
1. `/p` → header label "Pomodoro" with the hourglass; preview "Iniciar foco"; button "Executar"; Tab does nothing.
2. Enter → toast "Pomodoro: Iniciar foco"; overlay closes; Focus counts.
3. `/t 10m chá` → preview `10:00  ·  chá`; with a timer set, the preview adds `substitui o timer atual (mm:ss)`.
4. `/t` with no timer → preview "Nenhum timer definido. Use /t 10m"; Enter shows it as an error.
5. Tab from Link reaches Timer (alarm icon, timer placeholder); empty Enter → "Nada para salvar ainda".
6. `/p agora` → "Comando desconhecido...".
No daybar errors.

**Step 5: Commit**
Run: `/git commit`

---

### Task 11: BarWidget: timer clock and middle click

**Requirement:** REQ-011
**Files:**
- Modify: `BarWidget.qml`

**Team:**
- Track: frontend
- Implementer: frontend-engineer (skills: accessibility-guardrails)
- Reviewers: consequences-reviewer

**Step 1: Write the failing test**
Runtime check: capture `/t 1m`.

**Step 2: Run test to verify it fails**
Expected: FAIL. The bar keeps the tab label because only the pomodoro clock is shown.

**Step 3: Write minimal implementation**

In `BarWidget.qml`:
- Import `"utils/clock.js" as Clock`.
- Header comment: `// Bar entry: the next tab's icon and label, or the running clock (pomodoro or timer).` and `// Left click toggles the toolbar, middle click starts/pauses the clock shown (else the pomodoro).`
- Replace `timerVisible`:
```qml
  // "timer", "pomodoro" or "" (see Main.barClock).
  readonly property string clockSource: mainInstance ? mainInstance.barClock : ""
  readonly property bool timerVisible: clockSource !== ""
```
- `NIcon.icon: root.clockSource === "timer" ? Clock.TIMER_ICON : (root.timerVisible ? Tabs.ICONS.focus : root.nextTabIcon)`
- Clock `NText.text: Pomodoro.formatClock(root.clockSource === "timer" ? (root.mainInstance?.timerRemaining ?? 0) : (root.mainInstance?.pomodoroRemaining ?? 0))`
- Middle click:
```qml
      if (mouse.button === Qt.MiddleButton && root.mainInstance) {
        const m = root.mainInstance;
        if (Clock.middleClickTarget(root.clockSource) === "timer")
          m.timerRunning ? m.timerPause() : m.timerStart();
        else
          m.pomodoroRunning ? m.pomodoroPause() : m.pomodoroStart();
      } else if (root.pluginApi) {
```

**Step 4: Run test to verify it passes**
Restart the shell:
1. `/t 1m` → bar shows the alarm icon and `00:59`, counting.
2. Middle click → timer pauses (bar returns to the tab label); middle click again → the pomodoro starts and the toast says nothing about the timer, since it was paused.
3. `/t 5s` → when it rings, the bar shows `00:05` with the alarm icon until the alarm stops.
No daybar errors.

**Step 5: Commit**
Run: `/git commit`

---

### Task 12: Docs, smoke rows and full verification

**Requirement:** REQ-012 and all (verification)
**Files:**
- Modify: `README.md`, `CLAUDE.md`, `docs/SMOKE.md`, `docs/specs/focus-timer/SPEC.md`, `docs/specs/focus-timer/STATE.md`

**Team:**
- Track: docs
- Implementer: frontend-engineer (skills: verification-before-completion)
- Reviewers: test-reviewer

**Step 1: Write the failing test**
Run: `grep -n "/t 10m" README.md docs/SMOKE.md`
Expected: no match.

**Step 2: Run test to verify it fails**
Expected: FAIL (no docs for the timer).

**Step 3: Write minimal implementation**
- `README.md`: in the capture table after the `/n` row add
  `| /t 10m chá | timer: countdown with alarm (/t pauses or resumes, /t parar resets) |` and
  `| /p, /p foco, /p curta, /p longa, /p parar | start/pause, switch phase, reset the pomodoro |`
  (inline code like the existing rows). In the Focus description, mention the Timer chip, the accepted durations (`90s`, `10m`, `1h30`, `1:30`) and that only one clock runs at a time.
- `CLAUDE.md`: in "Capture handler registry", change the inference order to: "`=`, then `/p` (pomodoro command), then prefix (`/e`, `/l`, `/n`, `/t`), then the Tab-forced type, then a lone URL as link, then task"; in "Key utils" add `duration.js` (timer duration parser) and `clock.js` (bar source, ring progress, Focus chip action).
- `docs/SMOKE.md`: add a `## Focus timer` section, rows 52 onward, one per REQ:

| # | REQ | Step | Expected |
|---|-----|------|----------|
| 52 | FT-REQ-001 | Timer field: `chá`, `25h`, `1:30` | needs-duration, invalid-duration, 01:30 |
| 53 | FT-REQ-002 | Start focus, click Timer, click Foco | Focus still counting, no reset |
| 54 | FT-REQ-003 | Click the 1 min preset | Starts at once |
| 55 | FT-REQ-004 | Pause, reset, Novo timer | Paused; back to full and stopped; entry state |
| 56 | FT-REQ-005 | Focus view | Ring around the clock, shrinking each second |
| 57 | FT-REQ-006 | `/t 5s ovo` | Toast "Timer: ovo", alarm 5 s, back to 00:05 |
| 58 | FT-REQ-007 | Focus running, `/t 1m`; then `/p` | "Foco pausado para o timer"; then "Timer pausado para o foco", focus resumes |
| 59 | FT-REQ-008 | `/t 5m` with a timer set; `/t`; `/t parar` | Preview warns it replaces; pause/resume; reset |
| 60 | FT-REQ-009 | `/p curta` with the short break paused; `/p agora` | Resumes without reset; unknown-command |
| 61 | FT-REQ-010 | Tab from Link; empty Enter | Timer type; "Nada para salvar ainda" |
| 62 | FT-REQ-011 | Timer running, middle click on the bar | Alarm icon and clock; pauses the timer |

- `SPEC.md`: Requirement Traceability statuses from what was verified (unit-tested REQ-001 Done; the rest Done only if walked in the smoke run, else Pending).
- `STATE.md`: `phase: implement-complete`, `plan_path`, a "Verified" and a "Not walked" section, as in the earlier features.

**Step 4: Run test to verify it passes**
Run:
```bash
npm test > /tmp/daybar-test.log 2>&1; echo "EXIT=$?"; grep -E "Tests +[0-9]+ passed|failed" /tmp/daybar-test.log
grep -n "/t 10m" README.md docs/SMOKE.md
grep -rn "pomodoroStopAlarm" --include=*.qml . || echo "no stale alarm calls"
```
Expected: `EXIT=0`, `Tests  N passed` with no failures, README and SMOKE matches, "no stale alarm calls". Then run the project's attribution grep guard (as in the MVP plan's Task 24) over the new files and confirm it prints nothing. Restart the shell and walk smoke rows 52 to 62.

**Step 5: Commit**
Run: `/git commit`

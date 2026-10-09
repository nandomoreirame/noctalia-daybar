# Plan: daybar MVP

> **Spec:** docs/specs/daybar-mvp/SPEC.md

**Goal:** Ship `daybar`, a Noctalia Shell plugin with a centered quick-capture overlay and a bar toolbar (Calendar, Today, Focus, Inbox).
**Architecture:** Pure logic lives in `utils/**/*.js` as QML JavaScript libraries (`.pragma library`), unit-tested with vitest through a transform that turns them into ES modules at test time. `Main.qml` owns all long-lived services (data store, agenda writes, reminders, pomodoro, capture overlay, IPC); `Panel.qml`, `BarWidget.qml`, `Settings.qml` and `components/*.qml` are thin UI. Calendar data comes from Noctalia's `CalendarService` (khal provider); writes go through `khal new` + `vdirsyncer sync` as argument arrays.
**Tech Stack:** QML (Quickshell / noctalia-shell 4.7.x), ES2018 JavaScript, vitest 2, khal, vdirsyncer, wl-clipboard.
**Total Tasks:** 24
**Estimated Complexity:** large

---

## Conventions for every task

- Repo root: `~/dev/projects/noctalia-daybar` (run every command from there).
- Run tests with `npm test -- <file>` for a single file and `npm test` for the suite. Never trust a piped exit code; read the `Tests  N passed` line.
- `utils/**/*.js` files start with `.pragma library`; cross-file references use `.import "x.js" as X` (relative to the importing file). Top-level declarations MUST start at column 0 (the test transform exports them by regex); nested code is indented.
- No `eval`, no `Function`, no shell strings: every external command is an argv array (`Process.command` / `Quickshell.execDetached`).
- Do NOT reference any previous or source project in code, comments, docs or commits. The only attribution allowed is the forked pomodoro plugin's MIT notice (`THIRD_PARTY.md`).
- QML tasks have no automated harness (spec Test Strategy). Their Step 1/2 is a runtime check: the plugin is symlinked into Noctalia (Task 20), the shell is reloaded and its log is read with `qs log -c noctalia-shell | tail -50`. Expected FAIL before implementing = the missing component/file error; PASS = no `daybar` errors in the log plus the described visual check.
- Commit after every task with `/git commit` (never raw git). Implementers (subagents / external CLIs) DO NOT run any git command; only the orchestrator commits.

## Dependency graph

```
T1 scaffold
 ├─ T2 dates ─┬─ T3 when (days) ── T4 when (times)
 │            ├─ T8 events ─┬─ T9 today (also needs T7)
 │            │             └─ T10 month
 │            ├─ T12 reminders (also needs T6)
 │            └─ T15 format
 ├─ T5 calc
 ├─ T6 store ─┬─ T7 tasks
 │            └─ T11 inbox
 ├─ T13 khal
 ├─ T14 pomodoro
 └─ T18 i18n
T16 capture handlers (T4, T5, T11) ── T17 registry
T19 CaptureWindow (T15, T17, T18)
T20 Main + install (T6, T7, T11-T14, T19)
T21 Panel + tabs (T9, T10, T14, T20)
T22 BarWidget + Settings + manifest (T21)
T23 README + SMOKE (T22)
T24 Google end-to-end + final verification (all)
```

Parallel batches: {T2, T5, T6, T13, T14, T18} after T1; then {T3, T7, T8, T11, T12, T15}; then {T4, T9, T10}; then T16 to T24 in order.

---

### Task 1: Repository scaffold and test transform

**Requirement:** infrastructure for all REQs
**Files:**
- Create: `package.json`
- Create: `vitest.config.js`
- Create: `.gitignore`
- Create: `LICENSE`
- Create: `utils/sample.js` (deleted at the end of this task)
- Create: `utils/nested/sample-dep.js` (deleted at the end of this task)
- Test: `tests/transform.test.js` (deleted at the end of this task)

**Team:**
- Track: infra
- Implementer: infra-engineer (skills: bash-linux)
- Reviewers: consequences-reviewer

**Step 1: Write the failing test**

`package.json`:
```json
{
  "name": "noctalia-daybar",
  "private": true,
  "type": "module",
  "version": "0.1.0",
  "scripts": {
    "test": "vitest run"
  },
  "devDependencies": {
    "vitest": "^2.1.0"
  }
}
```

`utils/nested/sample-dep.js`:
```js
.pragma library

function double(n) {
  return n * 2;
}
```

`utils/sample.js`:
```js
.pragma library
.import "nested/sample-dep.js" as Dep

var BASE = 10;

function quadruple(n) {
  return Dep.double(Dep.double(n));
}
```

`tests/transform.test.js`:
```js
import { describe, it, expect } from "vitest";
import { BASE, quadruple } from "../utils/sample.js";

describe("qml library transform", () => {
  it("exports top-level declarations", () => {
    expect(BASE).toBe(10);
  });

  it("resolves .import between libraries, including subfolders", () => {
    expect(quadruple(3)).toBe(12);
  });
});
```

**Step 2: Run test to verify it fails**
Run: `npm install && npm test -- tests/transform.test.js`
Expected: FAIL with a syntax error on `.pragma library` (no transform yet).

**Step 3: Write minimal implementation**

`vitest.config.js`:
```js
import { defineConfig } from "vitest/config";

// Files under utils/ are QML JavaScript libraries: they start with `.pragma library`,
// may pull other libraries with `.import "x.js" as X`, and expose bare top-level
// declarations. Node needs ES modules, so at test time only we strip the pragma,
// turn each `.import` into an ES namespace import and export every top-level
// declaration. The files on disk stay valid QML libraries.
function qmlLibraryToEsm() {
  return {
    name: "qml-library-to-esm",
    enforce: "pre",
    transform(code, id) {
      if (!/\/utils\/.+\.js$/.test(id)) return null;

      let out = code
        .replace(/^[ \t]*\.pragma[ \t].*$/gm, "")
        .replace(/^[ \t]*\.import[ \t]+"([^"]+)"[ \t]+as[ \t]+([A-Za-z_$][\w$]*)[ \t]*$/gm, (_m, path, name) => {
          const spec = path.startsWith(".") ? path : "./" + path;
          return `import * as ${name} from "${spec}";`;
        });

      const names = new Set();
      const re = /^(?:function|const|let|var)\s+([A-Za-z_$][\w$]*)/gm;
      let match;
      while ((match = re.exec(out)) !== null) names.add(match[1]);

      if (names.size > 0) out += `\nexport { ${[...names].join(", ")} };\n`;
      return { code: out, map: null };
    }
  };
}

export default defineConfig({
  plugins: [qmlLibraryToEsm()],
  test: { environment: "node" }
});
```

`.gitignore`:
```
node_modules/
*.qmlc
*.jsc
```

`LICENSE`: MIT license text with `Copyright (c) 2026 Fernando Moreira Costa`.

**Step 4: Run test to verify it passes**
Run: `npm test -- tests/transform.test.js`
Expected: PASS (2 tests). Then delete the scaffolding probes: `rm utils/sample.js utils/nested/sample-dep.js tests/transform.test.js && rmdir utils/nested`, and confirm `npm test` reports "No test files found" (exit 1 is expected here, it is the empty suite).

**Step 5: Commit**
Run: `/git commit`

---

### Task 2: Date helpers

**Requirement:** REQ-008, REQ-009, REQ-010, REQ-013, REQ-015
**Files:**
- Create: `utils/dates.js`
- Test: `tests/dates.test.js`

**Team:**
- Track: backend
- Implementer: backend-engineer (skills: test-driven-development)
- Reviewers: business-logic-reviewer, test-reviewer

**Step 1: Write the failing test**
```js
import { describe, it, expect } from "vitest";
import { pad2, isoDate, parseIsoDate, addDays, hhmm, minutesOf, addMinutes, toDate } from "../utils/dates.js";

describe("dates", () => {
  it("pads to two digits", () => {
    expect(pad2(3)).toBe("03");
    expect(pad2(12)).toBe("12");
  });

  it("formats and parses local ISO dates", () => {
    expect(isoDate(new Date(2026, 9, 9, 23, 59))).toBe("2026-10-09");
    expect(isoDate(parseIsoDate("2026-02-28"))).toBe("2026-02-28");
    expect(parseIsoDate("2026-13-01")).toBeNull();
    expect(parseIsoDate("nope")).toBeNull();
  });

  it("adds days across month and year boundaries", () => {
    expect(isoDate(addDays(new Date(2026, 9, 31), 1))).toBe("2026-11-01");
    expect(isoDate(addDays(new Date(2026, 11, 31), 1))).toBe("2027-01-01");
    expect(isoDate(addDays(new Date(2026, 9, 1), -3))).toBe("2026-09-28");
  });

  it("formats and parses HH:MM", () => {
    expect(hhmm(new Date(2026, 0, 1, 9, 5))).toBe("09:05");
    expect(minutesOf("15:30")).toBe(930);
    expect(minutesOf("9:30")).toBeNull();
  });

  it("adds minutes rolling over midnight", () => {
    expect(addMinutes("2026-10-09", "23:30", 60)).toEqual({ date: "2026-10-10", time: "00:30" });
    expect(addMinutes("2026-10-09", "15:00", 15)).toEqual({ date: "2026-10-09", time: "15:15" });
  });

  it("builds a local Date from date and time", () => {
    expect(toDate("2026-10-09", "15:30").getTime()).toBe(new Date(2026, 9, 9, 15, 30).getTime());
    expect(toDate("2026-10-09", null).getTime()).toBe(new Date(2026, 9, 9).getTime());
  });
});
```

**Step 2: Run test to verify it fails**
Run: `npm test -- tests/dates.test.js`
Expected: FAIL with "Failed to load url ../utils/dates.js" (file does not exist).

**Step 3: Write minimal implementation**
```js
.pragma library

// Local-time date helpers. Dates travel as "YYYY-MM-DD" strings and times as
// "HH:MM" strings so they serialize to JSON without timezone drift.

function pad2(n) {
  return (n < 10 ? "0" : "") + n;
}

function isoDate(d) {
  return d.getFullYear() + "-" + pad2(d.getMonth() + 1) + "-" + pad2(d.getDate());
}

function parseIsoDate(s) {
  const m = /^(\d{4})-(\d{2})-(\d{2})$/.exec(s || "");
  if (!m) return null;
  const d = new Date(Number(m[1]), Number(m[2]) - 1, Number(m[3]));
  return isoDate(d) === s ? d : null;
}

function addDays(d, n) {
  const r = new Date(d.getFullYear(), d.getMonth(), d.getDate());
  r.setDate(r.getDate() + n);
  return r;
}

function hhmm(d) {
  return pad2(d.getHours()) + ":" + pad2(d.getMinutes());
}

function minutesOf(time) {
  const m = /^(\d{2}):(\d{2})$/.exec(time || "");
  return m ? Number(m[1]) * 60 + Number(m[2]) : null;
}

function toDate(date, time) {
  const base = parseIsoDate(date);
  const minutes = time ? minutesOf(time) : 0;
  return new Date(base.getFullYear(), base.getMonth(), base.getDate(), 0, minutes);
}

function addMinutes(date, time, minutes) {
  const d = toDate(date, time);
  d.setMinutes(d.getMinutes() + minutes);
  return { date: isoDate(d), time: hhmm(d) };
}
```

**Step 4: Run test to verify it passes**
Run: `npm test -- tests/dates.test.js`
Expected: PASS (6 tests)

**Step 5: Commit**
Run: `/git commit`

---
### Task 3: pt-BR "when" parser, day expressions

**Requirement:** REQ-003, REQ-008
**Depends on:** Task 2
**Files:**
- Create: `utils/when.js`
- Test: `tests/when.test.js`

**Team:**
- Track: backend
- Implementer: backend-engineer (skills: test-driven-development)
- Reviewers: business-logic-reviewer, test-reviewer

**Step 1: Write the failing test**
```js
import { describe, it, expect } from "vitest";
import { parseWhen } from "../utils/when.js";

// Friday, 9 October 2026, 15:00 local time.
const NOW = new Date(2026, 9, 9, 15, 0);

describe("parseWhen: days", () => {
  it.each([
    ["pagar boleto amanhã", "pagar boleto", "2026-10-10"],
    ["Amanhã comprar pão", "comprar pão", "2026-10-10"],
    ["comprar pão amanha", "comprar pão", "2026-10-10"],
    ["dentista depois de amanhã", "dentista", "2026-10-11"],
    ["hoje revisar PR", "revisar PR", "2026-10-09"],
    ["pagar boleto na segunda", "pagar boleto", "2026-10-12"],
    ["reunião sexta", "reunião", "2026-10-16"],
    ["feira no sábado", "feira", "2026-10-10"],
    ["feira sabado", "feira", "2026-10-10"],
    ["terca-feira academia", "academia", "2026-10-13"],
    ["consulta 05/11", "consulta", "2026-11-05"],
    ["aniversário 01/10", "aniversário", "2027-10-01"],
    ["prova 10/10/27", "prova", "2027-10-10"]
  ])("%s", (text, title, date) => {
    const r = parseWhen(text, NOW);
    expect(r.title).toBe(title);
    expect(r.date).toBe(date);
  });

  it("ignores invalid calendar dates", () => {
    expect(parseWhen("31/02 teste", NOW)).toEqual({ title: "31/02 teste", date: null, start: null, end: null });
  });

  it("leaves text without date untouched", () => {
    expect(parseWhen("comprar 2 pães", NOW)).toEqual({ title: "comprar 2 pães", date: null, start: null, end: null });
  });

  it("does not match weekday names inside other words", () => {
    expect(parseWhen("segundas intenções", NOW).date).toBeNull();
  });
});
```

**Step 2: Run test to verify it fails**
Run: `npm test -- tests/when.test.js`
Expected: FAIL with "Failed to load url ../utils/when.js".

**Step 3: Write minimal implementation**
```js
.pragma library
.import "dates.js" as Dates

// Natural-language "when" parser for pt-BR capture text.
//   parseWhen("comprar pão amanhã 9h", now)
//   -> { title: "comprar pão", date: "2026-10-10", start: "09:00", end: null }
// JS `\b` treats accented letters as non-word characters, so tokens are delimited
// with explicit whitespace/punctuation lookarounds instead.

var END = "(?=$|[\\s,.;!?])";
var LEAD = "(^|\\s)(?:(?:na|no|para|pra|em|de|às|as|a)\\s+)?";

var RELATIVE_DAYS = [
  ["depois de amanh[ãa]", 2],
  ["amanh[ãa]", 1],
  ["hoje", 0]
];

var WEEKDAYS = [
  ["domingo", 0],
  ["segunda(?:-feira)?", 1],
  ["ter[çc]a(?:-feira)?", 2],
  ["quarta(?:-feira)?", 3],
  ["quinta(?:-feira)?", 4],
  ["sexta(?:-feira)?", 5],
  ["s[áa]bado", 6]
];

// Finds the first match of `re` in state.rest; when `accept(match)` returns a
// non-null value, removes the match (keeping its leading whitespace) and returns it.
function take(state, re, accept) {
  const m = re.exec(state.rest);
  if (!m) return null;
  const value = accept(m);
  if (value === null) return null;
  state.rest = state.rest.slice(0, m.index) + m[1] + state.rest.slice(m.index + m[0].length);
  return value;
}

function parseDay(state, today) {
  for (const [word, offset] of RELATIVE_DAYS) {
    const v = take(state, new RegExp(LEAD + word + END, "i"), () => Dates.isoDate(Dates.addDays(today, offset)));
    if (v) return v;
  }
  for (const [word, dow] of WEEKDAYS) {
    const v = take(state, new RegExp(LEAD + word + END, "i"), () => {
      const diff = (dow - today.getDay() + 7) % 7 || 7;
      return Dates.isoDate(Dates.addDays(today, diff));
    });
    if (v) return v;
  }
  return take(state, new RegExp(LEAD + "(\\d{1,2})/(\\d{1,2})(?:/(\\d{4}|\\d{2}))?" + END, "i"), (m) => {
    const day = Number(m[2]);
    const month = Number(m[3]) - 1;
    const year = m[4] ? Number(m[4].length === 2 ? "20" + m[4] : m[4]) : today.getFullYear();
    let d = new Date(year, month, day);
    if (d.getMonth() !== month || d.getDate() !== day) return null;
    if (!m[4] && d < today) d = new Date(year + 1, month, day);
    return Dates.isoDate(d);
  });
}

function parseWhen(text, now) {
  const state = { rest: String(text || "") };
  const today = new Date(now.getFullYear(), now.getMonth(), now.getDate());
  const date = parseDay(state, today);
  const title = state.rest.replace(/\s+/g, " ").trim();
  return { title: title, date: date, start: null, end: null };
}
```

**Step 4: Run test to verify it passes**
Run: `npm test -- tests/when.test.js`
Expected: PASS (16 tests)

**Step 5: Commit**
Run: `/git commit`

---

### Task 4: pt-BR "when" parser, times and ranges

**Requirement:** REQ-003, REQ-008, REQ-009, REQ-010
**Depends on:** Task 3
**Files:**
- Modify: `utils/when.js` (replace whole file with the version below)
- Modify: `tests/when.test.js` (append the `describe` block below)

**Team:**
- Track: backend
- Implementer: backend-engineer (skills: test-driven-development)
- Reviewers: business-logic-reviewer, test-reviewer

**Step 1: Write the failing test** (append to `tests/when.test.js`)
```js
describe("parseWhen: times", () => {
  it.each([
    ["comprar pão amanhã 9h", { title: "comprar pão", date: "2026-10-10", start: "09:00", end: null }],
    ["ligar pro banco 16h", { title: "ligar pro banco", date: "2026-10-09", start: "16:00", end: null }],
    ["ligar pro banco 9h", { title: "ligar pro banco", date: "2026-10-10", start: "09:00", end: null }],
    ["standup 15h", { title: "standup", date: "2026-10-10", start: "15:00", end: null }],
    ["hoje 9h revisar", { title: "revisar", date: "2026-10-09", start: "09:00", end: null }],
    ["reunião sexta 15h-16h", { title: "reunião", date: "2026-10-16", start: "15:00", end: "16:00" }],
    ["15h às 16h30 call", { title: "call", date: "2026-10-10", start: "15:00", end: "16:30" }],
    ["depois de amanhã às 10h30 dentista", { title: "dentista", date: "2026-10-11", start: "10:30", end: null }],
    ["consulta 05/11 às 14:00", { title: "consulta", date: "2026-11-05", start: "14:00", end: null }],
    ["almoço 12:00 - 13:00 amanhã", { title: "almoço", date: "2026-10-10", start: "12:00", end: "13:00" }]
  ])("%s", (text, expected) => {
    expect(parseWhen(text, NOW)).toEqual(expected);
  });

  it("rejects impossible times", () => {
    expect(parseWhen("treino 25h", NOW)).toEqual({ title: "treino 25h", date: null, start: null, end: null });
    expect(parseWhen("treino 10h75", NOW).start).toBeNull();
  });

  it("leaves a range whose end is not after its start as plain text", () => {
    expect(parseWhen("plantão 23h-1h", NOW)).toEqual({ title: "plantão 23h-1h", date: null, start: null, end: null });
  });
});
```

**Step 2: Run test to verify it fails**
Run: `npm test -- tests/when.test.js`
Expected: FAIL (times not parsed: `start` is `null`).

**Step 3: Write minimal implementation** (full file)
```js
.pragma library
.import "dates.js" as Dates

// Natural-language "when" parser for pt-BR capture text.
//   parseWhen("comprar pão amanhã 9h", now)
//   -> { title: "comprar pão", date: "2026-10-10", start: "09:00", end: null }
// JS `\b` treats accented letters as non-word characters, so tokens are delimited
// with explicit whitespace/punctuation lookarounds instead.

var END = "(?=$|[\\s,.;!?])";
var LEAD = "(^|\\s)(?:(?:na|no|para|pra|em|de|às|as|a)\\s+)?";
var TIME = "(\\d{1,2})(?:h(\\d{2})?|:(\\d{2}))";
var TIME_OPT = "(\\d{1,2})(?:h(\\d{2})?|:(\\d{2}))?";
var RANGE_SEP = "\\s*(?:-|até|às|as)\\s*";

var RELATIVE_DAYS = [
  ["depois de amanh[ãa]", 2],
  ["amanh[ãa]", 1],
  ["hoje", 0]
];

var WEEKDAYS = [
  ["domingo", 0],
  ["segunda(?:-feira)?", 1],
  ["ter[çc]a(?:-feira)?", 2],
  ["quarta(?:-feira)?", 3],
  ["quinta(?:-feira)?", 4],
  ["sexta(?:-feira)?", 5],
  ["s[áa]bado", 6]
];

// Finds the first match of `re` in state.rest; when `accept(match)` returns a
// non-null value, removes the match (keeping its leading whitespace) and returns it.
function take(state, re, accept) {
  const m = re.exec(state.rest);
  if (!m) return null;
  const value = accept(m);
  if (value === null) return null;
  state.rest = state.rest.slice(0, m.index) + m[1] + state.rest.slice(m.index + m[0].length);
  return value;
}

function toTime(hours, minA, minB) {
  const h = Number(hours);
  const m = Number(minA || minB || 0);
  if (h > 23 || m > 59) return null;
  return Dates.pad2(h) + ":" + Dates.pad2(m);
}

function parseDay(state, today) {
  for (const [word, offset] of RELATIVE_DAYS) {
    const v = take(state, new RegExp(LEAD + word + END, "i"), () => Dates.isoDate(Dates.addDays(today, offset)));
    if (v) return v;
  }
  for (const [word, dow] of WEEKDAYS) {
    const v = take(state, new RegExp(LEAD + word + END, "i"), () => {
      const diff = (dow - today.getDay() + 7) % 7 || 7;
      return Dates.isoDate(Dates.addDays(today, diff));
    });
    if (v) return v;
  }
  return take(state, new RegExp(LEAD + "(\\d{1,2})/(\\d{1,2})(?:/(\\d{4}|\\d{2}))?" + END, "i"), (m) => {
    const day = Number(m[2]);
    const month = Number(m[3]) - 1;
    const year = m[4] ? Number(m[4].length === 2 ? "20" + m[4] : m[4]) : today.getFullYear();
    let d = new Date(year, month, day);
    if (d.getMonth() !== month || d.getDate() !== day) return null;
    if (!m[4] && d < today) d = new Date(year + 1, month, day);
    return Dates.isoDate(d);
  });
}

function parseTimes(state) {
  const range = take(state, new RegExp(LEAD + TIME + RANGE_SEP + TIME_OPT + END, "i"), (m) => {
    const start = toTime(m[2], m[3], m[4]);
    const end = toTime(m[5], m[6], m[7]);
    if (!start || !end || Dates.minutesOf(end) <= Dates.minutesOf(start)) return null;
    return { start: start, end: end };
  });
  if (range) return range;
  const start = take(state, new RegExp(LEAD + TIME + END, "i"), (m) => toTime(m[2], m[3], m[4]));
  return { start: start, end: null };
}

function parseWhen(text, now) {
  const state = { rest: String(text || "") };
  const today = new Date(now.getFullYear(), now.getMonth(), now.getDate());
  let date = parseDay(state, today);
  const times = parseTimes(state);
  if (!date && times.start) {
    const nowMinutes = now.getHours() * 60 + now.getMinutes();
    const past = Dates.minutesOf(times.start) <= nowMinutes;
    date = Dates.isoDate(past ? Dates.addDays(today, 1) : today);
  }
  const title = state.rest.replace(/\s+/g, " ").trim();
  return { title: title, date: date, start: times.start, end: times.end };
}
```

Notes for the implementer:
- A time with no explicit date that is not after `now` moves to tomorrow (`"standup 15h"` at 15:00 is tomorrow); an explicit `hoje` keeps today even in the past.
- An invalid range (`"23h-1h"`) is left as text: the single-time pass does not match `23h` because `-` is not a token delimiter.

**Step 4: Run test to verify it passes**
Run: `npm test -- tests/when.test.js`
Expected: PASS (28 tests)

**Step 5: Commit**
Run: `/git commit`

---
### Task 5: Safe calculator

**Requirement:** REQ-004, REQ-005
**Depends on:** Task 1
**Files:**
- Create: `utils/calc.js`
- Test: `tests/calc.test.js`

**Team:**
- Track: backend
- Implementer: backend-engineer (skills: test-driven-development, security-guardrails)
- Reviewers: security-reviewer, business-logic-reviewer, test-reviewer

**Step 1: Write the failing test**
```js
import { describe, it, expect } from "vitest";
import { evaluate, formatNumber } from "../utils/calc.js";

describe("calc.evaluate", () => {
  it.each([
    ["2+2", 4],
    ["2+3*4", 14],
    ["(2+3)*4", 20],
    ["2^3^2", 512],
    ["-2^2", -4],
    ["-2*3", -6],
    ["--2", 2],
    ["+5", 5],
    ["2,5*2", 5],
    ["1.234,5+0,5", 1235],
    ["10/4", 2.5],
    ["200*15%", 30],
    ["(50+50)%", 1],
    [" 7 - 10 ", -3]
  ])("%s = %s", (expr, value) => {
    expect(evaluate(expr)).toEqual({ ok: true, value });
  });

  it.each([
    ["", "empty"],
    ["2/0", "division-by-zero"],
    ["2+", "syntax"],
    ["(2", "syntax"],
    ["2)", "syntax"],
    ["()", "syntax"],
    ["2 3", "syntax"],
    ["1.2.3", "syntax"],
    ["*2", "syntax"],
    ["constructor", "syntax"],
    ["process.exit()", "syntax"],
    ["9^999", "overflow"]
  ])("%s -> %s", (expr, error) => {
    expect(evaluate(expr)).toEqual({ ok: false, error });
  });
});

describe("calc.formatNumber", () => {
  it("uses comma decimals and hides float noise", () => {
    expect(formatNumber(0.1 + 0.2)).toBe("0,3");
    expect(formatNumber(2.5)).toBe("2,5");
    expect(formatNumber(4)).toBe("4");
    expect(formatNumber(-1.5)).toBe("-1,5");
  });
});
```

**Step 2: Run test to verify it fails**
Run: `npm test -- tests/calc.test.js`
Expected: FAIL with "Failed to load url" for `calc.js` (file does not exist).

**Step 3: Write minimal implementation**

`utils/calc.js`:
```js
.pragma library

// Safe arithmetic evaluator for the "=" capture. Shunting-yard over a whitelisted
// token set; never uses eval/Function. Identifiers are rejected by the tokenizer.
//   evaluate("2+3*4")   -> { ok: true, value: 14 }
//   evaluate("200*15%") -> { ok: true, value: 30 }   (postfix percent)
//   evaluate("2/0")     -> { ok: false, error: "division-by-zero" }

var OPS = {
  "+": { prec: 1, right: false, unary: false },
  "-": { prec: 1, right: false, unary: false },
  "*": { prec: 2, right: false, unary: false },
  "/": { prec: 2, right: false, unary: false },
  "neg": { prec: 3, right: true, unary: true },
  "^": { prec: 4, right: true, unary: false }
};

// "2,5" -> 2.5, "1.234,5" -> 1234.5, "2.5" -> 2.5, "1.2.3" -> null
function parseNumber(raw) {
  let norm = raw;
  if (raw.indexOf(",") >= 0) {
    if (raw.split(",").length > 2) return null;
    norm = raw.replace(/\./g, "").replace(",", ".");
  } else if (raw.split(".").length > 2) {
    return null;
  }
  if (!/^(\d+\.?\d*|\.\d+)$/.test(norm)) return null;
  return Number(norm);
}

function tokenize(src) {
  const tokens = [];
  let i = 0;
  while (i < src.length) {
    const c = src[i];
    if (c === " " || c === "\t") {
      i++;
    } else if (/[0-9.,]/.test(c)) {
      let j = i;
      while (j < src.length && /[0-9.,]/.test(src[j])) j++;
      const value = parseNumber(src.slice(i, j));
      if (value === null) return null;
      tokens.push({ t: "num", v: value });
      i = j;
    } else if ("+-*/^%()".indexOf(c) >= 0) {
      tokens.push({ t: c });
      i++;
    } else {
      return null;
    }
  }
  return tokens;
}

function toRpn(tokens) {
  const out = [];
  const stack = [];
  let prev = null;
  for (const tok of tokens) {
    if (tok.t === "num") {
      if (prev === "num" || prev === ")" || prev === "%") return null;
      out.push(tok);
      prev = "num";
    } else if (tok.t === "(") {
      if (prev === "num" || prev === ")" || prev === "%") return null;
      stack.push(tok);
      prev = "(";
    } else if (tok.t === ")") {
      while (stack.length && stack[stack.length - 1].t !== "(") out.push(stack.pop());
      if (!stack.length || prev === "(") return null;
      stack.pop();
      prev = ")";
    } else if (tok.t === "%") {
      if (prev !== "num" && prev !== ")" && prev !== "%") return null;
      out.push({ t: "pct" });
      prev = "%";
    } else {
      let op = tok.t;
      const unary = prev === null || prev === "(" || OPS.hasOwnProperty(prev);
      if (unary) {
        if (op === "+") continue;
        if (op !== "-") return null;
        op = "neg";
      }
      const o1 = OPS[op];
      while (!o1.unary && stack.length) {
        const top = stack[stack.length - 1].t;
        if (top === "(") break;
        const o2 = OPS[top];
        if (o2.prec > o1.prec || (o2.prec === o1.prec && !o1.right)) out.push(stack.pop());
        else break;
      }
      stack.push({ t: op });
      prev = op;
    }
  }
  while (stack.length) {
    const tok = stack.pop();
    if (tok.t === "(") return null;
    out.push(tok);
  }
  return out;
}

function evalRpn(rpn) {
  const st = [];
  for (const tok of rpn) {
    if (tok.t === "num") {
      st.push(tok.v);
    } else if (tok.t === "pct") {
      st.push(st.pop() / 100);
    } else if (tok.t === "neg") {
      if (st.length < 1) return { ok: false, error: "syntax" };
      st.push(-st.pop());
    } else {
      if (st.length < 2) return { ok: false, error: "syntax" };
      const b = st.pop();
      const a = st.pop();
      if (tok.t === "/" && b === 0) return { ok: false, error: "division-by-zero" };
      if (tok.t === "+") st.push(a + b);
      else if (tok.t === "-") st.push(a - b);
      else if (tok.t === "*") st.push(a * b);
      else if (tok.t === "/") st.push(a / b);
      else st.push(Math.pow(a, b));
    }
  }
  if (st.length !== 1) return { ok: false, error: "syntax" };
  if (!isFinite(st[0])) return { ok: false, error: "overflow" };
  return { ok: true, value: st[0] };
}

function evaluate(expr) {
  const src = String(expr || "").trim();
  if (!src) return { ok: false, error: "empty" };
  const tokens = tokenize(src);
  if (!tokens) return { ok: false, error: "syntax" };
  const rpn = toRpn(tokens);
  if (!rpn) return { ok: false, error: "syntax" };
  return evalRpn(rpn);
}

// pt-BR display/copy format: comma decimal, float noise rounded away.
function formatNumber(value) {
  const rounded = Math.round(value * 1e10) / 1e10;
  return String(rounded).replace(".", ",");
}
```

Security note: the tokenizer accepts only digits, `.`, `,`, `+-*/^%()` and whitespace. Any letter (`constructor`, `process`) is a syntax error. Never replace this with `eval`/`Function` (Noctalia's `AdvancedMath.js` does, which is why it is not reused).

**Step 4: Run test to verify it passes**
Run: `npm test -- tests/calc.test.js`
Expected: PASS (27 tests)

**Step 5: Commit**
Run: `/git commit`

---

### Task 6: Data store schema and parsing

**Requirement:** REQ-021, REQ-025 (data model)
**Depends on:** Task 1
**Files:**
- Create: `utils/store.js`
- Test: `tests/store.test.js`

**Team:**
- Track: backend
- Implementer: backend-engineer (skills: test-driven-development)
- Reviewers: business-logic-reviewer, test-reviewer

**Step 1: Write the failing test**
```js
import { describe, it, expect } from "vitest";
import { VERSION, createEmpty, parse, serialize, makeId } from "../utils/store.js";

describe("store", () => {
  it("creates an empty versioned store", () => {
    expect(createEmpty()).toEqual({ version: VERSION, tasks: [], eventChecks: {}, reminders: [], links: [], notes: [] });
  });

  it("treats empty or missing text as a fresh store", () => {
    expect(parse("")).toEqual({ data: createEmpty(), corrupt: false });
    expect(parse(null)).toEqual({ data: createEmpty(), corrupt: false });
  });

  it("flags invalid JSON and non-object roots as corrupt", () => {
    expect(parse("{oops").corrupt).toBe(true);
    expect(parse("[1,2]").corrupt).toBe(true);
    expect(parse("42").corrupt).toBe(true);
  });

  it("migrates an unversioned file filling defaults", () => {
    const { data, corrupt } = parse(JSON.stringify({ tasks: [{ id: "a", title: "x" }, { title: "no id" }], eventChecks: [] }));
    expect(corrupt).toBe(false);
    expect(data.version).toBe(VERSION);
    expect(data.tasks).toEqual([{
      id: "a", title: "x", date: null, time: null, done: false, doneAt: null,
      pomodoros: 0, source: "local", externalId: null, createdAt: null
    }]);
    expect(data.eventChecks).toEqual({});
    expect(data.links).toEqual([]);
  });

  it("round-trips through serialize", () => {
    const data = createEmpty();
    data.notes.push({ id: "n1", text: "olá", createdAt: "2026-10-09T15:00:00.000Z" });
    expect(parse(serialize(data)).data).toEqual(data);
  });

  it("builds ids from time and randomness", () => {
    expect(makeId(1000, 0.5)).toBe("rs-" + (500000000).toString(36));
    expect(makeId(1000, 0.1)).not.toBe(makeId(1000, 0.2));
  });
});
```

**Step 2: Run test to verify it fails**
Run: `npm test -- tests/store.test.js`
Expected: FAIL with "Failed to load url" for `store.js` (file does not exist).

**Step 3: Write minimal implementation**

`utils/store.js`:
```js
.pragma library

// data.json schema, parsing and migration. Pure: file I/O lives in Main.qml.
// Tasks carry `source`/`externalId` so a future Google Tasks sync can map them.

var VERSION = 1;

function createEmpty() {
  return { version: VERSION, tasks: [], eventChecks: {}, reminders: [], links: [], notes: [] };
}

function list(value) {
  return Array.isArray(value) ? value : [];
}

function normalizeTask(t) {
  return {
    id: String(t.id),
    title: String(t.title || ""),
    date: t.date || null,
    time: t.time || null,
    done: !!t.done,
    doneAt: t.doneAt || null,
    pomodoros: Number(t.pomodoros) || 0,
    source: t.source || "local",
    externalId: t.externalId || null,
    createdAt: t.createdAt || null
  };
}

function migrate(raw) {
  const checks = raw.eventChecks;
  return {
    version: VERSION,
    tasks: list(raw.tasks).filter((t) => t && t.id !== undefined).map(normalizeTask),
    eventChecks: checks && typeof checks === "object" && !Array.isArray(checks) ? checks : {},
    reminders: list(raw.reminders),
    links: list(raw.links),
    notes: list(raw.notes)
  };
}

// Returns { data, corrupt }. Empty/missing text is a fresh store, not corruption.
function parse(text) {
  if (text === null || text === undefined || String(text).trim() === "") {
    return { data: createEmpty(), corrupt: false };
  }
  let raw;
  try {
    raw = JSON.parse(text);
  } catch (e) {
    return { data: createEmpty(), corrupt: true };
  }
  if (!raw || typeof raw !== "object" || Array.isArray(raw)) {
    return { data: createEmpty(), corrupt: true };
  }
  return { data: migrate(raw), corrupt: false };
}

function serialize(data) {
  return JSON.stringify(data, null, 2) + "\n";
}

// Collision-resistant id: time base36 + random base36. `rand` is injectable for tests.
function makeId(nowMs, rand) {
  return nowMs.toString(36) + "-" + Math.floor(rand * 1e9).toString(36);
}
```

**Step 4: Run test to verify it passes**
Run: `npm test -- tests/store.test.js`
Expected: PASS (6 tests)

**Step 5: Commit**
Run: `/git commit`

---

### Task 7: Task and event-check operations

**Requirement:** REQ-008, REQ-014, REQ-018
**Depends on:** Task 6
**Files:**
- Create: `utils/tasks.js`
- Test: `tests/tasks.test.js`

**Team:**
- Track: backend
- Implementer: backend-engineer (skills: test-driven-development)
- Reviewers: business-logic-reviewer, test-reviewer

**Step 1: Write the failing test**
```js
import { describe, it, expect } from "vitest";
import { createEmpty } from "../utils/store.js";
import { addTask, toggleTask, deleteTask, addPomodoro, eventKey, toggleEventCheck } from "../utils/tasks.js";

const T0 = "2026-10-09T15:00:00.000Z";

describe("tasks", () => {
  it("adds a local task without mutating the input", () => {
    const empty = createEmpty();
    const data = addTask(empty, { title: "comprar pão", date: "2026-10-10", time: "09:00" }, "t1", T0);
    expect(empty.tasks).toEqual([]);
    expect(data.tasks).toEqual([{
      id: "t1", title: "comprar pão", date: "2026-10-10", time: "09:00", done: false, doneAt: null,
      pomodoros: 0, source: "local", externalId: null, createdAt: T0
    }]);
  });

  it("toggles done and doneAt", () => {
    let data = addTask(createEmpty(), { title: "x", date: "2026-10-09" }, "t1", T0);
    data = toggleTask(data, "t1", "2026-10-09T16:00:00.000Z");
    expect(data.tasks[0].done).toBe(true);
    expect(data.tasks[0].doneAt).toBe("2026-10-09T16:00:00.000Z");
    data = toggleTask(data, "t1", "2026-10-09T17:00:00.000Z");
    expect(data.tasks[0]).toMatchObject({ done: false, doneAt: null });
  });

  it("deletes a task and counts pomodoros", () => {
    let data = addTask(createEmpty(), { title: "a", date: "2026-10-09" }, "a", T0);
    data = addTask(data, { title: "b", date: "2026-10-09" }, "b", T0);
    data = addPomodoro(addPomodoro(data, "b"), "b");
    expect(data.tasks.find((t) => t.id === "b").pomodoros).toBe(2);
    expect(deleteTask(data, "a").tasks.map((t) => t.id)).toEqual(["b"]);
  });

  it("toggles event checks per occurrence", () => {
    let data = toggleEventCheck(createEmpty(), "uid-1", "2026-10-09");
    expect(data.eventChecks).toEqual({ [eventKey("uid-1", "2026-10-09")]: true });
    data = toggleEventCheck(data, "uid-1", "2026-10-16");
    data = toggleEventCheck(data, "uid-1", "2026-10-09");
    expect(data.eventChecks).toEqual({ "uid-1|2026-10-16": true });
  });
});
```

**Step 2: Run test to verify it fails**
Run: `npm test -- tests/tasks.test.js`
Expected: FAIL with "Failed to load url" for `tasks.js` (file does not exist).

**Step 3: Write minimal implementation**

`utils/tasks.js`:
```js
.pragma library

// Pure task and event-check operations. Every function returns a NEW data object;
// Main.qml persists the result.

function withTasks(data, tasks) {
  return Object.assign({}, data, { tasks: tasks });
}

function addTask(data, fields, id, nowIso) {
  const task = {
    id: id,
    title: fields.title,
    date: fields.date || null,
    time: fields.time || null,
    done: false,
    doneAt: null,
    pomodoros: 0,
    source: "local",
    externalId: null,
    createdAt: nowIso
  };
  return withTasks(data, data.tasks.concat([task]));
}

function toggleTask(data, id, nowIso) {
  return withTasks(data, data.tasks.map((t) => t.id !== id ? t : Object.assign({}, t, { done: !t.done, doneAt: t.done ? null : nowIso })));
}

function deleteTask(data, id) {
  return withTasks(data, data.tasks.filter((t) => t.id !== id));
}

function addPomodoro(data, id) {
  return withTasks(data, data.tasks.map((t) => t.id !== id ? t : Object.assign({}, t, { pomodoros: t.pomodoros + 1 })));
}

function eventKey(uid, date) {
  return uid + "|" + date;
}

function toggleEventCheck(data, uid, date) {
  const checks = Object.assign({}, data.eventChecks);
  const key = eventKey(uid, date);
  if (checks[key]) delete checks[key];
  else checks[key] = true;
  return Object.assign({}, data, { eventChecks: checks });
}
```

**Step 4: Run test to verify it passes**
Run: `npm test -- tests/tasks.test.js`
Expected: PASS (4 tests)

**Step 5: Commit**
Run: `/git commit`

---

### Task 8: Calendar event helpers

**Requirement:** REQ-013, REQ-015
**Depends on:** Task 2
**Files:**
- Create: `utils/events.js`
- Test: `tests/events.test.js`

**Team:**
- Track: backend
- Implementer: backend-engineer (skills: test-driven-development)
- Reviewers: business-logic-reviewer, test-reviewer

**Step 1: Write the failing test**
```js
import { describe, it, expect } from "vitest";
import { overlapsDay, isAllDay, timeOn, eventsOn, compareTime } from "../utils/events.js";

const at = (y, mo, d, h = 0, mi = 0) => new Date(y, mo, d, h, mi).getTime() / 1000;
const ev = (uid, start, end, summary = uid) => ({ uid, summary, start, end, calendar: "c" });

describe("events", () => {
  const meeting = ev("m", at(2026, 9, 9, 15), at(2026, 9, 9, 16));
  const allDay = ev("a", at(2026, 9, 9), at(2026, 9, 10));
  const trip = ev("t", at(2026, 9, 8, 10), at(2026, 9, 11, 10));
  const tomorrow = ev("x", at(2026, 9, 10, 9), at(2026, 9, 10, 10));
  const breakfast = ev("b", at(2026, 9, 9, 8), at(2026, 9, 9, 9));

  it("detects overlap with a day", () => {
    expect(overlapsDay(meeting, "2026-10-09")).toBe(true);
    expect(overlapsDay(allDay, "2026-10-10")).toBe(false);
    expect(overlapsDay(trip, "2026-10-10")).toBe(true);
    expect(overlapsDay(tomorrow, "2026-10-09")).toBe(false);
  });

  it("detects all-day events", () => {
    expect(isAllDay(allDay)).toBe(true);
    expect(isAllDay(meeting)).toBe(false);
  });

  it("gives a start time only on the starting day", () => {
    expect(timeOn(meeting, "2026-10-09")).toBe("15:00");
    expect(timeOn(trip, "2026-10-09")).toBeNull();
    expect(timeOn(allDay, "2026-10-09")).toBeNull();
  });

  it("lists a day's events, untimed first then by time", () => {
    const list = eventsOn([meeting, tomorrow, breakfast, allDay, trip], "2026-10-09");
    expect(list.map((e) => [e.uid, e.time])).toEqual([["t", null], ["a", null], ["b", "08:00"], ["m", "15:00"]]);
  });

  it("orders null times first", () => {
    expect(compareTime(null, "09:00")).toBe(-1);
    expect(compareTime("10:00", "09:00")).toBe(1);
  });
});
```

**Step 2: Run test to verify it fails**
Run: `npm test -- tests/events.test.js`
Expected: FAIL with "Failed to load url" for `events.js` (file does not exist).

**Step 3: Write minimal implementation**

`utils/events.js`:
```js
.pragma library
.import "dates.js" as Dates

// Helpers over Noctalia CalendarService events:
//   { uid, calendar, summary, start, end, location, description }
// where start/end are UNIX timestamps in SECONDS.

function dayBounds(iso) {
  const start = Dates.parseIsoDate(iso);
  return { start: start.getTime(), end: Dates.addDays(start, 1).getTime() };
}

function overlapsDay(ev, iso) {
  const b = dayBounds(iso);
  const s = ev.start * 1000;
  const e = Math.max(ev.end * 1000, s + 1);
  return s < b.end && e > b.start;
}

// All-day = starts at local midnight and lasts a whole number of days.
function isAllDay(ev) {
  const s = new Date(ev.start * 1000);
  const durationMs = (ev.end - ev.start) * 1000;
  return s.getHours() === 0 && s.getMinutes() === 0 && durationMs > 0 && durationMs % 86400000 === 0;
}

// "HH:MM" when the event starts on that day with a time, else null.
function timeOn(ev, iso) {
  if (isAllDay(ev)) return null;
  const s = new Date(ev.start * 1000);
  return Dates.isoDate(s) === iso ? Dates.hhmm(s) : null;
}

function compareTime(a, b) {
  if (a === b) return 0;
  if (a === null) return -1;
  if (b === null) return 1;
  return a < b ? -1 : 1;
}

// Events of one day, untimed (all-day or continuing) first, then by start time.
function eventsOn(events, iso) {
  return (events || [])
    .filter((ev) => overlapsDay(ev, iso))
    .map((ev) => ({ ev: ev, time: timeOn(ev, iso) }))
    .sort((a, b) => compareTime(a.time, b.time) || (a.ev.start - b.ev.start))
    .map((x) => Object.assign({}, x.ev, { time: x.time }));
}
```

Note: `CalendarService` events carry `start`/`end` as UNIX seconds (`Khal.qml` `parseTimestamp` divides by 1000).

**Step 4: Run test to verify it passes**
Run: `npm test -- tests/events.test.js`
Expected: PASS (5 tests)

**Step 5: Commit**
Run: `/git commit`

---

### Task 9: Today checklist builder

**Requirement:** REQ-013, REQ-014
**Depends on:** Tasks 7, 8
**Files:**
- Create: `utils/today.js`
- Test: `tests/today.test.js`

**Team:**
- Track: backend
- Implementer: backend-engineer (skills: test-driven-development)
- Reviewers: business-logic-reviewer, test-reviewer

**Step 1: Write the failing test**
```js
import { describe, it, expect } from "vitest";
import { createEmpty } from "../utils/store.js";
import { addTask, toggleTask, toggleEventCheck } from "../utils/tasks.js";
import { buildToday } from "../utils/today.js";

const NOW = new Date(2026, 9, 9, 15, 0);
const at = (h, mi = 0, d = 9) => new Date(2026, 9, d, h, mi).getTime() / 1000;
const T0 = "2026-10-09T10:00:00.000Z";

describe("buildToday", () => {
  let data = createEmpty();
  data = addTask(data, { title: "sem hora", date: "2026-10-09" }, "t-untimed", "2026-10-09T09:00:00.000Z");
  data = addTask(data, { title: "banco", date: "2026-10-09", time: "16:00" }, "t-16", T0);
  data = addTask(data, { title: "atrasada", date: "2026-10-07", time: "09:00" }, "t-late", T0);
  data = addTask(data, { title: "atrasada feita", date: "2026-10-07" }, "t-late-done", T0);
  data = toggleTask(data, "t-late-done", T0);
  data = addTask(data, { title: "amanhã", date: "2026-10-10" }, "t-tomorrow", T0);
  data = toggleEventCheck(data, "e-am", "2026-10-09");

  const events = [
    { uid: "e-pm", summary: "reunião", start: at(14), end: at(15) },
    { uid: "e-am", summary: "café", start: at(8), end: at(9) },
    { uid: "e-next", summary: "amanhã", start: at(9, 0, 10), end: at(10, 0, 10) }
  ];

  it("orders events by time, then timed tasks, then untimed tasks", () => {
    const items = buildToday(events, data, NOW);
    expect(items.map((i) => i.id)).toEqual(["e-am|2026-10-09", "e-pm|2026-10-09", "t-late", "t-16", "t-untimed"]);
  });

  it("flags overdue tasks and checked events", () => {
    const items = buildToday(events, data, NOW);
    expect(items.find((i) => i.id === "t-late").overdue).toBe(true);
    expect(items.find((i) => i.id === "t-16").overdue).toBe(false);
    expect(items.find((i) => i.uid === "e-am").done).toBe(true);
    expect(items.find((i) => i.uid === "e-pm").done).toBe(false);
  });

  it("works with no calendar events", () => {
    expect(buildToday(null, createEmpty(), NOW)).toEqual([]);
  });
});
```

**Step 2: Run test to verify it fails**
Run: `npm test -- tests/today.test.js`
Expected: FAIL with "Failed to load url" for `today.js` (file does not exist).

**Step 3: Write minimal implementation**

`utils/today.js`:
```js
.pragma library
.import "dates.js" as Dates
.import "events.js" as Events
.import "tasks.js" as Tasks

// Builds the Today checklist:
//   1. today's calendar events (untimed first, then by time)
//   2. today's tasks and overdue undone tasks, timed by time, then untimed
// Item: { kind, id, uid, title, time, done, overdue, pomodoros }

function eventItems(events, data, iso) {
  return Events.eventsOn(events, iso).map((ev) => ({
    kind: "event",
    id: Tasks.eventKey(ev.uid, iso),
    uid: ev.uid,
    title: ev.summary,
    time: ev.time,
    done: !!data.eventChecks[Tasks.eventKey(ev.uid, iso)],
    overdue: false,
    pomodoros: 0
  }));
}

function compareTasks(a, b) {
  if (a.time && b.time) return a.time < b.time ? -1 : a.time > b.time ? 1 : 0;
  if (a.time) return -1;
  if (b.time) return 1;
  return String(a.createdAt || "") < String(b.createdAt || "") ? -1 : 1;
}

function taskItems(data, iso) {
  return data.tasks
    .filter((t) => {
      const date = t.date || iso;
      return date === iso || (date < iso && !t.done);
    })
    .slice()
    .sort(compareTasks)
    .map((t) => ({
      kind: "task",
      id: t.id,
      uid: null,
      title: t.title,
      time: t.time,
      done: t.done,
      overdue: (t.date || iso) < iso,
      pomodoros: t.pomodoros
    }));
}

function buildToday(events, data, now) {
  const iso = Dates.isoDate(now);
  return eventItems(events, data, iso).concat(taskItems(data, iso));
}
```

**Step 4: Run test to verify it passes**
Run: `npm test -- tests/today.test.js`
Expected: PASS (3 tests)

**Step 5: Commit**
Run: `/git commit`

---

### Task 10: Month grid

**Requirement:** REQ-015
**Depends on:** Task 8
**Files:**
- Create: `utils/month.js`
- Test: `tests/month.test.js`

**Team:**
- Track: backend
- Implementer: backend-engineer (skills: test-driven-development)
- Reviewers: business-logic-reviewer, test-reviewer

**Step 1: Write the failing test**
```js
import { describe, it, expect } from "vitest";
import { monthGrid, shiftMonth } from "../utils/month.js";

const NOW = new Date(2026, 9, 9, 15, 0);

describe("monthGrid", () => {
  const ev = { uid: "e", start: new Date(2026, 9, 12, 10).getTime() / 1000, end: new Date(2026, 9, 12, 11).getTime() / 1000 };
  const grid = monthGrid(2026, 9, NOW, [ev]);

  it("starts on Monday and has 42 cells", () => {
    expect(grid).toHaveLength(42);
    expect(grid[0]).toMatchObject({ date: "2026-09-28", day: 28, inMonth: false });
    expect(grid[3]).toMatchObject({ date: "2026-10-01", day: 1, inMonth: true });
  });

  it("marks today and days with events", () => {
    expect(grid.find((c) => c.today).date).toBe("2026-10-09");
    expect(grid.filter((c) => c.hasEvents).map((c) => c.date)).toEqual(["2026-10-12"]);
  });

  it("handles a month starting on Monday", () => {
    expect(monthGrid(2026, 5, NOW, [])[0].date).toBe("2026-06-01");
  });
});

describe("shiftMonth", () => {
  it("wraps across years", () => {
    expect(shiftMonth(2026, 11, 1)).toEqual({ year: 2027, month: 0 });
    expect(shiftMonth(2026, 0, -1)).toEqual({ year: 2025, month: 11 });
  });
});
```

**Step 2: Run test to verify it fails**
Run: `npm test -- tests/month.test.js`
Expected: FAIL with "Failed to load url" for `month.js` (file does not exist).

**Step 3: Write minimal implementation**

`utils/month.js`:
```js
.pragma library
.import "dates.js" as Dates
.import "events.js" as Events

// Monday-first 6x7 month grid: [{ date, day, inMonth, today, hasEvents }].
function monthGrid(year, month, now, events) {
  const first = new Date(year, month, 1);
  const offset = (first.getDay() + 6) % 7;
  const start = Dates.addDays(first, -offset);
  const todayIso = Dates.isoDate(now);
  const cells = [];
  for (let i = 0; i < 42; i++) {
    const d = Dates.addDays(start, i);
    const iso = Dates.isoDate(d);
    cells.push({
      date: iso,
      day: d.getDate(),
      inMonth: d.getMonth() === month,
      today: iso === todayIso,
      hasEvents: (events || []).some((ev) => Events.overlapsDay(ev, iso))
    });
  }
  return cells;
}

// Moves a {year, month} pair by `delta` months.
function shiftMonth(year, month, delta) {
  const d = new Date(year, month + delta, 1);
  return { year: d.getFullYear(), month: d.getMonth() };
}
```

**Step 4: Run test to verify it passes**
Run: `npm test -- tests/month.test.js`
Expected: PASS (4 tests)

**Step 5: Commit**
Run: `/git commit`

---

### Task 11: Inbox operations and clipboard prefill

**Requirement:** REQ-002, REQ-011, REQ-020
**Depends on:** Task 6
**Files:**
- Create: `utils/inbox.js`
- Test: `tests/inbox.test.js`

**Team:**
- Track: backend
- Implementer: backend-engineer (skills: test-driven-development, security-guardrails)
- Reviewers: security-reviewer, business-logic-reviewer, test-reviewer

**Step 1: Write the failing test**
```js
import { describe, it, expect } from "vitest";
import { createEmpty } from "../utils/store.js";
import { isHttpUrl, hasLink, addLink, archiveLink, addNote, deleteNote, prefillFromClipboard } from "../utils/inbox.js";

const T0 = "2026-10-09T15:00:00.000Z";

describe("inbox", () => {
  it.each([
    ["https://example.com", true],
    ["http://example.com/a?b=c#d", true],
    ["  https://example.com/x  ", true],
    ["ftp://example.com", false],
    ["https://", false],
    ["veja https://example.com", false],
    ["javascript:alert(1)", false],
    ["", false]
  ])("isHttpUrl(%j) = %s", (text, expected) => {
    expect(isHttpUrl(text)).toBe(expected);
  });

  it("adds links once and archives them", () => {
    let data = addLink(createEmpty(), " https://a.dev ", "l1", T0);
    data = addLink(data, "https://a.dev", "l2", T0);
    expect(data.links).toEqual([{ id: "l1", url: "https://a.dev", archived: false, createdAt: T0 }]);
    expect(hasLink(data, "https://a.dev")).toBe(true);
    expect(archiveLink(data, "l1").links[0].archived).toBe(true);
  });

  it("adds and deletes notes", () => {
    const data = addNote(createEmpty(), "  ideia  ", "n1", T0);
    expect(data.notes).toEqual([{ id: "n1", text: "ideia", createdAt: T0 }]);
    expect(deleteNote(data, "n1").notes).toEqual([]);
  });

  it("prefills only new http(s) URLs", () => {
    const data = addLink(createEmpty(), "https://old.dev", "l1", T0);
    expect(prefillFromClipboard("https://new.dev\n", data)).toBe("https://new.dev");
    expect(prefillFromClipboard("https://old.dev", data)).toBe("");
    expect(prefillFromClipboard("texto qualquer", data)).toBe("");
    expect(prefillFromClipboard(null, data)).toBe("");
  });
});
```

**Step 2: Run test to verify it fails**
Run: `npm test -- tests/inbox.test.js`
Expected: FAIL with "Failed to load url" for `inbox.js` (file does not exist).

**Step 3: Write minimal implementation**

`utils/inbox.js`:
```js
.pragma library

// Inbox (links and notes) operations plus clipboard prefill. Pure; returns new data.

function isHttpUrl(text) {
  const s = String(text || "").trim();
  return /^https?:\/\/[^\s/$.?#][^\s]*$/i.test(s);
}

function hasLink(data, url) {
  return data.links.some((l) => l.url === url);
}

function addLink(data, url, id, nowIso) {
  const clean = String(url).trim();
  if (hasLink(data, clean)) return data;
  const link = { id: id, url: clean, archived: false, createdAt: nowIso };
  return Object.assign({}, data, { links: data.links.concat([link]) });
}

function archiveLink(data, id) {
  return Object.assign({}, data, { links: data.links.map((l) => l.id !== id ? l : Object.assign({}, l, { archived: true })) });
}

function addNote(data, text, id, nowIso) {
  const note = { id: id, text: String(text).trim(), createdAt: nowIso };
  return Object.assign({}, data, { notes: data.notes.concat([note]) });
}

function deleteNote(data, id) {
  return Object.assign({}, data, { notes: data.notes.filter((n) => n.id !== id) });
}

// Clipboard text to prefill the capture field with: a new http(s) URL, else "".
function prefillFromClipboard(clip, data) {
  const s = String(clip || "").trim();
  return isHttpUrl(s) && !hasLink(data, s) ? s : "";
}
```

Security note: `isHttpUrl` is also the guard before `xdg-open` (Task 20), so `javascript:`/`file:` URLs can never be opened.

**Step 4: Run test to verify it passes**
Run: `npm test -- tests/inbox.test.js`
Expected: PASS (11 tests)

**Step 5: Commit**
Run: `/git commit`

---

### Task 12: Local reminder schedule

**Requirement:** REQ-010
**Depends on:** Tasks 2, 6
**Files:**
- Create: `utils/reminders.js`
- Test: `tests/reminders.test.js`

**Team:**
- Track: backend
- Implementer: backend-engineer (skills: test-driven-development)
- Reviewers: business-logic-reviewer, test-reviewer

**Step 1: Write the failing test**
```js
import { describe, it, expect } from "vitest";
import { createEmpty } from "../utils/store.js";
import { addReminder, dueReminders, markFired } from "../utils/reminders.js";

describe("reminders", () => {
  let data = createEmpty();
  data = addReminder(data, { title: "early", date: "2026-10-09", time: "14:00" }, "r1");
  data = addReminder(data, { title: "now", date: "2026-10-09", time: "14:55" }, "r2");
  data = addReminder(data, { title: "later", date: "2026-10-09", time: "16:00" }, "r3");

  it("splits due reminders into fire and expire", () => {
    const due = dueReminders(data, new Date(2026, 9, 9, 15, 0));
    expect(due.fire.map((r) => r.id)).toEqual(["r2"]);
    expect(due.expire.map((r) => r.id)).toEqual(["r1"]);
  });

  it("does not return fired reminders again", () => {
    const fired = markFired(data, ["r1", "r2"]);
    expect(dueReminders(fired, new Date(2026, 9, 9, 15, 0))).toEqual({ fire: [], expire: [] });
    expect(fired.reminders.find((r) => r.id === "r3").fired).toBe(false);
  });
});
```

**Step 2: Run test to verify it fails**
Run: `npm test -- tests/reminders.test.js`
Expected: FAIL with "Failed to load url" for `reminders.js` (file does not exist).

**Step 3: Write minimal implementation**

`utils/reminders.js`:
```js
.pragma library
.import "dates.js" as Dates

// Local reminder schedule. A reminder that became due while the shell was down
// fires only if it is at most GRACE_MINUTES late; older ones expire silently
// (the Google event alarm already covered them).

var GRACE_MINUTES = 10;

function addReminder(data, fields, id) {
  const reminder = { id: id, title: fields.title, date: fields.date, time: fields.time, fired: false };
  return Object.assign({}, data, { reminders: data.reminders.concat([reminder]) });
}

// Returns { fire: [reminder], expire: [reminder] } for reminders not fired yet.
function dueReminders(data, now) {
  const fire = [];
  const expire = [];
  const graceMs = GRACE_MINUTES * 60000;
  for (const r of data.reminders) {
    if (r.fired) continue;
    const at = Dates.toDate(r.date, r.time).getTime();
    if (at > now.getTime()) continue;
    if (now.getTime() - at <= graceMs) fire.push(r);
    else expire.push(r);
  }
  return { fire: fire, expire: expire };
}

function markFired(data, ids) {
  return Object.assign({}, data, {
    reminders: data.reminders.map((r) => ids.indexOf(r.id) < 0 ? r : Object.assign({}, r, { fired: true }))
  });
}
```

**Step 4: Run test to verify it passes**
Run: `npm test -- tests/reminders.test.js`
Expected: PASS (2 tests)

**Step 5: Commit**
Run: `/git commit`

---

### Task 13: khal / vdirsyncer argv builders

**Requirement:** REQ-009, REQ-010, REQ-012, REQ-023
**Depends on:** Task 1
**Files:**
- Create: `utils/khal.js`
- Test: `tests/khal.test.js`

**Team:**
- Track: backend
- Implementer: backend-engineer (skills: test-driven-development, security-guardrails)
- Reviewers: security-reviewer, business-logic-reviewer, test-reviewer

**Step 1: Write the failing test**
```js
import { describe, it, expect } from "vitest";
import { newEventArgs, syncArgs, printCalendarsArgs, parseCalendars, sanitizeSummary } from "../utils/khal.js";

describe("khal argv", () => {
  it("builds khal new for an event", () => {
    expect(newEventArgs({ calendar: "pessoal", date: "2026-10-16", start: "15:00", endDate: "2026-10-16", endTime: "16:00", title: "reunião", alarm: false }))
      .toEqual(["khal", "new", "-a", "pessoal", "--", "2026-10-16 15:00", "2026-10-16 16:00", "reunião"]);
  });

  it("adds an alarm at start for reminders and omits an empty calendar", () => {
    expect(newEventArgs({ calendar: "", date: "2026-10-10", start: "09:00", endDate: "2026-10-10", endTime: "09:15", title: "pagar boleto", alarm: true }))
      .toEqual(["khal", "new", "--alarms", "0m", "--", "2026-10-10 09:00", "2026-10-10 09:15", "pagar boleto"]);
  });

  it("keeps hostile titles as a single inert argument", () => {
    const args = newEventArgs({ calendar: "c", date: "2026-10-10", start: "09:00", endDate: "2026-10-10", endTime: "10:00", title: "--help; rm -rf ~ :: desc\nx", alarm: false });
    expect(args[args.length - 1]).toBe("--help; rm -rf ~ : desc x");
    expect(args.indexOf("--")).toBeLessThan(args.length - 1);
  });

  it("sanitizes summaries", () => {
    expect(sanitizeSummary("  a::b \r\n c ")).toBe("a:b c");
  });

  it("builds sync and calendar listing commands", () => {
    expect(syncArgs()).toEqual(["vdirsyncer", "sync"]);
    expect(printCalendarsArgs()).toEqual(["khal", "printcalendars"]);
    expect(parseCalendars("pessoal\ntrabalho\n\n")).toEqual(["pessoal", "trabalho"]);
  });
});
```

**Step 2: Run test to verify it fails**
Run: `npm test -- tests/khal.test.js`
Expected: FAIL with "Failed to load url" for `khal.js` (file does not exist).

**Step 3: Write minimal implementation**

`utils/khal.js`:
```js
.pragma library

// argv builders for khal/vdirsyncer. Always an array (Process.command), never a
// shell string, so user text cannot inject commands or options.
// Requires khal's [locale] formats set to ISO (see README):
//   dateformat = %Y-%m-%d, timeformat = %H:%M, datetimeformat = %Y-%m-%d %H:%M

function sanitizeSummary(title) {
  return String(title || "").replace(/::/g, ":").replace(/\s+/g, " ").trim();
}

// ev: { calendar, date, start, endDate, endTime, title, alarm }
function newEventArgs(ev) {
  const args = ["khal", "new"];
  if (ev.calendar) args.push("-a", ev.calendar);
  if (ev.alarm) args.push("--alarms", "0m");
  args.push("--", ev.date + " " + ev.start, ev.endDate + " " + ev.endTime, sanitizeSummary(ev.title));
  return args;
}

function syncArgs() {
  return ["vdirsyncer", "sync"];
}

function printCalendarsArgs() {
  return ["khal", "printcalendars"];
}

// `khal printcalendars` prints one calendar name per line.
function parseCalendars(stdout) {
  return String(stdout || "").split("\n").map((l) => l.trim()).filter((l) => l.length > 0);
}
```

Security note: user text only ever reaches khal as the last argv element after `--`; nothing goes through a shell.

**Step 4: Run test to verify it passes**
Run: `npm test -- tests/khal.test.js`
Expected: PASS (5 tests)

**Step 5: Commit**
Run: `/git commit`

---

### Task 14: Pomodoro phase machine (fork)

**Requirement:** REQ-017, REQ-018, REQ-019
**Depends on:** Task 1
**Files:**
- Create: `utils/pomodoro.js`
- Test: `tests/pomodoro.test.js`

**Team:**
- Track: backend
- Implementer: backend-engineer (skills: test-driven-development)
- Reviewers: business-logic-reviewer, test-reviewer

**Step 1: Write the failing test**
```js
import { describe, it, expect } from "vitest";
import { WORK, SHORT, LONG, durationFor, nextPhase, finish, formatClock } from "../utils/pomodoro.js";

const cfg = { work: 1500, short: 300, long: 900, sessionsBeforeLong: 2, autoStartBreaks: true, autoStartWork: false };

describe("pomodoro", () => {
  it("maps modes to durations", () => {
    expect([WORK, SHORT, LONG].map((m) => durationFor(m, cfg))).toEqual([1500, 300, 900]);
  });

  it("cycles work -> short -> work -> long -> work", () => {
    let s = { mode: WORK, completed: 0 };
    const seen = [];
    for (let i = 0; i < 5; i++) {
      s = nextPhase(s, cfg);
      seen.push([s.mode, s.completed]);
    }
    expect(seen).toEqual([[SHORT, 0], [WORK, 1], [LONG, 1], [WORK, 0], [SHORT, 0]]);
  });

  it("reports work completion and auto-start per phase", () => {
    expect(finish({ mode: WORK, completed: 0 }, cfg)).toEqual({ next: { mode: SHORT, completed: 0 }, remaining: 300, workCompleted: true, autoStart: true });
    expect(finish({ mode: SHORT, completed: 0 }, cfg)).toMatchObject({ workCompleted: false, autoStart: false, remaining: 1500 });
  });

  it("formats the clock", () => {
    expect(formatClock(1500)).toBe("25:00");
    expect(formatClock(59)).toBe("00:59");
    expect(formatClock(3725)).toBe("1:02:05");
    expect(formatClock(-3)).toBe("00:00");
  });
});
```

**Step 2: Run test to verify it fails**
Run: `npm test -- tests/pomodoro.test.js`
Expected: FAIL with "Failed to load url" for `pomodoro.js` (file does not exist).

**Step 3: Write minimal implementation**

`utils/pomodoro.js`:
```js
.pragma library

// Pomodoro phase machine, extracted from the MIT "pomodoro" Noctalia plugin
// (see THIRD_PARTY.md). Same semantics as the original:
//   - a finished WORK goes to LONG when completed+1 >= sessionsBeforeLong, else SHORT
//   - a finished SHORT increments `completed`; a finished LONG resets it to 0

var WORK = 0;
var SHORT = 1;
var LONG = 2;

// cfg: { work, short, long } in seconds, sessionsBeforeLong, autoStartBreaks, autoStartWork
function durationFor(mode, cfg) {
  if (mode === SHORT) return cfg.short;
  if (mode === LONG) return cfg.long;
  return cfg.work;
}

function nextPhase(state, cfg) {
  if (state.mode === WORK) {
    return { mode: state.completed + 1 >= cfg.sessionsBeforeLong ? LONG : SHORT, completed: state.completed };
  }
  return { mode: WORK, completed: state.mode === LONG ? 0 : state.completed + 1 };
}

// What happens when a phase timer reaches zero.
function finish(state, cfg) {
  const next = nextPhase(state, cfg);
  return {
    next: next,
    remaining: durationFor(next.mode, cfg),
    workCompleted: state.mode === WORK,
    autoStart: state.mode === WORK ? !!cfg.autoStartBreaks : !!cfg.autoStartWork
  };
}

// "mm:ss", or "h:mm:ss" past one hour.
function formatClock(seconds) {
  const s = Math.max(0, Math.floor(seconds));
  const h = Math.floor(s / 3600);
  const m = Math.floor((s % 3600) / 60);
  const pad = (n) => (n < 10 ? "0" : "") + n;
  return (h > 0 ? h + ":" + pad(m) : pad(m)) + ":" + pad(s % 60);
}
```

Semantics are copied from the MIT pomodoro plugin's `pomodoroAdvanceToNextPhase` (`~/.config/noctalia/plugins/pomodoro/Main.qml`). Keep them identical.

**Step 4: Run test to verify it passes**
Run: `npm test -- tests/pomodoro.test.js`
Expected: PASS (4 tests)

**Step 5: Commit**
Run: `/git commit`

---

### Task 15: Capture preview formatter

**Requirement:** REQ-003
**Depends on:** Task 2
**Files:**
- Create: `utils/format.js`
- Test: `tests/format.test.js`

**Team:**
- Track: backend
- Implementer: backend-engineer (skills: test-driven-development)
- Reviewers: business-logic-reviewer, test-reviewer

**Step 1: Write the failing test**
```js
import { describe, it, expect } from "vitest";
import { describeWhen } from "../utils/format.js";

const NOW = new Date(2026, 9, 9, 15, 0);

describe("describeWhen", () => {
  it("names today and tomorrow, else dd/mm", () => {
    expect(describeWhen("2026-10-09", null, null, NOW)).toEqual({ day: "today", time: "" });
    expect(describeWhen("2026-10-10", "09:00", null, NOW)).toEqual({ day: "tomorrow", time: "09:00" });
    expect(describeWhen("2026-10-16", "15:00", "16:00", NOW)).toEqual({ day: "16/10", time: "15:00–16:00" });
  });

  it("handles a missing date", () => {
    expect(describeWhen(null, null, null, NOW)).toEqual({ day: "", time: "" });
  });
});
```

**Step 2: Run test to verify it fails**
Run: `npm test -- tests/format.test.js`
Expected: FAIL with "Failed to load url" for `format.js` (file does not exist).

**Step 3: Write minimal implementation**

`utils/format.js`:
```js
.pragma library
.import "dates.js" as Dates

// Language-neutral pieces for the capture preview; QML translates `day` keys.
// describeWhen("2026-10-10", "15:00", "16:00", now) -> { day: "tomorrow", time: "15:00–16:00" }
// `day` is "today" | "tomorrow" | "dd/mm" | "" (no date).

function describeWhen(date, start, end, now) {
  let day = "";
  if (date) {
    const today = Dates.isoDate(now);
    const tomorrow = Dates.isoDate(Dates.addDays(now, 1));
    if (date === today) day = "today";
    else if (date === tomorrow) day = "tomorrow";
    else day = date.slice(8, 10) + "/" + date.slice(5, 7);
  }
  const time = start ? (end ? start + "–" + end : start) : "";
  return { day: day, time: time };
}
```

**Step 4: Run test to verify it passes**
Run: `npm test -- tests/format.test.js`
Expected: PASS (2 tests)

**Step 5: Commit**
Run: `/git commit`

---

### Task 16: Capture handlers

**Requirement:** REQ-003, REQ-004, REQ-008, REQ-009, REQ-010, REQ-011
**Depends on:** Tasks 4, 5, 11
**Files:**
- Create: `utils/capture/task.js`
- Create: `utils/capture/event.js`
- Create: `utils/capture/reminder.js`
- Create: `utils/capture/note.js`
- Create: `utils/capture/link.js`
- Create: `utils/capture/calculation.js`
- Test: `tests/capture.test.js`

**Team:**
- Track: backend
- Implementer: backend-engineer (skills: test-driven-development)
- Reviewers: business-logic-reviewer, test-reviewer

**Step 1: Write the failing test**
```js
import { describe, it, expect } from "vitest";
import * as Task from "../utils/capture/task.js";
import * as Event from "../utils/capture/event.js";
import * as Reminder from "../utils/capture/reminder.js";
import * as Note from "../utils/capture/note.js";
import * as Link from "../utils/capture/link.js";
import * as Calculation from "../utils/capture/calculation.js";

const NOW = new Date(2026, 9, 9, 15, 0);

describe("capture handlers", () => {
  it("task: defaults to today and keeps the parsed time", () => {
    expect(Task.build("comprar pão", NOW)).toEqual({ ok: true, type: "task", action: "addTask", payload: { title: "comprar pão", date: "2026-10-09", time: null } });
    expect(Task.build("comprar pão amanhã 9h", NOW).payload).toEqual({ title: "comprar pão", date: "2026-10-10", time: "09:00" });
    expect(Task.build("amanhã", NOW)).toEqual({ ok: false, type: "task", error: "empty-title" });
  });

  it("event: needs date and time, defaults to 1h", () => {
    expect(Event.build("reunião sexta 15h", NOW).payload).toEqual({ title: "reunião", date: "2026-10-16", start: "15:00", endDate: "2026-10-16", endTime: "16:00", alarm: false });
    expect(Event.build("reunião sexta 15h-15h30", NOW).payload.endTime).toBe("15:30");
    expect(Event.build("reunião sexta", NOW)).toEqual({ ok: false, type: "event", error: "needs-date-time" });
  });

  it("reminder: needs a time, lasts 15 minutes with alarm", () => {
    expect(Reminder.build("pagar boleto amanhã 10h", NOW)).toEqual({
      ok: true, type: "reminder", action: "createReminder",
      payload: { title: "pagar boleto", date: "2026-10-10", start: "10:00", endDate: "2026-10-10", endTime: "10:15", alarm: true }
    });
    expect(Reminder.build("pagar boleto amanhã", NOW)).toEqual({ ok: false, type: "reminder", error: "needs-time" });
  });

  it("note and link", () => {
    expect(Note.build("  ideia: app  ")).toEqual({ ok: true, type: "note", action: "addNote", payload: { text: "ideia: app" } });
    expect(Note.build("   ").ok).toBe(false);
    expect(Link.build("https://a.dev").payload).toEqual({ url: "https://a.dev" });
    expect(Link.build("a.dev")).toEqual({ ok: false, type: "link", error: "invalid-url" });
  });

  it("calculation", () => {
    expect(Calculation.build("2+2")).toEqual({ ok: true, type: "calculation", action: "copy", payload: { value: 4, display: "4" } });
    expect(Calculation.build("2/0")).toEqual({ ok: false, type: "calculation", error: "division-by-zero" });
  });
});
```

**Step 2: Run test to verify it fails**
Run: `npm test -- tests/capture.test.js`
Expected: FAIL with "Failed to load url" for `task.js` (file does not exist).

**Step 3: Write minimal implementation**

`utils/capture/task.js`:
```js
.pragma library
.import "../when.js" as When
.import "../dates.js" as Dates

// Task capture: local task; no date means today.
var TYPE = "task";

function build(text, now) {
  const w = When.parseWhen(text, now);
  if (!w.title) return { ok: false, type: TYPE, error: "empty-title" };
  return { ok: true, type: TYPE, action: "addTask", payload: { title: w.title, date: w.date || Dates.isoDate(now), time: w.start } };
}
```

`utils/capture/event.js`:
```js
.pragma library
.import "../when.js" as When
.import "../dates.js" as Dates

// Event capture: Google Calendar event via khal; 1h when no end is given.
var TYPE = "event";
var DEFAULT_MINUTES = 60;

function build(text, now) {
  const w = When.parseWhen(text, now);
  if (!w.title) return { ok: false, type: TYPE, error: "empty-title" };
  if (!w.date || !w.start) return { ok: false, type: TYPE, error: "needs-date-time" };
  const end = w.end ? { date: w.date, time: w.end } : Dates.addMinutes(w.date, w.start, DEFAULT_MINUTES);
  return {
    ok: true,
    type: TYPE,
    action: "createEvent",
    payload: { title: w.title, date: w.date, start: w.start, endDate: end.date, endTime: end.time, alarm: false }
  };
}
```

`utils/capture/reminder.js`:
```js
.pragma library
.import "../when.js" as When
.import "../dates.js" as Dates

// Reminder capture: 15-minute event with an alarm at start, plus a local toast.
var TYPE = "reminder";
var DURATION_MINUTES = 15;

function build(text, now) {
  const w = When.parseWhen(text, now);
  if (!w.title) return { ok: false, type: TYPE, error: "empty-title" };
  if (!w.start) return { ok: false, type: TYPE, error: "needs-time" };
  const end = Dates.addMinutes(w.date, w.start, DURATION_MINUTES);
  return {
    ok: true,
    type: TYPE,
    action: "createReminder",
    payload: { title: w.title, date: w.date, start: w.start, endDate: end.date, endTime: end.time, alarm: true }
  };
}
```

`utils/capture/note.js`:
```js
.pragma library

// Note capture: free text kept verbatim in the Inbox.
var TYPE = "note";

function build(text) {
  const body = String(text || "").trim();
  if (!body) return { ok: false, type: TYPE, error: "empty" };
  return { ok: true, type: TYPE, action: "addNote", payload: { text: body } };
}
```

`utils/capture/link.js`:
```js
.pragma library
.import "../inbox.js" as Inbox

// Link capture: read-later http(s) URL in the Inbox.
var TYPE = "link";

function isLink(text) {
  return Inbox.isHttpUrl(text);
}

function build(text) {
  const url = String(text || "").trim();
  if (!Inbox.isHttpUrl(url)) return { ok: false, type: TYPE, error: "invalid-url" };
  return { ok: true, type: TYPE, action: "addLink", payload: { url: url } };
}
```

`utils/capture/calculation.js`:
```js
.pragma library
.import "../calc.js" as Calc

// Calculation capture ("=2+2"): Enter copies the result and keeps the overlay open.
var TYPE = "calculation";

function build(expr) {
  const r = Calc.evaluate(expr);
  if (!r.ok) return { ok: false, type: TYPE, error: r.error };
  return { ok: true, type: TYPE, action: "copy", payload: { value: r.value, display: Calc.formatNumber(r.value) } };
}
```

**Step 4: Run test to verify it passes**
Run: `npm test -- tests/capture.test.js`
Expected: PASS (5 tests)

**Step 5: Commit**
Run: `/git commit`

---

### Task 17: Capture type registry

**Requirement:** REQ-006
**Depends on:** Task 16
**Files:**
- Create: `utils/capture/registry.js`
- Test: `tests/registry.test.js`

**Team:**
- Track: backend
- Implementer: backend-engineer (skills: test-driven-development)
- Reviewers: business-logic-reviewer, test-reviewer

**Step 1: Write the failing test**
```js
import { describe, it, expect } from "vitest";
import { resolve, nextType, CYCLE } from "../utils/capture/registry.js";

const NOW = new Date(2026, 9, 9, 15, 0);

describe("capture registry", () => {
  it("defaults to task", () => {
    expect(resolve("comprar pão", null, NOW).type).toBe("task");
  });

  it("always treats '=' as calculation, even with a forced type", () => {
    expect(resolve("=2+2", "note", NOW).payload.display).toBe("4");
  });

  it("applies prefixes and strips them", () => {
    expect(resolve("/e reunião sexta 15h", null, NOW).payload.title).toBe("reunião");
    expect(resolve("/l pagar boleto 18h", null, NOW).type).toBe("reminder");
    expect(resolve("/n uma ideia", null, NOW).payload).toEqual({ text: "uma ideia" });
    expect(resolve("/ex", null, NOW).type).toBe("task");
  });

  it("detects a lone URL as link", () => {
    expect(resolve("https://a.dev/x", null, NOW).type).toBe("link");
    expect(resolve("ler https://a.dev/x", null, NOW).type).toBe("task");
  });

  it("honors the Tab-forced type", () => {
    expect(resolve("https://a.dev", "note", NOW)).toMatchObject({ type: "note", payload: { text: "https://a.dev" } });
    expect(resolve("pagar boleto 18h", "reminder", NOW).type).toBe("reminder");
  });

  it("rejects empty input with the resolved type", () => {
    expect(resolve("  ", null, NOW)).toEqual({ ok: false, type: "task", error: "empty" });
    expect(resolve("/n", null, NOW)).toEqual({ ok: false, type: "note", error: "empty" });
  });

  it("cycles types with Tab", () => {
    expect(CYCLE).toEqual(["task", "event", "reminder", "note", "link"]);
    expect(nextType("task")).toBe("event");
    expect(nextType("link")).toBe("task");
    expect(nextType("calculation")).toBe("task");
  });
});
```

**Step 2: Run test to verify it fails**
Run: `npm test -- tests/registry.test.js`
Expected: FAIL with "Failed to load url" for `registry.js` (file does not exist).

**Step 3: Write minimal implementation**

`utils/capture/registry.js`:
```js
.pragma library
.import "task.js" as Task
.import "event.js" as Event
.import "reminder.js" as Reminder
.import "note.js" as Note
.import "link.js" as Link
.import "calculation.js" as Calculation

// Capture type resolution. Inference order:
//   1. "=" -> calculation (always)
//   2. prefix "/e" event, "/l" reminder, "/n" note
//   3. type forced with Tab
//   4. a lone http(s) URL -> link
//   5. task (default)
// To add a type: create capture/<type>.js with TYPE and build(text, now), then
// register it in HANDLERS, CYCLE and (optionally) PREFIXES.

var CYCLE = ["task", "event", "reminder", "note", "link"];
var PREFIXES = [["/e", "event"], ["/l", "reminder"], ["/n", "note"]];
var HANDLERS = { task: Task, event: Event, reminder: Reminder, note: Note, link: Link };

function resolve(text, forcedType, now) {
  const trimmed = String(text || "").trim();
  if (trimmed.charAt(0) === "=") return Calculation.build(trimmed.slice(1));

  let type = null;
  let body = trimmed;
  for (const [prefix, prefixType] of PREFIXES) {
    if (trimmed === prefix || trimmed.indexOf(prefix + " ") === 0) {
      type = prefixType;
      body = trimmed.slice(prefix.length).trim();
      break;
    }
  }
  if (!type) type = HANDLERS[forcedType] ? forcedType : (Link.isLink(trimmed) ? "link" : "task");
  if (!body) return { ok: false, type: type, error: "empty" };
  return HANDLERS[type].build(body, now);
}

function nextType(current) {
  const i = CYCLE.indexOf(current);
  return CYCLE[(i + 1) % CYCLE.length];
}
```

Extension point: a new capture type is one `utils/capture/<type>.js` (with `TYPE` and `build(text, now)`), one entry in `HANDLERS`/`CYCLE` (and optionally `PREFIXES`), its i18n keys and a test.

**Step 4: Run test to verify it passes**
Run: `npm test -- tests/registry.test.js`
Expected: PASS (7 tests)

**Step 5: Commit**
Run: `/git commit`

---

### Task 18: Translations (pt, en) and i18n coverage test

**Requirement:** REQ-003, REQ-007, REQ-016, REQ-023 (all user-facing strings)
**Depends on:** Task 1
**Files:**
- Create: `i18n/en.json`
- Create: `i18n/pt.json`
- Test: `tests/i18n.test.js`

**Team:**
- Track: docs
- Implementer: rpi-implementer
- Reviewers: self-review

**Step 1: Write the failing test**
The test keeps `en` and `pt` in lockstep and fails whenever a QML file calls `tr("some.key")` that is missing. Keys built at runtime are listed in `DYNAMIC`. From Task 19 on, this is the red test for every new string.
```js
import { describe, it, expect } from "vitest";
import { readFileSync, readdirSync, existsSync } from "node:fs";

const root = new URL("../", import.meta.url);
const load = (lang) => JSON.parse(readFileSync(new URL(`i18n/${lang}.json`, root), "utf8"));
const en = load("en");
const pt = load("pt");

function flatten(obj, prefix = "") {
  return Object.entries(obj).flatMap(([k, v]) => (v && typeof v === "object" ? flatten(v, prefix + k + ".") : [prefix + k]));
}

function qmlFiles() {
  const top = readdirSync(root).filter((f) => f.endsWith(".qml"));
  const dir = new URL("components/", root);
  const nested = existsSync(dir) ? readdirSync(dir).filter((f) => f.endsWith(".qml")).map((f) => "components/" + f) : [];
  return top.concat(nested);
}

// Keys built at runtime ("capture.error." + code) are listed here explicitly.
const DYNAMIC = [
  ...["empty", "empty-title", "needs-date-time", "needs-time", "invalid-url", "syntax", "division-by-zero", "overflow", "calendar-not-configured", "khal-failed"].map((c) => "capture.error." + c),
  ...["task", "event", "reminder", "note", "link", "calculation"].map((t) => "capture.type." + t),
  ...["task", "event", "reminder", "note", "link"].map((t) => "capture.saved." + t),
  ...["today", "tomorrow"].map((d) => "when." + d),
  ...["calendar", "today", "focus", "inbox"].map((t) => "tabs." + t),
  ...["work", "short", "long"].map((m) => "focus.mode." + m),
  "focus.toast-work-done",
  "focus.toast-break-done"
];

describe("i18n", () => {
  it("has the same keys in en and pt", () => {
    expect(flatten(pt).sort()).toEqual(flatten(en).sort());
  });

  it("defines every key used by the QML files", () => {
    const keys = new Set(flatten(en));
    const used = new Set(DYNAMIC);
    for (const file of qmlFiles()) {
      const src = readFileSync(new URL(file, root), "utf8");
      for (const m of src.matchAll(/\btr\("([a-z0-9.-]+)"/g)) if (!m[1].endsWith(".")) used.add(m[1]);
    }
    const missing = [...used].filter((k) => !keys.has(k));
    expect(missing).toEqual([]);
  });
});
```

**Step 2: Run test to verify it fails**
Run: `npm test -- tests/i18n.test.js`
Expected: FAIL with `ENOENT` for `i18n/en.json`.

**Step 3: Write minimal implementation**

`i18n/en.json`:
```json
{
  "tabs": {
    "calendar": "Calendar",
    "today": "Today",
    "focus": "Focus",
    "inbox": "Inbox",
    "capture": "Capture"
  },
  "capture": {
    "placeholder": "Buy bread tomorrow 9am, =2+2, /e meeting fri 3pm...",
    "hint": "Type to capture. Tab changes the type.",
    "keys": "Enter save · Shift+Enter save and keep open · Tab type · Esc close",
    "copied": "Result copied to clipboard",
    "type": {
      "task": "Task",
      "event": "Event",
      "reminder": "Reminder",
      "note": "Note",
      "link": "Link",
      "calculation": "Calculation"
    },
    "saved": {
      "task": "Task saved",
      "event": "Event created",
      "reminder": "Reminder set",
      "note": "Note saved",
      "link": "Link saved"
    },
    "error": {
      "empty": "Nothing to save yet",
      "empty-title": "Add a description",
      "needs-date-time": "Events need a date and time (e.g. fri 3pm)",
      "needs-time": "Reminders need a time (e.g. 6pm)",
      "invalid-url": "Not a valid http(s) link",
      "syntax": "Incomplete or invalid expression",
      "division-by-zero": "Division by zero",
      "overflow": "Result too large",
      "calendar-not-configured": "Calendar not configured (see README)",
      "khal-failed": "khal could not create the event"
    }
  },
  "when": {
    "today": "today",
    "tomorrow": "tomorrow"
  },
  "today": {
    "title": "Today",
    "empty": "Nothing for today. Add something below.",
    "overdue": "overdue",
    "delete": "Delete task",
    "add-placeholder": "New task for today. E.g.: call the bank 3pm"
  },
  "calendar": {
    "not-configured": "Calendar not configured. Install khal and vdirsyncer (see README).",
    "nothing": "Nothing scheduled.",
    "all-day": "all day",
    "previous": "Previous month",
    "next": "Next month",
    "weekdays": "M T W T F S S"
  },
  "focus": {
    "mode": {
      "work": "Focus",
      "short": "Short break",
      "long": "Long break"
    },
    "no-task": "No task",
    "cycle": "Cycle {n} of {total}",
    "start": "Start",
    "pause": "Pause",
    "reset": "Reset",
    "skip": "Skip",
    "toast-title": "Focus",
    "toast-work-done": "Focus session complete. Time for a break.",
    "toast-break-done": "Break over. Ready to focus?"
  },
  "inbox": {
    "links": "Links",
    "notes": "Notes",
    "no-links": "No saved links.",
    "no-notes": "No notes.",
    "open": "Open",
    "archive": "Archive",
    "copy": "Copy",
    "delete": "Delete"
  },
  "reminder": {
    "title": "Reminder"
  },
  "agenda": {
    "sync-failed-title": "Calendar sync failed",
    "sync-failed-body": "The event was saved locally and will sync on the next run."
  },
  "store": {
    "corrupt-title": "Daybar data was unreadable",
    "corrupt-body": "The old file was kept as data.json.bak and a new one was started."
  },
  "settings": {
    "focus": "Focus",
    "work-duration": "Focus duration",
    "short-break": "Short break",
    "long-break": "Long break",
    "sessions": "Sessions before long break",
    "auto-start-breaks": "Start breaks automatically",
    "auto-start-work": "Start focus automatically",
    "play-sound": "Play alarm sound",
    "focus-command": "Focus mode command",
    "focus-command-help": "Executable called with on/off when a focus session starts or stops. Leave empty to disable.",
    "general": "General",
    "default-calendar": "Default calendar",
    "default-calendar-none": "khal default",
    "initial-tab": "Initial tab"
  }
}
```

`i18n/pt.json`:
```json
{
  "tabs": {
    "calendar": "Calendário",
    "today": "Hoje",
    "focus": "Foco",
    "inbox": "Caixa",
    "capture": "Capturar"
  },
  "capture": {
    "placeholder": "Comprar pão amanhã 9h, =2+2, /e reunião sexta 15h...",
    "hint": "Digite para capturar. Tab troca o tipo.",
    "keys": "Enter salva · Shift+Enter salva e continua · Tab tipo · Esc fecha",
    "copied": "Resultado copiado",
    "type": {
      "task": "Tarefa",
      "event": "Evento",
      "reminder": "Lembrete",
      "note": "Nota",
      "link": "Link",
      "calculation": "Cálculo"
    },
    "saved": {
      "task": "Tarefa salva",
      "event": "Evento criado",
      "reminder": "Lembrete agendado",
      "note": "Nota salva",
      "link": "Link salvo"
    },
    "error": {
      "empty": "Nada para salvar ainda",
      "empty-title": "Adicione uma descrição",
      "needs-date-time": "Evento precisa de data e hora (ex.: sexta 15h)",
      "needs-time": "Lembrete precisa de hora (ex.: 18h)",
      "invalid-url": "Link http(s) inválido",
      "syntax": "Expressão incompleta ou inválida",
      "division-by-zero": "Divisão por zero",
      "overflow": "Resultado grande demais",
      "calendar-not-configured": "Agenda não configurada (veja o README)",
      "khal-failed": "O khal não conseguiu criar o evento"
    }
  },
  "when": {
    "today": "hoje",
    "tomorrow": "amanhã"
  },
  "today": {
    "title": "Hoje",
    "empty": "Nada para hoje. Adicione abaixo.",
    "overdue": "atrasada",
    "delete": "Excluir tarefa",
    "add-placeholder": "Nova tarefa para hoje. Ex.: ligar pro banco 15h"
  },
  "calendar": {
    "not-configured": "Agenda não configurada. Instale o khal e o vdirsyncer (veja o README).",
    "nothing": "Nada marcado para hoje.",
    "all-day": "dia todo",
    "previous": "Mês anterior",
    "next": "Próximo mês",
    "weekdays": "S T Q Q S S D"
  },
  "focus": {
    "mode": {
      "work": "Foco",
      "short": "Pausa curta",
      "long": "Pausa longa"
    },
    "no-task": "Sem tarefa",
    "cycle": "Ciclo {n} de {total}",
    "start": "Iniciar",
    "pause": "Pausar",
    "reset": "Reiniciar",
    "skip": "Pular",
    "toast-title": "Foco",
    "toast-work-done": "Sessão de foco concluída. Hora da pausa.",
    "toast-break-done": "Pausa encerrada. Pronto para focar?"
  },
  "inbox": {
    "links": "Links",
    "notes": "Notas",
    "no-links": "Nenhum link salvo.",
    "no-notes": "Nenhuma nota.",
    "open": "Abrir",
    "archive": "Arquivar",
    "copy": "Copiar",
    "delete": "Excluir"
  },
  "reminder": {
    "title": "Lembrete"
  },
  "agenda": {
    "sync-failed-title": "Falha ao sincronizar a agenda",
    "sync-failed-body": "O evento ficou salvo localmente e sobe na próxima sincronização."
  },
  "store": {
    "corrupt-title": "Dados do Daybar ilegíveis",
    "corrupt-body": "O arquivo antigo foi guardado como data.json.bak e um novo foi iniciado."
  },
  "settings": {
    "focus": "Foco",
    "work-duration": "Duração do foco",
    "short-break": "Pausa curta",
    "long-break": "Pausa longa",
    "sessions": "Sessões até a pausa longa",
    "auto-start-breaks": "Iniciar pausas automaticamente",
    "auto-start-work": "Iniciar foco automaticamente",
    "play-sound": "Tocar alarme",
    "focus-command": "Comando de modo foco",
    "focus-command-help": "Executável chamado com on/off quando um foco começa ou para. Deixe vazio para desligar.",
    "general": "Geral",
    "default-calendar": "Agenda padrão",
    "default-calendar-none": "Padrão do khal",
    "initial-tab": "Aba inicial"
  }
}
```

**Step 4: Run test to verify it passes**
Run: `npm test -- tests/i18n.test.js`
Expected: PASS (2 tests)

**Step 5: Commit**
Run: `/git commit`

---

### Task 19: Capture overlay window

**Requirement:** REQ-001, REQ-002, REQ-003, REQ-005, REQ-006, REQ-007
**Depends on:** Tasks 15, 17, 18
**Files:**
- Create: `CaptureWindow.qml`
- Test: `tests/i18n.test.js` (existing, covers the keys this file uses)

**Team:**
- Track: frontend
- Implementer: frontend-engineer (skills: accessibility-guardrails)
- Reviewers: type-safety-reviewer, test-reviewer, accessibility-guardrails

**Step 1: Write the failing test**
QML has no unit harness (spec Test Strategy). The red/green signal for this task is the i18n coverage test (any new `tr()` key) plus the runtime check below. Before writing the file, confirm the coverage test is the guard: temporarily add `NText { text: tr("capture.not-a-key") }` to an empty `CaptureWindow.qml`.

**Step 2: Run test to verify it fails**
Run: `npm test -- tests/i18n.test.js`
Expected: FAIL listing `capture.not-a-key` as missing. Remove that probe.

**Step 3: Write minimal implementation**
Behavior contract: layer-shell overlay with exclusive keyboard focus; a second `openOn` only refocuses; `prefill` fills only an untouched field; Tab cycles type (no-op for calculations); Enter/Shift+Enter/Esc per REQ-007; a click on the backdrop closes; errors keep the text.
```qml
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import qs.Commons
import qs.Widgets
import qs.Services.UI
import "utils/capture/registry.js" as Registry
import "utils/format.js" as Format

// Centered quick-capture overlay. Enter saves and closes, Shift+Enter saves and
// stays, Tab cycles the type, Esc or a click outside closes without saving.
PanelWindow {
  id: root

  property var pluginApi: null
  property var mainInstance: null
  property string forcedType: ""
  property var result: ({ ok: false, type: "task", error: "empty" })
  property bool busy: false
  property string feedback: ""
  property bool feedbackIsError: false

  anchors.top: true
  anchors.left: true
  anchors.right: true
  anchors.bottom: true
  visible: false
  color: "transparent"

  WlrLayershell.layer: WlrLayer.Overlay
  WlrLayershell.keyboardFocus: visible ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
  WlrLayershell.namespace: "noctalia-daybar-capture"
  WlrLayershell.exclusionMode: ExclusionMode.Ignore

  function tr(key) {
    return pluginApi ? pluginApi.tr(key) : key;
  }

  function openOn(targetScreen) {
    if (visible) {
      field.forceActiveFocus();
      return;
    }
    screen = targetScreen;
    forcedType = "";
    busy = false;
    field.text = "";
    visible = true;
    refresh();
    field.forceActiveFocus();
  }

  // Clipboard URL arrives asynchronously; only fill an untouched field.
  function prefill(url) {
    if (!visible || field.text !== "")
      return;
    field.text = url;
    field.selectAll();
    refresh();
  }

  function close() {
    visible = false;
    field.text = "";
  }

  function refresh() {
    result = Registry.resolve(field.text, forcedType || null, new Date());
    feedback = "";
  }

  function cycleType() {
    if (result.type === "calculation")
      return;
    forcedType = Registry.nextType(result.type);
    refresh();
  }

  function previewText(r) {
    if (!r.ok)
      return field.text.trim() === "" ? tr("capture.hint") : tr("capture.error." + r.error);
    const p = r.payload;
    if (r.type === "calculation")
      return "= " + p.display;
    if (r.type === "note")
      return p.text;
    if (r.type === "link")
      return p.url;
    const w = Format.describeWhen(p.date, p.time || p.start, r.type === "task" ? null : p.endTime, new Date());
    const day = w.day === "today" || w.day === "tomorrow" ? tr("when." + w.day) : w.day;
    return [p.title, [day, w.time].filter(s => s).join(" ")].filter(s => s).join("  ·  ");
  }

  function submit(keepOpen) {
    if (busy)
      return;
    refresh();
    const r = result;
    if (!r.ok) {
      feedback = tr("capture.error." + r.error);
      feedbackIsError = true;
      return;
    }
    if (r.action === "copy") {
      mainInstance.copyText(r.payload.display);
      feedback = tr("capture.copied");
      feedbackIsError = false;
      return;
    }
    busy = true;
    mainInstance.executeCapture(r, function (ok, error) {
      busy = false;
      if (!ok) {
        feedback = tr("capture.error." + error);
        feedbackIsError = true;
        return;
      }
      ToastService.showNotice(tr("capture.saved." + r.type), previewText(r), "check");
      if (keepOpen) {
        field.text = "";
        forcedType = "";
        refresh();
        field.forceActiveFocus();
      } else {
        root.close();
      }
    });
  }

  // Dimmed backdrop; clicking outside the card closes.
  MouseArea {
    anchors.fill: parent
    onClicked: root.close()

    Rectangle {
      anchors.fill: parent
      color: Qt.alpha(Color.mShadow, 0.35)
    }
  }

  Rectangle {
    id: card
    width: Math.min(640 * Style.uiScaleRatio, parent.width - Style.marginL * 2)
    height: column.implicitHeight + Style.marginL * 2
    anchors.horizontalCenter: parent.horizontalCenter
    y: parent.height * 0.28
    radius: Style.radiusL
    color: Color.mSurface
    border.color: Color.mOutline
    border.width: Style.borderS

    // Swallow clicks so they do not reach the backdrop.
    MouseArea {
      anchors.fill: parent
    }

    ColumnLayout {
      id: column
      anchors.fill: parent
      anchors.margins: Style.marginL
      spacing: Style.marginM

      RowLayout {
        spacing: Style.marginS

        Repeater {
          model: Registry.CYCLE

          Rectangle {
            required property string modelData
            readonly property bool active: root.result.type === modelData
            implicitWidth: chipLabel.implicitWidth + Style.marginM * 2
            implicitHeight: chipLabel.implicitHeight + Style.marginXS * 2
            radius: Style.radiusM
            color: active ? Color.mPrimary : "transparent"

            NText {
              id: chipLabel
              anchors.centerIn: parent
              text: root.tr("capture.type." + modelData)
              pointSize: Style.fontSizeS
              color: parent.active ? Color.mOnPrimary : Color.mOnSurfaceVariant
            }

            MouseArea {
              anchors.fill: parent
              cursorShape: Qt.PointingHandCursor
              onClicked: {
                root.forcedType = modelData;
                root.refresh();
                field.forceActiveFocus();
              }
            }
          }
        }

        Item {
          Layout.fillWidth: true
        }

        NText {
          visible: root.result.type === "calculation"
          text: root.tr("capture.type.calculation")
          pointSize: Style.fontSizeS
          color: Color.mPrimary
        }
      }

      TextField {
        id: field
        Layout.fillWidth: true
        font.pointSize: Style.fontSizeL * Style.uiScaleRatio
        color: Color.mOnSurface
        placeholderText: root.tr("capture.placeholder")
        placeholderTextColor: Color.mOnSurfaceVariant
        selectByMouse: true
        maximumLength: 500
        enabled: !root.busy
        background: Rectangle {
          radius: Style.radiusM
          color: Color.mSurfaceVariant
          border.color: field.activeFocus ? Color.mPrimary : Color.mOutline
          border.width: Style.borderS
        }
        leftPadding: Style.marginM
        rightPadding: Style.marginM
        topPadding: Style.marginS
        bottomPadding: Style.marginS

        onTextChanged: root.refresh()

        Keys.onTabPressed: event => {
          root.cycleType();
          event.accepted = true;
        }
        Keys.onBacktabPressed: event => {
          event.accepted = true;
        }
        Keys.onEscapePressed: event => {
          root.close();
          event.accepted = true;
        }
        Keys.onReturnPressed: event => {
          root.submit(event.modifiers & Qt.ShiftModifier);
          event.accepted = true;
        }
        Keys.onEnterPressed: event => {
          root.submit(event.modifiers & Qt.ShiftModifier);
          event.accepted = true;
        }
      }

      NText {
        Layout.fillWidth: true
        elide: Text.ElideRight
        text: root.feedback !== "" ? root.feedback : root.previewText(root.result)
        pointSize: Style.fontSizeS
        color: root.feedback !== "" && root.feedbackIsError ? Color.mError : Color.mOnSurfaceVariant
      }

      NText {
        Layout.fillWidth: true
        text: root.tr("capture.keys")
        pointSize: Style.fontSizeXS
        color: Color.mOnSurfaceVariant
        opacity: 0.7
      }
    }
  }
}
```

Lint for syntax (imports from `qs.*` resolve only inside the shell, so ignore import/unqualified warnings):
Run: `/usr/lib/qt6/bin/qmllint CaptureWindow.qml 2>&1 | grep -i "syntax\|expected token" || echo "no syntax errors"`

**Step 4: Run test to verify it passes**
Run: `npm test -- tests/i18n.test.js`
Expected: PASS (2 tests). Runtime check happens in Task 20 (the window is owned by `Main.qml`).

**Step 5: Commit**
Run: `/git commit`

---

### Task 20: Main services, install and first runtime check

**Requirement:** REQ-001, REQ-002, REQ-007..REQ-012, REQ-017, REQ-018, REQ-021, REQ-022
**Depends on:** Tasks 6, 7, 11, 12, 13, 14, 19
**Files:**
- Create: `Main.qml`
- Create: `manifest.json` (entry point `main` only for now)
- Create: `alarm.mp3` (copied from the MIT pomodoro plugin)
- Create: `THIRD_PARTY.md`
- Test: `tests/i18n.test.js` (existing)

**Team:**
- Track: backend
- Implementer: backend-engineer (skills: security-guardrails)
- Reviewers: security-reviewer, business-logic-reviewer, consequences-reviewer

**Step 1: Write the failing test**
QML has no unit harness (spec Test Strategy). The red/green signal for this task is the i18n coverage test (any new `tr()` key) plus the runtime check below. Install the plugin first so the runtime check fails before `Main.qml` exists:
```bash
ln -s ~/dev/projects/noctalia-daybar ~/.config/noctalia/plugins/daybar
cp ~/.config/noctalia/plugins/pomodoro/alarm.mp3 alarm.mp3
```
`manifest.json` (temporary: only `main`):
```json
{
  "id": "daybar",
  "name": "Daybar",
  "version": "0.1.0",
  "minNoctaliaVersion": "4.0.0",
  "author": "Fernando Moreira Costa",
  "license": "MIT",
  "repository": "https://github.com/nandomoreirame/noctalia-daybar",
  "description": "Quick capture, today's checklist, Google Calendar and focus timer in one bar toolbar.",
  "tags": [
    "Bar",
    "Productivity"
  ],
  "entryPoints": {
    "main": "Main.qml"
  },
  "dependencies": {
    "plugins": []
  },
  "metadata": {
    "defaultSettings": {
      "workDuration": 25,
      "shortBreakDuration": 5,
      "longBreakDuration": 15,
      "sessionsBeforeLongBreak": 4,
      "autoStartBreaks": false,
      "autoStartWork": false,
      "playSound": true,
      "focusModeCommand": "",
      "defaultCalendar": "",
      "initialTab": "today"
    }
  }
}
```
Enable **Daybar** in Noctalia Settings > Plugins.

**Step 2: Run test to verify it fails**
Run: `qs -c noctalia-shell ipc call plugin:daybar capture; qs log -c noctalia-shell | grep -i daybar | tail -5`
Expected: FAIL (no `plugin:daybar` IPC target / `Main.qml` not found in the log).

**Step 3: Write minimal implementation**
`Main.qml`. Notes: the data dir is created with `mkdir -p` before the `FileView` gets its path; writes are debounced (400 ms) and atomic; khal writes run one at a time through `writeQueue`; `vdirsyncer sync` runs after each successful write and always reloads `CalendarService`; the focus-mode command runs as `[cmd, "on"|"off"]` only when set.
```qml
import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Services.UI
import qs.Services.System
import qs.Services.Location
import "utils/store.js" as Store
import "utils/tasks.js" as Tasks
import "utils/inbox.js" as Inbox
import "utils/reminders.js" as Reminders
import "utils/khal.js" as Khal
import "utils/pomodoro.js" as Pomodoro

// Long-lived services: data store, IPC, agenda writes, reminders, pomodoro and
// the capture overlay. UI files only read state from here and call these functions.
Item {
  id: root

  property var pluginApi: null
  readonly property var settings: pluginApi?.pluginSettings ?? ({})
  readonly property var defaults: pluginApi?.manifest?.metadata?.defaultSettings ?? ({})

  function setting(key) {
    const v = settings[key];
    return v === undefined ? defaults[key] : v;
  }

  // ---------------------------------------------------------------- store

  readonly property string dataDir: (Quickshell.env("XDG_DATA_HOME") || (Quickshell.env("HOME") + "/.local/share")) + "/noctalia-daybar"
  readonly property string dataPath: dataDir + "/data.json"
  property var data: Store.createEmpty()
  property bool loaded: false
  property string requestedTab: ""

  function nowIso() {
    return new Date().toISOString();
  }

  function newId() {
    return Store.makeId(Date.now(), Math.random());
  }

  function commit(next) {
    root.data = next;
    saveTimer.restart();
  }

  function applyLoaded(text) {
    const r = Store.parse(text);
    root.data = r.data;
    root.loaded = true;
    if (r.corrupt) {
      Quickshell.execDetached(["mv", "-f", root.dataPath, root.dataPath + ".bak"]);
      ToastService.showWarning(pluginApi?.tr("store.corrupt-title"), pluginApi?.tr("store.corrupt-body"));
      saveTimer.restart();
    }
  }

  Process {
    id: mkdirProcess
    command: ["mkdir", "-p", root.dataDir]
    running: true
    onExited: dataFile.path = root.dataPath
  }

  FileView {
    id: dataFile
    path: ""
    atomicWrites: true
    printErrors: false
    onLoaded: root.applyLoaded(dataFile.text())
    onLoadFailed: function (error) {
      root.applyLoaded("");
    }
  }

  Timer {
    id: saveTimer
    interval: 400
    repeat: false
    onTriggered: {
      if (root.loaded)
        dataFile.setText(Store.serialize(root.data));
    }
  }

  // Tasks / events / inbox (called by the UI)
  function addTask(fields) { commit(Tasks.addTask(data, fields, newId(), nowIso())); }
  function toggleTask(id) { commit(Tasks.toggleTask(data, id, nowIso())); }
  function deleteTask(id) { commit(Tasks.deleteTask(data, id)); }
  function toggleEvent(uid, date) { commit(Tasks.toggleEventCheck(data, uid, date)); }
  function addLink(url) { commit(Inbox.addLink(data, url, newId(), nowIso())); }
  function archiveLink(id) { commit(Inbox.archiveLink(data, id)); }
  function addNote(text) { commit(Inbox.addNote(data, text, newId(), nowIso())); }
  function deleteNote(id) { commit(Inbox.deleteNote(data, id)); }

  function copyText(text) {
    Quickshell.execDetached(["wl-copy", "--", String(text)]);
  }

  function openUrl(url) {
    if (Inbox.isHttpUrl(url))
      Quickshell.execDetached(["xdg-open", url]);
  }

  // ---------------------------------------------------------------- IPC

  IpcHandler {
    target: "plugin:daybar"

    function toggle(): void {
      if (root.pluginApi)
        root.pluginApi.withCurrentScreen(screen => root.pluginApi.togglePanel(screen));
    }

    function open(tab: string): void {
      if (!root.pluginApi)
        return;
      root.requestedTab = tab;
      root.pluginApi.withCurrentScreen(screen => root.pluginApi.openPanel(screen));
    }

    function capture(): void {
      root.openCapture();
    }
  }

  // ---------------------------------------------------------------- agenda

  readonly property bool calendarReady: CalendarService.available
  property var calendars: []
  property var writeQueue: []
  property bool writing: false

  Process {
    id: calendarsProcess
    command: Khal.printCalendarsArgs()
    running: root.calendarReady
    stdout: StdioCollector {
      onStreamFinished: root.calendars = Khal.parseCalendars(text)
    }
  }

  // job: { payload, done: function(ok, error) }
  function enqueueEvent(payload, done) {
    writeQueue = writeQueue.concat([{ payload: payload, done: done }]);
    if (!writing)
      runNextWrite();
  }

  function runNextWrite() {
    if (writeQueue.length === 0) {
      writing = false;
      return;
    }
    writing = true;
    const job = writeQueue[0];
    khalNewProcess.job = job;
    khalNewProcess.command = Khal.newEventArgs(Object.assign({ calendar: setting("defaultCalendar") }, job.payload));
    khalNewProcess.running = true;
  }

  Process {
    id: khalNewProcess
    property var job: null
    stderr: StdioCollector {
      id: khalStderr
    }
    onExited: function (exitCode) {
      const job = khalNewProcess.job;
      root.writeQueue = root.writeQueue.slice(1);
      if (exitCode !== 0) {
        Logger.w("Daybar", "khal new failed: " + khalStderr.text);
        job.done(false, "khal-failed");
      } else {
        job.done(true, "");
        syncProcess.running = true;
      }
      root.runNextWrite();
    }
  }

  Process {
    id: syncProcess
    command: Khal.syncArgs()
    onExited: function (exitCode) {
      if (exitCode !== 0)
        ToastService.showWarning(root.pluginApi?.tr("agenda.sync-failed-title"), root.pluginApi?.tr("agenda.sync-failed-body"));
      CalendarService.loadEvents();
    }
  }

  // ---------------------------------------------------------------- capture

  // result: a successful registry.resolve() result; done(ok, errorCode)
  function executeCapture(result, done) {
    const p = result.payload;
    if (result.action === "addTask") {
      addTask({ title: p.title, date: p.date, time: p.time });
      done(true, "");
    } else if (result.action === "addNote") {
      addNote(p.text);
      done(true, "");
    } else if (result.action === "addLink") {
      addLink(p.url);
      done(true, "");
    } else if (result.action === "createEvent") {
      if (!calendarReady)
        return done(false, "calendar-not-configured");
      enqueueEvent(p, done);
    } else if (result.action === "createReminder") {
      const remember = function () {
        commit(Reminders.addReminder(data, { title: p.title, date: p.date, time: p.start }, newId()));
      };
      if (!calendarReady) {
        remember();
        return done(true, "");
      }
      enqueueEvent(p, function (ok, error) {
        if (ok)
          remember();
        done(ok, error);
      });
    }
  }

  CaptureWindow {
    id: captureWindow
    pluginApi: root.pluginApi
    mainInstance: root
  }

  Process {
    id: clipboardProcess
    command: ["wl-paste", "--no-newline", "--type", "text"]
    stdout: StdioCollector {
      onStreamFinished: {
        const url = Inbox.prefillFromClipboard(text, root.data);
        if (url)
          captureWindow.prefill(url);
      }
    }
  }

  function openCapture() {
    if (!pluginApi)
      return;
    pluginApi.withCurrentScreen(screen => {
      captureWindow.openOn(screen);
      clipboardProcess.running = true;
    });
  }

  // ---------------------------------------------------------------- reminders

  Timer {
    interval: 30000
    repeat: true
    running: root.loaded
    triggeredOnStart: true
    onTriggered: {
      const due = Reminders.dueReminders(root.data, new Date());
      for (const r of due.fire)
        ToastService.showNotice(root.pluginApi?.tr("reminder.title"), r.title, "bell", 10000);
      const ids = due.fire.concat(due.expire).map(r => r.id);
      if (ids.length > 0)
        root.commit(Reminders.markFired(root.data, ids));
    }
  }

  // ---------------------------------------------------------------- pomodoro
  // Fork of the MIT "pomodoro" Noctalia plugin (see THIRD_PARTY.md).

  readonly property string alarmSoundFile: Qt.resolvedUrl("alarm.mp3").toString().replace("file://", "")
  readonly property var pomodoroConfig: ({
      work: setting("workDuration") * 60,
      short: setting("shortBreakDuration") * 60,
      long: setting("longBreakDuration") * 60,
      sessionsBeforeLong: setting("sessionsBeforeLongBreak"),
      autoStartBreaks: setting("autoStartBreaks"),
      autoStartWork: setting("autoStartWork")
    })

  property bool pomodoroRunning: false
  property int pomodoroMode: Pomodoro.WORK
  property int pomodoroCompleted: 0
  property int pomodoroRemaining: 0
  property bool pomodoroSoundPlaying: false
  property string linkedTaskId: ""

  readonly property bool focusShouldBeOn: pomodoroRunning && pomodoroMode === Pomodoro.WORK
  onFocusShouldBeOnChanged: {
    const cmd = String(setting("focusModeCommand") || "").trim();
    if (cmd)
      Quickshell.execDetached([cmd, focusShouldBeOn ? "on" : "off"]);
  }

  Timer {
    interval: 1000
    repeat: true
    running: root.pomodoroRunning
    onTriggered: {
      root.pomodoroRemaining -= 1;
      if (root.pomodoroRemaining <= 0)
        root.pomodoroFinished();
    }
  }

  Timer {
    id: alarmLimitTimer
    interval: 5000
    onTriggered: root.pomodoroStopAlarm()
  }

  function pomodoroStart() {
    pomodoroStopAlarm();
    if (pomodoroRemaining <= 0)
      pomodoroRemaining = Pomodoro.durationFor(pomodoroMode, pomodoroConfig);
    pomodoroRunning = true;
  }

  function pomodoroPause() {
    pomodoroRunning = false;
    pomodoroStopAlarm();
  }

  function pomodoroReset() {
    pomodoroRunning = false;
    pomodoroRemaining = Pomodoro.durationFor(pomodoroMode, pomodoroConfig);
    pomodoroStopAlarm();
  }

  function pomodoroSkip() {
    pomodoroRunning = false;
    pomodoroStopAlarm();
    const next = Pomodoro.nextPhase({ mode: pomodoroMode, completed: pomodoroCompleted }, pomodoroConfig);
    pomodoroMode = next.mode;
    pomodoroCompleted = next.completed;
    pomodoroRemaining = Pomodoro.durationFor(next.mode, pomodoroConfig);
  }

  function pomodoroSetMode(mode) {
    pomodoroRunning = false;
    pomodoroStopAlarm();
    pomodoroMode = mode;
    pomodoroRemaining = Pomodoro.durationFor(mode, pomodoroConfig);
  }

  function pomodoroStopAlarm() {
    if (pomodoroSoundPlaying) {
      SoundService.stopSound(alarmSoundFile);
      pomodoroSoundPlaying = false;
      alarmLimitTimer.stop();
    }
  }

  function pomodoroFinished() {
    pomodoroRunning = false;
    const outcome = Pomodoro.finish({ mode: pomodoroMode, completed: pomodoroCompleted }, pomodoroConfig);
    if (outcome.workCompleted && linkedTaskId)
      commit(Tasks.addPomodoro(data, linkedTaskId));
    if (setting("playSound") !== false) {
      SoundService.playSound(alarmSoundFile, { repeat: true, volume: 0.3 });
      pomodoroSoundPlaying = true;
      alarmLimitTimer.start();
    }
    ToastService.showNotice(pluginApi?.tr("focus.toast-title"), pluginApi?.tr(outcome.workCompleted ? "focus.toast-work-done" : "focus.toast-break-done"), "clock");
    pomodoroMode = outcome.next.mode;
    pomodoroCompleted = outcome.next.completed;
    pomodoroRemaining = outcome.remaining;
    if (outcome.autoStart)
      Qt.callLater(() => { root.pomodoroRunning = true; });
  }

  // Settings arrive with pluginApi; size the idle timer once they exist.
  onPluginApiChanged: {
    if (pluginApi && !pomodoroRunning)
      pomodoroRemaining = Pomodoro.durationFor(pomodoroMode, pomodoroConfig);
  }
}
```

`THIRD_PARTY.md`:
```markdown
# Third-party code

## pomodoro (Noctalia plugin)

The focus timer (`utils/pomodoro.js`, the pomodoro section of `Main.qml`) and
`alarm.mp3` are derived from the `pomodoro` plugin by notprayasmitra, published in
<https://github.com/noctalia-dev/noctalia-plugins> under the MIT License:

~~~
MIT License

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
~~~
```

**Step 4: Run test to verify it passes**
Run: `npm test` (expect all green), then reload the shell (`qs -c noctalia-shell kill; qs -c noctalia-shell -d`) and run smoke rows 1-10 and 15 from `docs/SMOKE.md` (Task 23 writes it; the rows are: data file created, overlay opens/refocuses, URL prefill, preview, Enter/Shift+Enter/Esc, calculator copy, Tab cycling, note capture).
Expected: PASS: every listed row behaves as described and `qs log -c noctalia-shell | grep -iE "daybar.*(error|TypeError|ReferenceError)"` prints nothing.

**Step 5: Commit**
Run: `/git commit`

---

### Task 21: Toolbar panel and its four tabs

**Requirement:** REQ-013, REQ-014, REQ-015, REQ-016, REQ-017, REQ-018, REQ-020, REQ-022
**Depends on:** Tasks 9, 10, 14, 20
**Files:**
- Create: `Panel.qml`
- Create: `components/TodayView.qml`
- Create: `components/CalendarView.qml`
- Create: `components/FocusView.qml`
- Create: `components/InboxView.qml`
- Modify: `manifest.json` (add the `panel` entry point)
- Test: `tests/i18n.test.js` (existing)

**Team:**
- Track: frontend
- Implementer: frontend-engineer (skills: accessibility-guardrails)
- Reviewers: type-safety-reviewer, test-reviewer, accessibility-guardrails

**Step 1: Write the failing test**
QML has no unit harness (spec Test Strategy). The red/green signal for this task is the i18n coverage test (any new `tr()` key) plus the runtime check below. Add `"panel": "Panel.qml"` to `manifest.json` `entryPoints` first.

**Step 2: Run test to verify it fails**
Run: `qs -c noctalia-shell ipc call plugin:daybar toggle; qs log -c noctalia-shell | grep -i daybar | tail -5`
Expected: FAIL (`Panel.qml` not found / panel does not open).

**Step 3: Write minimal implementation**
`Panel.qml`:
```qml
import QtQuick
import QtQuick.Layouts
import qs.Commons
import qs.Widgets
import "components"

// Bar toolbar: Calendar, Today, Focus and Inbox tabs plus the Capture button.
Item {
  id: root

  property var pluginApi: null
  readonly property var geometryPlaceholder: panelContainer
  readonly property bool allowAttach: true
  readonly property var mainInstance: pluginApi?.mainInstance ?? null
  readonly property var tabKeys: ["calendar", "today", "focus", "inbox"]

  property real contentPreferredWidth: 680 * Style.uiScaleRatio
  property real contentPreferredHeight: 380 * Style.uiScaleRatio

  anchors.fill: parent

  function tr(key) {
    return pluginApi ? pluginApi.tr(key) : key;
  }

  // An IPC `open <tab>` wins over the configured initial tab, once.
  function pickInitialTab() {
    if (!mainInstance)
      return;
    const requested = mainInstance.requestedTab;
    const fallback = mainInstance.setting("initialTab");
    const index = tabKeys.indexOf(requested !== "" ? requested : fallback);
    tabBar.currentIndex = index >= 0 ? index : 1;
    mainInstance.requestedTab = "";
  }

  onMainInstanceChanged: pickInitialTab()
  Component.onCompleted: pickInitialTab()

  Rectangle {
    id: panelContainer
    anchors.fill: parent
    color: "transparent"

    ColumnLayout {
      anchors.fill: parent
      anchors.margins: Style.marginM
      spacing: Style.marginM

      RowLayout {
        Layout.fillWidth: true
        spacing: Style.marginS

        NTabBar {
          id: tabBar
          Layout.fillWidth: true

          Repeater {
            model: root.tabKeys

            NTabButton {
              required property string modelData
              required property int index
              text: root.tr("tabs." + modelData)
              tabIndex: index
              checked: tabBar.currentIndex === index
            }
          }
        }

        NIconButton {
          icon: "bolt"
          tooltipText: root.tr("tabs.capture")
          onClicked: {
            if (root.mainInstance)
              root.mainInstance.openCapture();
            root.pluginApi?.withCurrentScreen(screen => root.pluginApi.closePanel(screen));
          }
        }
      }

      StackLayout {
        Layout.fillWidth: true
        Layout.fillHeight: true
        currentIndex: tabBar.currentIndex

        CalendarView {
          pluginApi: root.pluginApi
          mainInstance: root.mainInstance
        }

        TodayView {
          pluginApi: root.pluginApi
          mainInstance: root.mainInstance
        }

        FocusView {
          pluginApi: root.pluginApi
          mainInstance: root.mainInstance
        }

        InboxView {
          pluginApi: root.pluginApi
          mainInstance: root.mainInstance
        }
      }
    }
  }
}
```

`components/TodayView.qml`:
```qml
import QtQuick
import QtQuick.Layouts
import qs.Commons
import qs.Widgets
import qs.Services.Location
import "../utils/today.js" as Today
import "../utils/capture/task.js" as TaskCapture

// Today checklist: calendar events + today's and overdue tasks, plus a quick add field.
NBox {
  id: root

  property var pluginApi: null
  property var mainInstance: null
  property date now: new Date()
  readonly property var items: mainInstance ? Today.buildToday(CalendarService.events, mainInstance.data, now) : []

  function tr(key) {
    return pluginApi ? pluginApi.tr(key) : key;
  }

  Timer {
    interval: 60000
    repeat: true
    running: root.visible
    triggeredOnStart: true
    onTriggered: root.now = new Date()
  }

  ColumnLayout {
    anchors.fill: parent
    anchors.margins: Style.marginM
    spacing: Style.marginS

    NText {
      text: root.tr("today.title")
      pointSize: Style.fontSizeM
      font.weight: Style.fontWeightBold
      color: Color.mOnSurface
    }

    NText {
      visible: root.items.length === 0
      text: root.tr("today.empty")
      color: Color.mOnSurfaceVariant
    }

    NScrollView {
      Layout.fillWidth: true
      Layout.fillHeight: true
      visible: root.items.length > 0

      ColumnLayout {
        width: parent.width
        spacing: Style.marginXS

        Repeater {
          model: root.items

          RowLayout {
            required property var modelData
            Layout.fillWidth: true
            spacing: Style.marginS

            NCheckbox {
              checked: modelData.done
              onToggled: {
                if (modelData.kind === "event")
                  root.mainInstance.toggleEvent(modelData.uid, Qt.formatDate(root.now, "yyyy-MM-dd"));
                else
                  root.mainInstance.toggleTask(modelData.id);
              }
            }

            NIcon {
              icon: modelData.kind === "event" ? "calendar" : "checkbox"
              color: Color.mOnSurfaceVariant
            }

            NText {
              visible: modelData.time !== null
              text: modelData.time || ""
              family: Settings.data.ui.fontFixed
              color: Color.mPrimary
            }

            NText {
              Layout.fillWidth: true
              elide: Text.ElideRight
              text: modelData.title
              color: modelData.done ? Color.mOnSurfaceVariant : Color.mOnSurface
              font.strikeout: modelData.done
            }

            NText {
              visible: modelData.overdue
              text: root.tr("today.overdue")
              pointSize: Style.fontSizeXS
              color: Color.mError
            }

            NText {
              visible: modelData.pomodoros > 0
              text: "● " + modelData.pomodoros
              pointSize: Style.fontSizeXS
              color: Color.mOnSurfaceVariant
            }

            NIconButton {
              visible: modelData.kind === "task"
              icon: "trash"
              baseSize: Style.baseWidgetSize * 0.7
              tooltipText: root.tr("today.delete")
              onClicked: root.mainInstance.deleteTask(modelData.id)
            }
          }
        }
      }
    }

    NTextInput {
      id: addField
      Layout.fillWidth: true
      placeholderText: root.tr("today.add-placeholder")
      onAccepted: {
        const r = TaskCapture.build(addField.text, new Date());
        if (!r.ok)
          return;
        root.mainInstance.addTask(r.payload);
        addField.text = "";
      }
    }
  }
}
```

`components/CalendarView.qml`:
```qml
import QtQuick
import QtQuick.Layouts
import qs.Commons
import qs.Widgets
import qs.Services.Location
import "../utils/month.js" as Month
import "../utils/events.js" as Events

// Clock + selected day's events on the left, Monday-first month grid on the right.
NBox {
  id: root

  property var pluginApi: null
  property var mainInstance: null
  property date now: new Date()
  property int year: now.getFullYear()
  property int month: now.getMonth()
  property string selected: Qt.formatDate(now, "yyyy-MM-dd")
  readonly property var cells: Month.monthGrid(year, month, now, CalendarService.events)
  readonly property var dayEvents: Events.eventsOn(CalendarService.events, selected)

  function tr(key) {
    return pluginApi ? pluginApi.tr(key) : key;
  }

  function shift(delta) {
    const next = Month.shiftMonth(year, month, delta);
    year = next.year;
    month = next.month;
  }

  Timer {
    interval: 1000
    repeat: true
    running: root.visible
    onTriggered: root.now = new Date()
  }

  RowLayout {
    anchors.fill: parent
    anchors.margins: Style.marginM
    spacing: Style.marginL

    ColumnLayout {
      Layout.preferredWidth: parent.width * 0.38
      Layout.fillHeight: true
      spacing: Style.marginS

      NText {
        text: Qt.formatTime(root.now, "HH:mm")
        pointSize: Style.fontSizeXXL * 1.6
        font.weight: Style.fontWeightBold
        color: Color.mOnSurface
      }

      NText {
        text: root.now.toLocaleDateString(Qt.locale(), "dddd, d MMMM")
        color: Color.mOnSurfaceVariant
      }

      NText {
        visible: !root.mainInstance?.calendarReady
        Layout.fillWidth: true
        wrapMode: Text.WordWrap
        text: root.tr("calendar.not-configured")
        color: Color.mError
      }

      NText {
        visible: root.mainInstance?.calendarReady && root.dayEvents.length === 0
        text: root.tr("calendar.nothing")
        color: Color.mOnSurfaceVariant
      }

      Repeater {
        model: root.dayEvents

        RowLayout {
          required property var modelData
          spacing: Style.marginS

          NText {
            text: modelData.time || root.tr("calendar.all-day")
            family: Settings.data.ui.fontFixed
            color: Color.mPrimary
          }

          NText {
            Layout.fillWidth: true
            elide: Text.ElideRight
            text: modelData.summary
            color: Color.mOnSurface
          }
        }
      }

      Item {
        Layout.fillHeight: true
      }
    }

    ColumnLayout {
      Layout.fillWidth: true
      Layout.fillHeight: true
      spacing: Style.marginS

      RowLayout {
        Layout.fillWidth: true

        NText {
          Layout.fillWidth: true
          text: new Date(root.year, root.month, 1).toLocaleDateString(Qt.locale(), "MMMM yyyy")
          font.weight: Style.fontWeightBold
          color: Color.mOnSurface
        }

        NIconButton {
          icon: "chevron-left"
          baseSize: Style.baseWidgetSize * 0.7
          tooltipText: root.tr("calendar.previous")
          onClicked: root.shift(-1)
        }

        NIconButton {
          icon: "chevron-right"
          baseSize: Style.baseWidgetSize * 0.7
          tooltipText: root.tr("calendar.next")
          onClicked: root.shift(1)
        }
      }

      GridLayout {
        Layout.fillWidth: true
        Layout.fillHeight: true
        columns: 7
        rowSpacing: Style.marginXS
        columnSpacing: Style.marginXS

        Repeater {
          model: root.tr("calendar.weekdays").split(" ")

          NText {
            required property string modelData
            Layout.fillWidth: true
            horizontalAlignment: Text.AlignHCenter
            text: modelData
            pointSize: Style.fontSizeXS
            color: Color.mOnSurfaceVariant
          }
        }

        Repeater {
          model: root.cells

          Rectangle {
            required property var modelData
            Layout.fillWidth: true
            Layout.fillHeight: true
            radius: Style.radiusS
            color: modelData.date === root.selected ? Color.mPrimary : (modelData.today ? Color.mHover : "transparent")

            NText {
              anchors.centerIn: parent
              text: modelData.day
              color: modelData.date === root.selected ? Color.mOnPrimary : (modelData.inMonth ? Color.mOnSurface : Color.mOnSurfaceVariant)
              opacity: modelData.inMonth ? 1 : 0.5
            }

            Rectangle {
              visible: modelData.hasEvents
              width: 4
              height: 4
              radius: 2
              anchors.horizontalCenter: parent.horizontalCenter
              anchors.bottom: parent.bottom
              anchors.bottomMargin: 2
              color: modelData.date === root.selected ? Color.mOnPrimary : Color.mPrimary
            }

            MouseArea {
              anchors.fill: parent
              cursorShape: Qt.PointingHandCursor
              onClicked: root.selected = modelData.date
            }
          }
        }
      }
    }
  }
}
```

`components/FocusView.qml`:
```qml
import QtQuick
import QtQuick.Layouts
import qs.Commons
import qs.Widgets
import "../utils/pomodoro.js" as Pomodoro
import "../utils/dates.js" as Dates

// Pomodoro controls with an optional link to one of today's tasks.
NBox {
  id: root

  property var pluginApi: null
  property var mainInstance: null
  readonly property var modes: [["work", Pomodoro.WORK], ["short", Pomodoro.SHORT], ["long", Pomodoro.LONG]]
  readonly property var taskOptions: {
    const none = [{ key: "", name: tr("focus.no-task") }];
    if (!mainInstance)
      return none;
    const today = Dates.isoDate(new Date());
    return none.concat(mainInstance.data.tasks
      .filter(t => !t.done && (t.date || today) <= today)
      .map(t => ({ key: t.id, name: t.title })));
  }

  function tr(key) {
    return pluginApi ? pluginApi.tr(key) : key;
  }

  RowLayout {
    anchors.fill: parent
    anchors.margins: Style.marginL
    spacing: Style.marginL

    NText {
      text: Pomodoro.formatClock(root.mainInstance?.pomodoroRemaining ?? 0)
      family: Settings.data.ui.fontFixed
      pointSize: Style.fontSizeXXL * 1.6
      font.weight: Style.fontWeightBold
      color: root.mainInstance?.pomodoroRunning ? Color.mPrimary : Color.mOnSurface
    }

    ColumnLayout {
      Layout.fillWidth: true
      spacing: Style.marginM

      RowLayout {
        spacing: Style.marginS

        Repeater {
          model: root.modes

          NButton {
            required property var modelData
            text: root.tr("focus.mode." + modelData[0])
            outlined: root.mainInstance?.pomodoroMode !== modelData[1]
            onClicked: root.mainInstance.pomodoroSetMode(modelData[1])
          }
        }
      }

      RowLayout {
        spacing: Style.marginM

        NComboBox {
          model: root.taskOptions
          currentKey: root.mainInstance?.linkedTaskId ?? ""
          placeholder: root.tr("focus.no-task")
          onSelected: key => root.mainInstance.linkedTaskId = key
        }

        NText {
          text: root.tr("focus.cycle").replace("{n}", (root.mainInstance?.pomodoroCompleted ?? 0) + 1).replace("{total}", root.mainInstance?.setting("sessionsBeforeLongBreak") ?? 4)
          color: Color.mOnSurfaceVariant
        }
      }

      RowLayout {
        spacing: Style.marginS

        NButton {
          text: root.mainInstance?.pomodoroRunning ? root.tr("focus.pause") : root.tr("focus.start")
          icon: root.mainInstance?.pomodoroRunning ? "player-pause" : "player-play"
          onClicked: root.mainInstance.pomodoroRunning ? root.mainInstance.pomodoroPause() : root.mainInstance.pomodoroStart()
        }

        NIconButton {
          icon: "refresh"
          tooltipText: root.tr("focus.reset")
          onClicked: root.mainInstance.pomodoroReset()
        }

        NIconButton {
          icon: "player-skip-forward"
          tooltipText: root.tr("focus.skip")
          onClicked: root.mainInstance.pomodoroSkip()
        }
      }
    }
  }
}
```

`components/InboxView.qml`:
```qml
import QtQuick
import QtQuick.Layouts
import qs.Commons
import qs.Widgets

// Read-later links and captured notes.
NBox {
  id: root

  property var pluginApi: null
  property var mainInstance: null
  readonly property var links: mainInstance ? mainInstance.data.links.filter(l => !l.archived).slice().reverse() : []
  readonly property var notes: mainInstance ? mainInstance.data.notes.slice().reverse() : []

  function tr(key) {
    return pluginApi ? pluginApi.tr(key) : key;
  }

  NScrollView {
    anchors.fill: parent
    anchors.margins: Style.marginM

    ColumnLayout {
      width: parent.width
      spacing: Style.marginS

      NText {
        text: root.tr("inbox.links")
        font.weight: Style.fontWeightBold
        color: Color.mOnSurface
      }

      NText {
        visible: root.links.length === 0
        text: root.tr("inbox.no-links")
        color: Color.mOnSurfaceVariant
      }

      Repeater {
        model: root.links

        RowLayout {
          required property var modelData
          Layout.fillWidth: true
          spacing: Style.marginS

          NText {
            Layout.fillWidth: true
            elide: Text.ElideMiddle
            text: modelData.url
            color: Color.mPrimary
          }

          NIconButton {
            icon: "external-link"
            baseSize: Style.baseWidgetSize * 0.7
            tooltipText: root.tr("inbox.open")
            onClicked: root.mainInstance.openUrl(modelData.url)
          }

          NIconButton {
            icon: "archive"
            baseSize: Style.baseWidgetSize * 0.7
            tooltipText: root.tr("inbox.archive")
            onClicked: root.mainInstance.archiveLink(modelData.id)
          }
        }
      }

      NDivider {
        Layout.fillWidth: true
      }

      NText {
        text: root.tr("inbox.notes")
        font.weight: Style.fontWeightBold
        color: Color.mOnSurface
      }

      NText {
        visible: root.notes.length === 0
        text: root.tr("inbox.no-notes")
        color: Color.mOnSurfaceVariant
      }

      Repeater {
        model: root.notes

        RowLayout {
          required property var modelData
          Layout.fillWidth: true
          spacing: Style.marginS

          NText {
            Layout.fillWidth: true
            wrapMode: Text.WordWrap
            text: modelData.text
            color: Color.mOnSurface
          }

          NIconButton {
            icon: "copy"
            baseSize: Style.baseWidgetSize * 0.7
            tooltipText: root.tr("inbox.copy")
            onClicked: root.mainInstance.copyText(modelData.text)
          }

          NIconButton {
            icon: "trash"
            baseSize: Style.baseWidgetSize * 0.7
            tooltipText: root.tr("inbox.delete")
            onClicked: root.mainInstance.deleteNote(modelData.id)
          }
        }
      }
    }
  }
}
```

Accessibility: every icon-only button has `tooltipText`; checkboxes and buttons are reachable by keyboard through the Noctalia widgets; overdue state is text ("atrasada"), not color only.

**Step 4: Run test to verify it passes**
Run: `npm test -- tests/i18n.test.js`, reload the shell, then smoke rows 16-18, 20, 21, 23 and 24 of `docs/SMOKE.md`.
Expected: PASS (2 tests) and the rows behave as described with no `daybar` errors in `qs log -c noctalia-shell`.

**Step 5: Commit**
Run: `/git commit`

---

### Task 22: Bar widget, settings page and final manifest

**Requirement:** REQ-019, REQ-023
**Depends on:** Task 21
**Files:**
- Create: `BarWidget.qml`
- Create: `Settings.qml`
- Modify: `manifest.json` (final version below)
- Test: `tests/manifest.test.js`

**Team:**
- Track: frontend
- Implementer: frontend-engineer (skills: accessibility-guardrails)
- Reviewers: type-safety-reviewer, test-reviewer, accessibility-guardrails

**Step 1: Write the failing test**
```js
import { describe, it, expect } from "vitest";
import { readFileSync, existsSync } from "node:fs";

const manifest = JSON.parse(readFileSync(new URL("../manifest.json", import.meta.url), "utf8"));

describe("manifest", () => {
  it("declares the plugin identity", () => {
    expect(manifest.id).toBe("daybar");
    expect(manifest.license).toBe("MIT");
  });

  it("points every entry point at an existing file", () => {
    for (const file of Object.values(manifest.entryPoints)) {
      expect(existsSync(new URL("../" + file, import.meta.url)), file).toBe(true);
    }
  });

  it("ships the default settings the services read", () => {
    expect(Object.keys(manifest.metadata.defaultSettings).sort()).toEqual([
      "autoStartBreaks", "autoStartWork", "defaultCalendar", "focusModeCommand", "initialTab",
      "longBreakDuration", "playSound", "sessionsBeforeLongBreak", "shortBreakDuration", "workDuration"
    ]);
  });
});
```

**Step 2: Run test to verify it fails**
Run: `npm test -- tests/manifest.test.js`
Expected: FAIL (`barWidget`/`settings` entry points and the full `defaultSettings` are missing).

**Step 3: Write minimal implementation**
`manifest.json`:
```json
{
  "id": "daybar",
  "name": "Daybar",
  "version": "0.1.0",
  "minNoctaliaVersion": "4.0.0",
  "author": "Fernando Moreira Costa",
  "license": "MIT",
  "repository": "https://github.com/nandomoreirame/noctalia-daybar",
  "description": "Quick capture, today's checklist, Google Calendar and focus timer in one bar toolbar.",
  "tags": ["Bar", "Productivity"],
  "entryPoints": {
    "main": "Main.qml",
    "barWidget": "BarWidget.qml",
    "panel": "Panel.qml",
    "settings": "Settings.qml"
  },
  "dependencies": {
    "plugins": []
  },
  "metadata": {
    "defaultSettings": {
      "workDuration": 25,
      "shortBreakDuration": 5,
      "longBreakDuration": 15,
      "sessionsBeforeLongBreak": 4,
      "autoStartBreaks": false,
      "autoStartWork": false,
      "playSound": true,
      "focusModeCommand": "",
      "defaultCalendar": "",
      "initialTab": "today"
    }
  }
}
```

`BarWidget.qml`:
```qml
import QtQuick
import QtQuick.Layouts
import Quickshell
import qs.Commons
import qs.Widgets
import "utils/pomodoro.js" as Pomodoro

// Bar entry: an icon, plus the focus clock while a pomodoro is running.
// Left click toggles the toolbar, middle click starts/pauses the timer.
Item {
  id: root

  property var pluginApi: null
  property ShellScreen screen
  property string widgetId: ""
  property string section: ""
  property int sectionWidgetIndex: -1
  property int sectionWidgetsCount: 0

  readonly property var mainInstance: pluginApi?.mainInstance ?? null
  readonly property bool timerVisible: !!mainInstance && (mainInstance.pomodoroRunning || mainInstance.pomodoroSoundPlaying)
  readonly property bool barIsVertical: (Settings.data.bar.position || "top") === "left" || Settings.data.bar.position === "right"

  implicitWidth: barIsVertical || !timerVisible ? Style.capsuleHeight : contentRow.implicitWidth + Style.marginM * 2
  implicitHeight: Style.capsuleHeight

  Rectangle {
    anchors.centerIn: parent
    width: root.implicitWidth
    height: root.implicitHeight
    radius: Style.radiusL
    color: mouseArea.containsMouse ? Color.mHover : Style.capsuleColor

    RowLayout {
      id: contentRow
      anchors.centerIn: parent
      spacing: Style.marginS

      NIcon {
        icon: root.timerVisible ? "brain" : "layout-list"
        applyUiScale: false
        color: root.timerVisible ? Color.mPrimary : (mouseArea.containsMouse ? Color.mOnHover : Color.mOnSurface)
      }

      NText {
        visible: root.timerVisible && !root.barIsVertical
        text: Pomodoro.formatClock(root.mainInstance?.pomodoroRemaining ?? 0)
        family: Settings.data.ui.fontFixed
        pointSize: Style.barFontSize
        color: Color.mPrimary
      }
    }
  }

  MouseArea {
    id: mouseArea
    anchors.fill: parent
    hoverEnabled: true
    cursorShape: Qt.PointingHandCursor
    acceptedButtons: Qt.LeftButton | Qt.MiddleButton

    onClicked: mouse => {
      if (mouse.button === Qt.MiddleButton && root.mainInstance) {
        root.mainInstance.pomodoroRunning ? root.mainInstance.pomodoroPause() : root.mainInstance.pomodoroStart();
      } else if (root.pluginApi) {
        root.pluginApi.togglePanel(root.screen, root);
      }
    }
  }
}
```

`Settings.qml`:
```qml
import QtQuick
import QtQuick.Layouts
import qs.Commons
import qs.Widgets

// Plugin settings. Noctalia calls saveSettings() when the dialog is confirmed.
ColumnLayout {
  id: root

  property var pluginApi: null
  readonly property var mainInstance: pluginApi?.mainInstance ?? null

  property int workDuration: 25
  property int shortBreakDuration: 5
  property int longBreakDuration: 15
  property int sessionsBeforeLongBreak: 4
  property bool autoStartBreaks: false
  property bool autoStartWork: false
  property bool playSound: true
  property string focusModeCommand: ""
  property string defaultCalendar: ""
  property string initialTab: "today"

  spacing: Style.marginM

  function tr(key) {
    return pluginApi ? pluginApi.tr(key) : key;
  }

  function value(key) {
    const s = pluginApi?.pluginSettings ?? {};
    const d = pluginApi?.manifest?.metadata?.defaultSettings ?? {};
    return s[key] === undefined ? d[key] : s[key];
  }

  function loadSettings() {
    workDuration = value("workDuration");
    shortBreakDuration = value("shortBreakDuration");
    longBreakDuration = value("longBreakDuration");
    sessionsBeforeLongBreak = value("sessionsBeforeLongBreak");
    autoStartBreaks = value("autoStartBreaks");
    autoStartWork = value("autoStartWork");
    playSound = value("playSound");
    focusModeCommand = value("focusModeCommand");
    defaultCalendar = value("defaultCalendar");
    initialTab = value("initialTab");
  }

  function saveSettings() {
    if (!pluginApi)
      return;
    const s = pluginApi.pluginSettings;
    s.workDuration = workDuration;
    s.shortBreakDuration = shortBreakDuration;
    s.longBreakDuration = longBreakDuration;
    s.sessionsBeforeLongBreak = sessionsBeforeLongBreak;
    s.autoStartBreaks = autoStartBreaks;
    s.autoStartWork = autoStartWork;
    s.playSound = playSound;
    s.focusModeCommand = focusModeCommand.trim();
    s.defaultCalendar = defaultCalendar;
    s.initialTab = initialTab;
    pluginApi.saveSettings();
  }

  onPluginApiChanged: if (pluginApi) loadSettings()
  Component.onCompleted: if (pluginApi) loadSettings()

  NHeader {
    label: root.tr("settings.focus")
  }

  NSpinBox {
    label: root.tr("settings.work-duration")
    from: 1
    to: 180
    value: root.workDuration
    suffix: " min"
    onValueChanged: root.workDuration = value
  }

  NSpinBox {
    label: root.tr("settings.short-break")
    from: 1
    to: 60
    value: root.shortBreakDuration
    suffix: " min"
    onValueChanged: root.shortBreakDuration = value
  }

  NSpinBox {
    label: root.tr("settings.long-break")
    from: 1
    to: 120
    value: root.longBreakDuration
    suffix: " min"
    onValueChanged: root.longBreakDuration = value
  }

  NSpinBox {
    label: root.tr("settings.sessions")
    from: 1
    to: 12
    value: root.sessionsBeforeLongBreak
    onValueChanged: root.sessionsBeforeLongBreak = value
  }

  NToggle {
    label: root.tr("settings.auto-start-breaks")
    checked: root.autoStartBreaks
    onToggled: checked => root.autoStartBreaks = checked
  }

  NToggle {
    label: root.tr("settings.auto-start-work")
    checked: root.autoStartWork
    onToggled: checked => root.autoStartWork = checked
  }

  NToggle {
    label: root.tr("settings.play-sound")
    checked: root.playSound
    onToggled: checked => root.playSound = checked
  }

  NTextInput {
    Layout.fillWidth: true
    label: root.tr("settings.focus-command")
    description: root.tr("settings.focus-command-help")
    text: root.focusModeCommand
    onTextChanged: root.focusModeCommand = text
  }

  NHeader {
    label: root.tr("settings.general")
  }

  NComboBox {
    label: root.tr("settings.default-calendar")
    description: root.mainInstance?.calendarReady ? "" : root.tr("calendar.not-configured")
    model: (root.mainInstance?.calendars ?? []).map(c => ({ key: c, name: c }))
    currentKey: root.defaultCalendar
    placeholder: root.tr("settings.default-calendar-none")
    onSelected: key => root.defaultCalendar = key
  }

  NComboBox {
    label: root.tr("settings.initial-tab")
    model: ["calendar", "today", "focus", "inbox"].map(k => ({ key: k, name: root.tr("tabs." + k) }))
    currentKey: root.initialTab
    onSelected: key => root.initialTab = key
  }
}
```

**Step 4: Run test to verify it passes**
Run: `npm test` (all files), reload the shell, add the **Daybar** widget to the bar, then smoke rows 20, 22 and 25 of `docs/SMOKE.md`.
Expected: PASS (all tests green; bar shows the icon and the clock while focusing; settings persist).

**Step 5: Commit**
Run: `/git commit`

---

### Task 23: README setup guide and smoke script

**Requirement:** REQ-016 (setup guide), Test Strategy (manual smoke)
**Depends on:** Task 22
**Files:**
- Create: `README.md`
- Create: `docs/SMOKE.md`

**Team:**
- Track: docs
- Implementer: rpi-implementer
- Reviewers: self-review

**Step 1: Write the failing test**
Docs task: the check is that every P1 REQ appears in `docs/SMOKE.md`.
Run: `for i in $(seq -w 1 23); do grep -q "REQ-0$i" docs/SMOKE.md || echo "missing REQ-0$i"; done`

**Step 2: Run test to verify it fails**
Expected: FAIL (`grep: docs/SMOKE.md: No such file`).

**Step 3: Write minimal implementation**
`README.md`:
```markdown
# Daybar

A [Noctalia Shell](https://github.com/noctalia-dev/noctalia) plugin for the day:
a centered quick-capture field and a bar toolbar with Calendar (Google Calendar),
Today, Focus (pomodoro) and Inbox.

## Capture

Open it with a shortcut (see [niri binding](#shortcuts)) and type:

| You type | It becomes |
|----------|------------|
| `comprar pão amanhã 9h` | task for tomorrow 09:00 (no date = today) |
| `/e reunião sexta 15h-16h` | Google Calendar event (1h when there is no end) |
| `/l pagar boleto 18h` | reminder: 15-minute event with alarm + local toast |
| `/n uma ideia` | note in the Inbox |
| `https://...` | read-later link in the Inbox (prefilled from the clipboard) |
| `=200*15%` | calculation; Enter copies the result |

`Tab` cycles the type, `Enter` saves and closes, `Shift+Enter` saves and keeps the
field open, `Esc` closes.

## Requirements

- noctalia-shell 4.x
- `khal`, `vdirsyncer`, `wl-clipboard`, `xdg-utils`

~~~bash
sudo pacman -S --needed khal vdirsyncer python-aiohttp-oauthlib wl-clipboard xdg-utils libsecret
~~~

## Install

~~~bash
git clone https://github.com/nandomoreirame/noctalia-daybar ~/dev/projects/noctalia-daybar
ln -s ~/dev/projects/noctalia-daybar ~/.config/noctalia/plugins/daybar
~~~

Enable **Daybar** in Noctalia Settings > Plugins, then add the **Daybar** widget to
the bar. Disable the standalone pomodoro plugin if you used it.

## Google Calendar setup (one time)

Daybar reads events through Noctalia's calendar service (khal provider) and writes
with `khal new`. vdirsyncer keeps khal and Google in sync.

1. **OAuth client.** In Google Cloud Console create a project, enable the
   **CalDAV API**, configure the OAuth consent screen as *External* and **publish it
   ("In production")**. In *Testing* status Google expires the refresh token every
   7 days. Create an OAuth client of type *Desktop app*.
2. **Store the secrets** in the keyring:
   ~~~bash
   secret-tool store --label="vdirsyncer google id" service vdirsyncer-google key client_id
   secret-tool store --label="vdirsyncer google secret" service vdirsyncer-google key client_secret
   ~~~
3. **vdirsyncer** (`~/.config/vdirsyncer/config`):
   ~~~ini
   [general]
   status_path = "~/.local/share/vdirsyncer/status/"

   [pair google_calendar]
   a = "google_calendar_remote"
   b = "google_calendar_local"
   collections = ["from a", "from b"]
   conflict_resolution = "a wins"

   [storage google_calendar_remote]
   type = "google_calendar"
   token_file = "~/.local/share/vdirsyncer/google_token"
   client_id.fetch = ["command", "secret-tool", "lookup", "service", "vdirsyncer-google", "key", "client_id"]
   client_secret.fetch = ["command", "secret-tool", "lookup", "service", "vdirsyncer-google", "key", "client_secret"]

   [storage google_calendar_local]
   type = "filesystem"
   path = "~/.local/share/calendars/google/"
   fileext = ".ics"
   ~~~
   Then authorize and sync (opens the browser once):
   ~~~bash
   vdirsyncer discover google_calendar && vdirsyncer metasync && vdirsyncer sync
   ~~~
4. **khal** (`~/.config/khal/config`). Daybar passes ISO dates, so the locale
   formats must be ISO:
   ~~~ini
   [calendars]
   [[google]]
   path = ~/.local/share/calendars/google/*
   type = discover

   [locale]
   timeformat = %H:%M
   dateformat = %Y-%m-%d
   longdateformat = %Y-%m-%d
   datetimeformat = %Y-%m-%d %H:%M
   longdatetimeformat = %Y-%m-%d %H:%M
   firstweekday = 0
   ~~~
   Check with `khal printcalendars` and pick the default calendar in Daybar's settings.
5. **Periodic sync** (`~/.config/systemd/user/vdirsyncer.service` and `.timer`):
   ~~~ini
   # vdirsyncer.service
   [Unit]
   Description=Synchronize calendars

   [Service]
   Type=oneshot
   ExecStart=/usr/bin/vdirsyncer sync
   ~~~
   ~~~ini
   # vdirsyncer.timer
   [Unit]
   Description=Synchronize calendars every 10 minutes

   [Timer]
   OnBootSec=2m
   OnUnitActiveSec=10m

   [Install]
   WantedBy=timers.target
   ~~~
   ~~~bash
   systemctl --user daemon-reload && systemctl --user enable --now vdirsyncer.timer
   ~~~
6. In Noctalia Settings > Location keep **Show calendar events** on.

Without khal the Calendar tab shows "Calendar not configured"; tasks, notes, links,
calculations and the focus timer keep working.

## Shortcuts

IPC target `plugin:daybar`:

~~~bash
qs -c noctalia-shell ipc call plugin:daybar capture      # quick capture
qs -c noctalia-shell ipc call plugin:daybar toggle       # toolbar
qs -c noctalia-shell ipc call plugin:daybar open today   # calendar | today | focus | inbox
~~~

niri (`~/.config/niri/config.kdl`):

~~~kdl
binds {
    Mod+Shift+Space hotkey-overlay-title="Daybar: capture" { spawn "qs" "-c" "noctalia-shell" "ipc" "call" "plugin:daybar" "capture"; }
}
~~~

## Focus mode hook

Settings > *Focus mode command* runs an executable with `on` when a focus session
starts and `off` when it stops (pause, break, finish). Leave it empty to disable.

## Data

`~/.local/share/noctalia-daybar/data.json` (tasks, event checks, reminders, links,
notes). A corrupt file is kept as `data.json.bak` and a fresh one is started.

## Development

~~~bash
npm install
npm test
~~~

Logic lives in `utils/**/*.js` (QML JavaScript libraries, tested with vitest through
a transform in `vitest.config.js`); QML files are thin UI. Manual checks:
[docs/SMOKE.md](docs/SMOKE.md).

## License

MIT. The focus timer is derived from an MIT plugin, see [THIRD_PARTY.md](THIRD_PARTY.md).
```

`docs/SMOKE.md`:
```markdown
# Smoke test (manual)

Run after `npm test` is green, with the plugin symlinked and enabled. Watch the shell
log in another terminal: `qs log -c noctalia-shell -f | grep -i daybar`.
Any `daybar` error or `ReferenceError`/`TypeError` fails the run.

| # | REQ | Step | Expected |
|---|-----|------|----------|
| 1 | REQ-021 | Reload the shell; `cat ~/.local/share/noctalia-daybar/data.json` after the first capture | File exists with `"version": 1` |
| 2 | REQ-001 | `qs -c noctalia-shell ipc call plugin:daybar capture` | Centered overlay, cursor in the field |
| 3 | REQ-001 | Run the same command again while open | No second window; focus stays in the field |
| 4 | REQ-002 | Copy `https://example.com`, open capture | Field prefilled and selected, type chip "Link" |
| 5 | REQ-002 | Save it, copy the same URL, open capture | Field empty |
| 6 | REQ-003/008 | Type `comprar pão amanhã 9h` | Preview "comprar pão · amanhã 09:00", chip "Tarefa" |
| 7 | REQ-007 | Enter | Overlay closes, toast "Tarefa salva" |
| 8 | REQ-007 | Type `a`, Shift+Enter, `b`, Shift+Enter, Esc | Two tasks saved, overlay closed by Esc |
| 9 | REQ-004/005 | `=200*15%`, Enter; then `=2/0` | Preview "= 30", Enter copies `30` (check `wl-paste`), overlay stays; `=2/0` shows "Divisão por zero" |
| 10 | REQ-006 | `pagar boleto 18h`, press Tab three times | Chip cycles Tarefa > Evento > Lembrete > Nota |
| 11 | REQ-009/012 | `/e teste daybar amanhã 10h` | Overlay closes; event appears in Google Calendar after `vdirsyncer sync` and in the Calendar tab |
| 12 | REQ-009 | `/e sem data` | Error "Evento precisa de data e hora", text kept |
| 13 | REQ-010 | `/l teste lembrete <now+2min>` | Event with alarm in Google; local toast at that minute |
| 14 | REQ-012 | Disconnect network, create an event | Warning toast "Falha ao sincronizar a agenda"; event in `khal list` |
| 15 | REQ-011 | `/n uma ideia` | Note in Inbox |
| 16 | REQ-013/014 | Open toolbar > Hoje | Events first by time, then tasks; check/uncheck persists after shell reload |
| 17 | REQ-014 | Type in the Hoje field `ligar 16h`, Enter; delete it | Task added, then removed |
| 18 | REQ-015 | Calendário tab | Clock, Monday-first grid, dots on days with events, prev/next month work |
| 19 | REQ-016 | `PATH` without khal (or uninstall), reload | "Agenda não configurada"; Hoje still lists tasks |
| 20 | REQ-017/019 | Foco: Iniciar | Bar shows the clock; toolbar closed, timer keeps counting |
| 21 | REQ-018 | Link a task, set focus to 1 min, let it finish | Toast, alarm, task shows "● 1" in Hoje |
| 22 | REQ-017 | Focus mode command set to a script that logs its argument | `on` at start, `off` at pause |
| 23 | REQ-020 | Caixa: open link, archive link, copy and delete note | xdg-open opens browser; lists update |
| 24 | REQ-022 | `qs -c noctalia-shell ipc call plugin:daybar open focus` | Toolbar opens on Foco |
| 25 | REQ-023 | Settings: change durations, default calendar, initial tab | Values persist and apply |
| 26 | REQ-021 | Write `{oops` into data.json, reload | Toast about unreadable data; `data.json.bak` exists |
```

**Step 4: Run test to verify it passes**
Run the Step 1 loop again.
Expected: PASS (no output).

**Step 5: Commit**
Run: `/git commit`

---

### Task 24: Google Calendar end-to-end and final verification

**Requirement:** REQ-009, REQ-010, REQ-012, REQ-015, REQ-016, all P1 (verification)
**Depends on:** Tasks 1-23
**Files:**
- Modify: `docs/specs/daybar-mvp/SPEC.md` (Requirement Traceability: P1 rows to `Done`)
- Modify: `docs/specs/daybar-mvp/STATE.md` (`phase: implement-complete`)

**Team:**
- Track: infra
- Implementer: infra-engineer (skills: bash-linux)
- Reviewers: consequences-reviewer

**Step 1: Write the failing test**
Run: `npm test > /tmp/daybar-test.log 2>&1; echo "EXIT=$?"; grep -E "Tests +[0-9]+ passed" /tmp/daybar-test.log`
Then the source-reference guard: `grep -rniE "n[i]ko" --exclude-dir=node_modules --exclude-dir=.git . && echo "FOUND REFERENCE" || echo "clean"`

**Step 2: Run test to verify it fails**
Before the Google setup, smoke rows 11-14 and 19 cannot pass (no khal/vdirsyncer configured).
Expected: FAIL on those rows; everything else already green.

**Step 3: Write minimal implementation**
This is the user-assisted step (OAuth needs a browser): follow README "Google Calendar setup" 1-6 with the user, pick the default calendar in Settings.

**Step 4: Run test to verify it passes**
Run: `npm test` (expect `Tests  124 passed`), the reference guard (expect `clean`), and the full `docs/SMOKE.md` (rows 1-26).
Expected: PASS on every row. Record any failing row in STATE.md instead of marking the REQ done.

**Step 5: Commit**
Run: `/git commit`

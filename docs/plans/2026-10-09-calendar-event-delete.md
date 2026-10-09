# Plan: Delete calendar events

> **Spec:** docs/specs/calendar-event-delete/SPEC.md
> **Depends on:** `inbox-bookmarks-notes` (creates `components/ui/ConfirmButton.qml`; both plans touch `Main.qml`, `components/TodayView.qml`, `i18n/*.json`, `tests/i18n.test.js`). Implement after it is merged.

**Goal:** Delete a Google Calendar event from the Calendar and Today tabs by removing its vdir `.ics` file and syncing, with the anchored confirmation bubble.
**Architecture:** Pure helpers in `utils/eventdelete.js` (khal roots, collections, UID lookup argv, file pick, recurrence, path validation, data cleanup, hidden filter). `Main.qml` loads the collections once, resolves an event to its file on demand and deletes it through `Process` argv, then reuses `requestSync()`. `components/EventDeleteButton.qml` wraps `ConfirmButton` (extended with `ready`/`opened`/`asking`).
**Tech Stack:** QML (noctalia-shell 4.7.x), ES2018 JavaScript, vitest 2, grep (PCRE), khal/vdirsyncer.
**Total Tasks:** 10
**Estimated Complexity:** medium (Standard)

---

## Conventions for every task

- Repo root: `~/dev/projects/noctalia-daybar`. `npm test -- <file>` for one file, `npm test` for the suite; read the `Tests  N passed` line.
- `utils/**/*.js`: `.pragma library`, `.import` for deps, top-level declarations at column 0, no ES modules.
- Every external command is an argv array; never a shell string.
- QML runtime check: restart the shell (`qs -c noctalia-shell kill`, wait until `pgrep -x qs` is empty, start it detached), then `grep -iE "ReferenceError|TypeError|is not a type|non-existent" "$(ls -t /run/user/1000/quickshell/by-id/*/log.log | head -1)"` prints nothing about daybar, plus the task's visual check.
- **Never run the deletion runtime checks on a real event.** Create a throwaway one first: `qs -c noctalia-shell ipc call plugin:daybar capture` → `/e daybar teste exclusao amanhã 10h` (and for recurring checks, create a weekly test event in Google Calendar named `daybar teste recorrente`).
- Commit after every task with `/git commit`. Implementers DO NOT run any git command.
- Do NOT reference any previous or source project in code, comments, docs or commits.

## Dependency graph

```
T1 roots/collections ── T2 lookup/pick ── T3 recurrence/paths/data
T4 today calendar field
T5 i18n keys
T6 ConfirmButton extension
T7 Main services (T1-T3)
T8 EventDeleteButton + TodayView (T4-T7)
T9 CalendarView (T8)
T10 docs, smoke, verification (all)
```

Parallel batches: {T1, T4, T5, T6} → T2 → T3 → T7 → T8 → T9 → T10.

---

### Task 1: khal calendar roots and collections

**Requirement:** REQ-001, REQ-002, REQ-006
**Files:**
- Create: `utils/eventdelete.js`
- Test: `tests/eventdelete.test.js`

**Team:**
- Track: backend
- Implementer: backend-engineer (skills: test-driven-development)
- Reviewers: business-logic-reviewer, test-reviewer

**Step 1: Write the failing test**

`tests/eventdelete.test.js`:
```js
import { describe, it, expect } from "vitest";
import { calendarRoots, collectionsArgs, parseCollections, isReadOnlyCollection, isWritableCalendar } from "../utils/eventdelete.js";

const HOME = "/opt/u";

describe("calendarRoots", () => {
  it("reads every path = line, expanding ~ and stripping /* and trailing slashes", () => {
    const config = `[calendars]\n[[google]]\npath = ~/.local/share/calendars/google/*\ntype = discover\n[[work]]\n  path = "/data/cal/work/"\n[locale]\ntimeformat = %H:%M\n`;
    expect(calendarRoots(config, HOME)).toEqual(["/opt/u/.local/share/calendars/google", "/data/cal/work"]);
  });

  it("drops duplicates and relative paths; empty config gives no roots", () => {
    expect(calendarRoots("path = rel/dir\npath = /a\npath = /a/", HOME)).toEqual(["/a"]);
    expect(calendarRoots("", HOME)).toEqual([]);
    expect(calendarRoots(null, HOME)).toEqual([]);
  });
});

describe("collections", () => {
  it("lists displayname files recursively under the roots", () => {
    expect(collectionsArgs(["/r1", "/r2"])).toEqual(["grep", "-rH", "--include=displayname", "", "--", "/r1", "/r2"]);
  });

  it("parses grep -H output into dir, id and name", () => {
    const out = "/r/abc@virtual/displayname:Feriados no Brasil\n/r/me@gmail.com/displayname:Eventos\n\n";
    expect(parseCollections(out)).toEqual([
      { dir: "/r/abc@virtual", id: "abc@virtual", name: "Feriados no Brasil" },
      { dir: "/r/me@gmail.com", id: "me@gmail.com", name: "Eventos" }
    ]);
  });

  it("treats virtual and holiday collections as read-only", () => {
    expect(isReadOnlyCollection("e1q2@virtual")).toBe(true);
    expect(isReadOnlyCollection("pt.brazilian#holiday@group.v.calendar.google.com")).toBe(true);
    expect(isReadOnlyCollection("me@gmail.com")).toBe(false);
  });

  it("allows deleting only in calendars backed by a writable collection", () => {
    const cols = parseCollections("/r/a@virtual/displayname:Feriados\n/r/me@gmail.com/displayname:Eventos\n");
    expect(isWritableCalendar(cols, "Eventos")).toBe(true);
    expect(isWritableCalendar(cols, "Feriados")).toBe(false);
    expect(isWritableCalendar(cols, "Unknown")).toBe(false);
    expect(isWritableCalendar([], "Eventos")).toBe(false);
  });
});
```

**Step 2: Run test to verify it fails**
Run: `npm test -- tests/eventdelete.test.js`
Expected: FAIL (cannot resolve `../utils/eventdelete.js`).

**Step 3: Write minimal implementation**

`utils/eventdelete.js`:
```js
.pragma library

// Deleting a synced event = removing its .ics file from the khal/vdirsyncer vdir,
// then syncing. Pure helpers; Main.qml runs the commands (argv arrays only).

// Roots from every `path = ...` line of the khal config ("~" expanded, "/*" stripped).
function calendarRoots(configText, home) {
  const roots = [];
  for (const line of String(configText || "").split(/\r?\n/)) {
    const m = /^\s*path\s*=\s*(.+?)\s*$/.exec(line);
    if (!m) continue;
    let p = m[1].replace(/^["']|["']$/g, "");
    if (p.indexOf("~/") === 0) p = home + p.slice(1);
    p = p.replace(/\/\*+$/, "").replace(/\/+$/, "");
    if (p.charAt(0) === "/" && roots.indexOf(p) < 0) roots.push(p);
  }
  return roots;
}

function collectionsArgs(roots) {
  return ["grep", "-rH", "--include=displayname", "", "--"].concat(roots);
}

// "<dir>/displayname:<name>" lines -> [{ dir, id, name }]
function parseCollections(stdout) {
  const out = [];
  for (const line of String(stdout || "").split("\n")) {
    const i = line.indexOf("/displayname:");
    if (i <= 0) continue;
    const dir = line.slice(0, i);
    out.push({ dir: dir, id: dir.slice(dir.lastIndexOf("/") + 1), name: line.slice(i + "/displayname:".length).trim() });
  }
  return out;
}

// Google's generated calendars (holidays, birthdays) reject writes.
function isReadOnlyCollection(id) {
  return /@virtual$/i.test(id) || /#holiday/i.test(id);
}

function isWritableCalendar(collections, calendarName) {
  return collections.some((c) => c.name === calendarName && !isReadOnlyCollection(c.id));
}
```

**Step 4: Run test to verify it passes**
Run: `npm test -- tests/eventdelete.test.js`
Expected: PASS (6 tests).

**Step 5: Commit**
Run: `/git commit`

---

### Task 2: UID lookup argv and file pick

**Requirement:** REQ-002, REQ-005, REQ-006
**Files:**
- Modify: `utils/eventdelete.js`
- Modify: `tests/eventdelete.test.js`

**Team:**
- Track: backend
- Implementer: backend-engineer (skills: test-driven-development, security-guardrails)
- Reviewers: business-logic-reviewer, security-reviewer, test-reviewer

**Step 1: Write the failing test**

Append to `tests/eventdelete.test.js` (extend the import with `escapeRegex, findArgs, parsePaths, pickFile`):
```js
describe("UID lookup", () => {
  it("escapes regex metacharacters", () => {
    expect(escapeRegex("a.b+c(1)[x]")).toBe("a\\.b\\+c\\(1\\)\\[x\\]");
  });

  it("greps the exact UID line, PCRE, .ics only, roots after --", () => {
    expect(findArgs("7799ut.p@google.com", ["/r"])).toEqual(["grep", "-rlP", "--include=*.ics", "-e", "^UID:7799ut\\.p@google\\.com\\r?$", "--", "/r"]);
  });

  it("keeps a hostile UID inside one argument", () => {
    const args = findArgs("x$(rm -rf ~)", ["/r"]);
    expect(args[4]).toBe("^UID:x\\$\\(rm -rf ~\\)\\r?$");
    expect(args.length).toBe(7);
  });

  it("parses grep -l output into .ics paths", () => {
    expect(parsePaths("/r/a/1.ics\n\n/r/b/2.ics\nnoise\n")).toEqual(["/r/a/1.ics", "/r/b/2.ics"]);
  });
});

describe("pickFile", () => {
  const cols = [{ dir: "/r/me", id: "me", name: "Eventos" }, { dir: "/r/fam", id: "fam", name: "Família" }];

  it("returns not-found for no match", () => {
    expect(pickFile([], cols, "Eventos")).toEqual({ ok: false, error: "not-found" });
  });

  it("accepts a single match", () => {
    expect(pickFile(["/r/me/1.ics"], cols, "Eventos")).toEqual({ ok: true, path: "/r/me/1.ics" });
    expect(pickFile(["/r/other/1.ics"], cols, "Eventos")).toEqual({ ok: true, path: "/r/other/1.ics" });
  });

  it("picks the copy in the event's calendar when the UID is in several", () => {
    expect(pickFile(["/r/me/1.ics", "/r/fam/9.ics"], cols, "Família")).toEqual({ ok: true, path: "/r/fam/9.ics" });
  });

  it("refuses when the calendar does not single one out", () => {
    expect(pickFile(["/r/me/1.ics", "/r/fam/9.ics"], cols, "Outra")).toEqual({ ok: false, error: "ambiguous" });
    expect(pickFile(["/r/me/1.ics", "/r/me/2.ics"], cols, "Eventos")).toEqual({ ok: false, error: "ambiguous" });
  });
});
```

**Step 2: Run test to verify it fails**
Run: `npm test -- tests/eventdelete.test.js`
Expected: FAIL (`escapeRegex` is not exported).

**Step 3: Write minimal implementation**

Append to `utils/eventdelete.js`:
```js
function escapeRegex(text) {
  return String(text).replace(/[\\^$.*+?()[\]{}|]/g, "\\$&");
}

// File names are not UIDs, so match the exact UID line (LF or CRLF endings).
function findArgs(uid, roots) {
  return ["grep", "-rlP", "--include=*.ics", "-e", "^UID:" + escapeRegex(uid) + "\\r?$", "--"].concat(roots);
}

function parsePaths(stdout) {
  return String(stdout || "").split("\n").map((l) => l.trim()).filter((l) => /^\/.+\.ics$/.test(l));
}

function dirOf(path) {
  return path.slice(0, path.lastIndexOf("/"));
}

// One match is used as is; several are narrowed to the event's calendar.
function pickFile(paths, collections, calendarName) {
  if (paths.length === 0) return { ok: false, error: "not-found" };
  if (paths.length === 1) return { ok: true, path: paths[0] };
  const dirs = collections.filter((c) => c.name === calendarName).map((c) => c.dir);
  const hits = paths.filter((p) => dirs.indexOf(dirOf(p)) >= 0);
  return hits.length === 1 ? { ok: true, path: hits[0] } : { ok: false, error: "ambiguous" };
}
```

**Step 4: Run test to verify it passes**
Run: `npm test -- tests/eventdelete.test.js`
Expected: PASS.

**Step 5: Commit**
Run: `/git commit`

---

### Task 3: Recurrence, path validation and data cleanup

**Requirement:** REQ-003, REQ-004, REQ-006
**Files:**
- Modify: `utils/eventdelete.js`
- Modify: `tests/eventdelete.test.js`

**Team:**
- Track: backend
- Implementer: backend-engineer (skills: test-driven-development, security-guardrails)
- Reviewers: business-logic-reviewer, security-reviewer, test-reviewer

**Step 1: Write the failing test**

Append (extend the import with `isRecurring, isDeletablePath, deleteArgs, readArgs, removeEventChecks, hideEvents`):
```js
describe("recurrence", () => {
  it("detects RRULE and RECURRENCE-ID, not the words inside other properties", () => {
    expect(isRecurring("BEGIN:VEVENT\nRRULE:FREQ=WEEKLY\nEND:VEVENT")).toBe(true);
    expect(isRecurring("BEGIN:VEVENT\r\nRECURRENCE-ID;TZID=X:20261010T100000\r\nEND:VEVENT")).toBe(true);
    expect(isRecurring("BEGIN:VEVENT\nDESCRIPTION:no RRULE: here\nEND:VEVENT")).toBe(false);
    expect(isRecurring("")).toBe(false);
  });
});

describe("paths and commands", () => {
  const roots = ["/opt/u/.local/share/calendars/google"];

  it("deletes only .ics files strictly inside a root, without dot segments", () => {
    expect(isDeletablePath("/opt/u/.local/share/calendars/google/me/1.ics", roots)).toBe(true);
    expect(isDeletablePath("/opt/u/.local/share/calendars/google/me/../../../x.ics", roots)).toBe(false);
    expect(isDeletablePath("/opt/u/.local/share/calendars/google/me/1.txt", roots)).toBe(false);
    expect(isDeletablePath("/opt/u/.local/share/calendars/googleX/me/1.ics", roots)).toBe(false);
    expect(isDeletablePath("/etc/passwd.ics", roots)).toBe(false);
  });

  it("builds rm and cat argv with the path after --", () => {
    expect(deleteArgs("/r/me/1.ics")).toEqual(["rm", "-f", "--", "/r/me/1.ics"]);
    expect(readArgs("/r/me/1.ics")).toEqual(["cat", "--", "/r/me/1.ics"]);
  });
});

describe("data cleanup", () => {
  it("removes every Today check of the UID", () => {
    const data = { eventChecks: { "u1|2026-10-09": true, "u1|2026-10-10": true, "u2|2026-10-09": true } };
    expect(removeEventChecks(data, "u1").eventChecks).toEqual({ "u2|2026-10-09": true });
    expect(data.eventChecks["u1|2026-10-09"]).toBe(true);
  });

  it("hides every occurrence of hidden UIDs", () => {
    const events = [{ uid: "a" }, { uid: "b" }, { uid: "a" }];
    expect(hideEvents(events, ["a"])).toEqual([{ uid: "b" }]);
    expect(hideEvents(events, [])).toBe(events);
    expect(hideEvents(null, ["a"])).toEqual([]);
  });
});
```

**Step 2: Run test to verify it fails**
Run: `npm test -- tests/eventdelete.test.js`
Expected: FAIL (`isRecurring` is not exported).

**Step 3: Write minimal implementation**

Append to `utils/eventdelete.js`:
```js
// Property names start a line; "RRULE:" inside a DESCRIPTION value does not.
function isRecurring(icsText) {
  return /^(RRULE|RECURRENCE-ID)[;:]/m.test(String(icsText || ""));
}

function isDeletablePath(path, roots) {
  const p = String(path || "");
  if (!/\.ics$/.test(p) || /(^|\/)\.{1,2}(\/|$)/.test(p)) return false;
  return roots.some((r) => p.indexOf(r + "/") === 0);
}

function deleteArgs(path) {
  return ["rm", "-f", "--", path];
}

function readArgs(path) {
  return ["cat", "--", path];
}

function removeEventChecks(data, uid) {
  const checks = {};
  for (const key of Object.keys(data.eventChecks || {})) if (key.indexOf(uid + "|") !== 0) checks[key] = data.eventChecks[key];
  return Object.assign({}, data, { eventChecks: checks });
}

// Same array back when nothing is hidden, so bindings do not churn.
function hideEvents(events, hiddenUids) {
  if (!events) return [];
  if (hiddenUids.length === 0) return events;
  return events.filter((ev) => hiddenUids.indexOf(ev.uid) < 0);
}
```

**Step 4: Run test to verify it passes**
Run: `npm test -- tests/eventdelete.test.js`
Expected: PASS.

**Step 5: Commit**
Run: `/git commit`

---

### Task 4: Today event items carry the calendar name

**Requirement:** REQ-001, REQ-002
**Files:**
- Modify: `utils/today.js`
- Modify: `tests/today.test.js`

**Team:**
- Track: backend
- Implementer: backend-engineer (skills: test-driven-development)
- Reviewers: test-reviewer

**Step 1: Write the failing test**
In `tests/today.test.js`, give the fixture events a `calendar` (e.g. `"Eventos"`) and assert that event items include `calendar: "Eventos"`; task items have `calendar: ""`. Adjust any `toEqual` on whole items to include the new field.

**Step 2: Run test to verify it fails**
Run: `npm test -- tests/today.test.js`
Expected: FAIL (`calendar` missing).

**Step 3: Write minimal implementation**
In `utils/today.js` `eventItems`, add `calendar: ev.calendar || "",` after `uid: ev.uid,`; in the task item builder add `calendar: "",` so every item has the same shape.

**Step 4: Run test to verify it passes**
Run: `npm test -- tests/today.test.js`
Expected: PASS.

**Step 5: Commit**
Run: `/git commit`

---

### Task 5: Translations

**Requirement:** REQ-001 to REQ-005 (UI strings)
**Files:**
- Modify: `i18n/pt.json`, `i18n/en.json`, `tests/i18n.test.js`

**Team:**
- Track: frontend
- Implementer: frontend-engineer (skills: pt-br-accent-fix)
- Reviewers: test-reviewer

**Step 1: Write the failing test**
Add to `DYNAMIC` in `tests/i18n.test.js`:
```js
  "events.confirm-delete", "events.confirm-delete-recurring",
  ...["not-found", "ambiguous", "failed"].map((e) => "events.error." + e),
```

**Step 2: Run test to verify it fails**
Run: `npm test -- tests/i18n.test.js`
Expected: FAIL (missing keys).

**Step 3: Write minimal implementation**
Add an `events` section to both catalogs:
pt:
```json
  "events": {
    "delete": "Excluir evento",
    "locating": "Localizando evento...",
    "confirm-delete": "Excluir este evento?",
    "confirm-delete-recurring": "Este evento se repete. Excluir todas as ocorrências?",
    "error": {
      "title": "Agenda",
      "not-found": "Evento não encontrado",
      "ambiguous": "Não foi possível excluir: evento ambíguo",
      "failed": "Não foi possível excluir o arquivo do evento"
    }
  },
```
en: "Delete event", "Locating event...", "Delete this event?", "This event repeats. Delete all occurrences?", error: "Calendar", "Event not found", "Could not delete: ambiguous event", "Could not delete the event file".
If the `confirm` section (`ok`, `cancel`) does not exist yet (it comes from `inbox-bookmarks-notes` Task 11), add it.

**Step 4: Run test to verify it passes**
Run: `npm test -- tests/i18n.test.js`
Expected: PASS.

**Step 5: Commit**
Run: `/git commit`

---

### Task 6: ConfirmButton: ready state, opened signal, asking flag

**Requirement:** REQ-002
**Files:**
- Modify: `components/ui/ConfirmButton.qml`

**Team:**
- Track: frontend
- Implementer: frontend-engineer (skills: accessibility-guardrails)
- Reviewers: consequences-reviewer

**Step 1: Write the failing test**
Runtime check: in a scratch copy of a view, set `ready: false` on a `ConfirmButton`.

**Step 2: Run test to verify it fails**
Expected: FAIL — log `Cannot assign to non-existent property "ready"`.

**Step 3: Write minimal implementation**
In `components/ui/ConfirmButton.qml` (additive; existing users keep working):
```qml
  // false while the action is being prepared (OK disabled, question can say so).
  property bool ready: true
  // True while the bubble is open: parents that show the button on hover keep it
  // visible, or hiding it would close the bubble under the pointer.
  readonly property bool asking: bubble.visible
  signal opened

  function close() {
    bubble.close();
  }
```
In the `Popup`: `onOpened: { cancelButton.forceActiveFocus(); root.opened(); }`.
On the OK `PillButton`: `enabled: root.ready`.

**Step 4: Run test to verify it passes**
Restart the shell; existing delete buttons (notes, bookmarks) behave as before; the scratch `ready: false` button shows a disabled OK. Remove the scratch code. No `daybar` errors.

**Step 5: Commit**
Run: `/git commit`

---

### Task 7: Main services (collections, resolve, delete)

**Requirement:** REQ-001 to REQ-006
**Files:**
- Modify: `Main.qml`

**Team:**
- Track: frontend
- Implementer: frontend-engineer (skills: security-guardrails)
- Reviewers: business-logic-reviewer, security-reviewer, consequences-reviewer

**Step 1: Write the failing test**
Runtime check: `qs -c noctalia-shell ipc call plugin:daybar open calendar`, then check the log while hovering an event row once Task 9 lands; for this task, add a temporary `Component.onCompleted: console.log("daybar roots", JSON.stringify(root.calendarRootsList))` after the new properties.

**Step 2: Run test to verify it fails**
Expected: FAIL — `calendarRootsList` undefined.

**Step 3: Write minimal implementation**

Add `import "utils/eventdelete.js" as EventDelete` and, in the agenda section:
```qml
  readonly property string khalConfigPath: (Quickshell.env("XDG_CONFIG_HOME") || (Quickshell.env("HOME") + "/.config")) + "/khal/config"
  property var calendarRootsList: []
  property var collections: []
  property var hiddenEventUids: []
  // CalendarService.events without the events deleted in this session (until reload).
  readonly property var visibleEvents: EventDelete.hideEvents(CalendarService.events, hiddenEventUids)

  function canDeleteEvent(calendarName) {
    return calendarReady && EventDelete.isWritableCalendar(collections, calendarName);
  }

  Process {
    id: khalConfigProcess
    command: EventDelete.readArgs(root.khalConfigPath)
    running: root.calendarReady
    stdout: StdioCollector {
      onStreamFinished: {
        root.calendarRootsList = EventDelete.calendarRoots(text, Quickshell.env("HOME"));
        if (root.calendarRootsList.length > 0) {
          collectionsProcess.command = EventDelete.collectionsArgs(root.calendarRootsList);
          collectionsProcess.running = true;
        }
      }
    }
  }

  Process {
    id: collectionsProcess
    stdout: StdioCollector {
      onStreamFinished: root.collections = EventDelete.parseCollections(text)
    }
  }

  Component {
    id: eventLookup
    Process {
      property var done: null
      stdout: StdioCollector {
        id: lookupOut
      }
      onExited: {
        done(lookupOut.text);
        destroy();
      }
    }
  }

  function runOnce(command, done) {
    const p = eventLookup.createObject(root, { command: command, done: done });
    p.running = true;
  }

  // done({ ok, path, recurring } | { ok: false, error })
  function resolveEvent(uid, calendarName, done) {
    if (calendarRootsList.length === 0)
      return done({ ok: false, error: "not-found" });
    runOnce(EventDelete.findArgs(uid, calendarRootsList), function (out) {
      const pick = EventDelete.pickFile(EventDelete.parsePaths(out), root.collections, calendarName);
      if (!pick.ok) {
        if (pick.error === "not-found")
          CalendarService.loadEvents();
        return done(pick);
      }
      runOnce(EventDelete.readArgs(pick.path), function (ics) {
        done({ ok: true, path: pick.path, recurring: EventDelete.isRecurring(ics) });
      });
    });
  }

  Component {
    id: eventRemover
    Process {
      property string uid: ""
      onExited: function (exitCode) {
        root.onEventFileRemoved(uid, exitCode === 0);
        destroy();
      }
    }
  }

  function deleteEvent(uid, path) {
    if (!EventDelete.isDeletablePath(path, calendarRootsList)) {
      ToastService.showWarning(pluginApi?.tr("events.error.title"), pluginApi?.tr("events.error.failed"));
      return;
    }
    const p = eventRemover.createObject(root, { uid: uid, command: EventDelete.deleteArgs(path) });
    p.running = true;
  }

  function onEventFileRemoved(uid, ok) {
    if (!ok) {
      ToastService.showWarning(pluginApi?.tr("events.error.title"), pluginApi?.tr("events.error.failed"));
      return;
    }
    hiddenEventUids = hiddenEventUids.concat([uid]);
    commit(EventDelete.removeEventChecks(data, uid));
    requestSync();
  }
```
Note: `rm -f` exits 0 even when the file is already gone; that is fine (the event is gone either way).

**Step 4: Run test to verify it passes**
Restart the shell; the log shows `daybar roots ["$HOME/.local/share/calendars/google"] (home expanded)`. Remove the temporary log line. No `daybar` errors.

**Step 5: Commit**
Run: `/git commit`

---

### Task 8: EventDeleteButton and Today rows

**Requirement:** REQ-001 to REQ-005
**Files:**
- Create: `components/EventDeleteButton.qml`
- Modify: `components/TodayView.qml`

**Team:**
- Track: frontend
- Implementer: frontend-engineer (skills: accessibility-guardrails)
- Reviewers: business-logic-reviewer, test-reviewer

**Step 1: Write the failing test**
Runtime check: hover the test event `daybar teste exclusao` in Today.

**Step 2: Run test to verify it fails**
Expected: FAIL — no trash on event rows.

**Step 3: Write minimal implementation**

`components/EventDeleteButton.qml`:
```qml
import QtQuick
import qs.Services.UI
import "ui"

// Trash for a synced event: locates its .ics when the bubble opens, then asks
// (recurring events say all occurrences go), then deletes through Main.
ConfirmButton {
  id: root

  property var pluginApi: null
  property var mainInstance: null
  property string uid: ""
  property string calendar: ""
  property var target: null   // { path, recurring } once located

  function tr(key) {
    return pluginApi ? pluginApi.tr(key) : key;
  }

  icon: "trash"
  tooltipText: tr("events.delete")
  ready: target !== null
  question: target === null ? tr("events.locating") : tr(target.recurring ? "events.confirm-delete-recurring" : "events.confirm-delete")
  okText: tr("confirm.ok")
  cancelText: tr("confirm.cancel")

  onOpened: {
    target = null;
    const asked = uid;
    mainInstance.resolveEvent(uid, calendar, function (r) {
      if (asked !== root.uid)
        return;
      if (!r.ok) {
        root.close();
        ToastService.showWarning(root.tr("events.error.title"), root.tr("events.error." + r.error));
        return;
      }
      root.target = r;
    });
  }

  onConfirmed: {
    if (target)
      mainInstance.deleteEvent(uid, target.path);
  }
}
```

`components/TodayView.qml`:
- `items` builds from `mainInstance.visibleEvents` instead of `CalendarService.events`.
- In the row's trailing slot (where the task trash lives), add for events:
```qml
            Item {
              implicitWidth: Math.round(24 * Style.uiScaleRatio)
              implicitHeight: implicitWidth
              visible: row.modelData.kind === "event"

              EventDeleteButton {
                id: eventTrash
                anchors.fill: parent
                visible: (row.hovered || activeFocus || asking) && (root.mainInstance?.canDeleteEvent(row.modelData.calendar) ?? false)
                pluginApi: root.pluginApi
                mainInstance: root.mainInstance
                uid: row.modelData.uid
                calendar: row.modelData.calendar
              }
            }
```
  Keep the task trash slot for tasks (`visible: row.modelData.kind === "task"` on its `Item`), so every row keeps the same trailing width. Also apply `|| asking` to the task `ConfirmButton`/trash if it is a `ConfirmButton` (same hover-hides-bubble problem).

**Step 4: Run test to verify it passes**
Restart the shell. Hover `daybar teste exclusao` in Today: trash appears; click → bubble "Localizando evento..." then "Excluir este evento?"; Cancel leaves it; OK removes the row at once; after the sync the event is gone from Google Calendar (check on the phone or web). Hover a holiday on its day: no trash. No `daybar` errors.

**Step 5: Commit**
Run: `/git commit`

---

### Task 9: Calendar tab day list

**Requirement:** REQ-001, REQ-004
**Files:**
- Modify: `components/CalendarView.qml`

**Team:**
- Track: frontend
- Implementer: frontend-engineer (skills: accessibility-guardrails)
- Reviewers: test-reviewer

**Step 1: Write the failing test**
Runtime check: select the day of `daybar teste recorrente` in the Calendar tab and hover it.

**Step 2: Run test to verify it fails**
Expected: FAIL — no trash in the day list.

**Step 3: Write minimal implementation**
In `components/CalendarView.qml`:
- `cells` and `dayEvents` read `root.mainInstance ? root.mainInstance.visibleEvents : CalendarService.events` instead of `CalendarService.events`.
- Wrap each day-list row: replace the `RowLayout` delegate with a `ListRow` (import `"ui"`), keep the time and summary `NText`s inside it, and append:
```qml
          Item {
            implicitWidth: Math.round(24 * Style.uiScaleRatio)
            implicitHeight: implicitWidth

            EventDeleteButton {
              anchors.fill: parent
              visible: (dayRow.hovered || activeFocus || asking) && (root.mainInstance?.canDeleteEvent(dayRow.modelData.calendar) ?? false)
              pluginApi: root.pluginApi
              mainInstance: root.mainInstance
              uid: dayRow.modelData.uid
              calendar: dayRow.modelData.calendar
            }
          }
```
  (give the `ListRow` `id: dayRow` and `required property var modelData`).

**Step 4: Run test to verify it passes**
Restart the shell. On the recurring test event: bubble says "Este evento se repete. Excluir todas as ocorrências?"; OK removes it from every day in the grid (dots gone) at once and from Google after sync. Holidays: no trash. No `daybar` errors.

**Step 5: Commit**
Run: `/git commit`

---

### Task 10: Docs, smoke rows, verification

**Requirement:** all
**Files:**
- Modify: `README.md` (one line under "Google Calendar setup": events can be deleted from the panel; read-only calendars excluded)
- Modify: `docs/SMOKE.md`
- Modify: `docs/specs/daybar-mvp/SPEC.md` (Out of Scope row "Editing or deleting Google events" → "Editing Google events"; deleting is covered by `calendar-event-delete`)
- Modify: `docs/specs/calendar-event-delete/SPEC.md` (Traceability → Done), `docs/specs/calendar-event-delete/STATE.md` (`phase: implement-complete`)

**Team:**
- Track: infra
- Implementer: infra-engineer (skills: technical-writer)
- Reviewers: consequences-reviewer

**Step 1: Write the failing test**
Run: `for i in 1 2 3 4 5 6; do grep -q "ED-REQ-00$i" docs/SMOKE.md || echo "missing ED-REQ-00$i"; done`
Expected: FAIL (6 lines).

**Step 2: Run test to verify it fails**
Same loop.

**Step 3: Write minimal implementation**
Append to `docs/SMOKE.md` an "Event delete" table (IDs prefixed `ED-`):

| # | REQ | Step | Expected |
|---|-----|------|----------|
| 46 | ED-REQ-001 | Hover a normal event, then a holiday | Trash on the event; none on the holiday |
| 47 | ED-REQ-002 | Click the trash | "Localizando evento..." with OK disabled, then the question |
| 48 | ED-REQ-003 | Same on `daybar teste recorrente` | "Este evento se repete. Excluir todas as ocorrências?" |
| 49 | ED-REQ-004 | OK on `daybar teste exclusao`; offline once | Row gone at once; gone in Google after sync; offline shows the sync warning and it does not come back |
| 50 | ED-REQ-005 | Delete the event on the phone, then try in Daybar | "Evento não encontrado"; calendar reloads |
| 51 | ED-REQ-006 | `ps -ef | grep -E "grep -rlP|rm -f --"` while deleting | argv processes only, no `sh -c` |

**Step 4: Run test to verify it passes**
Run the Step 1 loop (no output), `npm test > /tmp/daybar-test.log 2>&1; echo "EXIT=$?"; grep -E "Tests +[0-9]+ passed" /tmp/daybar-test.log` (EXIT=0), then walk SMOKE rows 46-51 with test events only.

**Step 5: Commit**
Run: `/git commit`

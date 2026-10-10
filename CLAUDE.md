# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Status

Pre-implementation. The repo holds only the RPI artifacts; code is built task by task from the plan:

- Spec: `docs/specs/daybar-mvp/SPEC.md` (REQ-001..026, architecture decisions, edge cases, grilling log)
- Plan: `docs/plans/2026-10-09-daybar-mvp.md` (24 TDD tasks with full file contents, dependency graph, parallel batches)
- State: `docs/specs/daybar-mvp/STATE.md`

The plan is the source of truth for file contents and order. When code and plan disagree, check the spec before changing either.

## What it is

`daybar` is a Noctalia Shell plugin (noctalia-shell 4.7.x, Quickshell/QML, run as `qs -c noctalia-shell`) with a centered quick-capture overlay (task, event, reminder, note, link, calculation) and a bar toolbar with Calendar, Today, Focus (pomodoro) and Inbox tabs. Noctalia 5 is not a target: its plugins are Luau scripts with a `plugin.toml` manifest, a different system from the v4 QML plugins (tested on noctalia-shell 4.7.7).

## Commands

```bash
npm install
npm test                          # full vitest suite
npm test -- tests/when.test.js    # single file
```

Read the `Tests  N passed` line; never trust the exit code of a piped command.

Runtime checks (QML has no automated harness):

```bash
ln -s ~/dev/projects/noctalia-daybar ~/.config/noctalia/plugins/daybar   # once
qs -c noctalia-shell kill; qs -c noctalia-shell -d                       # reload shell
qs log -c noctalia-shell | grep -i daybar | tail -50                     # read errors
qs -c noctalia-shell ipc call plugin:daybar capture                      # also: toggle, open <calendar|today|focus|inbox>
```

Manual end-to-end checklist: `docs/SMOKE.md` (one row per P1 REQ).

## Architecture

**Two layers, strictly separated.**

- `utils/**/*.js`: all logic, as QML JavaScript libraries. Pure functions, unit-tested with vitest (TDD).
- QML (`Main.qml`, `Panel.qml`, `BarWidget.qml`, `Settings.qml`, `CaptureWindow.qml`, `components/*View.qml`): thin UI and process wiring only. Anything testable belongs in `utils/`.

**The test transform** (`vitest.config.js`, plugin `qml-library-to-esm`) makes QML libraries importable from Node at test time only: strips `.pragma library`, rewrites `.import "x.js" as X` to `import * as X from "./x.js"`, and appends `export { ... }` for every top-level `function`/`const`/`let`/`var` found by a column-0 regex. Consequences:

- Every `utils/` file starts with `.pragma library`; cross-file deps use `.import` paths relative to the importing file.
- Top-level declarations MUST start at column 0, or they are silently not exported. Nested code is indented.
- No ES `import`/`export` syntax in `utils/`; the files on disk must stay valid QML libraries.

**Services live in `Main.qml`** (data store, agenda writes, reminders, pomodoro, capture overlay, IPC target `plugin:daybar`) so timers and reminders keep running with the panel closed. UI files reach them via `pluginApi.mainInstance`.

**Capture handler registry.** One file per type in `utils/capture/<type>.js` exposing `detect`, `preview`, `commit`, wired in `utils/capture/registry.js`. Adding a type means one handler file plus its test, no core changes. Inference order: prefix (`/e`, `/l`, `/n`), then `=`, then a lone URL as link, then task.

**Capture overlay** is its own `PanelWindow` on `WlrLayer.Overlay` with exclusive keyboard focus, because the plugin's single panel slot is the toolbar.

**Calendar** is read through Noctalia's `CalendarService` (khal provider, -14/+31 day window, 5-minute refresh, gated by `Settings.data.location.showCalendarEvents`). Writes go through `khal new` then `vdirsyncer sync`, then a `CalendarService` reload. Tasks are local only (Google CalDAV has no VTODO); `source`/`externalId` fields are reserved for a future Google Tasks sync.

**Persistence**: data in `~/.local/share/noctalia-daybar/data.json` (`version` field, `FileView` atomic writes, debounced). Corrupt file is renamed to `.bak` and the plugin starts empty. `pluginSettings` holds configuration only, never data.

**Key utils**: `when.js` (own pt-BR date/time parser: weekdays mean the next occurrence, a past time without date means tomorrow), `calc.js` (shunting-yard over whitelisted tokens, postfix `%` is percent not modulo), `today.js` (events by time, then timed tasks, then untimed; overdue flagged; event check state keyed `uid+date`), `pomodoro.js` (state machine forked from the MIT pomodoro plugin), `khal.js` (argv builders).

## Hard constraints

- No `eval`, no `Function`. Noctalia's `AdvancedMath.js` is off-limits for this reason.
- External commands are argv arrays (`Process.command`, `Quickshell.execDetached`), never shell strings. User text goes in as separate args (khal argument-injection edge case).
- Do not reference any previous or source project in code, comments, docs or commits. The only allowed attribution is the forked pomodoro plugin's MIT notice in `THIRD_PARTY.md` (keep it and `alarm.mp3`). Task 24 runs a grep guard for this.
- UI strings go through i18n (`i18n/pt.json`, `i18n/en.json`, via `pluginApi.tr(key)`); an i18n coverage test enforces both files stay in sync.
- Runtime dependencies: `khal`, `vdirsyncer`, `wl-clipboard`, `xdg-utils`. Without khal, the Calendar tab shows "Calendar not configured" and everything else must still work.

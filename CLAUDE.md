# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Status

Noctalia **v5** plugin (Luau, `plugin.toml`, `plugin_api = 32`), version 0.4.0, ported from the v4 QML plugin by the `daybar-v5` RPI feature:

- Spec: `docs/specs/daybar-v5/SPEC.md` (REQ-001..034, known gaps)
- Plan: `docs/plans/2026-10-16-daybar-v5.md` (30 tasks)
- State: `docs/specs/daybar-v5/STATE.md`

The v4 code (QML, `utils/*.js`, vitest) is frozen at 0.3.1 on branch `legacy-v4`. Read it with `git show legacy-v4:<path>` when checking parity. The older `docs/specs/*` and `docs/plans/*` describe v4 behavior, which is the parity baseline.

## Commands

```bash
./run-tests                                  # full Luau suite + tests/*.test.sh guards
./run-tests tests/when.test.luau             # one file
noctalia plugins lint .                      # manifest and entry checks
```

Read the `N passed, M failed` and `guards: ok` lines; never trust the exit code of a piped command. `run-tests` exports `TZ=America/Sao_Paulo`.

Runtime (installed as a symlink in `~/.local/share/noctalia/plugins/daybar`):

```bash
noctalia msg plugins enable nandomoreirame/daybar
noctalia msg plugin nandomoreirame/daybar:core all capture   # also: toggle, open <tab>
noctalia msg panel-toggle nandomoreirame/daybar:toolbar
```

Editing a file hot-reloads the owning entry. Manual end-to-end checklist: `docs/SMOKE.md`.

## Architecture

**Layers.**

- `lib/**/*.luau`: pure logic, one table per module, no host globals (`noctalia`, `ui`, `panel`, ...). Unit-tested with the Luau harness.
- `views/*.luau`: UI tree builders. They get `ui`, `tr`, the published `view` and a `send` function through a context table, because modules loaded with `require` do not see the host globals in tests.
- Entries at the root: `service.luau` (`[[service]] core`), `widget.luau` (bar), `toolbar.luau`, `capture.luau`, `note.luau`, `clockpin.luau` (panels), `clockdesk.luau` (desktop widget `clockface`). Entries are thin.

**The service owns all I/O (AD-201).** Files, processes (`khal`, `vdirsyncer`, `grep`, `xdg-open`, the focus mode command), HTTP, sound, timers, reminders and notifications. It publishes one plain `view` value on `noctalia.state` after every change (`lib/view.luau`).

**Commands go through an outbox (AD-202).** An entry pushes `{ seq, name, args }` to `cmd.<entry>` (`views/client.luau`); the service runs each seq once (`lib/outbox.luau`, `Outbox.take`) and answers on `ack.<entry>` = `{ seq, ok, error, result }`. A handler returns `ok, error, result`, or `PENDING` and calls `reply` later. On start the service seeds `lastSeen` from the last published ack so a restart does not rerun commands.

**Capture.** `lib/capture/<type>.luau` handlers wired in `lib/capture/registry.luau`. The capture panel resolves the text for the preview; `commit { text, type }` makes the service resolve it again and run the action (`CAPTURE_ACTIONS` in `service.luau`). A calculation is copied by the panel itself.

**Agenda.** `khal printcalendars` decides availability; `khal list --json` over today-14..today+31, reloaded every 5 minutes, parsed by `lib/khalread.luau`. Writes go through a serial `WriteQueue`: `khal new`, then `vdirsyncer sync`, then a reload. Delete: read `~/.config/khal/config`, scan collections, `grep -rlF UID:<uid>` for the `.ics`, confirm, `noctalia.removeFile` only when `EventDelete.isDeletablePath`.

**Clocks.** Running clocks keep a deadline (`endsAtMs`); entries compute the digits from it (`lib/clock.luau`, `views/clockfmt.luau`). Only one of pomodoro and timer runs at a time.

**Persistence.** `pluginDataDir()/data.json`, schema v2 (same as v4), debounced 500 ms, atomic (`.tmp` + `renameFile`). Corrupt file → `.bak`. First start imports the v4 file once.

## Hard constraints

- No `load`, `loadstring`, `getfenv`, `setfenv` in plugin code; external commands are argv tables, never strings. `tests/guards.test.sh` enforces both, plus no root QML, `package.json` or `utils/`.
- **Luau `os.time{...}` is UTC.** Use the local-time helpers in `lib/dates.luau` (`parseIsoDate`, `addDays`, `toDate`, `addMinutes`); never call `os.time` with a table in lib code.
- Lua patterns have no `|` and no quantifiers on groups: port JS regexes with branches or small scanners.
- User text reaches commands only as separate argv items; URLs opened with `xdg-open` must pass `Markdown.isOpenableLink`; preview fetches and image downloads must pass `Url.isPublicHttpUrl`.
- Do not reference any previous or source project in code, comments, docs or commits. The only allowed attribution is the forked pomodoro plugin's MIT notice in `THIRD_PARTY.md` (keep it and `alarm.mp3`).
- UI strings go through `noctalia.tr` with both `translations/en.json` and `translations/pt-BR.json`; `tests/i18n.test.luau` keeps them in sync.
- Never write an absolute `/home/<user>` path in code, tests or docs (a global pre-commit hook rejects it).

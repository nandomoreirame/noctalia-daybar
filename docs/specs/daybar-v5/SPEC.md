# SPEC: daybar-v5

**Status:** approved (2026-10-16) · **Depth:** Deep · **Repo:** `noctalia-daybar`
**Supersedes for `main`:** the v4 specs `daybar-mvp`, `focus-timer`, `focus-clock-detach`,
`inbox-bookmarks-notes`, `calendar-event-delete` (their behavior is the parity baseline; the
v4 code is frozen on branch `legacy-v4` at 0.3.1).

## Summary

Port `daybar` 0.3.1 from Noctalia Shell v4 (QML, `manifest.json`, `qs -c noctalia-shell`) to
Noctalia **v5** (Luau entry scripts, `plugin.toml`, `noctalia` 5.2.x and 5.3.x), keeping every 0.3.1
behavior: quick capture overlay (task, event, reminder, note, link, calculation, timer,
pomodoro), bar widget, toolbar with Calendar, Today, Focus, Bookmarks and Notes tabs, note
window, detached clock, khal/vdirsyncer agenda with event delete and details. v4 code is
removed from `main`. The user's v4 data is imported once.

## Goals

- Feature parity with 0.3.1 on Noctalia 5.3.0 (and 5.2.1), minus the documented Known gaps.
- Pure logic in `lib/*.luau`, ported one to one from `utils/*.js` with their vitest cases,
  run by `./run-tests` (Luau CLI). No Node in the repo.
- One `[[service]]` owns all I/O, timers and data; UI entries render from a state view.
- Same hard constraints as v4: no dynamic code evaluation, external commands as argv arrays,
  i18n for every UI string, no reference to any previous or source project.

## Non-goals

- Noctalia v4 support on `main` (that is `legacy-v4`).
- Community-plugins submission (`thumbnail.webp`, catalog PR). README follows the community
  layout anyway because it costs nothing.
- Reading Noctalia's own calendar service (not exposed to plugins, see W4).
- Google Tasks sync (still reserved through `source`/`externalId`).
- Writing back to the v4 data file or removing it.

## Verified Claims

| # | Claim | Evidence |
|---|-------|----------|
| W1 | Installed host is `noctalia` 5.3.0 (spec first verified on 5.2.1); levels up to 34 exist (33 `scroll-reveal-key`, 34 `widget-hover-highlight`), neither needed, so 32 keeps 5.2.1 compatible | `noctalia --version`; `docs/plugin-api.json` and `src/scripting/plugin_api.h` in `~/.cache/noctalia-v5-src` |
| W2 | Needed API levels: closures 9, `keyboard_focus` 10, `persistent` 11, `nowMs` 12, `capture_keys` 13, `openSettings` 15, sound 20, `ui.markdown`/`submitOnEnter` 21, `require` 22, argv `runAsync` 24, context menu 28, panel `layer` 30, container tooltip 32 → `plugin_api = 32` | `plugin-api.json` |
| W3 | Entries are isolated VMs sharing plain values through `noctalia.state.set/get/watch` (in memory, process lifetime) | `runtime-api.mdx` "Sharing state across entries" |
| W4 | Noctalia 5 has its own calendar service (CalDAV/Google/vdir, read-only) but no plugin API for it | `services/calendar.mdx`; no calendar symbol in `runtime-api.mdx` |
| W5 | `khal list --json <field> ... <from> <to>` prints one JSON array per day line, fields `uid`, `calendar`, `all-day` (`"True"`/`"False"`), `start-date`, `start-time` (empty when all-day), `end-date`, `end-time`, `location`, `url`, `description`, `repeat-symbol` | probe on khal 0.14.1 |
| W6 | Panels: size host-owned (`width`/`height`), no runtime resize; `placement`, `position`, `layer` are host-injected per-entry settings the plugin cannot write | `declarative-ui.mdx` "panel.*", `runtime-api.mdx` `openSettings` |
| W7 | `capture_keys` chords reach `onKey` even with a focused `ui.input` unless the key is printable; Escape always closes the panel and cannot be captured | `declarative-ui.mdx` "Handling keys directly" |
| W8 | `ui.input` is uncontrolled: `value` seeds once; `focus = true` grabs focus on creation; a fresh `key` recreates it (used to clear) | `declarative-ui.mdx` |
| W9 | `ui.markdown` has no link activation and no image rendering | `src/ui/controls/markdown_view.cpp` (no link/image handling) |
| W10 | No arc/ring primitive in `ui.*` (only `ui.progress`, `ui.graph`, `ui.box`) | `declarative-ui.mdx` controls table |
| W11 | Persistent panels: floating only, `dismiss_on_outside_click = false` required, no exclusive focus; `keyboard_focus = "none"` never takes focus | `declarative-ui.mdx` "Persistent panels" |
| W12 | Desktop widgets are placed and sized by the user in the desktop-widgets editor; the plugin cannot open or close them | `declarative-ui.mdx` "Position is host-owned" |
| W13 | `noctalia.sound` decodes with libsndfile; the installed libsndfile links `libmpg123`, so `alarm.mp3` decodes | `src/pipewire/sound_player.cpp`; `ldd /usr/lib/libsndfile.so.1` |
| W14 | `noctalia.http` has no timeout or size option; `noctalia.download(url, dest, cb)` has no size cap | `runtime-api.mdx` "HTTP and downloads" |
| W15 | `noctalia.togglePanel(id)` takes no context; `noctalia msg panel-toggle <id>` works from a keybind | `runtime-api.mdx`, `declarative-ui.mdx` |
| W16 | `noctalia.clipboardText()` and `noctalia.copyToClipboard(text, mime)` are native | `runtime-api.mdx` |
| W17 | `pluginDataDir()` survives updates; `pluginDir()` is rewritten on update; `writeFile` + `renameFile` give an atomic replace | `runtime-api.mdx` "Persisting data" |
| W18 | The aibar v5 repo has a working Luau harness (`run-tests`, `tests/support/*`: runner, assert, module loader, entry loader, recorded `noctalia` mock) | `~/dev/projects/noctalia-plugins/aibar` |
| W19 | `noctalia.json.decode` maps JSON `null` to `nil` and Luau tables have no key order | aibar-v5 W9 |

## Requirements

### Manifest, layout and tooling

- **[REQ-001]** The plugin SHALL ship a `plugin.toml` with `id = "nandomoreirame/daybar"`,
  `name = "Daybar"`, `version = "0.4.0"`, `plugin_api = 32`, MIT, a description of at most 120
  characters, `dependencies = ["khal", "vdirsyncer", "xdg-utils"]`, and these entries:
  `[[service]] core` (`service.luau`); `[[widget]] bar` (`widget.luau`, `[widget.actions] middle = "none"`); `[[panel]] toolbar`
  (`toolbar.luau`, 680x450, `placement = "attached"`, `open_near_click = true`);
  `[[panel]] capture` (`capture.luau`, 640x200, `placement = "floating"`, `position = "center"`,
  `layer = "overlay"`, `keyboard_focus = "exclusive"`, `capture_keys = ["tab", "shift+tab", "shift+Return"]`);
  `[[panel]] note` (`note.luau`, 1100x800, floating, center, `keyboard_focus = "exclusive"`,
  `capture_keys = ["ctrl+e", "ctrl+s"]`); `[[panel]] clock` (`clockpin.luau`, 200x200,
  `persistent = true`, `keyboard_focus = "none"`, `dismiss_on_outside_click = false`,
  `position = "top_right"`, `layer = "overlay"`); `[[desktop_widget]] clockface`
  (`clockdesk.luau`). `noctalia plugins lint .` SHALL pass.
- **[REQ-002]** Before any v5 file lands, branch `legacy-v4` SHALL point at the 0.3.1 commit.
  Then all QML, `utils/`, `components/`, `i18n/`, `manifest.json`, `settings.json`,
  `package*.json`, `vitest.config.js`, `coverage/` and `tests/*.test.js` SHALL be removed from
  `main`. `alarm.mp3`, `THIRD_PARTY.md` and `LICENSE` stay.
- **[REQ-003]** `./run-tests` and `tests/support/` SHALL be adapted from the Luau harness in
  W18 (no mention of the source repo in any file), run with `TZ=America/Sao_Paulo`, wrap
  `lib/**/*.luau` (including `lib/capture/`), `plugin.toml`, `translations/*.json` and `tests/fixtures/*` as string modules, and print
  `N passed, M failed`. The `noctalia` mock SHALL record every call and add what daybar uses:
  `runAsync` argv with scripted results, `http`, `download`, `sound.load/play`,
  `clipboardText`, `copyToClipboard`, `writeFile`, `renameFile`, `removeFile`, `mkdirAll`,
  `readFile`, `fileExists`, `listDir`, `commandExists`, `togglePanel`, `openSettings`,
  `notify`, `notifyError`, plus `panel.render/close/setWantsSecondTicks`,
  `barWidget.render/setTooltip/isVertical` and `desktopWidget.render/setWantsSecondTicks`.

### Pure logic (lib)

- **[REQ-004]** Every pure module of `utils/` SHALL be ported to `lib/<name>.luau` with the
  same behavior and its vitest cases ported to `tests/<name>.test.luau`: `when`, `calc`,
  `duration`, `dates`, `month`, `today`, `tasks`, `events`, `eventinfo`, `eventdelete`,
  `reminders`, `pomodoro`, `timers`, `clock`, `focuslog`, `format`, `text`, `url`,
  `bookmarks`, `pagemeta`, `notes`, `markdown`, `tabs`, `store`, `writequeue`, `fetchpool`,
  `khal`, and `capture/<type>` + `capture/registry`. `cmd.js` and `fetch.js` are dropped
  (replaced by `noctalia.removeFile` and `noctalia.http`/`download`); `mdrender.js` is
  replaced by REQ-031. Lib modules SHALL NOT touch host globals.
- **[REQ-005]** Dates SHALL use local time through `os.time`/`os.date` with the same
  semantics as the v4 `Date` code (weekday = next occurrence, past time without date =
  tomorrow, ISO `YYYY-MM-DD`/`HH:MM` strings, event `start`/`end` in epoch seconds).
- **[REQ-006]** `lib/calc.luau` SHALL keep the shunting-yard evaluator over whitelisted
  tokens (postfix `%` is percent); no `load`, `loadstring`, `getfenv` or `setfenv` in plugin
  code (root `*.luau` and `lib/**`), enforced by `tests/guards.test.sh` (run by `./run-tests`), which scans those files (the
  test harness under `tests/support/` is exempt).

### Settings

- **[REQ-007]** Plugin-level settings, labels and descriptions as translation keys:
  `work_duration` (int 25, 1..180), `short_break_duration` (int 5, 1..60),
  `long_break_duration` (int 15, 1..120), `sessions_before_long_break` (int 4, 1..12),
  `daily_pomodoro_goal` (int 8, 0..24), `auto_start_breaks` (bool false), `auto_start_work`
  (bool false), `play_sound` (bool true), `focus_mode_command` (string ""),
  `default_calendar` (string "", description says it must match `khal printcalendars`),
  `initial_tab` (select `last`, `calendar`, `today`, `focus`, `bookmarks`, `notes`; default
  `last`), `fetch_previews` (bool true). The service defines `onConfigChanged()` and applies
  new values without restarting timers. The pinned clock corner is the host-injected
  `clock_position` panel setting.

### Data

- **[REQ-008]** Data SHALL live in `pluginDataDir()/data.json` with the v4 schema
  (`version: 2`, `tasks`, `eventChecks`, `reminders`, `bookmarks`, `notes`, `focusLog`,
  `recentTimers`, `ui.lastTab`, `ui.clockOverlay`). Writes are debounced (500 ms after the
  last change) and atomic (`data.json.tmp` then `renameFile`). A missing file starts empty and
  is created on the first write. A corrupt file is renamed to `data.json.bak`, the service
  starts empty and calls `notifyError`.
- **[REQ-009]** WHEN the service starts and `pluginDataDir()/data.json` does not exist and
  `~/.local/share/noctalia-daybar/data.json` does THEN it SHALL import it through
  `Store.parse` (same migrations), copy each bookmark thumbnail from
  `~/.cache/noctalia-daybar/thumbs/<id>` to `pluginDataDir()/thumbs/<id>` when present, write
  the v5 file, and `notify` once with the imported counts. The v4 files are never modified. A
  corrupt v4 file is skipped (start empty, `notifyError`, no `.bak`). `ui.clockWindow` is
  dropped.

### Service and state channel

- **[REQ-010]** The service SHALL publish one plain `view` value on `noctalia.state` after
  every change: tasks, eventChecks, reminders, bookmarks (with local thumb paths), notes,
  focusLog, recentTimers, ui, settings snapshot, calendar `{ available, calendars, events
  (window), writing, syncFailed }`, pomodoro and timer state with `endsAtMs`/`remainingMs`,
  and `rev`. Entries SHALL render only from `view` and compute countdowns from `endsAtMs`
  with their own second ticks; the service does not republish every second.
- **[REQ-011]** Entries SHALL send commands through an outbox: `noctalia.state` key
  `cmd.<entry>` holds a list of `{ seq, name, args }` with strictly increasing `seq` (seeded
  from `nowMs()`); the service runs each `seq` it has not seen once, in order, and publishes
  `ack.<entry> = { seq, ok, error, result }`; the entry trims acknowledged items. Unknown
  command names are logged and acked with `error = "unknown-command"`.
- **[REQ-012]** The service SHALL handle `onIpc` events `toggle`, `open <tab>` and `capture`
  (`noctalia msg plugin nandomoreirame/daybar:core all <event> [payload]`). `open <tab>` sets
  `ui.requestedTab` in the view and opens the toolbar only when it is not already open (the
  toolbar publishes `toolbar.open`). The capture keybind may also use
  `noctalia msg panel-toggle nandomoreirame/daybar:capture` directly.

### Capture

- **[REQ-013]** WHEN the capture panel opens THEN its input SHALL have focus; WHEN the
  clipboard holds an http(s) URL not already bookmarked THEN the input SHALL be seeded with it.
  As the user types, a live preview SHALL show the inferred type and parsed data. Inference
  order: `=`, `/p`, prefix (`/e`, `/l`, `/n`, `/t`), Tab-forced type, lone URL as link, task.
- **[REQ-014]** `tab` / `shift+tab` (captured) SHALL cycle the forced type forward / backward
  through task, event, reminder, note, link, timer. Enter SHALL commit and close on success; `shift+Return` (captured)
  SHALL commit and keep the panel open with a cleared input (new input `key`); Esc closes
  without saving. A valid `=` calculation on Enter copies the result and keeps the panel open;
  an invalid one does nothing. A commit error keeps the text and shows the error line plus
  `notifyError`.
- **[REQ-015]** Commits SHALL behave as v4: task (local, no date = today), event (khal,
  default calendar, 1 h without end, rejected without date/time), reminder (15 min khal event
  with alarm at start plus a local reminder, rejected without time), note, link (bookmark,
  invalid URL rejected), `/t <duration> [label]` and `/t`, `/t parar`, `/p`, `/p foco`,
  `/p curta`, `/p longa`, `/p parar`. The capture panel validates with the lib handlers and
  the service performs the commit (REQ-011).

### Agenda

- **[REQ-016]** The service SHALL read events with
  `khal list --json uid --json calendar --json all-day --json start-date --json start-time
  --json end-date --json end-time --json location --json url --json description
  --json repeat-symbol <from> <to>` (argv), window -14/+31 days, at start, every 5 minutes,
  after each write or delete, and for any month the Calendar tab navigates to outside the
  loaded window. `lib/khalread.luau` SHALL parse the per-day arrays into the v4 event shape
  `{ uid, calendar, summary, start, end, allDay, location, url, description, repeats }`
  (epoch seconds, all-day end exclusive at midnight), deduplicated by `uid + start`.
- **[REQ-017]** WHEN `khal` is missing (`commandExists`) or `khal printcalendars` fails or
  lists nothing THEN `calendar.available` SHALL be false, the Calendar tab SHALL show
  "Calendar not configured" with the setup pointer, and everything else SHALL work.
- **[REQ-018]** Writes SHALL go `khal new` (argv from `lib/khal.luau`, sanitized summary) then
  `vdirsyncer sync` then a calendar reload, serialized by `lib/writequeue.luau`. A failed sync
  SHALL `notifyError` once, keep the event local and retry on the 5-minute timer.
- **[REQ-019]** Event delete SHALL keep the `calendar-event-delete` behavior: trash button on
  hover for events of writable calendars, locate the `.ics` by exact `UID:` line inside the
  khal calendar paths with the calendar's `displayname` (argv `grep -rlF`), repeat-aware
  question, delete with `noctalia.removeFile` only for an `.ics` path under a khal calendar
  path, hide every occurrence at once, drop its Today checks, sync, and the not-found and
  ambiguous outcomes.
- **[REQ-020]** Event details SHALL keep 0.3.1: time ranges (`16:00–17:00`), and an expandable
  row with attendees (name, status), Meet link (opens via `xdg-open`) and location, read from
  the located `.ics` with `noctalia.readFile` and parsed by `lib/eventinfo.luau`.

### Toolbar tabs

- **[REQ-021]** The toolbar SHALL show five tabs (Calendar, Today, Focus, Bookmarks, Notes;
  glyphs `calendar`, `list-check`, `hourglass`, `bookmark`, `notes`) and open on
  `ui.requestedTab`, else the `initial_tab` rule (`last` = `ui.lastTab`, fallback Today).
  Selecting a tab sends `setLastTab`.
- **[REQ-022]** Today SHALL list today's events, today's tasks and overdue undone tasks
  (events by time, then timed tasks, then untimed; overdue flagged), toggle events (keyed
  `uid+date`) and tasks (`done`/`doneAt`), add a task from its field (no date = today), rename
  and delete tasks.
- **[REQ-023]** Calendar SHALL show the current date, a navigable month grid (days with events
  marked) and the selected day's events with time ranges, details and delete.
- **[REQ-024]** Focus SHALL offer the Focus, Short break, Long break and Timer chips with
  start, pause, skip and reset, auto start, daily goal and today's count, optional task link
  (today's tasks; a completed focus session adds one pomodoro to it), the timer duration field
  (`90s`, `10m`, `1h30`, `1h 30m`, `1:30`, bare minutes, max 24 h, optional label), presets
  1/5/10/15/30 min and recent timers. Only one clock counts at a time (starting one pauses
  the other, keeping its remaining time). The clock is big digits over a `ui.progress` bar.
  The header has a "Pin to corner" toggle (REQ-027).
- **[REQ-025]** The service SHALL keep pomodoro and timer running with every panel closed,
  play `alarm.mp3` through `noctalia.sound` when `play_sound` is on, `notify` phase and timer
  ends as v4, fire due local reminders (10 min grace, older ones expire silently), and run
  `focus_mode_command` as argv `{ command, "on" | "off" }` when a focus session starts or stops
  running (empty = disabled).

### Bar

- **[REQ-026]** The bar widget SHALL `barWidget.render` a row (column on a vertical bar) with
  the clock-source glyph, plus `mm:ss` and a 32 px `ui.progress` while a pomodoro or timer
  runs or rings (`lib/clock.luau` source rules). Left click toggles the toolbar; middle click
  starts or pauses the clock shown, else the pomodoro (`Clock.middleClickTarget`). The tooltip
  shows the running clock or today's next event. Before the first `view`: glyph only.

### Detached clock

- **[REQ-027]** The Focus "Pin to corner" toggle SHALL open or close the persistent `clock`
  panel and store `ui.clockOverlay`; the service reopens it at start when the flag is set. It
  shows the active clock (running or ringing, else the one selected in Focus): digits and a
  progress bar; hovering shows play/pause, reset and close. Corner comes from the host
  `clock_position` setting; size is fixed.
- **[REQ-028]** The `clockface` desktop widget SHALL show the same active clock with digits and a
  progress bar, scale with the tile the user sizes, tick every second, and show play/pause
  and reset on hover. It replaces the v4 "Open in a window" form.

### Bookmarks

- **[REQ-029]** Bookmarks SHALL keep `inbox-bookmarks-notes` REQ-003..010 and REQ-019:
  immediate save with the domain as title, URL normalization and replace-on-duplicate, search
  (case and accent insensitive), row with thumbnail (or `world` glyph), title, description,
  `domain · date`, click opens via `xdg-open` (argv), hover actions copy, refresh preview,
  rename (inline input) and delete. Previews: `noctalia.http` GET (http/https only,
  `follow_redirects = true`), at most 3 in flight, an answer older than 8 s abandoned by
  generation id, body truncated to 2 MB before `lib/pagemeta.luau` parses it; the image goes
  through `noctalia.download` to `pluginDataDir()/thumbs/<id>`. With `fetch_previews` off no
  request is made. Rendering the list never touches the network. Deleting removes the thumb.
- **[REQ-030]** Delete of a bookmark, note or event SHALL ask first with an inline
  confirmation (the row's actions become the question plus "Delete" / "Cancel"); only
  "Delete" deletes.

### Notes

- **[REQ-031]** Notes SHALL keep `inbox-bookmarks-notes` REQ-011, 015 and 017 (derived title
  and snippet, relative time, newest edit first, search, "New note", empty new note discarded,
  `/n text`). Opening a note sets `note.request = { id | "new", seq }` and toggles the `note`
  panel. Preview mode is rendered by `lib/mdview.luau` into `ui.*` nodes: headings, paragraphs,
  lists, quotes, code blocks, horizontal rules; links as buttons that open only `http`,
  `https` and `mailto` via `xdg-open`; remote images as a link button with the alt text; local
  images as `ui.image`. `ctrl+e` (and a pencil button) toggles a multiline plain-text editor;
  text is saved 600 ms after the last change, at once on `ctrl+s`, and on close. Header: title,
  last-edit date, edit/preview, copy, delete, close.

### i18n, docs and guards

- **[REQ-032]** Every UI string SHALL go through `noctalia.tr`/`trp` with
  `translations/en.json` and `translations/pt-BR.json` holding the same key set (test) and
  covering every `label_key`/`description_key`/option `label_key` in `plugin.toml` (test).
  Texts are ported from `i18n/en.json` and `i18n/pt.json`.
- **[REQ-033]** Every external command SHALL be an argv array (`runAsync` table form);
  `tests/guards.test.sh` SHALL fail on any string-form `runAsync`/`runStream`/`runInTerminal`
  call in entries or lib, and SHALL keep the v4 guard that no file references a previous or
  source project (same pattern as the v4 Task 24 grep).
- **[REQ-034]** `README.md` (community layout: title, plugin table with entry ids, usage,
  niri bind `noctalia msg panel-toggle nandomoreirame/daybar:capture`, requirements,
  settings, IPC, notes disclosing network calls, file writes and processes, Known gaps),
  `CLAUDE.md` and `docs/SMOKE.md` SHALL be rewritten for v5; `screenshots/` retaken in the
  smoke run.

## Architecture Decisions

- **AD-201 Service owns all I/O.** One service does files, processes, HTTP, sound, timers and
  notifications. UI entries are renderers of `view` plus command senders, so timers and
  reminders run with every panel closed (as v4 `Main.qml`).
- **AD-202 Outbox commands with acks.** A single shared key can coalesce two quick writes;
  per-entry ordered queues with `seq` and acks make every command run exactly once and let
  the capture panel wait for the commit result before closing.
- **AD-203 Countdown by deadline.** The view carries `endsAtMs`; views tick locally. One state
  publish per change instead of one per second.
- **AD-204 khal JSON instead of CalendarService.** v5 does not expose its calendar to plugins
  (W4); khal stays the single read and write path, so writes and reads agree.
- **AD-205 Own Markdown renderer.** `ui.markdown` cannot click links or show images (W9);
  `lib/mdview.luau` returns plain node descriptions that the note entry maps to `ui.*`, so the
  renderer is unit-tested without the host.
- **AD-206 Native HTTP for previews.** `noctalia.http`/`download` replace curl; the 2 MB cap
  applies to parsing, the 8 s limit to waiting (generation id). Network still happens off the
  list rendering path.
- **AD-207 Clock surfaces.** Persistent `clock` panel for the corner, `clockface` desktop widget
  for the movable/resizable form. Both read the same `view`; the ring becomes a progress bar
  (W10).
- **AD-208 Data in pluginDataDir with a one-time import.** Keeps v4 untouched (it may still
  run under `qs`) and avoids two writers on one file.

## Edge Cases

All v4 edge cases hold (corrupt data, khal missing, argument injection in summaries, past
reminders, duplicate bookmarks, ambiguous delete, empty new note, invalid calc). New:

- `noctalia.json.decode` drops `null` keys: `Store.parse` treats a missing field as its
  default; `json.encode` of an empty list may emit `{}`, so every list field is normalized on
  load.
- A late `http` answer or khal result after a newer request: dropped by generation id.
- Commands from an entry VM that restarted: `seq` seeded from `nowMs()` stays above the last
  seen value.
- `open <tab>` while the toolbar is open only switches the tab.
- Capture panel opened while the service is not up yet (`view` nil): input works, commit shows
  "service not ready" and keeps the text.
- `khal list` output with a multi-day event repeated on each day line: one event after dedupe.
- Persistent clock panel reopened at start while no clock is active: shows the selected clock
  at its full duration.
- `alarm.mp3` load failure: logged once, notifications still fire.
- The import finds thumbnails missing: the bookmark keeps the `world` glyph and "Refresh
  preview".

## Known gaps vs 0.3.1

- No floating toplevel "Daybar timer" window or niri window-rule; the desktop widget replaces
  it, and the `clockWindow` flag is dropped.
- Pinned clock size setting is gone (panel size is host-owned); corner is the host
  `clock_position` setting instead of a plugin setting.
- Rings become linear progress bars (no arc primitive).
- The clipboard URL seeded in capture is not pre-selected (`ui.input` has no selection prop).
- `default_calendar` is a free-text setting instead of a list from `khal printcalendars`
  (settings cannot be populated at runtime); the toolbar shows the khal calendars to help.
- Confirmation is an inline row instead of an anchored bubble; keyboard focus does not start
  on Cancel.
- Note preview: no inline bold/italic inside paragraphs if `ui.label` cannot mix styles (the
  renderer strips the markers); double-click to edit becomes the pencil button and `ctrl+e`.
- Thumbnail downloads have no size cap (W14).
- Panel highlight of the bar widget while the toolbar is open is host-owned.

## Grilling Log

| # | Decision | Resolution | Rationale |
|---|----------|------------|-----------|
| 1 | v4 code on `main` | Removed; `legacy-v4` keeps 0.3.1 | One manifest, one suite (same as the aibar port) |
| 2 | Detached clock | Persistent corner panel + desktop widget | Closest v5 equivalents of the overlay and the window |
| 3 | v4 data | One-time import into `pluginDataDir`, v4 untouched | No shared writer, no data loss |
| 4 | Scope | Full 0.3.1 parity | User choice |
| 5 | Note preview | Own md → `ui.*` renderer | Keeps clickable, scheme-filtered links and local images |
| 6 | Previews | `noctalia.http` + `download` | User choice; caps re-applied where the API allows |
| 7 | Id and version | `nandomoreirame/daybar`, `0.4.0` | Parity port bumps the minor |
| 8 | Calendar read | `khal list --json` | Host calendar not exposed; same path as writes |
| 9 | Commands | Per-entry outbox + ack | Exactly-once, capture waits for commit result |
| 10 | Countdowns | `endsAtMs` in view, local second ticks | One publish per change |
| 11 | Clock corner/size | Host `clock_position`; fixed size | Plugins cannot set panel position or size |
| 12 | `plugin_api` | 32 | Last level needed (container tooltip); 33 and 34 (5.3.0) add nothing daybar uses, and 32 still runs on 5.2.1 |
| 13 | Shift+Enter and Tab | `capture_keys` on the capture panel | Non-printable chords reach `onKey` with the input focused |
| 14 | Test TZ | `TZ=America/Sao_Paulo` in `run-tests` | Deterministic local-time tests, no DST since 2019 |
| 15 | Thumbs location | `pluginDataDir()/thumbs` | No plugin cache dir API; survives updates |

## Traceability

See `docs/plans/2026-10-16-daybar-v5.md` (Traceability table).

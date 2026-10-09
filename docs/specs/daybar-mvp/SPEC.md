# Spec: daybar MVP

## Problem Statement

Day-to-day planning (calendar, today's checklist, quick capture, focus timer) is spread across
separate tools, and a heavyweight desktop app carries far more features than are used daily.
`daybar` is a single, native Noctalia Shell plugin that covers exactly these four uses from the
bar, with a centered quick-capture overlay as the main entry point for everything.

## Goals

- Open any capture (task, event, reminder, note, link, calculation) in under 1 second from a
  keyboard shortcut, and save it with a single Enter.
- See today's Google Calendar events and local tasks in one checklist, without leaving the bar.
- Replace the standalone pomodoro bar widget with the toolbar's Focus tab (one bar icon).
- Add a new capture type by adding one handler file plus its test, without touching the core.

## Context

- Target shell: `noctalia-shell` 4.7.7 (Quickshell/QML), running as `qs -c noctalia-shell`.
  The `noctalia` 5.x rewrite is installed but not running.
- Noctalia ships a `CalendarService` singleton with khal and Evolution Data Server providers.
  Neither khal nor vdirsyncer is installed yet (both available in Arch `extra`: khal 0.14.1,
  vdirsyncer 0.21.0).
- The installed `pomodoro` plugin (MIT, `noctalia-dev/noctalia-plugins`) keeps its state in
  `Main.qml` and is the base of the Focus tab fork.
- The `noctalia-desktop-sticky-notes` repo establishes the testing pattern: pure logic in
  `utils/*.js` (`.pragma library`) tested with vitest, thin QML on top.
- Google CalDAV does not expose tasks (VTODO), so Google Tasks requires the Tasks REST API.
  Tasks stay local in the MVP; the data model is prepared for a later sync.

## Verified Claims

| Claim | Source (file:line) | Verified |
|-------|--------------------|----------|
| `CalendarService.loadEvents(daysAhead = 31, daysBehind = 14)` defines the event window | `/etc/xdg/quickshell/noctalia-shell/Services/Location/CalendarService.qml:129` | yes |
| `CalendarService` auto-refreshes every 5 minutes (`interval: 300000`) | `/etc/xdg/quickshell/noctalia-shell/Services/Location/CalendarService.qml:105` | yes |
| `CalendarService` is disabled unless `Settings.data.location.showCalendarEvents` | `/etc/xdg/quickshell/noctalia-shell/Services/Location/CalendarService.qml:113` | yes |
| Khal provider maps events to `{uid, calendar, summary, start, end, location, description}` (`summary: event.title`) | `/etc/xdg/quickshell/noctalia-shell/Services/Location/Calendar/Khal.qml:146` | yes |
| `ToastService.showNotice(title, description, icon, duration, ...)` | `/etc/xdg/quickshell/noctalia-shell/Services/UI/ToastService.qml:16` | yes |
| Noctalia calculator evaluates via `new Function('return ' + processed)` (rejected by AppSec) | `/etc/xdg/quickshell/noctalia-shell/Helpers/AdvancedMath.js:98` | yes |
| Plugin panel slot supports anchors (`panelAnchorHorizontalCenter`) but is one panel per plugin | `/etc/xdg/quickshell/noctalia-shell/Modules/Panels/Plugins/PluginPanelSlot.qml:27` | yes |
| Plugin API exposes `togglePanel` and `withCurrentScreen` | `/etc/xdg/quickshell/noctalia-shell/Services/Noctalia/PluginService.qml:1059` | yes |
| Quickshell `FileView` has an `atomicWrites` property | `/usr/lib/qt6/qml/Quickshell/Io/quickshell-io.qmltypes:360` | yes |
| A plugin can open its own `PanelWindow` on `WlrLayer.Overlay` | `~/.config/noctalia/plugins/sticky-notes/ExpandedPanelWindow.qml:27` | yes |
| Pomodoro plugin keeps timer state in `Main.qml` (`property bool pomodoroRunning`) | `~/.config/noctalia/plugins/pomodoro/Main.qml:100` | yes |
| Pomodoro plugin exposes IPC target `plugin:pomodoro` | `~/.config/noctalia/plugins/pomodoro/Main.qml:61` | yes |
| Pomodoro plugin is MIT licensed | `~/.config/noctalia/plugins/pomodoro/manifest.json:7` | yes |
| `khal new --alarms 0m` creates an event with an alarm at start | n/a (external CLI) | assumption |
| `vdirsyncer sync` pushes locally created events to Google | n/a (external CLI) | assumption |
| Google OAuth client in "Testing" status expires refresh tokens after 7 days | n/a (external) | assumption |

## Requirements

### P1 (MVP)

**Capture overlay**

1. **[REQ-001]** WHEN the IPC `capture` is called THEN the system SHALL open a centered overlay window with keyboard focus on the input field; if it is already open, it SHALL only refocus it.
2. **[REQ-002]** WHEN the overlay opens and the clipboard holds an http(s) URL not already saved in the Inbox THEN the system SHALL prefill the field with it, fully selected.
3. **[REQ-003]** WHEN the user types THEN the system SHALL show a live preview of the inferred type and the parsed data (date, time, range, calculation result).
4. **[REQ-004]** WHEN the text starts with `=` THEN the system SHALL evaluate the expression (`+ - * / ^`, postfix percent `%` as in `200*15%`, parentheses, comma or dot decimal) with its own parser, never `eval`/`Function`; an invalid expression SHALL show an error and Enter SHALL do nothing.
5. **[REQ-005]** WHEN Enter is pressed on a valid calculation THEN the system SHALL copy the result to the clipboard and keep the overlay open.
6. **[REQ-006]** WHEN Tab is pressed THEN the system SHALL cycle the type (task, event, reminder, note, link); WHEN the text starts with `/e`, `/l` or `/n` THEN the type SHALL be forced to event, reminder or note. Inference order: prefix, then `=`, then a lone URL as link, then task as default.
7. **[REQ-007]** WHEN Enter is pressed THEN the system SHALL save, close the overlay and show a toast; WHEN Shift+Enter THEN it SHALL save and keep the overlay open with an empty field; WHEN Esc THEN it SHALL close without saving.
8. **[REQ-008]** WHEN a task is saved THEN the system SHALL store it locally with the parsed date/time; with no date, it SHALL be due today.
9. **[REQ-009]** WHEN an event is saved THEN the system SHALL create it via khal in the default calendar, lasting 1h when no end is given; with no date/time it SHALL be rejected with a message and the text kept in the field.
10. **[REQ-010]** WHEN a reminder is saved THEN the system SHALL create a 15-minute event with an alarm at start and schedule a local toast at that time; with no time it SHALL be rejected.
11. **[REQ-011]** WHEN a note or link is saved THEN the system SHALL store it in the Inbox; an invalid URL for a link SHALL be rejected.
12. **[REQ-012]** WHEN an event or reminder is written via khal THEN the system SHALL run `vdirsyncer sync` and reload `CalendarService`; WHEN the sync fails THEN it SHALL show a warning toast and keep the event local.

**Today**

13. **[REQ-013]** WHEN the Today tab is shown THEN the system SHALL list today's calendar events, today's tasks and overdue undone tasks, ordered: events by time, then tasks by time, then untimed tasks; overdue tasks SHALL be flagged.
14. **[REQ-014]** WHEN the user toggles an item THEN the system SHALL store event state locally keyed by `uid+date` and task state as `done`/`doneAt`; the user SHALL be able to add a task from the Today field (no date = today) and delete a task.

**Calendar**

15. **[REQ-015]** WHEN the Calendar tab is shown THEN the system SHALL show a clock with the current date, a navigable month grid with days that have events marked, and the events of the selected day.
16. **[REQ-016]** WHEN khal is not installed or `CalendarService` is unavailable THEN the system SHALL show "Calendar not configured" pointing to the setup guide, and Today SHALL still list tasks.

**Focus**

17. **[REQ-017]** WHEN the Focus tab is used THEN the system SHALL provide focus, short break and long break, configurable cycles, start, pause, skip and reset, and the alarm sound; the timer SHALL keep running with the panel closed; WHEN a focus (work) session starts or stops running THEN the system SHALL run the configured focus-mode command with `on`/`off` (empty command = disabled).
18. **[REQ-018]** WHEN a focus session completes with a linked task THEN that task's pomodoro count SHALL increase by 1; linking is optional and lists today's tasks.
19. **[REQ-019]** WHEN the panel is closed THEN the bar widget SHALL show the icon, plus `mm:ss` while a session is running; clicking it SHALL toggle the toolbar.

**Inbox**

20. **[REQ-020]** WHEN the Inbox tab is shown THEN the system SHALL list links (open via `xdg-open`, archive) and notes (view, copy, delete).

**Infrastructure**

21. **[REQ-021]** WHEN data changes THEN the system SHALL persist it to `~/.local/share/noctalia-daybar/data.json` (with `version`, atomic writes, debounced); WHEN the file is missing it SHALL be created; WHEN it is corrupt it SHALL be renamed to `.bak`, start empty and show a toast.
22. **[REQ-022]** WHEN the IPC target `plugin:daybar` receives `toggle`, `open <tab>` or `capture` THEN the system SHALL toggle the toolbar, open it on that tab, or open the capture overlay.
23. **[REQ-023]** WHEN the Settings page is opened THEN the system SHALL allow configuring pomodoro durations, cycles, sound and focus-mode command, the default calendar (from `khal printcalendars`) and the initial tab.

### P2 (Should Have)

24. **[REQ-024]** WHEN the user edits a note in the Inbox THEN the system SHALL save the new content.

### P3 (Nice to Have)

25. **[REQ-025]** WHEN Google Tasks sync is enabled THEN local tasks SHALL sync with Google Tasks using `source`/`externalId`.
26. **[REQ-026]** WHEN the user navigates beyond the -14/+31 day window THEN the calendar SHALL load events for that range.

## Edge Cases

- **Ambiguous weekday** - "sexta" typed on a Friday means next Friday.
- **Past time without date** - "9h" typed at 15:00 means tomorrow 09:00.
- **Calculation errors** - division by zero, incomplete expression or unknown token show an error in the preview; Enter does nothing. Identifiers (`constructor`, `process`) are rejected by the tokenizer.
- **Clipboard** - empty, binary or non-URL content does not prefill; a failing `wl-paste` is ignored silently.
- **khal failure** - `khal new` failing (invalid default calendar, missing binary) shows an error toast and keeps the text in the field.
- **Offline sync** - `vdirsyncer sync` failing keeps the event local; it syncs on the next timer run.
- **Reminder while shell is down** - the local toast is lost; the Google alarm still fires on other devices.
- **Recurring events** - checked state is per occurrence (`uid+date`).
- **Overlay already open** - `capture` refocuses instead of opening a second window.
- **Corrupt data.json** - renamed to `.bak`, plugin starts empty, toast shown.
- **Burst capture** - writes are debounced so Shift+Enter bursts do not rewrite the file per item.
- **Calendar window** - navigating beyond -14/+31 days shows the grid without events (accepted MVP limit).
- **khal argument injection** - user text is passed as separate `Process` args, never through a shell.

## Architecture Decisions

1. **Native QML plugin** - Chose a Noctalia plugin over a Tauri app or a QML panel plus daemon. It is light, opens like other plugins and has no webview. Discarded: Tauri (heavy, separate window), hybrid (more moving parts).
2. **Services live in `Main.qml`** - Agenda, Tasks, Inbox, Focus and Capture services live in `Main.qml` so the timer and reminders run with the panel closed; `Panel.qml` is UI only.
3. **Own overlay window for capture** - A `PanelWindow` on `WlrLayer.Overlay` with exclusive keyboard focus, because the plugin's single panel slot is the toolbar. Discarded: Noctalia launcher provider (cannot prefill from clipboard, flow tied to the launcher); re-anchoring the panel (conflicts with the toolbar).
4. **Calendar via khal + vdirsyncer** - Read through Noctalia `CalendarService`, write with `khal new` then `vdirsyncer sync`. No OAuth code in the plugin, works offline, and the native Noctalia calendar also gets the events. Discarded: own Calendar API helper (deferred until Google Tasks needs OAuth anyway); gcalcli (fragile output parsing).
5. **Capture handler registry** - One file per type in `utils/capture/<type>.js` exposing `detect`, `preview`, `commit`. New types are one file plus a test.
6. **Own calculator parser** - Shunting-yard over a whitelisted token set. Discarded: Noctalia `AdvancedMath.js` (uses `Function`, violates AppSec).
7. **Own pt-BR date parser** - Written from scratch in `utils/when.js`, no external dependency.
8. **Persistence in a dedicated data file** - `~/.local/share/noctalia-daybar/data.json` with `version` and `atomicWrites`; `pluginSettings` holds configuration only. Discarded: everything in `pluginSettings` (mixes config and data, rewrites settings on every check); SQLite helper (overkill).
9. **Pomodoro as a fork** - The MIT pomodoro plugin's state machine is extracted into `utils/pomodoro.js`, keeping the original license notice and `alarm.mp3`.

## Grilling Log

| # | Decision | Resolution | Rationale |
|---|----------|------------|-----------|
| 1 | App form factor | Noctalia QML plugin | Native, light, same UX as other plugins |
| 2 | Google Calendar access | khal + vdirsyncer through `CalendarService` | No OAuth in plugin, offline, native calendar benefits |
| 3 | Read-only or read/write calendar | Read and create | Reminders and events must land in Google |
| 4 | Google Tasks for local tasks | Local now, Tasks later (P3) | CalDAV has no tasks; avoids OAuth in MVP |
| 5 | Expense capture | Out of MVP | No destination to consult the data |
| 6 | Link capture | Read-later list in Inbox | Links need a place to be revisited |
| 7 | Note capture | List inside the plugin (Inbox) | Keeps notes self-contained |
| 8 | Reminder delivery | Google event with alarm + local toast | Phone and desktop both notify |
| 9 | Focus linked to a task | Optional, +1 pomodoro count | Useful without forcing it |
| 10 | Bar widget content | Icon + timer while running | Replaces the pomodoro widget |
| 11 | Where links/notes live | Dedicated Inbox tab | User preference |
| 12 | Persistence | Dedicated versioned data.json | Separates data from config |
| 13 | Events checkable in Today | Yes, local state `uid+date` | Today closes the whole day |
| 14 | Overdue tasks | Shown in Today flagged as overdue | Hiding them loses pending work |
| 15 | Task without date | Due today | Matches a today checklist |
| 16 | Calendar range | Accept -14/+31 window in MVP | Widening changes a global Noctalia service |
| 17 | Target calendar for writes | Default calendar chosen in Settings | Explicit, predictable |
| 18 | Reminder shape | 15-min event, alarm at start; time required | Reminder without time cannot fire |
| 19 | Write failure handling | Sync, reload; offline keeps local + warning toast | Never lose a capture |
| 20 | vdirsyncer/OAuth setup | README guide + empty state | One-time setup, not worth automating |
| 21 | Completed tasks retention | Kept in data.json | YAGNI |
| 22 | Pomodoro state across restarts | Not persisted | Same as original plugin |
| 23 | Language | i18n `pt` and `en` | Noctalia plugin convention |
| 24 | Shortcuts | IPC `toggle`, `open <tab>`, `capture` | Bind in niri |
| 25 | Capture entry point | Centered overlay with shortcut, the app's core | User's primary workflow |
| 26 | Type selection | Live inference + preview, Tab cycles, prefixes | Fast default, explicit override |
| 27 | MVP capture types | task, event, reminder, note, link, calculation | Covers stated needs |
| 28 | Calculator UX | Live result; Enter copies and stays open | Quick math without leaving |
| 29 | Clipboard prefill | Only new http(s) URL, selected | Avoids stale prefill |
| 30 | After save | Enter saves+closes, Shift+Enter saves+stays, Esc closes | Single and burst capture |
| 31 | Capture tab in toolbar | Removed; toolbar gets a Capture button | One capture surface |
| 32 | Extensibility | Handler registry per type | New type = one file + test |
| 33 | Today ordering | Events by time, tasks by time, untimed last | Mirrors the day |
| 34 | Note editing | P2 | Not needed for capture-first flow |
| 35 | Installed pomodoro has a local focus-mode hook (`focus-mode on/off`) | Kept as a configurable Settings command, empty by default | Preserves current DND/keep-awake behavior without hardcoding a home path |
| 36 | Meaning of `%` in the calculator | Postfix percent (`200*15%` = 30), not modulo | Quick everyday math |

## Constraints

- Targets noctalia-shell 4.x; Noctalia 5 compatibility is not guaranteed (accepted risk).
- Runtime dependencies: `khal`, `vdirsyncer`, `wl-clipboard`, `xdg-utils`. The Google OAuth client is the user's own and must be published "In production" to avoid weekly token expiry.
- No reference to any previous or source project in code, docs, comments or commits. Only the forked pomodoro plugin's MIT attribution is kept, as its license requires.
- Code, comments and commits in English; UI strings in `pt` and `en` via i18n.
- No `eval`/`Function`; external commands run via `Process` with argument arrays, never a shell string.

## Out of Scope

| Item | Reason |
|------|--------|
| Expense capture | No destination to consult; revisit with a finance module |
| Google Tasks sync | P3; data model prepared (`source`, `externalId`) |
| Editing or deleting Google events from the plugin | Create only; edit in Google Calendar |
| Automated vdirsyncer/OAuth setup | README guide; one-time setup |
| Calendar beyond -14/+31 days | P3; touches a global Noctalia service |
| Characters/mascots | Not part of this app |
| Noctalia 5 compatibility | Accepted risk, revisit on migration |
| Persisting pomodoro state across shell restarts | Keeps original plugin behavior |
| Disabling the old pomodoro plugin | Manual user action |

## Test Strategy

- **Unit (vitest, TDD):** all pure logic in `utils/`:
  - `when.js`: today, tomorrow, weekdays, `9h`, `15h30`, `15h-16h`, `dd/mm`, next-occurrence and past-time rules.
  - `calc.js`: precedence, parentheses, comma decimal, division by zero, rejection of identifiers.
  - `capture/*.js`: `detect`/`preview`/`commit` per type and the inference order.
  - `today.js`: Today assembly, ordering, overdue, recurring event state.
  - `store.js`: schema, `version` migration, corrupt-file recovery.
  - `pomodoro.js`: extracted state machine (cycles, long break, skip, reset, +1 on linked task).
  - `khal.js`: `khal new` argument array building (no shell).
- **Integration:** manual smoke script in `docs/` run inside Noctalia: IPC, overlay, clipboard prefill, `khal new` + sync, reminder toast. QML has no automated harness.
- **Gate:** `npm test` green before each commit.

## Requirement Traceability

| ID | Description | Priority | Status |
|----|-------------|----------|--------|
| REQ-001 | Capture overlay via IPC, refocus if open | P1 | Done |
| REQ-002 | Clipboard URL prefill | P1 | Pending |
| REQ-003 | Live type/data preview | P1 | Pending |
| REQ-004 | Safe calculator | P1 | Pending |
| REQ-005 | Enter copies calculation result | P1 | Pending |
| REQ-006 | Tab cycling, prefixes, inference order | P1 | Pending |
| REQ-007 | Enter / Shift+Enter / Esc behavior | P1 | Pending |
| REQ-008 | Task capture | P1 | Pending |
| REQ-009 | Event capture via khal | P1 | Pending |
| REQ-010 | Reminder capture + local toast | P1 | Pending |
| REQ-011 | Note and link capture | P1 | Pending |
| REQ-012 | vdirsyncer sync and reload | P1 | Pending |
| REQ-013 | Today list and ordering | P1 | Pending |
| REQ-014 | Toggle, add, delete in Today | P1 | Pending |
| REQ-015 | Calendar tab | P1 | Pending |
| REQ-016 | Calendar not configured state | P1 | Done |
| REQ-017 | Pomodoro timer | P1 | Pending |
| REQ-018 | Task-linked pomodoro count | P1 | Pending |
| REQ-019 | Bar widget | P1 | Pending |
| REQ-020 | Inbox tab | P1 | Pending |
| REQ-021 | Persistence and recovery | P1 | Pending |
| REQ-022 | IPC commands | P1 | Done |
| REQ-023 | Settings | P1 | Pending |
| REQ-024 | Edit note | P2 | Pending |
| REQ-025 | Google Tasks sync | P3 | Pending |
| REQ-026 | Configurable calendar window | P3 | Pending |

# Smoke test (manual, Noctalia v5)

Run after `./run-tests` and `noctalia plugins lint .` are green, with the plugin
symlinked into `~/.local/share/noctalia/plugins/daybar` and enabled. Watch the
Noctalia log in another terminal and filter for `daybar`; any error from a Daybar
entry fails the run.

The rows marked **host** check what the unit tests cannot prove (the mock stands in
for the host there).

| # | REQ | Step | Expected |
|---|-----|------|----------|
| 1 | REQ-001 | `noctalia plugins lint .`; enable the plugin | `0 errors`; the service, bar widget, five panels and the desktop clock are listed in Settings, Plugins |
| 2 | REQ-002 | `git log --oneline -1 legacy-v4` | 0.3.1 release commit |
| 3 | REQ-003, REQ-006, REQ-033 | `./run-tests` | `N passed, 0 failed` and `guards: ok` |
| 4 | REQ-004, REQ-005 | Capture `comprar pão sexta 9h` on a Thursday night | Task dated the next Friday 09:00 (local time) |
| 5 | REQ-007 | Change every setting in Settings, Plugins, Daybar | Values persist; a new focus duration applies to an untouched phase without restarting a running one |
| 6 | REQ-008 | Add a task, wait one second, read `data.json` in the plugin data dir | File has `"version": 2` and the task |
| 7 | REQ-008 | Write `{oops` into `data.json`, restart Noctalia | Error notification; `data.json.bak` kept; plugin starts empty |
| 8 | REQ-009 (host) | Move the v5 `data.json` away with the v4 file in place, restart | One "Imported N tasks..." notification; thumbnails copied; v4 file untouched |
| 9 | REQ-010, REQ-025 | Start a pomodoro, close every panel, wait | Bar keeps counting; the end notifies with the panels closed |
| 10 | REQ-011 | Toggle a task twice quickly | Each click applies once; nothing repeats after a Noctalia restart |
| 11 | REQ-012 | `noctalia msg plugin nandomoreirame/daybar:core all open focus` | Toolbar opens on Focus; `toggle` and `capture` work too |
| 12 | REQ-013 | Copy `https://example.com`, open capture | Field focused and prefilled; after saving, the same URL is not prefilled again |
| 13 | REQ-014 (host) | Type `pagar boleto 18h`, press Tab three times, then Shift+Tab | Type chip cycles Task, Event, Reminder, Note and back, with the input focused |
| 14 | REQ-014 (host) | Type `a`, Shift+Enter, `b`, Enter | Two tasks saved; the panel stays open after the first and closes after the second |
| 15 | REQ-015 | `/e teste daybar amanhã 10h`; `/l teste <now+2min>`; `/n ideia`; `=200*15%` | Event in khal and Google after sync; reminder notification at that minute; note listed; `30` on the clipboard and the panel stays open |
| 16 | REQ-016 (host) | Open Calendar with real calendars | Events match `khal list`, including all-day and multi-day ones |
| 17 | REQ-017 | Rename `khal` out of `PATH`, restart | Calendar says "Calendar not configured"; Today, Focus, Bookmarks and Notes still work |
| 18 | REQ-018 | Disconnect the network, create an event | One "Calendar sync failed" notification; the event is in `khal list`; the next sync after reconnecting clears it |
| 19 | REQ-019 | Delete a test event from Calendar; try a holiday | Locating, then the question (repeat warning on a recurring one); the event disappears and is gone from Google after sync; the holiday says read-only |
| 20 | REQ-020 | Expand an event with attendees and Meet | Time range `16:00–17:00`, attendees, place, Join Meet opens the browser |
| 21 | REQ-021 | Open the toolbar, switch tabs, close, reopen | Five tabs; it reopens on the last tab when Initial tab is `last` |
| 22 | REQ-022 | Today with an event, a timed task, an untimed task and an overdue one | Events first, then timed tasks, then untimed; overdue flagged; check, rename and delete work |
| 23 | REQ-023 | Calendar: next and previous month past the loaded range | Dots on event days of the new month; selecting a day lists it |
| 24 | REQ-024 | Focus: chips, start, skip, reset; Timer: `10m chá`, presets, recent chips | Each control acts on the shown clock; starting one clock pauses the other with a notification |
| 25 | REQ-024 (host) | Let a 1-minute focus end with Play alarm sound on | `alarm.mp3` plays; the linked task gets a pomodoro; today's count goes up |
| 26 | REQ-026 | Bar on a horizontal and a vertical bar, with and without a running clock | Glyph, digits and progress; column on the vertical bar; middle click pauses or resumes |
| 27 | REQ-027 (host) | Focus, Pin to corner; change the clock panel Position; restart | Small clock above windows at that corner, not taking focus; it comes back after the restart; hover shows the controls and close unpins |
| 28 | REQ-028 (host) | Add the desktop clock in the desktop-widgets editor | Same clock, scales with the tile; controls on hover, no close |
| 29 | REQ-029 | Save a link, search it without accents, hover: copy, refresh, rename | Preview and thumbnail appear; search finds it; each action works; a `192.168.x.x` link is saved without a request |
| 30 | REQ-030 | Delete a bookmark, a note and an event | Each asks inline first; Cancel keeps it |
| 31 | REQ-031 | Notes: new note, type Markdown with a link, Ctrl+E, Ctrl+S, Esc | Saved 600 ms after typing; preview renders; the link opens through xdg-open; a new note closed empty is not stored |
| 32 | REQ-032 | Switch the shell language between English and Portuguese | Every Daybar string follows |
| 33 | REQ-033 | Set Focus mode command to a script that logs its argument | `on` when focus starts, `off` when it pauses or ends |
| 34 | REQ-034 | Read README, CLAUDE.md and this file against the running plugin | Entry ids, commands and settings match |

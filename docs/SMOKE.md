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
| 6 | REQ-003, REQ-008 | Type `comprar pão amanhã 9h` | Preview "comprar pão · amanhã 09:00", chip "Tarefa" |
| 7 | REQ-007 | Enter | Overlay closes, toast "Tarefa salva" |
| 8 | REQ-007 | Type `a`, Shift+Enter, `b`, Shift+Enter, Esc | Two tasks saved, overlay closed by Esc |
| 9 | REQ-004, REQ-005 | `=200*15%`, Enter; then `=2/0` | Preview "= 30", Enter copies `30` (check `wl-paste`), overlay stays; `=2/0` shows "Divisão por zero" |
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
| 20 | REQ-017, REQ-019 | Foco: Iniciar | Bar shows the clock; toolbar closed, timer keeps counting |
| 21 | REQ-018 | Link a task, set focus to 1 min, let it finish | Toast, alarm, task shows "● 1" in Hoje |
| 22 | REQ-017 | Focus mode command set to a script that logs its argument | `on` at start, `off` at pause |
| 23 | REQ-020 | Caixa: open link, archive link, copy and delete note | xdg-open opens browser; lists update |
| 24 | REQ-022 | `qs -c noctalia-shell ipc call plugin:daybar open focus` | Toolbar opens on Foco |
| 25 | REQ-023 | Settings: change durations, default calendar, initial tab | Values persist and apply |
| 26 | REQ-021 | Write `{oops` into data.json, reload | Toast about unreadable data; `data.json.bak` exists |
## Bookmarks and Notes

| # | REQ | Step | Expected |
|---|-----|------|----------|
| 27 | BN-REQ-001 | Open the toolbar | Five tabs; Bookmarks and Notes after Focus |
| 28 | BN-REQ-002 | Start with a v1 `data.json` holding links/notes | `version: 2`, no links/notes |
| 29 | BN-REQ-003 | Capture `https://github.com` | Row appears at once with `github.com` |
| 30 | BN-REQ-004 | Capture `https://github.com/?utm_source=x` | Same row moves to top, refetched |
| 31 | BN-REQ-005 | Wait a few seconds | Title and description from the page |
| 32 | BN-REQ-006 | `ls ~/.cache/noctalia-daybar/thumbs/` | File named after the bookmark id |
| 33 | BN-REQ-007 | Capture `https://nonexistent.invalid` | Domain title, no toast, refresh on hover |
| 34 | BN-REQ-008 | Look at a row; click it | Thumbnail, title, 2-line description, domain · date; browser opens |
| 35 | BN-REQ-009 | Hover: copy, refresh, rename | Clipboard has URL; spinner; Enter saves title |
| 36 | BN-REQ-010 | Search `acao` with a title "Ação" | Row stays; others hidden |
| 37 | BN-REQ-011 | Open Notes | Title, snippet, "há N min", newest edit first |
| 38 | BN-REQ-012 | Click a note | Large centered window, rendered Markdown |
| 39 | BN-REQ-013 | Ctrl+E twice; double-click text | Editor (monospace) then preview; double-click edits |
| 40 | BN-REQ-014 | Type, wait 1 s, `cat data.json` | Text saved; Ctrl+S saves at once; Esc closes |
| 41 | BN-REQ-015 | New note, close without typing | No new note in data.json |
| 42 | BN-REQ-016 | Note with `![x](https://example.com/a.png)` and `[js](javascript:alert(1))` | Image shown as a link; js link does nothing |
| 43 | BN-REQ-017 | Capture `/n uma ideia` | Note "uma ideia" in Notes |
| 44 | BN-REQ-018 | Delete a note and a bookmark | Bubble with OK/Cancel; Esc cancels; OK deletes and removes the thumbnail |
| 45 | BN-REQ-019 | Turn "Fetch link previews" off, capture a link | Domain title only; no curl process |

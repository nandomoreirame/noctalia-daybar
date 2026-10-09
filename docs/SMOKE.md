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

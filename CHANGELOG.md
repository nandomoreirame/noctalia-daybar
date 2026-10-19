# Changelog

All notable changes to this project are documented here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and the project uses
[Semantic Versioning](https://semver.org/).

## [0.4.0] - 2026-10-19

### Changed

- **Noctalia v5**: Daybar is now a Noctalia v5 plugin (Luau entries and a
  `plugin.toml`, plugin API 32): a service that owns data, processes, timers and
  network, a bar widget, the toolbar, quick capture and note panels, a pinned clock
  panel and a desktop clock. Every 0.3.1 feature is kept except the gaps below. The
  v4 plugin stays on branch `legacy-v4`.
- **Data** moves to the plugin data directory (same format). The v4
  `data.json` and bookmark thumbnails are imported once on the first start and left
  untouched.
- **Calendar** is read straight from khal (`khal list --json`) every 5 minutes and
  after each write, instead of through the shell's calendar service.
- **Detached clock**: the floating "Daybar timer" window becomes a desktop clock
  placed in the desktop-widgets editor; the pinned clock's corner is its panel
  Position setting.

### Removed

- Pinned clock size setting, progress rings (now bars), the anchored confirmation
  bubble (now an inline row) and the preselected clipboard URL in capture: the v5
  plugin API has no way to express them yet.

### Security

- A bookmark preview image is downloaded only from a public host, and a URL with
  credentials (`http://user@host/`) is judged by its real host.

## [0.3.1] - 2026-10-13

### Added

- **Event time ranges**: calendar events in the Calendar and Today tabs show start
  and end (`16:00–17:00`) when both fall on that day.
- **Event details**: clicking an event (or Enter/Space on it) expands it to show the
  place, the organizer and attendees (without the calendar owner and rooms, declined
  ones struck through) and a button to join the Meet call. The details are read from
  the event's `.ics` file only when expanded, and read again after a calendar sync.

## [0.3.0] - 2026-10-12

### Added

- **Timer**: a fourth Focus chip next to Foco, Pausa curta and Pausa longa. It takes
  free-form durations (`90s`, `10m`, `1h30`, `1h 30m`, `1:30`, up to 24 h) with an
  optional label, rings the same alarm as the pomodoro and shows a toast with the
  label. Only one clock counts at a time: starting one pauses the other.
- **Recent timers**: the last four timers started show as one-click chips above the
  controls, and the last one is loaded after a shell restart. The duration field
  opens from the + button.
- **Quick capture commands**: `/t 10m chá` starts a timer (`/t` pauses or resumes,
  `/t parar` resets) and `/p`, `/p foco`, `/p curta`, `/p longa`, `/p parar` drive the
  pomodoro. Timer joins the Tab cycle.
- **Progress ring** around the pomodoro and timer clocks.
- **Detached clock**: one click opens the active clock as a Niri window titled
  *Daybar timer* (resizable, with mode chips and controls on hover) or pins it to a
  screen corner above windows on every workspace. Corner and size are settings, and
  both reopen after a restart. The README has a niri window-rule to float the window.
- **Bar timer**: the bar shows the timer clock with an alarm icon while it runs or
  rings; middle click pauses or resumes the clock shown.
- **Linked task**: the task picker opens from a + button, the linked task shows as
  text in the panel and the detached clock, and it is released when its focus
  session ends.

### Changed

- The Focus panel is 25% taller with a larger clock; mode chips are centered and a
  footer holds the window, pin and settings buttons with today's progress.
- The daily progress dots and the cycle line are gone from the Focus tab.
- The month grid starts on Sunday, and the selected day is a circle with its dot
  below.
- Read-only calendar events no longer show the checklist in Today.
- The README binds capture to Mod+Space and the toolbar to Mod+Shift+Space.

### Fixed

- A ringing timer is silenced by play instead of restarting its countdown, and
  pausing one clock no longer stops the other clock's alarm.

## [0.2.0] - 2026-10-09

### Added

- **Bar label**: the bar widget shows the label of the tab the panel opens on, with
  today's done/total count for Today (`Hoje (1/3)`).
- **Next event in the bar**: when the panel opens on Calendar, the bar shows
  today's next timed event (`15:00 Reunião`), cut with an ellipsis and shown in
  full on hover. With nothing left today it shows "Nada marcado para hoje.",
  dimmed and in italics.
- **Tab counts**: the active panel tab shows done/total for Calendar and Today,
  and the number of items for Bookmarks and Notes.
- **Screenshots** in the README and in `screenshots/`.

### Changed

- The running focus timer uses the hourglass icon in the bar.
- Opening a note closes the toolbar panel, leaving only the note window.
- Note and bookmark rows show a pointer cursor.
- The empty-day message in the Calendar tab is dimmed and in italics.
- The README states Noctalia v4 support (tested on 4.7.7) and the planned v5 port.

### Fixed

- Text in the note preview can be selected and copied.

## [0.1.0] - 2026-10-09

First public release. Requires Noctalia Shell v4 (`noctalia-shell` 4.7.x, tested on
4.7.7); Noctalia v5 is not supported.

### Added

- **Quick capture overlay**: a centered window for tasks, events, reminders,
  notes, links and calculations. The type is inferred from the text (`/e`, `/l`,
  `/n` prefixes, `=` for math, a lone URL for a link) and Tab / Shift+Tab cycle it.
  Enter saves and closes, Shift+Enter saves and stays.
- **pt-BR date and time parser** for captures ("amanhã 9h", weekdays, ranges).
- **Safe calculator** with whitelisted tokens and percent support, no `eval`.
- **Bar toolbar** with Calendar, Today, Focus, Bookmarks and Notes tabs, icon tabs
  that show the label only when active, and the last tab remembered.
- **Calendar tab**: Monday-first month grid and day list with Google Calendar
  events (through khal and vdirsyncer) and local tasks; days with tasks are marked.
- **Today tab**: daily checklist of events and tasks, overdue flags, in-place task
  editing and a button to start a focus session from a task.
- **Delete calendar events** from the Calendar and Today tabs, with a confirmation
  bubble, only from the event's own writable collection.
- **Focus tab**: pomodoro timer with configurable durations, breaks, intervals and a
  daily goal.
- **Bookmarks**: links saved from capture with a page preview (title, description,
  image) fetched with bounded `curl` calls; refresh, rename and delete.
- **Notes**: list with derived titles and relative times, a dedicated note window
  with editing and a themed markdown preview.
- **Reminders** scheduled locally, running with the panel closed.
- **IPC target** `plugin:daybar` (`capture`, `toggle`, `open <tab>`).
- Portuguese and English translations.

### Security

- Remote images in notes never load: every remote image form becomes a link.
- Preview image downloads refuse private, local and numeric hosts.
- External commands are argv arrays only; user text is never passed through a shell.

[0.2.0]: https://github.com/nandomoreirame/noctalia-daybar/releases/tag/v0.2.0
[0.1.0]: https://github.com/nandomoreirame/noctalia-daybar/releases/tag/v0.1.0

# Changelog

All notable changes to this project are documented here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and the project uses
[Semantic Versioning](https://semver.org/).

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

[0.1.0]: https://github.com/nandomoreirame/noctalia-daybar/releases/tag/v0.1.0

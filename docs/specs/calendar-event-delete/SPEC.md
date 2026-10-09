# Spec: Delete calendar events

## Problem Statement

Events synced from Google Calendar can be seen and checked off in Daybar, but removing one
means opening Google Calendar. The user wants to delete an event from the panel, with the
same anchored confirmation bubble used for notes and bookmarks.

## Goals

- Delete an event from the Calendar tab (selected day list) and the Today tab.
- The deletion reaches Google through the existing vdirsyncer sync, with no OAuth code.
- A read-only calendar (holidays) never offers deletion.

## Context

- Events reach QML through Noctalia's `CalendarService` (khal provider) as
  `{ uid, calendar, summary, start, end, location, description }`; recurrence information is
  dropped before QML (`/etc/xdg/quickshell/noctalia-shell/Services/Location/Calendar/Khal.qml:140`).
- khal has no scriptable delete (`khal edit` is interactive). Each event is one `.ics` file in
  a vdir under the paths listed by `path =` in `~/.config/khal/config`; deleting the file and
  running `vdirsyncer sync` propagates the deletion to Google.
- File names are not the UID (sample `00456103-ffd1-...ics` holds `UID:7799utap...@google.com`),
  so the file is found by its `UID:` line.
- Writes already go through `Main.requestSync()` (coalesced) which reloads `CalendarService`
  and shows a warning toast on failure.
- `components/ui/ConfirmButton.qml` is created by the `inbox-bookmarks-notes` plan.

## Verified Claims

| Claim | Source (file:line) | Verified |
|-------|--------------------|----------|
| QML events carry uid, calendar, summary, start, end only | `/etc/xdg/quickshell/noctalia-shell/Services/Location/Calendar/Khal.qml:144` | yes |
| khal 0.14.1 offers no non-interactive delete | `khal --help` (commands list) | yes |
| vdir file names differ from event UIDs | `~/.local/share/calendars/google/nandomoreira.me@gmail.com/*.ics` | yes |
| UID lines end with LF in the local vdir | `od -c` of a sample `.ics` | yes |
| Each vdir collection has a `displayname` file matching the khal calendar name | `~/.local/share/calendars/google/*/displayname` | yes |
| The holidays collection id ends with `@virtual` and has no RRULE events | `~/.local/share/calendars/google/` | yes |
| 70 recurring events in Eventos, 9 in Família | `grep -l ^RRULE` per collection | yes |
| Today event items carry the calendar name | `utils/today.js` eventItems | yes |
| Sync requests are coalesced and reload CalendarService on exit | `Main.qml:362` | yes |
| `ConfirmButton` exposes question/okText/cancelText and `confirmed` | `components/ui/ConfirmButton.qml:12` | yes |
| Deleting a vdir file makes vdirsyncer delete the remote item | n/a (vdirsyncer behavior) | assumption |
| Google UIDs are short enough not to be folded across lines | n/a (iCalendar folding at 75 octets) | assumption |

## Requirements

### P1

1. **[REQ-001]** WHEN the pointer is over an event in the Calendar tab day list or an event row in the Today tab THEN the system SHALL show a trash button, except for events of read-only calendars (collection id ending with `@virtual` or containing `#holiday`).
2. **[REQ-002]** WHEN the trash button is clicked THEN the system SHALL locate the event file (exact `UID:` line, inside the khal calendar paths, in the collection whose `displayname` equals the event's calendar) and open the confirmation bubble; while locating, OK SHALL be disabled.
3. **[REQ-003]** WHEN the located event repeats (`RRULE` or `RECURRENCE-ID` in the file) THEN the bubble SHALL ask "This event repeats. Delete all occurrences?"; otherwise "Delete this event?".
4. **[REQ-004]** WHEN OK is chosen THEN the system SHALL delete the file, hide every occurrence of that UID at once, remove its Today check entries, and request a sync; a failed sync SHALL show the existing sync warning and the periodic timer SHALL retry.
5. **[REQ-005]** WHEN no file matches THEN the system SHALL close the bubble, show "Event not found" and reload the calendar; WHEN several files match and the calendar does not single one out THEN it SHALL show "Could not delete: ambiguous event" and delete nothing.
6. **[REQ-006]** WHEN a command (`grep`, `cat`, `rm`) runs THEN it SHALL be an argv array and the path to delete SHALL be an `.ics` file under one of the khal calendar paths.

## Edge Cases

- **Shared invite in two calendars** (same UID) - the calendar name picks the file; no match or two matches → ambiguous, nothing deleted.
- **Deleted on another device meanwhile** - lookup finds nothing → "Event not found", reload.
- **Offline** - file deleted locally, warning toast, timer sync sends it later; the event does not come back.
- **Folded UID line** (UID > 75 octets) - not found by the lookup → "Event not found" (accepted limit).
- **khal config with `~` or a trailing `/*`** - expanded and stripped; missing config → no roots → trash hidden.
- **Event checked in Today** - its `eventChecks` entries (`uid|date`) are removed.
- **Bubble cancelled after lookup** - nothing changes.

## Architecture Decisions

1. **Delete the vdir file** - then `vdirsyncer sync`. Discarded: driving `khal edit` through stdin (fragile, interactive), Google API (OAuth in the plugin).
2. **Lookup by UID with grep -P** - exact `^UID:<escaped>\r?$`. Discarded: assuming file name = UID (false here).
3. **Whole series for recurring events** - a different question in the bubble. Discarded: EXDATE for one occurrence (iCalendar editing, out of scope).
4. **Optimistic hide** - hidden UIDs filtered out of `CalendarService.events` until the reload. Discarded: spinner until sync ends.
5. **Read-only by collection id** - `@virtual` / `#holiday`. Discarded: probing the server for write access.

## Grilling Log

Decisions surfaced and resolved during the grilling pass (pre-build stress test).

| # | Decision | Resolution | Rationale |
|---|----------|------------|-----------|
| 1 | Recurring events | Delete the whole series; bubble says so | One-occurrence delete needs iCalendar editing |
| 2 | Where the trash appears | Calendar day list and Today event rows, on hover | Same pattern as tasks |
| 3 | After OK | Hide at once; sync in background; existing warning on failure; timer retries | The file is gone; nothing comes back |
| 4 | Read-only calendars | No trash for `@virtual` / `#holiday` collections | Remote delete would fail every sync |
| 5 | Finding the file | Exact `UID:` line under the khal `path =` roots | File names are not UIDs |
| 6 | Same UID in several calendars | Pick by `displayname`; otherwise refuse as ambiguous | Never delete the wrong copy |
| 7 | File not found | "Event not found" + reload | Deleted elsewhere |
| 8 | Today checks | Removed with the event | No orphan state |
| 9 | Undo | None | Consistent with notes and bookmarks |
| 10 | Dependency | After `inbox-bookmarks-notes` (ConfirmButton) | Shared component |

## Constraints

- Argv arrays only; no shell strings; path validated before `rm`.
- UI strings in `pt` and `en`.
- No reference to any previous or source project.

## Out of Scope

| Item | Reason |
|------|--------|
| Delete a single occurrence | Needs EXDATE editing |
| Edit events | User chose delete only |
| Delete from read-only calendars | Server rejects it |
| Undo | Consistency with other deletes |

## Test Strategy

- **Unit (vitest, TDD):** `utils/eventdelete.js` (calendar roots from khal config, read-only ids, grep argv with regex escaping, grep/displayname output parsing, file pick, recurrence detection, path validation, check removal, hidden filter); `utils/today.js` (calendar field).
- **Runtime (manual):** SMOKE rows for hover trash, recurring question, delete + sync, not found, read-only calendar.
- **Gate:** `npm test` green before each commit.

## Requirement Traceability

| ID | Description | Priority | Status |
|----|-------------|----------|--------|
| REQ-001 | Trash on hover, not for read-only calendars | P1 | Pending |
| REQ-002 | Locate file, bubble with OK disabled while locating | P1 | Pending |
| REQ-003 | Recurring question | P1 | Pending |
| REQ-004 | Delete, hide, clear checks, sync | P1 | Pending |
| REQ-005 | Not found / ambiguous handling | P1 | Pending |
| REQ-006 | Argv and path validation | P1 | Done |

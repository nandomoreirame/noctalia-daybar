# Daybar

Quick capture, today's checklist, a khal calendar, a focus timer, bookmarks and
notes for the [Noctalia](https://github.com/noctalia-dev/noctalia) bar.

This branch is the Noctalia v5 plugin (Luau, `plugin.toml`). The Noctalia v4
plugin (QML, for noctalia-shell 4.7.x) is frozen at v0.3.1 on branch
[`legacy-v4`](https://github.com/nandomoreirame/noctalia-daybar/tree/legacy-v4).

![Daybar calendar tab](screenshots/calendar.png)

![Quick capture](screenshots/capture-event.png)

| Today | Focus |
|-------|-------|
| ![Today tab](screenshots/today.png) | ![Focus tab](screenshots/focus.png) |
| **Bookmarks** | **Notes** |
| ![Bookmarks tab](screenshots/bookmarks.png) | ![Notes tab](screenshots/notes.png) |

## Plugin

| | |
|---|---|
| Id | `nandomoreirame/daybar` |
| Service | `nandomoreirame/daybar:core` |
| Bar widget | `nandomoreirame/daybar:bar` |
| Toolbar panel | `nandomoreirame/daybar:toolbar` |
| Quick capture panel | `nandomoreirame/daybar:capture` |
| Note panel | `nandomoreirame/daybar:note` |
| Pinned clock panel | `nandomoreirame/daybar:clock` |
| Desktop clock | `nandomoreirame/daybar:clockface` |

## Usage

Symlink this repo into the v5 plugin directory and enable it:

```bash
git clone https://github.com/nandomoreirame/noctalia-daybar ~/src/noctalia-daybar
ln -s ~/src/noctalia-daybar ~/.local/share/noctalia/plugins/daybar
noctalia msg plugins enable nandomoreirame/daybar
```

Add `nandomoreirame/daybar:bar` to a bar. Left click opens the toolbar; middle
click starts or pauses the clock the bar shows (else the pomodoro). Add the desktop
clock from the desktop-widgets editor if you want one.

niri (`~/.config/niri/config.kdl`):

```kdl
binds {
    Mod+Space       hotkey-overlay-title="Daybar: capture" { spawn "noctalia" "msg" "panel-toggle" "nandomoreirame/daybar:capture"; }
    Mod+Shift+Space hotkey-overlay-title="Daybar: toolbar" { spawn "noctalia" "msg" "panel-toggle" "nandomoreirame/daybar:toolbar"; }
}
```

### Capture

| You type | It becomes |
|----------|------------|
| `comprar pão amanhã 9h` | task for tomorrow 09:00 (no date = today) |
| `/e reunião sexta 15h-16h` | calendar event (1h when there is no end) |
| `/l pagar boleto 18h` | reminder: 15-minute event with an alarm, plus a local notification |
| `/n uma ideia` | note, listed in Notes |
| `/t 10m chá` | timer with an alarm (`/t` pauses or resumes, `/t parar` resets) |
| `/p`, `/p foco`, `/p curta`, `/p longa`, `/p parar` | pomodoro: start or pause, switch phase and start, reset |
| `https://...` | bookmark with a page preview (prefilled from the clipboard) |
| `=200*15%` | calculation; Enter copies the result and the field stays open |

`Tab` and `Shift+Tab` cycle the type, `Enter` saves and closes, `Shift+Enter`
saves and keeps the field open, `Esc` closes.

### Toolbar

- **Calendar**: month grid with dots on days with events, the selected day's
  events, details on expand (attendees, place, Meet link), delete.
- **Today**: today's events, then today's and overdue tasks. Check, rename,
  delete, or start a focus session on a task.
- **Focus**: pomodoro phases and a free timer (`90s`, `10m`, `1h30`, `1:30` or a
  bare number of minutes, up to 24 h, with an optional label). Presets start 1, 5,
  10, 15 or 30 minutes; the last four timers are one click away. Only one clock
  counts at a time. "Pin to corner" shows a small clock above windows.
- **Bookmarks**: saved links with a thumbnail, title, description and domain.
  Search ignores accents. Hover a row to copy, refresh, rename or delete.
- **Notes**: notes newest-edit first. Opening one shows a Markdown preview;
  `Ctrl+E` switches to the editor, which saves 600 ms after the last change
  (`Ctrl+S` saves at once). A new note closed while empty is not stored.

## Requirements

- Noctalia 5.2 or newer (plugin API 32)
- `khal`, `vdirsyncer` and `xdg-utils` (without khal the Calendar tab says so and
  everything else keeps working)

```bash
sudo pacman -S --needed khal vdirsyncer python-aiohttp-oauthlib xdg-utils libsecret
```

## Google Calendar setup (one time)

Daybar reads and writes events with khal; vdirsyncer keeps khal and Google in sync.

1. **OAuth client.** In Google Cloud Console create a project, enable the
   **CalDAV API**, configure the OAuth consent screen as *External* and **publish it
   ("In production")**. In *Testing* status Google expires the refresh token every
   7 days. Create an OAuth client of type *Desktop app*.
2. **Store the secrets** in the keyring:

   ```bash
   secret-tool store --label="vdirsyncer google id" service vdirsyncer-google key client_id
   secret-tool store --label="vdirsyncer google secret" service vdirsyncer-google key client_secret
   ```

3. **vdirsyncer** (`~/.config/vdirsyncer/config`):

   ```ini
   [general]
   status_path = "~/.local/share/vdirsyncer/status/"

   [pair google_calendar]
   a = "google_calendar_remote"
   b = "google_calendar_local"
   collections = ["from a", "from b"]
   conflict_resolution = "a wins"

   [storage google_calendar_remote]
   type = "google_calendar"
   token_file = "~/.local/share/vdirsyncer/google_token"
   client_id.fetch = ["command", "secret-tool", "lookup", "service", "vdirsyncer-google", "key", "client_id"]
   client_secret.fetch = ["command", "secret-tool", "lookup", "service", "vdirsyncer-google", "key", "client_secret"]

   [storage google_calendar_local]
   type = "filesystem"
   path = "~/.local/share/calendars/google/"
   fileext = ".ics"
   ```

   Then authorize and sync (opens the browser once):

   ```bash
   vdirsyncer discover google_calendar && vdirsyncer metasync && vdirsyncer sync
   ```

4. **khal** (`~/.config/khal/config`). Daybar passes ISO dates, so the locale
   formats must be ISO:

   ```ini
   [calendars]
   [[google]]
   path = ~/.local/share/calendars/google/*
   type = discover

   [locale]
   timeformat = %H:%M
   dateformat = %Y-%m-%d
   longdateformat = %Y-%m-%d
   datetimeformat = %Y-%m-%d %H:%M
   longdatetimeformat = %Y-%m-%d %H:%M
   firstweekday = 0
   ```

   Check with `khal printcalendars` and copy the calendar name into the *Default
   calendar* setting.
5. **Periodic sync** (`~/.config/systemd/user/vdirsyncer.service` and `.timer`):

   ```ini
   # vdirsyncer.service
   [Unit]
   Description=Synchronize calendars

   [Service]
   Type=oneshot
   ExecStart=/usr/bin/vdirsyncer sync
   ```

   ```ini
   # vdirsyncer.timer
   [Unit]
   Description=Synchronize calendars every 10 minutes

   [Timer]
   OnBootSec=2m
   OnUnitActiveSec=10m

   [Install]
   WantedBy=timers.target
   ```

   ```bash
   systemctl --user daemon-reload && systemctl --user enable --now vdirsyncer.timer
   ```

Daybar also reloads the calendar every 5 minutes and syncs after each write.

## Settings

| Setting | Default | What it does |
|---------|---------|--------------|
| Focus duration (minutes) | `25` | Pomodoro focus phase, 1 to 180. |
| Short break (minutes) | `5` | 1 to 60. |
| Long break (minutes) | `15` | 1 to 120. |
| Sessions before long break | `4` | 1 to 12. |
| Daily pomodoro goal (0 turns it off) | `8` | Today's count in the Focus tab shows `n of goal`. |
| Start breaks automatically | off | Start the break when focus ends. |
| Start focus automatically | off | Start focus when a break ends. |
| Play alarm sound | on | Alarm when a clock ends. |
| Focus mode command | empty | Executable run with `on` when focus starts and `off` when it stops. |
| Default calendar | empty | khal calendar for new events; must match `khal printcalendars`. |
| Initial tab | `last` | Tab the toolbar opens on. |
| Fetch link previews | on | Off keeps bookmarks as plain links and downloads nothing. |

The pinned clock's corner is the panel's own *Position* setting (Settings, Plugins,
Daybar, gear).

## IPC

```bash
noctalia msg plugin nandomoreirame/daybar:core all toggle         # toolbar
noctalia msg plugin nandomoreirame/daybar:core all capture        # quick capture
noctalia msg plugin nandomoreirame/daybar:core all open focus     # calendar | today | focus | bookmarks | notes
noctalia msg panel-toggle nandomoreirame/daybar:capture
```

## Notes

**Data.** `data.json` in the plugin data directory (tasks, event checks,
reminders, bookmarks, notes, focus log, recent timers), written atomically 500 ms
after the last change. Bookmark thumbnails live in `thumbs/` next to it. A corrupt
file is kept as `data.json.bak` and a fresh one is started.

**Import from v4.** On the first start, when the plugin data directory has no
`data.json` and `~/.local/share/noctalia-daybar/data.json` exists, Daybar imports
it once (with the thumbnails in `~/.cache/noctalia-daybar/thumbs/`) and notifies
the counts. The v4 files are never modified.

**Network.** One `GET` per saved bookmark to read its title, description and
image (native HTTP, at most 3 at a time, 8 s budget, links to private networks
are not requested), and one download of the preview image to `thumbs/`.

**Processes.** `khal` (list, new, printcalendars), `vdirsyncer sync`, `grep` (to
find an event's `.ics` file before deleting it), `xdg-open` (links), and the
focus mode command when set. Every command is an argument list, never a shell
string.

**Files read.** `~/.config/khal/config` and the `.ics` files under its calendar
paths. Deleting an event removes its `.ics` file and syncs.

## Known gaps

Differences from the [v4 version](https://github.com/nandomoreirame/noctalia-daybar/tree/legacy-v4) that the v5 plugin API does not allow today:

- No floating "Daybar timer" window; the desktop clock replaces it.
- The pinned clock has no size setting (panel size is host-owned) and its corner is
  the panel's Position setting.
- Progress rings are linear bars (no arc primitive).
- The clipboard URL seeded in capture is not preselected.
- *Default calendar* is free text instead of a list from `khal printcalendars`.
- Confirmations are an inline row instead of an anchored bubble.
- The alarm plays once and cannot be stopped early (no stop call for plugin sounds).
- The delete button shows on read-only calendars too; the delete is refused with
  "This calendar is read-only".
- Preview requests follow redirects, so the private-network check covers the saved
  URL only; thumbnail downloads have no size cap.
- The bar widget is not highlighted while the toolbar is open (host-owned).

## Development

`./run-tests` needs the `luau` CLI. `lib/**/*.luau` is pure logic, `views/*.luau`
builds UI trees, the entries (`service.luau`, `widget.luau`, `toolbar.luau`,
`capture.luau`, `note.luau`, `clockpin.luau`, `clockdesk.luau`) and `plugin.toml`
sit at the repo root. Manual checks: [docs/SMOKE.md](docs/SMOKE.md).

```bash
./run-tests
noctalia plugins lint .
```

## License

MIT. The pomodoro machine is derived from an MIT plugin, see
[THIRD_PARTY.md](THIRD_PARTY.md).

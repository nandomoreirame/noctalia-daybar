-- Daybar service (AD-201): the only entry that does files, processes, HTTP, sound,
-- timers and notifications. UI entries render the published `view` and send
-- commands through the outbox (`cmd.<entry>` -> `ack.<entry>`, AD-202).

local Store = require("./lib/store.luau")
local View = require("./lib/view.luau")
local Outbox = require("./lib/outbox.luau")
local Tasks = require("./lib/tasks.luau")
local Dates = require("./lib/dates.luau")
local Tbl = require("./lib/tbl.luau")
local Clock = require("./lib/clock.luau")
local Tabs = require("./lib/tabs.luau")
local Notes = require("./lib/notes.luau")
local Markdown = require("./lib/markdown.luau")
local Khal = require("./lib/khal.luau")
local KhalRead = require("./lib/khalread.luau")
local EventDelete = require("./lib/eventdelete.luau")
local EventInfo = require("./lib/eventinfo.luau")
local WriteQueue = require("./lib/writequeue.luau")
local Reminders = require("./lib/reminders.luau")
local Registry = require("./lib/capture/registry.luau")
local Pomodoro = require("./lib/pomodoro.luau")
local PomodoroCommand = require("./lib/capture/pomodoro.luau")
local Timers = require("./lib/timers.luau")
local FocusLog = require("./lib/focuslog.luau")
local Duration = require("./lib/duration.luau")
local Bookmarks = require("./lib/bookmarks.luau")
local FetchPool = require("./lib/fetchpool.luau")
local PageMeta = require("./lib/pagemeta.luau")
local Url = require("./lib/url.luau")
local Ring = require("./lib/ring.luau")

local PLUGIN_ID = "nandomoreirame/daybar"
local TOOLBAR_PANEL = PLUGIN_ID .. ":toolbar"
local CAPTURE_PANEL = PLUGIN_ID .. ":capture"
local CLOCK_PANEL = PLUGIN_ID .. ":clock"
local ENTRIES = { "bar", "toolbar", "capture", "note", "clockpin", "clockdesk" }
local SAVE_DELAY_MS = 500
local UPDATE_MS = 250
local V4_DATA_PATH = "~/.local/share/noctalia-daybar/data.json"
local V4_THUMB_DIR = "~/.cache/noctalia-daybar/thumbs"
local SETTING_KEYS = {
	"work_duration",
	"short_break_duration",
	"long_break_duration",
	"sessions_before_long_break",
	"daily_pomodoro_goal",
	"auto_start_breaks",
	"auto_start_work",
	"play_sound",
	"focus_mode_command",
	"default_calendar",
	"initial_tab",
	"fetch_previews",
}
-- Returned by an async command handler: it acks later through its `reply`.
local PENDING = {}
local CALENDAR_RELOAD_MS = 5 * 60 * 1000
local WINDOW_BEFORE_DAYS = 14
local WINDOW_AFTER_DAYS = 31
local KHAL_CONFIG = "~/.config/khal/config"
local ALARM_SOUND = "alarm"
local ALARM_FILE = "alarm.mp3"
local ALARM_MS = 5000
local REMINDER_CHECK_MS = 30000
local FETCH_LIMIT = 3
local FETCH_TIMEOUT_MS = 8000
local BODY_MAX = 2 * 1024 * 1024
local THEME_CHECK_MS = 5000

local dataDir = noctalia.pluginDataDir() or ""
local dataPath = dataDir .. "/data.json"
local thumbDir = dataDir .. "/thumbs"

local data = Store.createEmpty()
local settings: { [string]: any } = {}
local dirtyAt: number? = nil
local rev = 0
local server = Outbox.newServer()
-- Tab the toolbar opens on after `open <tab>`; cleared when the toolbar closes.
local requestedTab: string? = nil

-- Agenda (REQ-015..020): khal reads and writes, vdirsyncer syncs.
local calendar: { [string]: any } = {
	available = false,
	calendars = {},
	events = {},
	from = nil,
	to = nil,
	writing = false,
	syncFailed = false,
	loading = false,
}
local listGen = 0
local lastReloadMs: number? = nil
local writeQueue = WriteQueue.createQueue()
local writeCallbacks: { [number]: (boolean, string?) -> () } = {}
local syncState = WriteQueue.createSync()
local hiddenKeys: { string } = {}
-- uid -> { phase, recurring, error } for the view; located files stay here.
local deleting: { [string]: any } = {}
local located: { [string]: { path: string, calendar: string, roots: { string } } } = {}
local details: { [string]: any } = {}

-- Focus (REQ-024..027): one pomodoro and one free timer, never both running.
-- Running clocks keep a deadline (endsAtMs); `remaining` is exact while paused.
local pom: { [string]: any } = {
	mode = Pomodoro.WORK,
	running = false,
	started = false,
	remaining = 0,
	endsAtMs = nil,
	completed = 0,
	linkedTaskId = nil,
}
local tmr: { [string]: any } = { total = 0, remaining = 0, running = false, endsAtMs = nil, label = "" }
local alarmSource = ""
local alarmUntilMs: number? = nil
local focusPanel = "pomodoro"
local soundReady = false
local focusModeOn = false
local lastReminderCheckMs: number? = nil

-- Bookmark previews (REQ-029, REQ-030): native HTTP, bounded pool, 8 s budget.
local fetchPool = FetchPool.createPool(FETCH_LIMIT)
-- id -> { token, startedAt, gen } of each request in flight.
local inFlight: { [string]: { token: number, startedAt: number, gen: number } } = {}
local fetchGen = 0

-- Progress rings (lib/ring.luau) for the theme's primary color.
local ringDir: string? = nil
local lastThemeCheckMs: number? = nil

-- ---------------------------------------------------------------- helpers

local function nowMs(): number
	return noctalia.nowMs()
end

local function nowSec(): number
	return math.floor(nowMs() / 1000)
end

local function todayIso(): string
	return Dates.isoDate(nowSec())
end

-- Same shape as the v4 `new Date().toISOString()`.
local function nowIso(): string
	local ms = math.floor(nowMs())
	return (os.date("!%Y-%m-%dT%H:%M:%S", math.floor(ms / 1000)) :: string) .. string.format(".%03dZ", ms % 1000)
end

local function newId(): string
	return Store.makeId(nowMs(), math.random())
end

local function decode(text: string): (any, string?)
	return noctalia.json.decode(text)
end

local function encode(value: any, pretty: boolean?): (string?, string?)
	return noctalia.json.encode(value, pretty)
end

local function tr(key: string, subst: any?): string
	return noctalia.tr(key, subst)
end

local function log(message: string)
	noctalia.log("daybar: " .. message)
end

local function trim(value: any): string
	if typeof(value) ~= "string" then
		return ""
	end
	return (string.match(value, "^%s*(.-)%s*$") :: string)
end

-- Ids name files under thumbs/: only plain characters, never a path.
local function safeId(id: any): boolean
	return typeof(id) == "string" and #id > 0 and #id <= 64 and string.match(id, "^[%w%-_]+$") ~= nil
end

local function thumbPathOf(id: any): string?
	if not safeId(id) then
		return nil
	end
	return thumbDir .. "/" .. id
end

local function readSettings()
	local out = {}
	for _, key in ipairs(SETTING_KEYS) do
		out[key] = noctalia.getConfig(key)
	end
	settings = out
end

-- ---------------------------------------------------------------- view

local function publish()
	rev += 1
	noctalia.state.set(
		"view",
		View.build({
			data = data,
			settings = settings,
			rev = rev,
			now = nowMs(),
			requestedTab = requestedTab,
			calendar = Tbl.merge(calendar, { events = EventDelete.hideEvents(calendar.events, hiddenKeys) }),
			details = details,
			deleting = deleting,
			pomodoro = Tbl.merge(pom, { total = Pomodoro.durationFor(pom.mode, Pomodoro.configFrom(settings)) }),
			timer = Tbl.merge(tmr, { set = tmr.total > 0 }),
			alarmSource = alarmSource,
			focusPanel = focusPanel,
			ringDir = ringDir,
			thumbDir = thumbDir,
			thumbExists = function(id: string): boolean
				local path = thumbPathOf(id)
				return path ~= nil and noctalia.fileExists(path)
			end,
		})
	)
end

-- ---------------------------------------------------------------- store

local function flush()
	dirtyAt = nil
	local okEncode, text = pcall(Store.serialize, data, encode)
	if not okEncode then
		log("cannot encode data: " .. tostring(text))
		return
	end
	local tmp = dataPath .. ".tmp"
	local wrote, writeErr = noctalia.writeFile(tmp, text)
	if not wrote then
		log("cannot write " .. tmp .. ": " .. tostring(writeErr))
		return
	end
	local renamed, renameErr = noctalia.renameFile(tmp, dataPath)
	if not renamed then
		log("cannot replace " .. dataPath .. ": " .. tostring(renameErr))
	end
end

local function markDirty()
	dirtyAt = nowMs()
end

-- Adopts a new data table (lib mutators return the same table when nothing changed).
local function change(nextData: { [string]: any })
	if nextData == data then
		return
	end
	data = nextData
	markDirty()
	publish()
end

-- REQ-009: v4 data and thumbnails are read, never modified.
local function importV4()
	local text = noctalia.readFile(V4_DATA_PATH)
	if text == nil then
		return
	end
	local parsed = Store.parse(text, decode)
	if parsed.corrupt then
		noctalia.notifyError(tr("store.corrupt-title"), tr("store.import-failed"))
		return
	end
	local bookmarks = {}
	for _, b in ipairs(parsed.data.bookmarks) do
		local copy = Tbl.merge(b, { image = "" })
		local dest = thumbPathOf(b.id)
		if dest ~= nil then
			local bytes = noctalia.readFile(V4_THUMB_DIR .. "/" .. b.id)
			if bytes ~= nil then
				noctalia.mkdirAll(thumbDir)
				if noctalia.writeFile(dest, bytes) then
					copy.image = dest
				end
			end
		end
		table.insert(bookmarks, copy)
	end
	data = Tbl.merge(parsed.data, { bookmarks = bookmarks })
	flush()
	local counts = { tasks = #data.tasks, notes = #data.notes, bookmarks = #data.bookmarks }
	if counts.tasks + counts.notes + counts.bookmarks > 0 then
		noctalia.notify("Daybar", tr("store.imported", counts))
	end
end

local function loadData()
	if not noctalia.fileExists(dataPath) then
		importV4()
		return
	end
	local text = noctalia.readFile(dataPath)
	local parsed = if text ~= nil then Store.parse(text, decode) else { data = Store.createEmpty(), corrupt = true }
	data = parsed.data
	if parsed.corrupt then
		noctalia.renameFile(dataPath, dataPath .. ".bak")
		noctalia.notifyError(tr("store.corrupt-title"), tr("store.corrupt-body"))
	end
end

-- ---------------------------------------------------------------- commands
-- COMMANDS[name](args, reply) -> ok, error, result; or PENDING, then reply(ok, error, result).

local COMMANDS: { [string]: (any, (boolean, string?, any?) -> ()) -> (any, string?, any?) } = {}

COMMANDS.addTask = function(args)
	local title = trim(args.title)
	if title == "" then
		return false, "empty-title"
	end
	local date = if args.date == nil or args.date == "" then todayIso() else args.date
	if Dates.parseIsoDate(date) == nil then
		return false, "invalid-date"
	end
	local time = if args.time == "" then nil else args.time
	if time ~= nil and Dates.minutesOf(time) == nil then
		return false, "invalid-time"
	end
	local id = newId()
	change(Tasks.addTask(data, { title = title, date = date, time = time }, id, nowIso()))
	return true, nil, { id = id }
end

-- Ids that reach lib lookups: non-empty strings only.
local function validId(id: any): boolean
	return typeof(id) == "string" and id ~= "" and #id <= 256
end

COMMANDS.toggleTask = function(args)
	if not validId(args.id) then
		return false, "invalid-id"
	end
	change(Tasks.toggleTask(data, args.id, nowIso()))
	return true
end

COMMANDS.deleteTask = function(args)
	if not validId(args.id) then
		return false, "invalid-id"
	end
	change(Tasks.deleteTask(data, args.id))
	return true
end

COMMANDS.renameTask = function(args)
	if not validId(args.id) then
		return false, "invalid-id"
	end
	change(Tasks.renameTask(data, args.id, if typeof(args.title) == "string" then args.title else ""))
	return true
end

COMMANDS.toggleEvent = function(args)
	if not validId(args.uid) then
		return false, "invalid-id"
	end
	if Dates.parseIsoDate(args.date) == nil then
		return false, "invalid-date"
	end
	change(Tasks.toggleEventCheck(data, args.uid, args.date))
	return true
end

COMMANDS.setLastTab = function(args)
	if not Tabs.isTab(args.tab) then
		return false, "invalid-tab"
	end
	change(Tabs.setLastTab(data, args.tab))
	return true
end

-- Creates the note on its first non-blank save (id nil); result.id is the note id,
-- nil when a blank new note was discarded.
COMMANDS.saveNote = function(args)
	local text = if typeof(args.text) == "string" then args.text else ""
	if args.id == nil or args.id == "" then
		if Notes.isBlank(text) then
			return true, nil, {}
		end
		local id = newId()
		change(Notes.add(data, text, id, nowIso()))
		return true, nil, { id = id }
	end
	if not validId(args.id) then
		return false, "invalid-id"
	end
	change(Notes.update(data, args.id, text, nowIso()))
	return true, nil, { id = args.id }
end

COMMANDS.deleteNote = function(args)
	if not validId(args.id) then
		return false, "invalid-id"
	end
	change(Notes.remove(data, args.id))
	return true
end

COMMANDS.copyText = function(args)
	if typeof(args.text) ~= "string" then
		return false, "invalid-text"
	end
	noctalia.copyToClipboard(args.text, "text/plain")
	return true
end

-- http, https and mailto only (REQ-029, REQ-031); argv, never a shell string.
COMMANDS.openUrl = function(args)
	local url = trim(args.url)
	if not Markdown.isOpenableLink(url) then
		return false, "invalid-url"
	end
	noctalia.runAsync({ "xdg-open", url })
	return true
end

COMMANDS.setClockOverlay = function(args)
	local nextData = Store.setUiFlag(data, "clockOverlay", args.value == true)
	if nextData ~= data then
		change(nextData)
		noctalia.togglePanel(CLOCK_PANEL)
	end
	return true
end

COMMANDS.openSettings = function()
	noctalia.openSettings()
	return true
end


-- ---------------------------------------------------------------- agenda

local function home(): string
	return (string.gsub(noctalia.expandPath("~/"), "/$", ""))
end

local function okResult(r: any): boolean
	return typeof(r) == "table" and r.exitCode == 0 and r.timedOut ~= true
end

local function runCmd(argv: { string }, cb: (any) -> ())
	noctalia.runAsync(argv, function(r: any)
		cb(r)
	end)
end

local function windowRange(): (string, string)
	local today = Dates.parseIsoDate(todayIso()) :: number
	return Dates.isoDate(Dates.addDays(today, -WINDOW_BEFORE_DAYS)), Dates.isoDate(Dates.addDays(today, WINDOW_AFTER_DAYS))
end

-- Same event twice (overlapping ranges) is kept once: uid + start.
local function mergeEvents(base: { any }, extra: { any }): { any }
	local out = Tbl.copyList(base)
	local seen: { [string]: boolean } = {}
	for _, ev in ipairs(base) do
		seen[tostring(ev.uid) .. "@" .. tostring(ev.start)] = true
	end
	for _, ev in ipairs(extra) do
		local key = tostring(ev.uid) .. "@" .. tostring(ev.start)
		if not seen[key] then
			seen[key] = true
			table.insert(out, ev)
		end
	end
	return out
end

-- Reloads the -14/+31 window; an answer older than the newest reload is dropped.
local function loadWindow()
	if not calendar.available then
		return
	end
	lastReloadMs = nowMs()
	listGen += 1
	local gen = listGen
	local from, to = windowRange()
	calendar.loading = true
	publish()
	runCmd(Khal.listArgs(from, to), function(r)
		if gen ~= listGen then
			return
		end
		calendar.loading = false
		if okResult(r) then
			calendar.events = KhalRead.parse(r.stdout, decode)
			calendar.from = from
			calendar.to = to
			-- Events deleted this session are gone from a fresh read.
			hiddenKeys = {}
		else
			log("khal list failed: " .. tostring(r and r.stderr))
		end
		publish()
	end)
end

local function runSync()
	runCmd(Khal.syncArgs(), function(r)
		local failed = not okResult(r)
		if failed and not calendar.syncFailed then
			noctalia.notifyError(tr("agenda.sync-failed-title"), tr("agenda.sync-failed-body"))
		end
		calendar.syncFailed = failed
		local nextSync = WriteQueue.syncFinished(syncState)
		syncState = nextSync.state
		if nextSync.start then
			runSync()
		else
			loadWindow()
		end
	end)
end

-- Pull from the server then reload; without vdirsyncer there is only the reload.
local function requestSync()
	if not noctalia.commandExists("vdirsyncer") then
		loadWindow()
		return
	end
	local r = WriteQueue.requestSync(syncState)
	syncState = r.state
	if r.start then
		runSync()
	end
end

local startWrite: (any) -> ()

local function finishWrite(token: number, ok: boolean, err: string?)
	local r = WriteQueue.settle(writeQueue, token)
	if r.settled == nil then
		return
	end
	writeQueue = r.queue
	calendar.writing = writeQueue.active ~= nil
	local done = writeCallbacks[token]
	writeCallbacks[token] = nil
	publish()
	if ok then
		requestSync()
	end
	if done ~= nil then
		done(ok, err)
	end
	if r.start ~= nil then
		startWrite(r.start)
	end
end

startWrite = function(job: any)
	local payload = Tbl.merge(job.payload, { calendar = settings.default_calendar })
	calendar.writing = true
	publish()
	runCmd(Khal.newEventArgs(payload), function(r)
		if not okResult(r) then
			log("khal new failed: " .. tostring(r and r.stderr))
		end
		finishWrite(job.token, okResult(r), "khal-failed")
	end)
end

local function enqueueEvent(payload: any, done: (boolean, string?) -> ())
	local r = WriteQueue.enqueue(writeQueue, payload)
	writeQueue = r.queue
	writeCallbacks[writeQueue.seq] = done
	if r.start ~= nil then
		startWrite(r.start)
	end
end

local function startCalendar()
	if not noctalia.commandExists("khal") then
		return
	end
	runCmd(Khal.printCalendarsArgs(), function(r)
		local names = if okResult(r) then Khal.parseCalendars(r.stdout) else {}
		calendar.calendars = names
		calendar.available = #names > 0
		publish()
		loadWindow()
	end)
end

-- Roots and collections from the khal config, then the .ics files holding UID.
-- done({ ok, path, roots, self } | { ok = false, error })
local function findEventFile(uid: string, calendarName: string, readable: boolean, done: (any) -> ())
	local configText = noctalia.readFile(noctalia.expandPath(KHAL_CONFIG))
	local h = home()
	local roots = EventDelete.calendarRoots(configText, h)
	if #roots == 0 then
		done({ ok = false, error = "not-found" })
		return
	end
	local sections = EventDelete.calendarSections(configText, h)
	runCmd(EventDelete.collectionsArgs(roots), function(cr)
		local collections = EventDelete.parseCollections(if typeof(cr) == "table" then cr.stdout else "", sections)
		runCmd(EventDelete.findArgs(uid, roots), function(fr)
			local paths = EventDelete.parsePaths(if typeof(fr) == "table" then fr.stdout else "")
			local pick = if readable
				then EventDelete.pickReadable(paths, collections, calendarName)
				else EventDelete.pickFile(paths, collections, calendarName)
			if not pick.ok then
				done(pick)
				return
			end
			done({ ok = true, path = pick.path, roots = roots, self = pick.self })
		end)
	end)
end

-- uid and calendar reach argv and file lookups: plain strings, no NUL or newline.
local function validEventArgs(args: any): (boolean, string?)
	if not validId(args.uid) or string.find(args.uid, "[%z\n\r]") then
		return false, "invalid-id"
	end
	if typeof(args.calendar) ~= "string" or args.calendar == "" or string.find(args.calendar, "[%z\n\r]") then
		return false, "invalid-calendar"
	end
	return true
end

COMMANDS.reloadCalendar = function()
	if not calendar.available then
		return false, "calendar-not-configured"
	end
	requestSync()
	return true
end

COMMANDS.loadRange = function(args, reply)
	local from, to = args.from, args.to
	if Dates.parseIsoDate(from) == nil or Dates.parseIsoDate(to) == nil or from > to then
		return false, "invalid-date"
	end
	if not calendar.available then
		return false, "calendar-not-configured"
	end
	if calendar.from ~= nil and from >= calendar.from and to <= calendar.to then
		return true
	end
	local gen = listGen
	runCmd(Khal.listArgs(from, to), function(r)
		if not okResult(r) then
			reply(false, "khal-failed")
			return
		end
		if gen == listGen then
			calendar.events = mergeEvents(calendar.events, KhalRead.parse(r.stdout, decode))
			publish()
		end
		reply(true)
	end)
	return PENDING
end

COMMANDS.locateEvent = function(args, reply)
	local valid, err = validEventArgs(args)
	if not valid then
		return false, err
	end
	local uid, calendarName = args.uid, args.calendar
	deleting[uid] = { phase = "locating", recurring = false }
	located[uid] = nil
	publish()
	findEventFile(uid, calendarName, false, function(found)
		if deleting[uid] == nil then
			reply(false, "cancelled")
			return
		end
		if not found.ok then
			deleting[uid] = { phase = "error", recurring = false, error = found.error }
			publish()
			reply(false, found.error)
			return
		end
		local ics = noctalia.readFile(found.path)
		located[uid] = { path = found.path, calendar = calendarName, roots = found.roots }
		deleting[uid] = { phase = "ready", recurring = EventDelete.isRecurring(ics) }
		publish()
		reply(true)
	end)
	return PENDING
end

COMMANDS.cancelDelete = function(args)
	if not validId(args.uid) then
		return false, "invalid-id"
	end
	deleting[args.uid] = nil
	located[args.uid] = nil
	publish()
	return true
end

COMMANDS.deleteEvent = function(args)
	local valid, err = validEventArgs(args)
	if not valid then
		return false, err
	end
	local uid = args.uid
	local where = located[uid]
	if where == nil or where.calendar ~= args.calendar then
		return false, "not-located"
	end
	if not EventDelete.isDeletablePath(where.path, where.roots) then
		return false, "not-deletable"
	end
	local removed = noctalia.removeFile(where.path)
	if not removed then
		return false, "delete-failed"
	end
	located[uid] = nil
	deleting[uid] = nil
	table.insert(hiddenKeys, EventDelete.eventKey(uid, args.calendar))
	-- Checks are keyed by uid only.
	change(EventDelete.removeEventChecks(data, uid))
	publish()
	requestSync()
	return true
end

COMMANDS.loadDetails = function(args, reply)
	local valid, err = validEventArgs(args)
	if not valid then
		return false, err
	end
	local uid = args.uid
	if details[uid] ~= nil then
		return true
	end
	findEventFile(uid, args.calendar, true, function(found)
		if not found.ok then
			reply(false, found.error)
			return
		end
		details[uid] = EventInfo.parseEventInfo(noctalia.readFile(found.path), found.self)
		publish()
		reply(true)
	end)
	return PENDING
end

-- ---------------------------------------------------------------- capture

-- Capture result actions; each acks through done(ok, err).
local CAPTURE_ACTIONS: { [string]: (any, (boolean, string?) -> ()) -> () } = {}

CAPTURE_ACTIONS.addTask = function(p, done)
	change(Tasks.addTask(data, { title = p.title, date = p.date, time = p.time }, newId(), nowIso()))
	done(true)
end

CAPTURE_ACTIONS.addNote = function(p, done)
	change(Notes.add(data, p.text, newId(), nowIso()))
	done(true)
end

CAPTURE_ACTIONS.copy = function(p, done)
	noctalia.copyToClipboard(tostring(p.display), "text/plain")
	done(true)
end

CAPTURE_ACTIONS.createEvent = function(p, done)
	if not calendar.available then
		done(false, "calendar-not-configured")
		return
	end
	enqueueEvent(p, done)
end

CAPTURE_ACTIONS.createReminder = function(p, done)
	local function remember()
		change(Reminders.addReminder(data, { title = p.title, date = p.date, time = p.start }, newId()))
	end
	if not calendar.available then
		remember()
		done(true)
		return
	end
	enqueueEvent(p, function(ok, err)
		if ok then
			remember()
		end
		done(ok, err)
	end)
end

COMMANDS.commit = function(args, reply)
	local text = if typeof(args.text) == "string" then args.text else ""
	local forced = if typeof(args.type) == "string" then args.type else nil
	local result = Registry.resolve(text, forced, nowSec())
	if not result.ok then
		return false, result.error or "invalid"
	end
	local action = rawget(CAPTURE_ACTIONS, result.action)
	if action == nil then
		return false, "unsupported-action"
	end
	action(result.payload, reply)
	return PENDING
end

-- ---------------------------------------------------------------- rings

-- Writes the 101 ring files for the current primary color once; returns true when
-- the published directory changed.
local function ensureRings(): boolean
	lastThemeCheckMs = nowMs()
	local hex = noctalia.getColor("primary")
	local name = Ring.dirName(hex)
	local dir = if name ~= nil then dataDir .. "/rings/" .. name else nil
	if dir == ringDir then
		return false
	end
	if dir ~= nil and not noctalia.fileExists(dir .. "/" .. Ring.STEPS .. ".svg") then
		noctalia.mkdirAll(dir)
		for step = 0, Ring.STEPS do
			noctalia.writeFile(dir .. "/" .. step .. ".svg", Ring.svg(step, hex :: string))
		end
	end
	ringDir = dir
	return true
end

-- ---------------------------------------------------------------- focus

local function cfg(): { [string]: any }
	return Pomodoro.configFrom(settings)
end

local function remainingOf(clock: { [string]: any }): number
	return Clock.remaining(clock, nowMs())
end

-- Runs the focus-mode command with "on"/"off" when focus starts or stops.
local function syncFocusMode()
	local shouldBeOn = pom.running and pom.mode == Pomodoro.WORK
	if shouldBeOn == focusModeOn then
		return
	end
	focusModeOn = shouldBeOn
	local cmd = trim(settings.focus_mode_command)
	if cmd ~= "" then
		noctalia.runAsync({ cmd, if shouldBeOn then "on" else "off" })
	end
end

local function playAlarm(source: string)
	alarmSource = source
	alarmUntilMs = nowMs() + ALARM_MS
	if settings.play_sound ~= false and soundReady then
		noctalia.sound.play(ALARM_SOUND)
	end
end

-- Without a source, any ringing alarm stops; with one, only that clock's.
local function stopAlarm(source: string?)
	if alarmSource == "" or (source ~= nil and alarmSource ~= source) then
		return
	end
	alarmSource = ""
	alarmUntilMs = nil
end

local function pausePomodoro()
	if pom.running then
		pom.remaining = remainingOf(pom)
	end
	pom.running = false
	pom.endsAtMs = nil
end

local function pauseTimer()
	if tmr.running then
		tmr.remaining = remainingOf(tmr)
	end
	tmr.running = false
	tmr.endsAtMs = nil
end

local function startPomodoro()
	stopAlarm()
	if tmr.running then
		pauseTimer()
		noctalia.notify(tr("timer.toast-title"), tr("timer.paused-timer"))
	end
	if pom.remaining <= 0 then
		pom.remaining = Pomodoro.durationFor(pom.mode, cfg())
	end
	pom.started = true
	pom.running = true
	pom.endsAtMs = nowMs() + pom.remaining * 1000
end

local function resetPomodoro()
	pausePomodoro()
	pom.started = false
	pom.remaining = Pomodoro.durationFor(pom.mode, cfg())
	stopAlarm("pomodoro")
end

local function setPomodoroMode(mode: number)
	pausePomodoro()
	pom.started = false
	pom.mode = mode
	pom.remaining = Pomodoro.durationFor(mode, cfg())
	stopAlarm("pomodoro")
end

local function skipPomodoro()
	local nextPhase = Pomodoro.nextPhase({ mode = pom.mode, completed = pom.completed }, cfg())
	setPomodoroMode(nextPhase.mode)
	pom.completed = nextPhase.completed
end

local function startTimer(): boolean
	if tmr.total <= 0 then
		return false
	end
	stopAlarm()
	if pom.running then
		pausePomodoro()
		noctalia.notify(tr("timer.toast-title"), tr("timer.paused-pomodoro"))
	end
	if tmr.remaining <= 0 then
		tmr.remaining = tmr.total
	end
	tmr.running = true
	tmr.endsAtMs = nowMs() + tmr.remaining * 1000
	change(Timers.recordRecent(data, { seconds = tmr.total, label = tmr.label }))
	return true
end

local function setTimer(seconds: number, label: string?)
	pauseTimer()
	stopAlarm("timer")
	tmr.total = seconds
	tmr.remaining = seconds
	tmr.label = label or ""
	focusPanel = "timer"
end

local function resetTimer()
	pauseTimer()
	tmr.remaining = tmr.total
	stopAlarm("timer")
end

local function pomodoroFinished()
	pom.running = false
	pom.started = false
	pom.endsAtMs = nil
	local outcome = Pomodoro.finish({ mode = pom.mode, completed = pom.completed }, cfg())
	local goalReached = false
	if outcome.workCompleted then
		local today = todayIso()
		local nextData = FocusLog.addSession(data, today)
		if pom.linkedTaskId ~= nil then
			nextData = Tasks.addPomodoro(nextData, pom.linkedTaskId)
		end
		change(nextData)
		-- Each focus session links its task anew.
		pom.linkedTaskId = nil
		goalReached = FocusLog.goalJustReached(FocusLog.sessionsOn(data, today), cfg().dailyGoal)
	end
	playAlarm("pomodoro")
	local key = if goalReached
		then "focus.toast-goal-reached"
		elseif outcome.workCompleted then "focus.toast-work-done"
		else "focus.toast-break-done"
	noctalia.notify(tr("focus.toast-title"), tr(key))
	pom.mode = outcome["next"].mode
	pom.completed = outcome["next"].completed
	pom.remaining = outcome.remaining
	if outcome.autoStart then
		pom.started = true
		pom.running = true
		pom.endsAtMs = nowMs() + pom.remaining * 1000
	end
end

local function timerFinished()
	tmr.running = false
	tmr.endsAtMs = nil
	tmr.remaining = tmr.total
	playAlarm("timer")
	noctalia.notify(tr("timer.toast-title"), if tmr.label ~= "" then tmr.label else tr("timer.toast-done"))
end

local function checkReminders()
	lastReminderCheckMs = nowMs()
	local due = Reminders.dueReminders(data, nowSec())
	for _, r in ipairs(due.fire) do
		noctalia.notify(tr("reminder.title"), tostring(r.title))
	end
	local ids = {}
	for _, r in ipairs(due.fire) do
		table.insert(ids, r.id)
	end
	for _, r in ipairs(due.expire) do
		table.insert(ids, r.id)
	end
	if #ids > 0 then
		change(Reminders.markFired(data, ids))
	end
end

-- Advances deadlines; returns true when something visible changed.
local function tickFocus(): boolean
	local changed = false
	local now = nowMs()
	if pom.running and pom.endsAtMs ~= nil and now >= pom.endsAtMs then
		pomodoroFinished()
		changed = true
	end
	if tmr.running and tmr.endsAtMs ~= nil and now >= tmr.endsAtMs then
		timerFinished()
		changed = true
	end
	if alarmUntilMs ~= nil and now >= (alarmUntilMs :: number) then
		stopAlarm()
		changed = true
	end
	if lastReminderCheckMs == nil or now - (lastReminderCheckMs :: number) >= REMINDER_CHECK_MS then
		checkReminders()
	end
	return changed
end

-- Every focus command ends here: focus mode follows the pomodoro, the view republishes.
local function focusChanged()
	syncFocusMode()
	publish()
end

local function runPomodoroCommand(command: string)
	local step = PomodoroCommand.plan(command, { running = pom.running, mode = pom.mode })
	focusPanel = "pomodoro"
	if step.switchTo >= 0 then
		setPomodoroMode(step.switchTo)
	end
	if step.op == "start" then
		startPomodoro()
	elseif step.op == "pause" then
		pausePomodoro()
		stopAlarm("pomodoro")
	else
		resetPomodoro()
	end
end

local POMODORO_MODES: { [number]: boolean } = { [Pomodoro.WORK] = true, [Pomodoro.SHORT] = true, [Pomodoro.LONG] = true }

COMMANDS.pomodoro = function(args)
	local action = args.action
	if action == "toggle" then
		runPomodoroCommand("toggle")
	elseif action == "start" then
		startPomodoro()
	elseif action == "pause" then
		pausePomodoro()
		stopAlarm("pomodoro")
	elseif action == "skip" then
		skipPomodoro()
	elseif action == "reset" then
		resetPomodoro()
	elseif action == "setMode" then
		if typeof(args.mode) ~= "number" or POMODORO_MODES[args.mode] ~= true then
			return false, "invalid-mode"
		end
		setPomodoroMode(args.mode)
	else
		return false, "invalid-action"
	end
	focusChanged()
	return true
end

COMMANDS.timer = function(args)
	local action = args.action
	if action == "set" then
		local d = Duration.parseDuration(args.text)
		if not d.ok then
			return false, d.error or "invalid-duration"
		end
		setTimer(d.seconds, d.label)
		-- The Focus entry starts at once ("Enter starts"); capture uses startTimer.
		if args.start == true then
			startTimer()
		end
	elseif action == "preset" then
		local seconds = args.seconds
		if typeof(seconds) ~= "number" or seconds <= 0 or seconds > Duration.MAX_SECONDS then
			return false, "invalid-duration"
		end
		setTimer(math.floor(seconds), if typeof(args.label) == "string" then args.label else "")
		startTimer()
	elseif action == "toggle" then
		if tmr.total <= 0 then
			return false, "no-timer"
		end
		focusPanel = "timer"
		if alarmSource == "timer" then
			stopAlarm("timer")
		elseif tmr.running then
			pauseTimer()
		else
			startTimer()
		end
	elseif action == "reset" then
		resetTimer()
	else
		return false, "invalid-action"
	end
	focusChanged()
	return true
end

COMMANDS.setFocusPanel = function(args)
	if args.panel ~= "pomodoro" and args.panel ~= "timer" then
		return false, "invalid-panel"
	end
	focusPanel = args.panel
	publish()
	return true
end

-- Today's play button: link the task, switch to focus (ending a break) and start.
COMMANDS.linkTask = function(args)
	if not validId(args.id) then
		return false, "invalid-id"
	end
	if not Pomodoro.canFocusTask(pom.running, pom.mode) then
		return false, "focus-running"
	end
	pom.linkedTaskId = args.id
	if pom.mode ~= Pomodoro.WORK then
		setPomodoroMode(Pomodoro.WORK)
	end
	startPomodoro()
	focusPanel = "pomodoro"
	focusChanged()
	return true
end

CAPTURE_ACTIONS.pomodoro = function(p, done)
	runPomodoroCommand(tostring(p.command))
	focusChanged()
	done(true)
end

CAPTURE_ACTIONS.startTimer = function(p, done)
	setTimer(p.seconds, p.label)
	startTimer()
	focusChanged()
	done(true)
end

CAPTURE_ACTIONS.timerToggle = function(_p, done)
	local ok, err = COMMANDS.timer({ action = "toggle" }, done)
	done(ok == true, err)
end

CAPTURE_ACTIONS.timerStop = function(_p, done)
	if tmr.total <= 0 then
		done(false, "no-timer")
		return
	end
	focusPanel = "timer"
	resetTimer()
	focusChanged()
	done(true)
end

-- ---------------------------------------------------------------- bookmarks

local function fetchEnabled(): boolean
	return settings.fetch_previews ~= false
end

local startFetches: ({ any }) -> ()

local function finishFetch(id: string)
	inFlight[id] = nil
	local r = FetchPool.finish(fetchPool, id)
	fetchPool = r.pool
	startFetches(r.start)
end

local function downloadImage(id: string, token: number, imageUrl: string)
	local dest = thumbPathOf(id)
	if dest == nil or not Url.isPublicHttpUrl(imageUrl) then
		return
	end
	noctalia.mkdirAll(thumbDir)
	noctalia.download(imageUrl, dest, function(ok: boolean)
		if ok and Bookmarks.isCurrent(data, id, token) then
			change(Bookmarks.setImage(data, id, token, dest))
		end
	end)
end

startFetches = function(jobs: { any })
	for _, job in ipairs(jobs) do
		fetchGen += 1
		local gen = fetchGen
		inFlight[job.id] = { token = job.token, startedAt = nowMs(), gen = gen }
		noctalia.http({ url = job.url, method = "GET", follow_redirects = true }, function(res: any)
			local current = inFlight[job.id]
			if current == nil or current.gen ~= gen then
				return
			end
			finishFetch(job.id)
			if typeof(res) ~= "table" or res.ok ~= true or res.status ~= 200 or typeof(res.body) ~= "string" then
				change(Bookmarks.markFailed(data, job.id, job.token))
				return
			end
			local meta = PageMeta.parse(string.sub(res.body, 1, BODY_MAX), job.url)
			change(Bookmarks.applyPreview(data, job.id, job.token, meta))
			if meta.image ~= "" then
				downloadImage(job.id, job.token, meta.image)
			end
		end)
	end
end

-- Queues a fetch, or fails at once a URL that points at a private network.
local function requestPreview(bookmark: any)
	if not fetchEnabled() then
		return
	end
	if not Url.isPublicHttpUrl(bookmark.url) then
		change(Bookmarks.markFailed(data, bookmark.id, bookmark.token))
		return
	end
	local r = FetchPool.request(fetchPool, { id = bookmark.id, token = bookmark.token, url = bookmark.url })
	fetchPool = r.pool
	startFetches(r.start)
end

-- Requests past the budget fail; a late answer is dropped by its generation.
local function expireFetches(): boolean
	local expired = {}
	for id, f in inFlight do
		if nowMs() - f.startedAt >= FETCH_TIMEOUT_MS then
			table.insert(expired, { id = id, token = f.token })
		end
	end
	for _, e in ipairs(expired) do
		finishFetch(e.id)
		change(Bookmarks.markFailed(data, e.id, e.token))
	end
	return #expired > 0
end

local function addBookmark(url: any): (boolean, string?, any?)
	local r = Bookmarks.add(data, url, newId(), nowIso(), fetchEnabled())
	if r == nil then
		return false, "invalid-url"
	end
	change(r.data)
	requestPreview(r.bookmark)
	return true, nil, { id = r.bookmark.id, replaced = r.replaced }
end

COMMANDS.addBookmark = function(args)
	return addBookmark(args.url)
end

COMMANDS.refreshBookmark = function(args)
	if not validId(args.id) then
		return false, "invalid-id"
	end
	local r = Bookmarks.refresh(data, args.id, nowIso(), fetchEnabled())
	if r == nil then
		return false, "not-found"
	end
	change(r.data)
	requestPreview(r.bookmark)
	return true
end

COMMANDS.renameBookmark = function(args)
	if not validId(args.id) then
		return false, "invalid-id"
	end
	change(Bookmarks.rename(data, args.id, args.title))
	return true
end

COMMANDS.deleteBookmark = function(args)
	if not validId(args.id) then
		return false, "invalid-id"
	end
	inFlight[args.id] = nil
	change(Bookmarks.remove(data, args.id))
	local path = thumbPathOf(args.id)
	if path ~= nil then
		noctalia.removeFile(path)
	end
	return true
end

CAPTURE_ACTIONS.addBookmark = function(p, done)
	local ok, err = addBookmark(p.url)
	done(ok, err)
end

local function sendAck(entryName: string, seq: number, ok: boolean, err: string?, result: any?)
	noctalia.state.set("ack." .. entryName, {
		seq = seq,
		ok = ok,
		error = if ok then nil else (err or "failed"),
		result = result,
	})
end

local function runCommand(entryName: string, cmd: any)
	local handler = rawget(COMMANDS, cmd.name)
	if handler == nil then
		log("unknown command " .. tostring(cmd.name) .. " from " .. entryName)
		sendAck(entryName, cmd.seq, false, "unknown-command")
		return
	end
	local args = if typeof(cmd.args) == "table" then cmd.args else {}
	local replied = false
	local function reply(ok: boolean, err: string?, result: any?)
		if replied then
			return
		end
		replied = true
		sendAck(entryName, cmd.seq, ok == true, err, result)
	end
	local called, ok, err, result = pcall(handler, args, reply)
	if not called then
		log("command " .. tostring(cmd.name) .. " failed: " .. tostring(ok))
		reply(false, "internal-error")
		return
	end
	if ok == PENDING then
		return
	end
	reply(ok == true, err, result)
end

local function onCommands(entryName: string, list: any)
	for _, cmd in ipairs(Outbox.take(server, entryName, list)) do
		runCommand(entryName, cmd)
	end
end

-- ---------------------------------------------------------------- lifecycle

function update()
	if calendar.available and lastReloadMs ~= nil and nowMs() - (lastReloadMs :: number) >= CALENDAR_RELOAD_MS then
		if calendar.syncFailed then
			lastReloadMs = nowMs()
			requestSync()
		else
			loadWindow()
		end
	end
	if tickFocus() then
		focusChanged()
	end
	if lastThemeCheckMs == nil or nowMs() - (lastThemeCheckMs :: number) >= THEME_CHECK_MS then
		if ensureRings() then
			publish()
		end
	end
	expireFetches()
	if dirtyAt ~= nil and nowMs() - (dirtyAt :: number) >= SAVE_DELAY_MS then
		flush()
	end
end

-- REQ-012: noctalia msg plugin nandomoreirame/daybar:core all <event> [payload]
function onIpc(event: any, payload: any)
	if event == "toggle" then
		noctalia.togglePanel(TOOLBAR_PANEL)
	elseif event == "capture" then
		noctalia.togglePanel(CAPTURE_PANEL)
	elseif event == "open" then
		requestedTab = Tabs.initialTab(payload, settings.initial_tab, (data.ui or {}).lastTab)
		publish()
		if noctalia.state.get("toolbar.open") ~= true then
			noctalia.togglePanel(TOOLBAR_PANEL)
		end
	end
end

-- New settings apply without restarting a running clock.
function onConfigChanged()
	readSettings()
	pom.remaining = Pomodoro.idleRemaining(pom.started, pom.remaining, pom.mode, cfg())
	focusChanged()
end

function onExit(_signal: number?, _reason: string?)
	if dirtyAt ~= nil then
		flush()
	end
end

math.randomseed(math.floor(nowMs()) % 2147483647)
noctalia.setUpdateInterval(UPDATE_MS)
readSettings()
loadData()
pom.remaining = Pomodoro.durationFor(pom.mode, cfg())
-- After a restart the Timer view shows the last timer started, ready to run.
local recent = data.recentTimers or {}
if #recent > 0 and typeof(recent[1].seconds) == "number" then
	tmr.total = recent[1].seconds
	tmr.remaining = tmr.total
	tmr.label = recent[1].label or ""
end
ensureRings()
noctalia.sound.load(ALARM_SOUND, ALARM_FILE, function(ok: boolean, err: string?)
	soundReady = ok
	if not ok then
		log("cannot load the alarm sound: " .. tostring(err))
	end
end)
publish()
startCalendar()

if (data.ui or {}).clockOverlay == true then
	noctalia.togglePanel(CLOCK_PANEL)
end

noctalia.state.watch("toolbar.open", function(open: any)
	if open ~= true and requestedTab ~= nil then
		requestedTab = nil
		publish()
	end
end)

for _, entryName in ipairs(ENTRIES) do
	-- A restarted service must not rerun what it acked before the restart.
	local last = noctalia.state.get("ack." .. entryName)
	if typeof(last) == "table" and typeof(last.seq) == "number" then
		server.seen[entryName] = last.seq
	end
	noctalia.state.watch("cmd." .. entryName, function(list: any)
		onCommands(entryName, list)
	end)
	onCommands(entryName, noctalia.state.get("cmd." .. entryName))
end

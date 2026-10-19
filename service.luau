-- Daybar service (AD-201): the only entry that does files, processes, HTTP, sound,
-- timers and notifications. UI entries render the published `view` and send
-- commands through the outbox (`cmd.<entry>` -> `ack.<entry>`, AD-202).

local Store = require("./lib/store.luau")
local View = require("./lib/view.luau")
local Outbox = require("./lib/outbox.luau")
local Tasks = require("./lib/tasks.luau")
local Dates = require("./lib/dates.luau")
local Tbl = require("./lib/tbl.luau")
local Tabs = require("./lib/tabs.luau")
local Notes = require("./lib/notes.luau")
local Markdown = require("./lib/markdown.luau")

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

function onExit(_signal: number?, _reason: string?)
	if dirtyAt ~= nil then
		flush()
	end
end

math.randomseed(math.floor(nowMs()) % 2147483647)
noctalia.setUpdateInterval(UPDATE_MS)
readSettings()
loadData()
publish()

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

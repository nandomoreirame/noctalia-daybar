-- Daybar quick capture (REQ-013..015): one input, a live preview of what Enter
-- saves, Tab/Shift+Tab to force the type. The service resolves and saves the text
-- again on `commit`; a calculation is copied here and the panel stays open.

local Client = require("./views/client.luau")
local Registry = require("./lib/capture/registry.luau")
local TimerCapture = require("./lib/capture/timer.luau")
local PomodoroCapture = require("./lib/capture/pomodoro.luau")
local Format = require("./lib/format.luau")
local Pomodoro = require("./lib/pomodoro.luau")
local Bookmarks = require("./lib/bookmarks.luau")
local Tabs = require("./lib/tabs.luau")
local Clock = require("./lib/clock.luau")

local SEP = "  ·  "
local TYPE_ICONS: { [string]: string } = {
	task = "checkbox",
	event = "calendar-event",
	reminder = "bell",
	note = "note",
	link = "link",
	calculation = "calculator",
	timer = Clock.TIMER_ICON,
	pomodoro = Tabs.ICONS.focus,
}

local client = Client.new(noctalia.state, noctalia.nowMs(), "capture")

local text = ""
local forcedType: string? = nil
local inputRev = 0
local feedback = ""
local feedbackIsError = false
local busy = false
-- Bumped on open and close: an answer for an older session only notifies.
local session = 0

local function tr(key: string): string
	return noctalia.tr(key)
end

local function view(): { [string]: any }?
	local v = noctalia.state.get("view")
	return if typeof(v) == "table" then v else nil
end

local function nowSec(): number
	return math.floor(noctalia.nowMs() / 1000)
end

local function resolve(): { [string]: any }
	return Registry.resolve(text, forcedType, nowSec())
end

local function isCommandType(kind: string?): boolean
	return kind == "timer" or kind == "pomodoro"
end

local function timerHead(p: { [string]: any }): string
	local parts = { Pomodoro.formatClock(p.seconds) }
	if p.label ~= nil and p.label ~= "" then
		table.insert(parts, p.label)
	end
	return table.concat(parts, SEP)
end

local function previewText(r: { [string]: any }): string
	if not r.ok then
		return if string.match(text, "^%s*$") then tr("capture.hint") else tr("capture.error." .. tostring(r.error))
	end
	local p = r.payload
	local v = view() or {}
	if r.type == "timer" then
		local t = v.timer or {}
		local key = TimerCapture.previewKey(r.action, { set = t.set == true, running = t.running == true, ringing = v.alarmSource == "timer" })
		if r.action ~= "startTimer" then
			return tr(key)
		end
		local head = timerHead(p)
		if key == "" then
			return head
		end
		local note = string.gsub(tr(key), "{clock}", Pomodoro.formatClock(t.remaining or 0))
		return head .. SEP .. note
	end
	if r.type == "pomodoro" then
		local pom = v.pomodoro or {}
		return tr(PomodoroCapture.previewKey(p.command, { running = pom.running == true, mode = pom.mode or Pomodoro.WORK }))
	end
	if r.type == "calculation" then
		return "= " .. p.display
	end
	if r.type == "note" then
		return p.text
	end
	if r.type == "link" then
		return p.url
	end
	local w = Format.describeWhen(p.date, p.time or p.start, if r.type == "task" then nil else p.endTime, nowSec())
	local day = if w.day == "today" or w.day == "tomorrow" then tr("when." .. w.day) else w.day
	local whenParts = {}
	for _, s in { day, w.time } do
		if s ~= "" then
			table.insert(whenParts, s)
		end
	end
	local parts = {}
	for _, s in { p.title, table.concat(whenParts, " ") } do
		if s ~= nil and s ~= "" then
			table.insert(parts, s)
		end
	end
	return table.concat(parts, SEP)
end

local render: () -> ()

render = function()
	local r = resolve()
	local kind = r.type or "task"
	local offCycle = rawget(TYPE_ICONS, kind) == nil or not table.find(Registry.CYCLE, kind)
	local line = if feedback ~= "" then feedback else previewText(r)
	-- One tab per type in the Tab cycle; calculation and pomodoro sit outside it
	-- and show as a label on the right instead.
	local header = {}
	for _, t in ipairs(Registry.CYCLE) do
		local current = t == kind
		table.insert(header, ui.button({
			key = "type-" .. t,
			glyph = TYPE_ICONS[t],
			text = tr("capture.type." .. t),
			variant = if current then "secondary" else "ghost",
			selected = current,
			controlSize = "sm",
			onClick = function()
				forcedType = t
				-- A fresh input takes the focus back from the clicked tab (the
				-- seeded value keeps what was typed).
				inputRev += 1
				feedback = ""
				feedbackIsError = false
				render()
			end,
		}))
	end
	table.insert(header, ui.spacer({ flexGrow = 1 }))
	if offCycle then
		table.insert(header, ui.row({ key = "offcycle", gap = 6, align = "center" }, {
			ui.glyph({ name = TYPE_ICONS[kind] or "checkbox", size = 16, color = "primary" }),
			ui.label({ text = tr("capture.type." .. kind), fontWeight = "bold", color = "primary" }),
		}))
	end
	panel.render(ui.column({ gap = 10, padding = 16 }, {
		ui.row({ gap = 4, align = "center" }, header),
		ui.input({
			key = "input-" .. inputRev,
			value = text,
			focus = true,
			placeholder = tr("capture.placeholders." .. (if offCycle then "task" else kind)),
			onChange = "onChange",
			onSubmit = "onSubmit",
		}),
		ui.label({ text = line, color = if feedbackIsError then "error" else "on_surface_variant", maxLines = 2 }),
		ui.label({ text = tr("capture.keys"), fontSize = 11, color = "on_surface_variant" }),
	}))
end

local function clearField()
	text = ""
	forcedType = nil
	inputRev += 1
end

local function savedTitle(r: { [string]: any }): string
	return if isCommandType(r.type) then tr("capture.type." .. r.type) else tr("capture.saved." .. r.type)
end

local function submit(keepOpen: boolean)
	if busy then
		return
	end
	feedback = ""
	feedbackIsError = false
	if view() == nil then
		feedback = tr("capture.not-ready")
		feedbackIsError = true
		render()
		return
	end
	local r = resolve()
	if not r.ok then
		feedback = tr("capture.error." .. tostring(r.error))
		feedbackIsError = true
		render()
		return
	end
	if r.action == "copy" then
		noctalia.copyToClipboard(tostring(r.payload.display), "text/plain")
		feedback = tr("capture.copied")
		render()
		return
	end
	busy = true
	local startedIn = session
	local typed = text
	-- Commands describe the state BEFORE they run, so the line is taken now.
	local shown = if r.action == "startTimer" then timerHead(r.payload) else previewText(r)
	client.send("commit", { text = typed, type = forcedType }, function(ack: any)
		if startedIn ~= session then
			if ack.ok then
				noctalia.notify(savedTitle(r), shown)
			else
				noctalia.notifyError(tr("capture.failed-title"), tr("capture.error." .. tostring(ack.error)) .. "\n" .. typed)
			end
			return
		end
		busy = false
		if not ack.ok then
			feedback = tr("capture.error." .. tostring(ack.error))
			feedbackIsError = true
			noctalia.notifyError(tr("capture.failed-title"), feedback)
			render()
			return
		end
		noctalia.notify(savedTitle(r), shown)
		if keepOpen then
			clearField()
			render()
		else
			panel.close()
		end
	end)
	render()
end

function onOpen(_context: string?)
	session += 1
	busy = false
	feedback = ""
	feedbackIsError = false
	clearField()
	local v = view()
	if v ~= nil then
		text = Bookmarks.prefillFromClipboard(noctalia.clipboardText(), v.data or { bookmarks = {} })
	end
	render()
end

function onClose()
	session += 1
	busy = false
	clearField()
end

function onChange(value: string)
	text = value or ""
	feedback = ""
	feedbackIsError = false
	render()
end

function onSubmit(value: string)
	text = value or text
	submit(false)
end

-- tab / shift+tab force the next / previous type; shift+Return saves and stays open.
function onKey(chord: string, pressed: boolean)
	if not pressed then
		return
	end
	if chord == "shift+Return" then
		submit(true)
		return
	end
	if chord ~= "tab" and chord ~= "shift+tab" then
		return
	end
	local current = resolve().type
	if not table.find(Registry.CYCLE, current) then
		return
	end
	forcedType = if chord == "shift+tab" then Registry.prevType(current) else Registry.nextType(current)
	render()
end

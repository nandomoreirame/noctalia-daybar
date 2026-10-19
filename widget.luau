-- Daybar bar widget (REQ-026): the running clock, else the tab the toolbar opens
-- on. Click toggles the toolbar; middle click pauses or resumes the clock shown.

local ClockFmt = require("./views/clockfmt.luau")
local Client = require("./views/client.luau")
local Clock = require("./lib/clock.luau")
local Tabs = require("./lib/tabs.luau")
local Events = require("./lib/events.luau")

local TOOLBAR_PANEL = "nandomoreirame/daybar:toolbar"
local PROGRESS_WIDTH = 32

local client = Client.new(noctalia.state, noctalia.nowMs(), "bar")

local function view(): { [string]: any }?
	local v = noctalia.state.get("view")
	return if typeof(v) == "table" then v else nil
end

local function tooltipFor(v: { [string]: any }?, clock: { [string]: any }?): string
	if clock ~= nil then
		local suffix = if clock.labelKey ~= nil then noctalia.tr(clock.labelKey) else clock.label
		return clock.text .. (if suffix ~= "" then " · " .. suffix else "")
	end
	if v ~= nil then
		local nextEv = Events.nextEvent((v.calendar or {}).events, math.floor(noctalia.nowMs() / 1000))
		if nextEv ~= nil then
			return nextEv.time .. " " .. tostring(nextEv.summary)
		end
	end
	return "Daybar"
end

local function render()
	local v = view()
	local container = if barWidget.isVertical() then ui.column else ui.row
	if v == nil then
		barWidget.render(container({ gap = 6, align = "center" }, {
			ui.glyph({ name = "calendar-event", size = 14 }),
		}))
		barWidget.setTooltip("Daybar")
		return
	end
	local clock = ClockFmt.bar(v, noctalia.nowMs())
	local children
	if clock ~= nil then
		children = {
			ui.glyph({ name = clock.glyph, size = 14, color = "primary" }),
			ui.label({ text = clock.text, color = "primary" }),
			ui.progress({ progress = clock.progress, width = PROGRESS_WIDTH, height = 4, fill = "primary" }),
		}
	else
		local tab = Tabs.initialTab("", (v.settings or {}).initial_tab, ((v.data or {}).ui or {}).lastTab)
		children = {
			ui.glyph({ name = Tabs.ICONS[tab], size = 14 }),
			ui.label({ text = noctalia.tr("tabs." .. tab) }),
		}
	end
	barWidget.render(container({ gap = 6, align = "center" }, children))
	barWidget.setTooltip(tooltipFor(v, clock))
end

function update()
	render()
end

function onClick()
	noctalia.togglePanel(TOOLBAR_PANEL)
end

-- A ringing timer is only silenced by its toggle; the service owns that rule.
function onMiddleClick()
	local v = view()
	local clock = if v ~= nil then ClockFmt.bar(v, noctalia.nowMs()) else nil
	local target = Clock.middleClickTarget(if clock ~= nil then clock.source else "")
	client.send(target, { action = "toggle" })
end

noctalia.setUpdateInterval(1000)
noctalia.state.watch("view", function()
	render()
end)
render()

-- Daybar toolbar (REQ-021..031): Calendar, Today, Focus, Bookmarks and Notes tabs
-- over the service's published view. Every change goes out as a command.

local Client = require("./views/client.luau")
local TabsView = require("./views/tabs.luau")
local TodayView = require("./views/today.luau")
local CalendarView = require("./views/calendar.luau")
local FocusView = require("./views/focus.luau")
local BookmarksView = require("./views/bookmarks.luau")
local NotesView = require("./views/notes.luau")
local Tabs = require("./lib/tabs.luau")

local client = Client.new(noctalia.state, noctalia.nowMs(), "toolbar")

-- The panel is 450 px tall (plugin.toml) and the root column does not stretch to
-- it, so the body gets an explicit height: what is left after the host's own
-- padding, the tab row and the gaps, with room for the bottom padding.
local BODY_HEIGHT = 340

local TAB_VIEWS: { [string]: any } = {
	today = TodayView,
	calendar = CalendarView,
	focus = FocusView,
	bookmarks = BookmarksView,
	notes = NotesView,
}

local isOpen = false
local activeTab = Tabs.FALLBACK
-- Per-tab UI state (inline edits, confirmations), kept across renders.
local tabState: { [string]: { [string]: any } } = {}

local render: () -> ()

local function view(): { [string]: any }?
	local v = noctalia.state.get("view")
	return if typeof(v) == "table" then v else nil
end

local function stateOf(tab: string): { [string]: any }
	local st = tabState[tab]
	if st == nil then
		st = {}
		tabState[tab] = st
	end
	return st
end

local function context(v: { [string]: any }?): { [string]: any }
	return {
		ui = ui,
		tr = noctalia.tr,
		view = v,
		nowMs = noctalia.nowMs(),
		send = client.send,
		st = stateOf(activeTab),
		render = function()
			render()
		end,
		panel = panel,
		state = noctalia.state,
		togglePanel = noctalia.togglePanel,
	}
end

local function selectTab(tab: string)
	if not Tabs.isTab(tab) then
		return
	end
	activeTab = tab
	panel.setWantsSecondTicks(tab == "focus")
	client.send("setLastTab", { tab = tab })
	render()
end

render = function()
	if not isOpen then
		return
	end
	local v = view()
	local ctx = context(v)
	local body
	local tabView = TAB_VIEWS[activeTab]
	if v == nil then
		body = ui.label({ text = noctalia.tr("capture.not-ready"), color = "on_surface_variant" })
	elseif tabView ~= nil then
		body = tabView.build(ctx)
	else
		body = ui.label({ text = noctalia.tr("tabs." .. activeTab) })
	end
	panel.render(ui.column({ gap = 10, padding = 12 }, {
		TabsView.build(ctx, activeTab, selectTab, function()
			client.send("reloadCalendar", {})
		end),
		ui.column({ key = "body", height = BODY_HEIGHT }, { body }),
	}))
end

function onOpen(_context: string?)
	isOpen = true
	noctalia.state.set("toolbar.open", true)
	local v = view() or {}
	local requested = v.requestedTab
	activeTab = if Tabs.isTab(requested)
		then requested
		else Tabs.initialTab(nil, (v.settings or {}).initial_tab, ((v.data or {}).ui or {}).lastTab)
	panel.setWantsSecondTicks(activeTab == "focus")
	render()
end

function onClose()
	isOpen = false
	noctalia.state.set("toolbar.open", false)
end

function update()
	render()
end

noctalia.state.watch("view", function()
	render()
end)

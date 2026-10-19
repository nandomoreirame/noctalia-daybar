local assert = require("./support/assert")
local runner = require("./support/runner")
local mock = require("./support/noctalia_mock")
local entry = require("./support/entry")
local U = require("./support/ui_helpers")

local describe, it = runner.describe, runner.it

local NOW = 1792065600000

local function view(over)
	local v = {
		rev = 1,
		now = NOW,
		data = { tasks = {}, eventChecks = {}, bookmarks = {}, notes = {}, recentTimers = {}, focusLog = {}, ui = { lastTab = "calendar" } },
		settings = { initial_tab = "last", daily_pomodoro_goal = 8 },
		calendar = { available = false, events = {} },
		pomodoro = { mode = 0, running = false, remaining = 1500, total = 1500, completed = 0 },
		timer = { set = false, running = false, remaining = 0, total = 0, label = "" },
		alarmSource = "",
		focusPanel = "pomodoro",
		details = {},
		deleting = {},
	}
	for k, val in over or {} do
		v[k] = val
	end
	return v
end

local function boot(v)
	local p = entry.load("toolbar.luau", { now = NOW })
	p.env.noctalia.state.set("view", v or view())
	p.call("onOpen")
	return p
end

local function tree(p)
	local calls = mock.calls(p.env, "panel.render")
	return calls[#calls][1]
end

local function selectedTab(p)
	return U.findAll(tree(p), function(n)
		return n.type == "button" and n.props.selected == true and n.props.key ~= nil and string.sub(n.props.key, 1, 4) == "tab-"
	end)[1].props.key
end

describe("toolbar", function()
	it("publishes its open state", function()
		local p = boot()
		assert.equal(p.env.noctalia.state.get("toolbar.open"), true)
		p.call("onClose")
		assert.equal(p.env.noctalia.state.get("toolbar.open"), false)
	end)

	it("opens on the requested tab, else the initial tab", function()
		assert.equal(selectedTab(boot()), "tab-calendar")
		assert.equal(selectedTab(boot(view({ requestedTab = "notes" }))), "tab-notes")
	end)

	it("a tab click switches and remembers it", function()
		local p = boot()
		U.byKey(tree(p), "tab-today").props.onClick()
		assert.equal(selectedTab(p), "tab-today")
		local cmd = p.env.noctalia.state.get("cmd.toolbar")[1]
		assert.equal(cmd.name, "setLastTab")
		assert.same(cmd.args, { tab = "today" })
	end)

	it("re-renders on view changes only while open", function()
		local p = boot()
		local n = #mock.calls(p.env, "panel.render")
		p.env.noctalia.state.set("view", view({ rev = 2 }))
		assert.equal(#mock.calls(p.env, "panel.render"), n + 1)
		p.call("onClose")
		p.env.noctalia.state.set("view", view({ rev = 3 }))
		assert.equal(#mock.calls(p.env, "panel.render"), n + 1)
	end)

	it("ticks every second only on the Focus tab", function()
		local p = boot()
		local ticks = mock.calls(p.env, "panel.setWantsSecondTicks")
		assert.same(ticks[#ticks], { false })
		U.byKey(tree(p), "tab-focus").props.onClick()
		ticks = mock.calls(p.env, "panel.setWantsSecondTicks")
		assert.same(ticks[#ticks], { true })
	end)

	it("gives the tab body the panel's remaining height", function()
		local p = boot()
		local body = U.byKey(tree(p), "body")
		assert.equal(typeof(body.props.height), "number")
		assert.equal(body.props.height > 300, true)
		-- Room left under the body for the bottom padding (panel 450, tab row and gaps).
		assert.equal(body.props.height <= 350, true)
	end)

	it("refresh pushes reloadCalendar", function()
		local p = boot()
		U.byKey(tree(p), "reload").props.onClick()
		assert.equal(p.env.noctalia.state.get("cmd.toolbar")[1].name, "reloadCalendar")
	end)
end)

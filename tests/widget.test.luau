local assert = require("./support/assert")
local runner = require("./support/runner")
local mock = require("./support/noctalia_mock")
local entry = require("./support/entry")

local describe, it = runner.describe, runner.it

local NOW = 1792065600000 -- 2026-10-15 09:00 in America/Sao_Paulo

local function baseView(over)
	local v = {
		rev = 1,
		now = NOW,
		data = { ui = { lastTab = "today" }, tasks = {} },
		settings = { initial_tab = "last" },
		calendar = { available = true, events = {} },
		pomodoro = { mode = 0, running = false, started = false, remaining = 1500, total = 1500, completed = 0 },
		timer = { set = false, running = false, remaining = 0, total = 0, label = "" },
		alarmSource = "",
		focusPanel = "pomodoro",
	}
	for k, val in over or {} do
		v[k] = val
	end
	return v
end

local function boot(opts)
	local o = opts or {}
	local w = entry.load("widget.luau", { now = NOW, vertical = o.vertical })
	if o.view ~= nil then
		w.env.noctalia.state.set("view", o.view)
	end
	return w
end

-- The last tree passed to barWidget.render.
local function tree(w)
	local calls = mock.calls(w.env, "barWidget.render")
	return calls[#calls][1]
end

local function find(node, kind)
	if node.type == kind then
		return node
	end
	for _, child in node.children or {} do
		local hit = find(child, kind)
		if hit ~= nil then
			return hit
		end
	end
	return nil
end

local function lastTooltip(w)
	local calls = mock.calls(w.env, "barWidget.setTooltip")
	return calls[#calls][1]
end

describe("bar widget", function()
	it("renders only the calendar glyph before the service publishes", function()
		local w = boot()
		local t = tree(w)
		assert.equal(t.type, "row")
		assert.equal(#t.children, 1)
		assert.equal(t.children[1].type, "glyph")
		assert.equal(t.children[1].props.name, "calendar-event")
	end)

	it("shows the running pomodoro with its digits and progress", function()
		local view = baseView({
			pomodoro = { mode = 0, running = true, started = true, endsAtMs = NOW + 754000, remaining = 1500, total = 1500 },
		})
		local w = boot({ view = view })
		local t = tree(w)
		assert.equal(t.type, "row")
		assert.equal(find(t, "glyph").props.name, "hourglass")
		assert.equal(find(t, "label").props.text, "12:34")
		local bar = find(t, "progress")
		assert.equal(bar.props.width, 32)
		assert.equal(math.abs(bar.props.progress - 754 / 1500) < 0.001, true)
	end)

	it("uses a column on a vertical bar", function()
		local view = baseView({
			pomodoro = { mode = 0, running = true, started = true, endsAtMs = NOW + 754000, remaining = 1500, total = 1500 },
		})
		local w = boot({ view = view, vertical = true })
		assert.equal(tree(w).type, "column")
	end)

	it("shows a ringing timer as the alarm at 00:00", function()
		local view = baseView({
			alarmSource = "timer",
			timer = { set = true, running = false, remaining = 0, total = 300, label = "chá" },
		})
		local w = boot({ view = view })
		local t = tree(w)
		assert.equal(find(t, "glyph").props.name, "alarm")
		assert.equal(find(t, "label").props.text, "00:00")
	end)

	it("keys the clock and idle nodes apart so a stopped clock drops its colors", function()
		local running = baseView({
			pomodoro = { mode = 0, running = true, started = true, endsAtMs = NOW + 754000, remaining = 1500, total = 1500 },
		})
		local w = boot({ view = running })
		local clockKey = find(tree(w), "glyph").props.key
		w.env.noctalia.state.set("view", baseView())
		local idleKey = find(tree(w), "glyph").props.key
		assert.equal(typeof(clockKey), "string")
		assert.equal(typeof(idleKey), "string")
		assert.equal(clockKey ~= idleKey, true)
	end)

	it("idles on the next tab's glyph and name", function()
		local w = boot({ view = baseView() })
		local t = tree(w)
		assert.equal(find(t, "glyph").props.name, "list-check")
		assert.equal(find(t, "label").props.text, "tabs.today")
	end)

	it("click toggles the toolbar", function()
		local w = boot({ view = baseView() })
		w.call("onClick")
		assert.equal(mock.calls(w.env, "noctalia.togglePanel")[1][1], "nandomoreirame/daybar:toolbar")
	end)

	it("middle click toggles the clock shown, else the pomodoro", function()
		local w = boot({ view = baseView() })
		w.call("onMiddleClick")
		local cmds = w.env.noctalia.state.get("cmd.bar")
		assert.equal(cmds[1].name, "pomodoro")
		assert.same(cmds[1].args, { action = "toggle" })

		local w2 = boot({
			view = baseView({ timer = { set = true, running = true, endsAtMs = NOW + 60000, remaining = 300, total = 300, label = "" } }),
		})
		w2.call("onMiddleClick")
		local cmds2 = w2.env.noctalia.state.get("cmd.bar")
		assert.equal(cmds2[1].name, "timer")
		assert.same(cmds2[1].args, { action = "toggle" })
	end)

	it("drops acknowledged commands from the outbox", function()
		local w = boot({ view = baseView() })
		w.call("onMiddleClick")
		local seq = w.env.noctalia.state.get("cmd.bar")[1].seq
		w.env.noctalia.state.set("ack.bar", { seq = seq, ok = true })
		assert.same(w.env.noctalia.state.get("cmd.bar"), {})
	end)

	it("tooltip shows the running clock, else the next event, else the name", function()
		local running = baseView({
			pomodoro = { mode = 0, running = true, started = true, endsAtMs = NOW + 754000, remaining = 1500, total = 1500 },
		})
		assert.equal(lastTooltip(boot({ view = running })), "12:34 · focus.mode.work")

		local start = 1792065600 + 3600 -- 10:00 today
		local withEvent = baseView({
			calendar = {
				available = true,
				events = { { uid = "a", summary = "Daily", start = start, ["end"] = start + 1800, allDay = false } },
			},
		})
		assert.equal(lastTooltip(boot({ view = withEvent })), "10:00 Daily")

		assert.equal(lastTooltip(boot({ view = baseView() })), "Daybar")
	end)

	it("update recomputes the digits from the deadline", function()
		local view = baseView({
			pomodoro = { mode = 0, running = true, started = true, endsAtMs = NOW + 754000, remaining = 1500, total = 1500 },
		})
		local w = boot({ view = view })
		mock.advance(w.env, 4000)
		w.call("update")
		assert.equal(find(tree(w), "label").props.text, "12:30")
	end)
end)

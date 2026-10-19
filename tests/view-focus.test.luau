local assert = require("./support/assert")
local runner = require("./support/runner")
local mock = require("./support/noctalia_mock")
local modules = require("./support/modules")
local U = require("./support/ui_helpers")

local describe, it = runner.describe, runner.it

local FocusView = modules.load("views/focus.luau")

local NOW = 1792065600000
local TODAY = "2026-10-15"

local function makeCtx(over)
	local env = mock.new({})
	local sent = {}
	local ctx = {
		ui = env.ui,
		tr = function(k)
			return k
		end,
		nowMs = NOW,
		st = {},
		sent = sent,
		view = {
			data = {
				tasks = { { id = "t1", title = "write", date = TODAY, done = false }, { id = "t2", title = "done", date = TODAY, done = true } },
				focusLog = { [TODAY] = 3 },
				recentTimers = { { seconds = 300, label = "chá" } },
				ui = { clockOverlay = false },
			},
			settings = { daily_pomodoro_goal = 8 },
			pomodoro = { mode = 0, running = true, started = true, endsAtMs = NOW + 754000, remaining = 1500, total = 1500, completed = 1 },
			timer = { set = false, running = false, remaining = 0, total = 0, label = "" },
			alarmSource = "",
			focusPanel = "pomodoro",
		},
	}
	ctx.send = function(name, args)
		table.insert(sent, { name = name, args = args })
	end
	ctx.render = function() end
	for k, v in over or {} do
		ctx.view[k] = v
	end
	return ctx
end

describe("focus view", function()
	it("has four mode chips and maps clicks through chipAction", function()
		local ctx = makeCtx()
		local tree = FocusView.build(ctx)
		for _, key in { "chip-0", "chip-1", "chip-2", "chip-timer" } do
			assert.equal(U.byKey(tree, key) ~= nil, true)
		end
		U.byKey(tree, "chip-1").props.onClick()
		assert.same(ctx.sent[1], { name = "pomodoro", args = { action = "setMode", mode = 1 } })
		U.byKey(tree, "chip-timer").props.onClick()
		assert.same(ctx.sent[2], { name = "setFocusPanel", args = { panel = "timer" } })
	end)

	it("coming back from the timer to the current mode only switches the view", function()
		local ctx = makeCtx({ focusPanel = "timer" })
		U.byKey(FocusView.build(ctx), "chip-0").props.onClick()
		assert.equal(#ctx.sent, 1)
		assert.same(ctx.sent[1], { name = "setFocusPanel", args = { panel = "pomodoro" } })
	end)

	it("shows the pomodoro digits, progress, controls and today's count", function()
		local ctx = makeCtx()
		local tree = FocusView.build(ctx)
		assert.equal(U.hasLabel(tree, "12:34"), true)
		assert.equal(#U.ofType(tree, "progress"), 1)
		assert.equal(U.hasLabel(tree, "focus.today-goal"), true)
		U.button(tree, "glyph", "player-pause").props.onClick()
		U.button(tree, "glyph", "player-skip-forward").props.onClick()
		U.button(tree, "glyph", "refresh").props.onClick()
		assert.same(ctx.sent[1].args, { action = "toggle" })
		assert.same(ctx.sent[2].args, { action = "skip" })
		assert.same(ctx.sent[3].args, { action = "reset" })
	end)

	it("links one of today's open tasks", function()
		local ctx = makeCtx()
		local select = U.ofType(FocusView.build(ctx), "select")[1]
		assert.same(select.props.options, { "focus.no-task", "write" })
		select.props.onChange("1")
		assert.same(ctx.sent[1], { name = "linkTask", args = { id = "t1" } })
	end)

	it("sets, presets and replays timers", function()
		local ctx = makeCtx({ focusPanel = "timer" })
		local tree = FocusView.build(ctx)
		U.ofType(tree, "input")[1].props.onSubmit("10m chá")
		assert.same(ctx.sent[1], { name = "timer", args = { action = "set", text = "10m chá" } })
		U.byKey(tree, "preset-5").props.onClick()
		assert.same(ctx.sent[2].args, { action = "preset", seconds = 300 })
		U.byKey(tree, "recent-1").props.onClick()
		assert.same(ctx.sent[3].args, { action = "preset", seconds = 300, label = "chá" })
		assert.equal(U.hasLabel(tree, "05:00 · chá") or U.button(tree, "text", "05:00 · chá") ~= nil, true)
	end)

	it("controls a timer that is set", function()
		local ctx = makeCtx({ focusPanel = "timer", timer = { set = true, running = false, remaining = 300, total = 300, label = "" } })
		local tree = FocusView.build(ctx)
		assert.equal(U.hasLabel(tree, "05:00"), true)
		U.button(tree, "glyph", "player-play").props.onClick()
		U.button(tree, "glyph", "refresh").props.onClick()
		assert.same(ctx.sent[1], { name = "timer", args = { action = "toggle" } })
		assert.same(ctx.sent[2], { name = "timer", args = { action = "reset" } })
	end)

	it("the pin toggle mirrors and sets the clock overlay", function()
		local ctx = makeCtx()
		local toggle = U.ofType(FocusView.build(ctx), "toggle")[1]
		assert.equal(toggle.props.checked, false)
		toggle.props.onChange("true")
		assert.same(ctx.sent[1], { name = "setClockOverlay", args = { value = true } })
	end)
end)

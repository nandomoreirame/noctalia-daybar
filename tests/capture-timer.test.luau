local assert = require("./support/assert")
local runner = require("./support/runner")
local modules = require("./support/modules")

local describe, it = runner.describe, runner.it
local Timer = modules.load("lib/capture/timer.luau")
local PomodoroCommand = modules.load("lib/capture/pomodoro.luau")

describe("timer capture", function()
	it("starts a timer with a duration and label", function()
		assert.same(Timer.build("chá 5m"), { ok = true, type = "timer", action = "startTimer", payload = { seconds = 300, label = "chá" } })
	end)

	it("toggles with an empty body and resets with parar/stop", function()
		assert.same(Timer.build(""), { ok = true, type = "timer", action = "timerToggle", payload = {} })
		assert.same(Timer.build(nil), { ok = true, type = "timer", action = "timerToggle", payload = {} })
		assert.equal(Timer.build("PARAR").action, "timerStop")
		assert.equal(Timer.build("stop").action, "timerStop")
	end)

	it("passes the parser error through", function()
		assert.same(Timer.build("chá"), { ok = false, type = "timer", error = "needs-duration" })
		assert.same(Timer.build("25h"), { ok = false, type = "timer", error = "invalid-duration" })
	end)

	it("allows an empty body only through its prefix", function()
		assert.equal(Timer.ALLOW_EMPTY, true)
	end)

	it("names the preview line from the timer state", function()
		local none = { set = false, running = false }
		local paused = { set = true, running = false }
		local running = { set = true, running = true }
		assert.equal(Timer.previewKey("startTimer", none), "")
		assert.equal(Timer.previewKey("startTimer", paused), "capture.timer.replaces")
		assert.equal(Timer.previewKey("timerToggle", none), "capture.error.no-timer")
		assert.equal(Timer.previewKey("timerToggle", paused), "capture.timer.resume")
		assert.equal(Timer.previewKey("timerToggle", running), "capture.timer.pause")
		assert.equal(Timer.previewKey("timerStop", running), "capture.timer.stop")
		-- While its alarm rings, "/t" only silences it instead of restarting the countdown.
		assert.equal(Timer.previewKey("timerToggle", { set = true, running = false, ringing = true }), "capture.timer.dismiss")
	end)
end)

describe("pomodoro command capture", function()
	local cases = {
		{ "", "toggle" },
		{ "foco", "work" },
		{ "Focus", "work" },
		{ "curta", "short" },
		{ "pausa  curta", "short" },
		{ "short", "short" },
		{ "longa", "long" },
		{ "pausa longa", "long" },
		{ "parar", "stop" },
		{ "stop", "stop" },
	}
	for _, case in cases do
		it(string.format("'%s' -> %s", case[1], case[2]), function()
			assert.same(PomodoroCommand.build(case[1]), { ok = true, type = "pomodoro", action = "pomodoro", payload = { command = case[2] } })
		end)
	end

	it("rejects anything else", function()
		assert.same(PomodoroCommand.build("agora"), { ok = false, type = "pomodoro", error = "unknown-command" })
		assert.same(PomodoroCommand.build("constructor"), { ok = false, type = "pomodoro", error = "unknown-command" })
		assert.same(PomodoroCommand.build("__index"), { ok = false, type = "pomodoro", error = "unknown-command" })
	end)

	it("allows an empty body", function()
		assert.equal(PomodoroCommand.ALLOW_EMPTY, true)
	end)

	-- modes: WORK 0, SHORT 1, LONG 2
	it("plans what Enter does from the pomodoro state", function()
		assert.same(PomodoroCommand.plan("toggle", { running = true, mode = 0 }), { op = "pause", switchTo = -1 })
		assert.same(PomodoroCommand.plan("toggle", { running = false, mode = 0 }), { op = "start", switchTo = -1 })
		assert.same(PomodoroCommand.plan("short", { running = false, mode = 1 }), { op = "start", switchTo = -1 })
		assert.same(PomodoroCommand.plan("long", { running = true, mode = 0 }), { op = "start", switchTo = 2 })
		assert.same(PomodoroCommand.plan("stop", { running = true, mode = 2 }), { op = "reset", switchTo = -1 })
	end)

	it("names the preview line", function()
		assert.equal(PomodoroCommand.previewKey("toggle", { running = true, mode = 0 }), "capture.pomodoro.pause")
		assert.equal(PomodoroCommand.previewKey("toggle", { running = false, mode = 1 }), "capture.pomodoro.start-short")
		assert.equal(PomodoroCommand.previewKey("work", { running = false, mode = 2 }), "capture.pomodoro.start-work")
		assert.equal(PomodoroCommand.previewKey("stop", { running = false, mode = 0 }), "capture.pomodoro.stop")
	end)
end)

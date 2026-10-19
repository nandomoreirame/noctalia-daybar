local assert = require("./support/assert")
local runner = require("./support/runner")
local modules = require("./support/modules")

local describe, it = runner.describe, runner.it
local Clock = modules.load("lib/clock.luau")

describe("barSource", function()
	local base = { pomodoroRunning = false, timerRunning = false, alarmSource = "" }

	it("shows the running clock first", function()
		assert.equal(Clock.barSource({
			pomodoroRunning = false,
			timerRunning = true,
			alarmSource = "",
		}), "timer")
		assert.equal(Clock.barSource({
			pomodoroRunning = true,
			timerRunning = false,
			alarmSource = "timer",
		}), "pomodoro")
		-- Never expected (starting one pauses the other), but the timer must still win.
		assert.equal(Clock.barSource({
			pomodoroRunning = true,
			timerRunning = true,
			alarmSource = "pomodoro",
		}), "timer")
	end)

	it("falls back to the clock whose alarm rings, else nothing", function()
		assert.equal(Clock.barSource({
			pomodoroRunning = false,
			timerRunning = false,
			alarmSource = "timer",
		}), "timer")
		assert.equal(Clock.barSource({
			pomodoroRunning = false,
			timerRunning = false,
			alarmSource = "pomodoro",
		}), "pomodoro")
		assert.equal(Clock.barSource(base), "")
		assert.equal(Clock.barSource({
			pomodoroRunning = false,
			timerRunning = false,
			alarmSource = "junk",
		}), "")
	end)
end)

describe("progress", function()
	it("is remaining over total, clamped to [0, 1]", function()
		assert.equal(Clock.progress(150, 300), 0.5)
		assert.equal(Clock.progress(400, 300), 1)
		assert.equal(Clock.progress(-2, 300), 0)
	end)

	it("is 0 without a positive total", function()
		assert.equal(Clock.progress(10, 0), 0)
		assert.equal(Clock.progress(10, nil), 0)
	end)
end)

describe("middleClickTarget", function()
	it("drives the clock shown, else the pomodoro", function()
		assert.equal(Clock.middleClickTarget("timer"), "timer")
		assert.equal(Clock.middleClickTarget("pomodoro"), "pomodoro")
		assert.equal(Clock.middleClickTarget(""), "pomodoro")
	end)
end)

describe("chipAction", function()
	it("the Timer chip only switches the view", function()
		assert.equal(Clock.chipAction(Clock.TIMER_CHIP, "pomodoro", 0), "show-timer")
		assert.equal(Clock.chipAction(Clock.TIMER_CHIP, "timer", 0), "show-timer")
	end)

	it("the current pomodoro mode seen from the Timer view switches back without a reset", function()
		assert.equal(Clock.chipAction(1, "timer", 1), "show-pomodoro")
		assert.equal(Clock.chipAction(0, "timer", 0), "show-pomodoro")
	end)

	it("any other pomodoro chip sets the mode, as before", function()
		assert.equal(Clock.chipAction(2, "timer", 1), "set-mode")
		assert.equal(Clock.chipAction(1, "pomodoro", 1), "set-mode")
	end)

	it("names the timer icon", function()
		assert.equal(Clock.TIMER_ICON, "alarm")
	end)
end)

describe("shownClock", function()
	local base = {
		pomodoroRunning = false,
		timerRunning = false,
		alarmSource = "",
		focusPanel = "pomodoro",
	}

	it("follows the bar rule while a clock runs or rings", function()
		assert.equal(Clock.shownClock({
			pomodoroRunning = false,
			timerRunning = true,
			alarmSource = "",
			focusPanel = "pomodoro",
		}), "timer")
		assert.equal(Clock.shownClock({
			pomodoroRunning = true,
			timerRunning = false,
			alarmSource = "",
			focusPanel = "timer",
		}), "pomodoro")
		assert.equal(Clock.shownClock({
			pomodoroRunning = false,
			timerRunning = false,
			alarmSource = "timer",
			focusPanel = "pomodoro",
		}), "timer")
	end)

	it("falls back to the Focus view when nothing runs", function()
		assert.equal(Clock.shownClock(base), "pomodoro")
		assert.equal(Clock.shownClock({
			pomodoroRunning = false,
			timerRunning = false,
			alarmSource = "",
			focusPanel = "timer",
		}), "timer")
		assert.equal(Clock.shownClock({
			pomodoroRunning = false,
			timerRunning = false,
			alarmSource = "",
			focusPanel = "junk",
		}), "pomodoro")
	end)
end)

describe("remaining", function()
	it("computes the remaining seconds from the deadline while running", function()
		assert.equal(Clock.remaining({ running = true, endsAtMs = 10500, remaining = 99 }, 1000), 10)
		assert.equal(Clock.remaining({ running = false, remaining = 42 }, 1000), 42)
	end)
end)

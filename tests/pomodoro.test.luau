local assert = require("./support/assert")
local runner = require("./support/runner")
local modules = require("./support/modules")

local describe, it = runner.describe, runner.it
local Pomodoro = modules.load("lib/pomodoro.luau")

local cfg = {
	work = 1500,
	short = 300,
	long = 900,
	sessionsBeforeLong = 2,
	autoStartBreaks = true,
	autoStartWork = false,
}

describe("pomodoro", function()
	it("maps modes to durations", function()
		assert.same({
			Pomodoro.durationFor(Pomodoro.WORK, cfg),
			Pomodoro.durationFor(Pomodoro.SHORT, cfg),
			Pomodoro.durationFor(Pomodoro.LONG, cfg),
		}, { 1500, 300, 900 })
	end)

	it("cycles work -> short -> work -> long -> work", function()
		local s = { mode = Pomodoro.WORK, completed = 0 }
		local seen = {}
		for _ = 1, 5 do
			s = Pomodoro.nextPhase(s, cfg)
			table.insert(seen, { s.mode, s.completed })
		end
		assert.same(seen, {
			{ Pomodoro.SHORT, 0 },
			{ Pomodoro.WORK, 1 },
			{ Pomodoro.LONG, 1 },
			{ Pomodoro.WORK, 0 },
			{ Pomodoro.SHORT, 0 },
		})
	end)

	it("reports work completion and auto-start per phase", function()
		assert.same(Pomodoro.finish({ mode = Pomodoro.WORK, completed = 0 }, cfg), {
			next = { mode = Pomodoro.SHORT, completed = 0 },
			remaining = 300,
			workCompleted = true,
			autoStart = true,
		})
		local fromShort = Pomodoro.finish({ mode = Pomodoro.SHORT, completed = 0 }, cfg)
		assert.equal(fromShort.workCompleted, false)
		assert.equal(fromShort.autoStart, false)
		assert.equal(fromShort.remaining, 1500)
	end)

	it("formats the clock", function()
		assert.equal(Pomodoro.formatClock(1500), "25:00")
		assert.equal(Pomodoro.formatClock(59), "00:59")
		assert.equal(Pomodoro.formatClock(3725), "1:02:05")
		assert.equal(Pomodoro.formatClock(-3), "00:00")
	end)
end)

describe("pomodoro config", function()
	local defaults = {
		work_duration = 25,
		short_break_duration = 5,
		long_break_duration = 15,
		sessions_before_long_break = 4,
		daily_pomodoro_goal = 8,
		auto_start_breaks = false,
		auto_start_work = true,
	}

	it("converts minutes to seconds and keeps the flags", function()
		assert.same(Pomodoro.configFrom(defaults), {
			work = 1500,
			short = 300,
			long = 900,
			sessionsBeforeLong = 4,
			dailyGoal = 8,
			autoStartBreaks = false,
			autoStartWork = true,
		})
	end)

	it("clamps out-of-range and non-numeric values", function()
		local out = Pomodoro.configFrom({
			work_duration = 0,
			short_break_duration = 999,
			long_break_duration = "x",
			sessions_before_long_break = -3,
			daily_pomodoro_goal = 99,
			auto_start_breaks = false,
			auto_start_work = true,
		})
		assert.same({
			work = out.work,
			short = out.short,
			long = out.long,
			sessionsBeforeLong = out.sessionsBeforeLong,
			dailyGoal = out.dailyGoal,
		}, {
			work = 60,
			short = 3600,
			long = 900,
			sessionsBeforeLong = 1,
			dailyGoal = 24,
		})
	end)

	it("allows a zero daily goal (disabled)", function()
		assert.equal(Pomodoro.configFrom({
			work_duration = 25,
			short_break_duration = 5,
			long_break_duration = 15,
			sessions_before_long_break = 4,
			daily_pomodoro_goal = 0,
			auto_start_breaks = false,
			auto_start_work = true,
		}).dailyGoal, 0)
	end)
end)

describe("pomodoro idle resize", function()
	it("follows the new duration while the phase has not started", function()
		assert.equal(
			Pomodoro.idleRemaining(false, 1500, Pomodoro.WORK, {
				work = 3000,
				short = 300,
				long = 900,
				sessionsBeforeLong = 2,
				autoStartBreaks = true,
				autoStartWork = false,
			}),
			3000
		)
		assert.equal(
			Pomodoro.idleRemaining(false, 300, Pomodoro.SHORT, {
				work = 1500,
				short = 600,
				long = 900,
				sessionsBeforeLong = 2,
				autoStartBreaks = true,
				autoStartWork = false,
			}),
			600
		)
	end)

	it("keeps the remaining time of a started (running or paused) phase", function()
		assert.equal(
			Pomodoro.idleRemaining(true, 1234, Pomodoro.WORK, {
				work = 3000,
				short = 300,
				long = 900,
				sessionsBeforeLong = 2,
				autoStartBreaks = true,
				autoStartWork = false,
			}),
			1234
		)
	end)
end)

describe("pomodoro task shortcut", function()
	it("is blocked only while a focus session is running", function()
		assert.equal(Pomodoro.canFocusTask(true, Pomodoro.WORK), false)
		assert.equal(Pomodoro.canFocusTask(false, Pomodoro.WORK), true)
		assert.equal(Pomodoro.canFocusTask(true, Pomodoro.SHORT), true)
		assert.equal(Pomodoro.canFocusTask(true, Pomodoro.LONG), true)
		assert.equal(Pomodoro.canFocusTask(false, Pomodoro.LONG), true)
	end)
end)

local assert = require("./support/assert")
local runner = require("./support/runner")
local modules = require("./support/modules")

local describe, it = runner.describe, runner.it
local FocusLog = modules.load("lib/focuslog.luau")

local function createEmpty()
	return {
		version = 2,
		tasks = {},
		eventChecks = {},
		reminders = {},
		bookmarks = {},
		notes = {},
		focusLog = {},
		recentTimers = {},
		ui = { lastTab = "", clockOverlay = false },
	}
end

describe("focus log", function()
	it("counts completed focus sessions per day without mutating the input", function()
		local data = createEmpty()
		local once = FocusLog.addSession(data, "2026-10-09")
		local twice = FocusLog.addSession(once, "2026-10-09")
		assert.equal(FocusLog.sessionsOn(data, "2026-10-09"), 0)
		assert.equal(FocusLog.sessionsOn(twice, "2026-10-09"), 2)
		assert.equal(FocusLog.sessionsOn(FocusLog.addSession(twice, "2026-10-10"), "2026-10-10"), 1)
	end)

	it("tolerates a store without a focus log", function()
		assert.equal(FocusLog.sessionsOn({}, "2026-10-09"), 0)
		assert.same(FocusLog.addSession({ tasks = {} }, "2026-10-09").focusLog, { ["2026-10-09"] = 1 })
	end)

	it("reports the goal only on the session that reaches it", function()
		assert.equal(FocusLog.goalJustReached(7, 8), false)
		assert.equal(FocusLog.goalJustReached(8, 8), true)
		assert.equal(FocusLog.goalJustReached(9, 8), false)
		assert.equal(FocusLog.goalJustReached(1, 0), false)
	end)
end)

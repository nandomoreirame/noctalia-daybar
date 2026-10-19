local assert = require("./support/assert")
local runner = require("./support/runner")
local modules = require("./support/modules")

local describe, it = runner.describe, runner.it
local Dates = modules.load("lib/dates.luau")
local Reminders = modules.load("lib/reminders.luau")

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

describe("reminders", function()
	local data = createEmpty()
	data = Reminders.addReminder(data, { title = "early", date = "2026-10-09", time = "14:00" }, "r1")
	data = Reminders.addReminder(data, { title = "now", date = "2026-10-09", time = "14:55" }, "r2")
	data = Reminders.addReminder(data, { title = "later", date = "2026-10-09", time = "16:00" }, "r3")

	local now = Dates.toDate("2026-10-09", "15:00")

	it("splits due reminders into fire and expire", function()
		local due = Reminders.dueReminders(data, now)
		local fireIds = {}
		local expireIds = {}
		for _, r in ipairs(due.fire) do
			table.insert(fireIds, r.id)
		end
		for _, r in ipairs(due.expire) do
			table.insert(expireIds, r.id)
		end
		assert.same(fireIds, { "r2" })
		assert.same(expireIds, { "r1" })
	end)

	it("does not return fired reminders again", function()
		local fired = Reminders.markFired(data, { "r1", "r2" })
		assert.same(Reminders.dueReminders(fired, now), { fire = {}, expire = {} })
		local r3 = nil
		for _, r in ipairs(fired.reminders) do
			if r.id == "r3" then
				r3 = r
			end
		end
		assert.equal(r3.fired, false)
	end)
end)

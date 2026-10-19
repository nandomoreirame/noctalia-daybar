local assert = require("./support/assert")
local runner = require("./support/runner")
local modules = require("./support/modules")

local describe, it = runner.describe, runner.it
local Timers = modules.load("lib/timers.luau")

describe("recent timers", function()
	it("puts the newest first, drops duplicates and keeps four", function()
		local list = {}
		for _, e in ipairs({
			{ seconds = 60, label = "" },
			{ seconds = 300, label = "chá" },
			{ seconds = 600, label = "" },
			{ seconds = 900, label = "bolo" },
			{ seconds = 1200, label = "" },
		}) do
			list = Timers.addRecent(list, e)
		end
		assert.equal(Timers.MAX_RECENT, 4)
		assert.same(list, {
			{ seconds = 1200, label = "" },
			{ seconds = 900, label = "bolo" },
			{ seconds = 600, label = "" },
			{ seconds = 300, label = "chá" },
		})
		assert.same(Timers.addRecent(list, { seconds = 300, label = "chá" }), {
			{ seconds = 300, label = "chá" },
			{ seconds = 1200, label = "" },
			{ seconds = 900, label = "bolo" },
			{ seconds = 600, label = "" },
		})
	end)

	it("returns the same list when the timer is already the newest", function()
		local list = { { seconds = 300, label = "chá" } }
		assert.equal(Timers.addRecent(list, { seconds = 300, label = "chá" }), list)
	end)

	it("tells timers apart by duration and label", function()
		assert.equal(Timers.sameTimer({ seconds = 300, label = "chá" }, { seconds = 300, label = "chá" }), true)
		assert.equal(Timers.sameTimer({ seconds = 300, label = "chá" }, { seconds = 300, label = "" }), false)
	end)

	it("normalizes stored entries", function()
		-- Luau sequences cannot hold nil; the v4 null entry is omitted (same filter outcome).
		local raw = {
			{ seconds = 300, label = "chá" },
			{ seconds = 0 },
			{ seconds = 86401 },
			{ seconds = 90.5 },
			"x",
			false,
			{ seconds = 60, label = 7 },
			{ seconds = 120 },
			{ seconds = 30 },
			{ seconds = 45 },
		}
		assert.same(Timers.normalizeRecent(raw), {
			{ seconds = 300, label = "chá" },
			{ seconds = 60, label = "" },
			{ seconds = 120, label = "" },
			{ seconds = 30, label = "" },
		})
		assert.same(Timers.normalizeRecent("x"), {})
		assert.same(Timers.normalizeRecent(nil), {})
	end)

	it("records into the store data, same object when nothing changes", function()
		local data = { tasks = {}, recentTimers = {} }
		local nextData = Timers.recordRecent(data, { seconds = 300, label = "chá" })
		assert.same(nextData.recentTimers, { { seconds = 300, label = "chá" } })
		assert.same(data.recentTimers, {})
		assert.equal(Timers.recordRecent(nextData, { seconds = 300, label = "chá" }), nextData)
		assert.same(Timers.recordRecent({ tasks = {} }, { seconds = 60, label = "" }).recentTimers, {
			{ seconds = 60, label = "" },
		})
	end)

	it("formats the chip text with a short label", function()
		assert.equal(Timers.chipText({ seconds = 300, label = "" }), "05:00")
		assert.equal(Timers.chipText({ seconds = 300, label = "chá" }), "05:00 · chá")
		assert.equal(
			Timers.chipText({ seconds = 5400, label = "uma pausa bem longa para o café" }),
			"1:30:00 · uma pausa bem lon…"
		)
	end)
end)

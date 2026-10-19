local assert = require("./support/assert")
local runner = require("./support/runner")
local modules = require("./support/modules")

local describe, it = runner.describe, runner.it
local Dates = modules.load("lib/dates.luau")
local Month = modules.load("lib/month.luau")

local NOW = Dates.toDate("2026-10-09", "15:00")

describe("monthGrid", function()
	local ev = {
		uid = "e",
		start = Dates.toDate("2026-10-12", "10:00"),
		["end"] = Dates.toDate("2026-10-12", "11:00"),
	}
	local grid = Month.monthGrid(2026, 9, NOW, { ev })

	it("starts on Sunday and has 42 cells", function()
		assert.equal(#grid, 42)
		assert.same({ date = grid[1].date, day = grid[1].day, inMonth = grid[1].inMonth }, {
			date = "2026-09-27",
			day = 27,
			inMonth = false,
		})
		assert.same({ date = grid[5].date, day = grid[5].day, inMonth = grid[5].inMonth }, {
			date = "2026-10-01",
			day = 1,
			inMonth = true,
		})
	end)

	it("marks today and days with events", function()
		local todayCell = nil
		local eventDates = {}
		for _, c in ipairs(grid) do
			if c.today then
				todayCell = c
			end
			if c.hasEvents then
				table.insert(eventDates, c.date)
			end
		end
		assert.equal(todayCell.date, "2026-10-09")
		assert.same(eventDates, { "2026-10-12" })
	end)

	it("marks days with pending tasks; done tasks and other months do not count", function()
		local tasks = {
			{ id = "a", title = "a", date = "2026-10-15", done = false },
			{ id = "b", title = "b", date = "2026-10-16", done = true },
			{ id = "c", title = "c", date = nil, done = false },
		}
		local g = Month.monthGrid(2026, 9, NOW, {}, tasks)
		local taskDates = {}
		for _, c in ipairs(g) do
			if c.hasTasks then
				table.insert(taskDates, c.date)
			end
		end
		assert.same(taskDates, { "2026-10-09", "2026-10-15" })
		local any = false
		for _, c in ipairs(Month.monthGrid(2026, 9, NOW, {})) do
			if c.hasTasks then
				any = true
				break
			end
		end
		assert.equal(any, false)
	end)

	it("handles a month starting on Sunday", function()
		assert.equal(Month.monthGrid(2026, 10, NOW, {})[1].date, "2026-11-01")
	end)
end)

describe("shiftMonth", function()
	it("wraps across years", function()
		assert.same(Month.shiftMonth(2026, 11, 1), { year = 2027, month = 0 })
		assert.same(Month.shiftMonth(2026, 0, -1), { year = 2025, month = 11 })
	end)
end)

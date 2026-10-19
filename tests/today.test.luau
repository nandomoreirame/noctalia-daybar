local assert = require("./support/assert")
local runner = require("./support/runner")
local modules = require("./support/modules")

local describe, it = runner.describe, runner.it
local Dates = modules.load("lib/dates.luau")
local Tasks = modules.load("lib/tasks.luau")
local Today = modules.load("lib/today.luau")

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

local function pad2(n: number): string
	return if n < 10 then "0" .. tostring(n) else tostring(n)
end

local function at(h: number, mi: number?, d: number?): number
	local day = d or 9
	local minute = mi or 0
	return Dates.toDate("2026-10-" .. pad2(day), pad2(h) .. ":" .. pad2(minute))
end

local NOW = Dates.toDate("2026-10-09", "15:00")
local T0 = "2026-10-09T10:00:00.000Z"

describe("buildToday", function()
	local data = createEmpty()
	data = Tasks.addTask(data, { title = "sem hora", date = "2026-10-09" }, "t-untimed", "2026-10-09T09:00:00.000Z")
	data = Tasks.addTask(data, { title = "banco", date = "2026-10-09", time = "16:00" }, "t-16", T0)
	data = Tasks.addTask(data, { title = "atrasada", date = "2026-10-07", time = "09:00" }, "t-late", T0)
	data = Tasks.addTask(data, { title = "atrasada feita", date = "2026-10-07" }, "t-late-done", T0)
	data = Tasks.toggleTask(data, "t-late-done", T0)
	data = Tasks.addTask(data, { title = "amanhã", date = "2026-10-10" }, "t-tomorrow", T0)
	data = Tasks.toggleEventCheck(data, "e-am", "2026-10-09")

	local events = {
		{ uid = "e-pm", summary = "reunião", start = at(14), ["end"] = at(15), calendar = "Eventos" },
		{ uid = "e-am", summary = "café", start = at(8), ["end"] = at(9), calendar = "Eventos" },
		{ uid = "e-next", summary = "amanhã", start = at(9, 0, 10), ["end"] = at(10, 0, 10), calendar = "Eventos" },
	}

	it("orders events by time, then timed tasks, then untimed tasks", function()
		local items = Today.buildToday(events, data, NOW)
		local ids = {}
		for _, i in ipairs(items) do
			table.insert(ids, i.id)
		end
		assert.same(ids, { "e-am|2026-10-09", "e-pm|2026-10-09", "t-late", "t-16", "t-untimed" })
	end)

	it("flags overdue tasks and checked events", function()
		local items = Today.buildToday(events, data, NOW)
		local byId = {}
		for _, i in ipairs(items) do
			byId[i.id] = i
		end
		assert.equal(byId["t-late"].overdue, true)
		assert.equal(byId["t-16"].overdue, false)
		assert.equal(byId["e-am|2026-10-09"].done, true)
		assert.equal(byId["e-pm|2026-10-09"].done, false)
	end)

	it("works with no calendar events", function()
		assert.same(Today.buildToday(nil, createEmpty(), NOW), {})
	end)

	it("carries the calendar name on events and an empty one on tasks", function()
		local items = Today.buildToday(events, data, NOW)
		local eventCals = {}
		local taskCalsOk = true
		for _, i in ipairs(items) do
			if i.kind == "event" then
				table.insert(eventCals, i.calendar)
			elseif i.calendar ~= "" then
				taskCalsOk = false
			end
		end
		assert.same(eventCals, { "Eventos", "Eventos" })
		assert.equal(taskCalsOk, true)
	end)
end)

describe("read-only calendars", function()
	local cols = {
		{ dir = "/r/h", id = "pt.brazilian#holiday@group.v.calendar.google.com", name = "Feriados" },
		{ dir = "/r/me", id = "me@gmail.com", name = "Eventos" },
	}
	local data = createEmpty()
	data = Tasks.addTask(data, { title = "banco", date = "2026-10-09" }, "t-1", T0)
	data = Tasks.toggleEventCheck(data, "e-hol", "2026-10-09")
	local events = {
		{ uid = "e-hol", summary = "Feriado", start = at(0), ["end"] = at(0, 0, 10), calendar = "Feriados" },
		{ uid = "e-mine", summary = "reunião", start = at(14), ["end"] = at(15), calendar = "Eventos" },
	}

	it("marks events from read-only calendars as not checkable and never done", function()
		local items = Today.buildToday(events, data, NOW, cols)
		local hol = nil
		local mine = nil
		local t1 = nil
		for _, i in ipairs(items) do
			if i.uid == "e-hol" then
				hol = i
			elseif i.uid == "e-mine" then
				mine = i
			elseif i.id == "t-1" then
				t1 = i
			end
		end
		assert.same({ checkable = hol.checkable, done = hol.done }, { checkable = false, done = false })
		assert.equal(mine.checkable, true)
		assert.equal(t1.checkable, true)
	end)

	it("keeps every event checkable while collections are unknown", function()
		local all = true
		for _, i in ipairs(Today.buildToday(events, data, NOW)) do
			if not i.checkable then
				all = false
			end
		end
		assert.equal(all, true)
	end)

	it("leaves read-only events out of the progress counts", function()
		assert.same(Today.todayProgress(events, data, "2026-10-09", cols), { done = 0, total = 2 })
		assert.same(Today.dayProgress(events, data, "2026-10-09", cols), { done = 0, total = 2 })
	end)
end)

describe("dayItems (Calendar day list)", function()
	it("lists the day's events then its tasks; undated tasks belong to today only", function()
		local function atDay(d: number, h: number): number
			return Dates.toDate("2026-10-" .. pad2(d), pad2(h) .. ":00")
		end
		local events = {
			{
				uid = "e1",
				calendar = "Eventos",
				summary = "Reunião",
				start = atDay(15, 10),
				["end"] = atDay(15, 11),
			},
		}
		local data = {
			eventChecks = {},
			tasks = {
				{ id = "t1", title = "Com hora", date = "2026-10-15", time = "09:00", done = false, pomodoros = 0, createdAt = "1" },
				{ id = "t2", title = "Dia todo", date = "2026-10-15", time = nil, done = true, pomodoros = 0, createdAt = "2" },
				{ id = "t3", title = "Sem data", date = nil, time = nil, done = false, pomodoros = 0, createdAt = "3" },
				{ id = "t4", title = "Atrasada", date = "2026-10-01", time = nil, done = false, pomodoros = 0, createdAt = "4" },
			},
		}
		local day = Today.dayItems(events, data, "2026-10-15", "2026-10-09")
		local rows = {}
		for _, i in ipairs(day) do
			table.insert(rows, { i.kind, i.title, i.time })
		end
		assert.same(rows, {
			{ "event", "Reunião", "10:00" },
			{ "task", "Com hora", "09:00" },
			{ "task", "Dia todo", nil },
		})
		local noOverdue = true
		for _, i in ipairs(day) do
			if i.overdue ~= false then
				noOverdue = false
			end
		end
		assert.equal(noOverdue, true)
		local titles = {}
		for _, i in ipairs(Today.dayItems({}, data, "2026-10-09", "2026-10-09")) do
			table.insert(titles, i.title)
		end
		assert.same(titles, { "Sem data" })
	end)
end)

describe("progress counts", function()
	local data = createEmpty()
	data = Tasks.addTask(data, { title = "hoje", date = "2026-10-09" }, "t-today", T0)
	data = Tasks.addTask(data, { title = "feita", date = "2026-10-09" }, "t-done", T0)
	data = Tasks.toggleTask(data, "t-done", T0)
	data = Tasks.addTask(data, { title = "atrasada", date = "2026-10-07" }, "t-late", T0)
	data = Tasks.addTask(data, { title = "amanhã", date = "2026-10-10" }, "t-tomorrow", T0)
	local events = {
		{ uid = "e-1", summary = "reunião", start = at(14), ["end"] = at(15), calendar = "Eventos" },
	}

	it("counts done and total items of a list", function()
		assert.same(Today.progress({ { done = true }, { done = false }, { done = true } }), { done = 2, total = 3 })
		assert.same(Today.progress({}), { done = 0, total = 0 })
	end)

	it("counts Today with overdue tasks, and the calendar day without them", function()
		assert.same(Today.todayProgress(events, data, "2026-10-09"), { done = 1, total = 4 })
		assert.same(Today.dayProgress(events, data, "2026-10-09"), { done = 1, total = 3 })
	end)

	it("appends (done/total) to a label only when there is something", function()
		assert.equal(Today.withProgress("Hoje", { done = 1, total = 3 }), "Hoje (1/3)")
		assert.equal(Today.withProgress("Hoje", { done = 0, total = 0 }), "Hoje")
	end)
end)

describe("withCount", function()
	it("appends (n) to a label only when n > 0", function()
		assert.equal(Today.withCount("Notas", 4), "Notas (4)")
		assert.equal(Today.withCount("Notas", 0), "Notas")
	end)
end)

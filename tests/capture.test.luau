local assert = require("./support/assert")
local runner = require("./support/runner")
local modules = require("./support/modules")

local describe, it = runner.describe, runner.it
local Dates = modules.load("lib/dates.luau")
local Task = modules.load("lib/capture/task.luau")
local Event = modules.load("lib/capture/event.luau")
local Reminder = modules.load("lib/capture/reminder.luau")
local Note = modules.load("lib/capture/note.luau")
local Link = modules.load("lib/capture/link.luau")
local Calculation = modules.load("lib/capture/calculation.luau")

-- Friday, 9 October 2026, 15:00 local time.
local NOW = Dates.toDate("2026-10-09", "15:00")

describe("capture handlers", function()
	it("task: defaults to today and keeps the parsed time", function()
		assert.same(Task.build("comprar pão", NOW), {
			ok = true,
			type = "task",
			action = "addTask",
			payload = { title = "comprar pão", date = "2026-10-09", time = nil },
		})
		assert.same(Task.build("comprar pão amanhã 9h", NOW).payload, { title = "comprar pão", date = "2026-10-10", time = "09:00" })
		assert.same(Task.build("amanhã", NOW), { ok = false, type = "task", error = "empty-title" })
	end)

	it("event: needs date and time, defaults to 1h", function()
		assert.same(Event.build("reunião sexta 15h", NOW).payload, {
			title = "reunião",
			date = "2026-10-16",
			start = "15:00",
			endDate = "2026-10-16",
			endTime = "16:00",
			alarm = false,
		})
		assert.equal(Event.build("reunião sexta 15h-15h30", NOW).payload.endTime, "15:30")
		assert.same(Event.build("reunião sexta", NOW), { ok = false, type = "event", error = "needs-date-time" })
	end)

	it("event: a 1h default crossing midnight moves the end date", function()
		local p = Event.build("festa sexta 23h30", NOW).payload
		assert.equal(p.endDate, "2026-10-17")
		assert.equal(p.endTime, "00:30")
	end)

	it("reminder: needs a time, lasts 15 minutes with alarm", function()
		assert.same(Reminder.build("pagar boleto amanhã 10h", NOW), {
			ok = true,
			type = "reminder",
			action = "createReminder",
			payload = {
				title = "pagar boleto",
				date = "2026-10-10",
				start = "10:00",
				endDate = "2026-10-10",
				endTime = "10:15",
				alarm = true,
			},
		})
		assert.same(Reminder.build("pagar boleto amanhã", NOW), { ok = false, type = "reminder", error = "needs-time" })
	end)

	it("note and link", function()
		assert.same(Note.build("  ideia: app  "), { ok = true, type = "note", action = "addNote", payload = { text = "ideia: app" } })
		assert.equal(Note.build("   ").ok, false)
		assert.equal(Note.build(nil).ok, false)
		assert.same(Link.build("https://a.dev"), { ok = true, type = "link", action = "addBookmark", payload = { url = "https://a.dev" } })
		assert.same(Link.build("a.dev"), { ok = false, type = "link", error = "invalid-url" })
		assert.equal(Link.isLink("https://a.dev"), true)
		assert.equal(Link.isLink("ler https://a.dev"), false)
	end)

	it("calculation", function()
		assert.same(Calculation.build("2+2"), { ok = true, type = "calculation", action = "copy", payload = { value = 4, display = "4" } })
		assert.same(Calculation.build("2/0"), { ok = false, type = "calculation", error = "division-by-zero" })
	end)
end)

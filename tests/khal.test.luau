local assert = require("./support/assert")
local runner = require("./support/runner")
local modules = require("./support/modules")

local describe, it = runner.describe, runner.it
local Khal = modules.load("lib/khal.luau")

local function indexOf(list, value)
	for i, v in ipairs(list) do
		if v == value then
			return i
		end
	end
	return nil
end

describe("khal argv", function()
	it("builds khal new for an event", function()
		assert.same(
			Khal.newEventArgs({ calendar = "pessoal", date = "2026-10-16", start = "15:00", endDate = "2026-10-16", endTime = "16:00", title = "reunião", alarm = false }),
			{ "khal", "new", "-a", "pessoal", "--", "2026-10-16 15:00", "2026-10-16 16:00", "reunião" }
		)
	end)

	it("adds an alarm at start for reminders and omits an empty calendar", function()
		assert.same(
			Khal.newEventArgs({ calendar = "", date = "2026-10-10", start = "09:00", endDate = "2026-10-10", endTime = "09:15", title = "pagar boleto", alarm = true }),
			{ "khal", "new", "--alarms", "0m", "--", "2026-10-10 09:00", "2026-10-10 09:15", "pagar boleto" }
		)
	end)

	it("omits a missing calendar too", function()
		local args = Khal.newEventArgs({ date = "2026-10-10", start = "09:00", endDate = "2026-10-10", endTime = "09:15", title = "x" })
		assert.same(args, { "khal", "new", "--", "2026-10-10 09:00", "2026-10-10 09:15", "x" })
	end)

	it("keeps hostile titles as a single inert argument", function()
		local args = Khal.newEventArgs({ calendar = "c", date = "2026-10-10", start = "09:00", endDate = "2026-10-10", endTime = "10:00", title = "--help; rm -rf ~ :: desc\nx", alarm = false })
		assert.equal(args[#args], "--help; rm -rf ~ : desc x")
		assert.equal(indexOf(args, "--") < #args, true)
	end)

	it("sanitizes summaries", function()
		assert.equal(Khal.sanitizeSummary("  a::b \r\n c "), "a:b c")
		assert.equal(Khal.sanitizeSummary("a:::b"), "a:b")
		assert.equal(Khal.sanitizeSummary("a::::::b"), "a:b")
		assert.equal(Khal.sanitizeSummary(nil), "")
	end)

	it("builds sync and calendar listing commands", function()
		assert.same(Khal.syncArgs(), { "vdirsyncer", "sync" })
		assert.same(Khal.printCalendarsArgs(), { "khal", "printcalendars" })
		assert.same(Khal.parseCalendars("pessoal\ntrabalho\n\n"), { "pessoal", "trabalho" })
		assert.same(Khal.parseCalendars("  a \r\n"), { "a" })
		assert.same(Khal.parseCalendars(nil), {})
	end)

	it("builds khal list with one --json flag per field and the range last", function()
		assert.same(Khal.listArgs("2026-10-02", "2026-11-16"), {
			"khal", "list",
			"--json", "uid", "--json", "title", "--json", "calendar", "--json", "all-day",
			"--json", "start-date", "--json", "start-time", "--json", "end-date", "--json", "end-time",
			"--json", "location", "--json", "url", "--json", "description", "--json", "repeat-symbol",
			"2026-10-02", "2026-11-16",
		})
	end)
end)

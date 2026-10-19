local assert = require("./support/assert")
local runner = require("./support/runner")
local modules = require("./support/modules")

local describe, it = runner.describe, runner.it
local Dates = modules.load("lib/dates.luau")
local Registry = modules.load("lib/capture/registry.luau")
local resolve, nextType, prevType, CYCLE = Registry.resolve, Registry.nextType, Registry.prevType, Registry.CYCLE

local NOW = Dates.toDate("2026-10-09", "15:00")

describe("capture registry", function()
	it("defaults to task", function()
		assert.equal(resolve("comprar pão", nil, NOW).type, "task")
	end)

	it("always treats '=' as calculation, even with a forced type", function()
		assert.equal(resolve("=2+2", "note", NOW).payload.display, "4")
	end)

	it("applies prefixes and strips them", function()
		assert.equal(resolve("/e reunião sexta 15h", nil, NOW).payload.title, "reunião")
		assert.equal(resolve("/l pagar boleto 18h", nil, NOW).type, "reminder")
		assert.same(resolve("/n uma ideia", nil, NOW).payload, { text = "uma ideia" })
		assert.equal(resolve("/ex", nil, NOW).type, "task")
	end)

	it("detects a lone URL as link", function()
		assert.equal(resolve("https://a.dev/x", nil, NOW).type, "link")
		assert.equal(resolve("ler https://a.dev/x", nil, NOW).type, "task")
	end)

	it("honors the Tab-forced type", function()
		local r = resolve("https://a.dev", "note", NOW)
		assert.equal(r.type, "note")
		assert.same(r.payload, { text = "https://a.dev" })
		assert.equal(resolve("pagar boleto 18h", "reminder", NOW).type, "reminder")
		-- An unknown forced type falls back to inference.
		assert.equal(resolve("comprar pão", "bogus", NOW).type, "task")
	end)

	it("rejects empty input with the resolved type", function()
		assert.same(resolve("  ", nil, NOW), { ok = false, type = "task", error = "empty" })
		assert.same(resolve(nil, nil, NOW), { ok = false, type = "task", error = "empty" })
		assert.same(resolve("/n", nil, NOW), { ok = false, type = "note", error = "empty" })
	end)

	it("cycles types with Tab", function()
		assert.same(CYCLE, { "task", "event", "reminder", "note", "link", "timer" })
		assert.equal(nextType("task"), "event")
		assert.equal(nextType("link"), "timer")
		assert.equal(nextType("timer"), "task")
		assert.equal(nextType("calculation"), "task")
		assert.equal(nextType("pomodoro"), "task")
	end)

	it("cycles backwards with prevType (Shift+Tab)", function()
		assert.equal(prevType("event"), "task")
		assert.equal(prevType("task"), "timer")
		assert.equal(prevType("calculation"), "timer")
		local back = {}
		for i, t in CYCLE do
			back[i] = nextType(prevType(t))
		end
		assert.same(back, CYCLE)
	end)
end)

describe("timer and pomodoro commands", function()
	it("/t starts, toggles and stops the timer", function()
		local r = resolve("/t 5m chá", nil, NOW)
		assert.same(r, { ok = true, type = "timer", action = "startTimer", payload = { seconds = 300, label = "chá" } })
		local t = resolve("/t", nil, NOW)
		assert.equal(t.ok, true)
		assert.equal(t.action, "timerToggle")
		local s = resolve("/t parar", nil, NOW)
		assert.equal(s.ok, true)
		assert.equal(s.action, "timerStop")
	end)

	it("an empty field on the Timer tab stays empty, so a stray Enter does nothing", function()
		assert.same(resolve("", "timer", NOW), { ok = false, type = "timer", error = "empty" })
		local r = resolve("10m", "timer", NOW)
		assert.equal(r.ok, true)
		assert.equal(r.action, "startTimer")
	end)

	it("/p is a pomodoro command whatever type Tab forced", function()
		local a = resolve("/p", nil, NOW)
		assert.equal(a.ok, true)
		assert.equal(a.type, "pomodoro")
		assert.same(a.payload, { command = "toggle" })
		local b = resolve("/p curta", "note", NOW)
		assert.equal(b.type, "pomodoro")
		assert.same(b.payload, { command = "short" })
		assert.same(resolve("/p xyz", nil, NOW), { ok = false, type = "pomodoro", error = "unknown-command" })
	end)

	it("does not read /px or /tx as commands", function()
		assert.equal(resolve("/px", nil, NOW).type, "task")
		assert.equal(resolve("/tx", nil, NOW).type, "task")
	end)

	it("other prefixes still reject an empty body", function()
		assert.same(resolve("/e", nil, NOW), { ok = false, type = "event", error = "empty" })
	end)
end)

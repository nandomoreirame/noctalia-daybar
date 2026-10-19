local assert = require("./support/assert")
local runner = require("./support/runner")
local modules = require("./support/modules")

local describe, it = runner.describe, runner.it
local Duration = modules.load("lib/duration.luau")

describe("parseDuration", function()
	local okCases = {
		{ "90s", 90 },
		{ "10m", 600 },
		{ "10min", 600 },
		{ "10MIN", 600 },
		{ "1h", 3600 },
		{ "1h30", 5400 },
		{ "1h30m", 5400 },
		{ "1:30", 90 },
		{ "1:02:03", 3723 },
		{ "25", 1500 },
	}
	for _, c in ipairs(okCases) do
		it(c[1] .. " -> " .. tostring(c[2]) .. " s", function()
			assert.same(Duration.parseDuration(c[1]), { ok = true, seconds = c[2], label = "" })
		end)
	end

	it("keeps the other words as the label, wherever the duration is", function()
		assert.same(Duration.parseDuration("chá 5m"), { ok = true, seconds = 300, label = "chá" })
		assert.same(Duration.parseDuration("10m tirar o bolo"), {
			ok = true,
			seconds = 600,
			label = "tirar o bolo",
		})
	end)

	it("prefers a token with a unit over a bare number", function()
		assert.same(Duration.parseDuration("2 ovos 7m"), { ok = true, seconds = 420, label = "2 ovos" })
	end)

	it("fails without a duration", function()
		assert.same(Duration.parseDuration("chá"), { ok = false, error = "needs-duration" })
		assert.same(Duration.parseDuration(""), { ok = false, error = "needs-duration" })
		assert.same(Duration.parseDuration(nil), { ok = false, error = "needs-duration" })
	end)

	it("rejects zero, more than 24 h and out-of-range fields", function()
		for _, t in ipairs({ "0", "0s", "25h", "1441m", "1:75", "1h75", "86401s" }) do
			assert.same(Duration.parseDuration(t), { ok = false, error = "invalid-duration" })
		end
		assert.same(Duration.parseDuration("24h"), {
			ok = true,
			seconds = Duration.MAX_SECONDS,
			label = "",
		})
		assert.same(Duration.parseDuration("86400s"), {
			ok = true,
			seconds = Duration.MAX_SECONDS,
			label = "",
		})
	end)

	it("checks each field at its boundary", function()
		assert.equal(Duration.parseDuration("1:59").seconds, 119)
		assert.equal(Duration.parseDuration("1h59").seconds, 7140)
		assert.equal(Duration.parseDuration("1:59:59").seconds, 7199)
		for _, t in ipairs({ "1:60", "1h60", "1:60:00", "1:00:60", "0:00" }) do
			assert.same(Duration.parseDuration(t), { ok = false, error = "invalid-duration" })
		end
	end)

	it("reads oversized numbers as invalid, not as missing", function()
		for _, t in ipairs({ "100000s", "99999", "100:00:00", "12345m" }) do
			assert.same(Duration.parseDuration(t), { ok = false, error = "invalid-duration" })
		end
	end)

	it("accepts 1h30min", function()
		assert.same(Duration.parseDuration("1H30MIN"), { ok = true, seconds = 5400, label = "" })
	end)

	it("sums consecutive unit words", function()
		assert.same(Duration.parseDuration("1h 30m chá"), {
			ok = true,
			seconds = 5400,
			label = "chá",
		})
		assert.same(Duration.parseDuration("bolo 5m 30s"), {
			ok = true,
			seconds = 330,
			label = "bolo",
		})
	end)

	it("prefers h/m/s units over a clock time in the label", function()
		assert.same(Duration.parseDuration("reunião às 14:30 5m"), {
			ok = true,
			seconds = 300,
			label = "reunião às 14:30",
		})
		assert.same(Duration.parseDuration("chá 1:30"), {
			ok = true,
			seconds = 90,
			label = "chá",
		})
	end)

	it("takes a bare number only as the first word", function()
		assert.same(Duration.parseDuration("10 chá"), { ok = true, seconds = 600, label = "chá" })
		assert.same(Duration.parseDuration("ler 3 capítulos"), { ok = false, error = "needs-duration" })
	end)
end)

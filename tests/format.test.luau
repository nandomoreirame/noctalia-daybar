local assert = require("./support/assert")
local runner = require("./support/runner")
local modules = require("./support/modules")

local describe, it = runner.describe, runner.it
local Dates = modules.load("lib/dates.luau")
local Format = modules.load("lib/format.luau")

-- Friday, 9 October 2026, 15:00 local time (same as vitest NOW for describeWhen).
local NOW = Dates.toDate("2026-10-09", "15:00")

-- Parse a UTC ISO instant (…Z) to epoch seconds. Luau os.time({…}) is UTC.
local function parseUtcIso(iso: string): number
	local y, mo, d, h, mi, s = string.match(iso, "^(%d%d%d%d)%-(%d%d)%-(%d%d)T(%d%d):(%d%d):(%d%d)")
	assert.equal(y ~= nil, true)
	return os.time({
		year = tonumber(y) :: number,
		month = tonumber(mo) :: number,
		day = tonumber(d) :: number,
		hour = tonumber(h) :: number,
		min = tonumber(mi) :: number,
		sec = tonumber(s) :: number,
	}) :: number
end

local REL_NOW = parseUtcIso("2026-10-09T15:00:00.000Z")

describe("describeWhen", function()
	it("names today and tomorrow, else dd/mm", function()
		assert.same(Format.describeWhen("2026-10-09", nil, nil, NOW), { day = "today", time = "" })
		assert.same(Format.describeWhen("2026-10-10", "09:00", nil, NOW), { day = "tomorrow", time = "09:00" })
		assert.same(Format.describeWhen("2026-10-16", "15:00", "16:00", NOW), { day = "16/10", time = "15:00–16:00" })
	end)

	it("handles a missing date", function()
		assert.same(Format.describeWhen(nil, nil, nil, NOW), { day = "", time = "" })
	end)
end)

describe("format.relativeTime", function()
	local cases = {
		{ "2026-10-09T14:59:40.000Z", { unit = "now", n = 0 } },
		{ "2026-10-09T14:55:00.000Z", { unit = "minutes", n = 5 } },
		{ "2026-10-09T12:00:00.000Z", { unit = "hours", n = 3 } },
		{ "2026-10-06T15:00:00.000Z", { unit = "days", n = 3 } },
		{ "2026-09-01T15:00:00.000Z", { unit = "date", n = 0, date = "2026-09-01" } },
		{ "2026-10-09T15:05:00.000Z", { unit = "now", n = 0 } },
	}
	for _, c in ipairs(cases) do
		local iso, expected = c[1], c[2]
		it(iso, function()
			assert.same(Format.relativeTime(iso, REL_NOW), expected)
		end)
	end
end)

describe("format.relativeKey", function()
	it("maps units to i18n keys and leaves dates keyless", function()
		assert.same(Format.relativeKey({ unit = "now", n = 0 }), { key = "time.now", n = 0, date = "" })
		assert.same(Format.relativeKey({ unit = "minutes", n = 5 }), { key = "time.minutes", n = 5, date = "" })
		assert.same(Format.relativeKey({ unit = "date", n = 0, date = "2026-09-01" }), { key = "", n = 0, date = "2026-09-01" })
	end)
end)

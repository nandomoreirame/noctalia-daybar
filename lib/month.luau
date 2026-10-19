--!strict
-- Sunday-first 6x7 month grid and month navigation.

local Dates = require("./dates.luau")
local Events = require("./events.luau")

local Month = {}

-- Sunday-first 6x7 month grid: [{ date, day, inMonth, today, hasEvents, hasTasks }].
-- hasTasks: a pending task is dated that day (undated tasks belong to today).
-- month is 0-based (JS Date convention), matching v4.
function Month.monthGrid(
	year: number,
	month: number,
	now: number,
	events: { any }?,
	tasks: { any }?
): { any }
	-- First day of month: month is 0-based so civil month = month + 1.
	local first = Dates.parseIsoDate(
		string.format("%04d-%02d-01", year, month + 1)
	) :: number
	local parts = os.date("*t", first) :: { wday: number }
	-- os.date wday: Sunday=1 .. Saturday=7; JS getDay: Sunday=0 .. Saturday=6.
	local offset = parts.wday - 1
	local start = Dates.addDays(first, -offset)
	local todayIso = Dates.isoDate(now)
	local pending: { [string]: boolean } = {}
	for _, t in ipairs(tasks or {}) do
		if not t.done then
			pending[t.date or todayIso] = true
		end
	end
	local cells = {}
	for i = 0, 41 do
		local d = Dates.addDays(start, i)
		local iso = Dates.isoDate(d)
		local dParts = os.date("*t", d) :: { day: number, month: number }
		local hasEvents = false
		for _, ev in ipairs(events or {}) do
			if Events.overlapsDay(ev, iso) then
				hasEvents = true
				break
			end
		end
		table.insert(cells, {
			date = iso,
			day = dParts.day,
			inMonth = dParts.month == (month + 1),
			today = iso == todayIso,
			hasEvents = hasEvents,
			hasTasks = pending[iso] == true,
		})
	end
	return cells
end

-- Moves a {year, month} pair by `delta` months. month is 0-based.
function Month.shiftMonth(year: number, month: number, delta: number): { year: number, month: number }
	local total = year * 12 + month + delta
	local y = math.floor(total / 12)
	local m = total % 12
	if m < 0 then
		m += 12
		y -= 1
	end
	return { year = y, month = m }
end

return Month

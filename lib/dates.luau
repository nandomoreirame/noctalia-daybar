--!strict
-- Local-time date helpers. Dates travel as "YYYY-MM-DD" and times as "HH:MM".
-- Instants are epoch seconds (local time via os.date / civilLocal).
--
-- Luau's os.time({...}) treats the table as UTC, while os.date without "!" uses
-- the process TZ. civilLocal converts a local civil wall clock to epoch seconds.

local Dates = {}

local function civilLocal(year: number, month: number, day: number, hour: number?, min: number?, sec: number?): number?
	local h = hour or 0
	local mi = min or 0
	local s = sec or 0
	-- os.time normalizes overflowing fields (day 32, min 70, ...).
	-- Returns nil for civil instants before 1970 UTC.
	local asUtc = os.time({ year = year, month = month, day = day, hour = h, min = mi, sec = s })
	if asUtc == nil then
		return nil
	end
	-- Probe at max(asUtc, 86400) so os.date("*t", ...) never lands before the epoch
	-- in west-of-UTC zones (e.g. America/Sao_Paulo on 1970-01-01).
	local probe = math.max(asUtc, 86400)
	local parts = os.date("*t", probe) :: { year: number, month: number, day: number, hour: number, min: number, sec: number }
	local wallAsUtc = os.time({
		year = parts.year,
		month = parts.month,
		day = parts.day,
		hour = parts.hour,
		min = parts.min,
		sec = parts.sec or 0,
	})
	if wallAsUtc == nil then
		return nil
	end
	local offset = probe - wallAsUtc
	return asUtc + offset
end

function Dates.pad2(n: number): string
	if n < 10 then
		return "0" .. tostring(n)
	end
	return tostring(n)
end

function Dates.isoDate(t: number): string
	return os.date("%Y-%m-%d", t) :: string
end

function Dates.parseIsoDate(s: any): number?
	if typeof(s) ~= "string" then
		return nil
	end
	local y, m, d = string.match(s, "^(%d%d%d%d)%-(%d%d)%-(%d%d)$")
	if y == nil then
		return nil
	end
	local t = civilLocal(tonumber(y) :: number, tonumber(m) :: number, tonumber(d) :: number, 0, 0, 0)
	if t == nil then
		return nil
	end
	if Dates.isoDate(t) ~= s then
		return nil
	end
	return t
end

function Dates.addDays(t: number, n: number): number
	local parts = os.date("*t", t) :: { year: number, month: number, day: number }
	return civilLocal(parts.year, parts.month, parts.day + n, 0, 0, 0) :: number
end

function Dates.hhmm(t: number): string
	return os.date("%H:%M", t) :: string
end

function Dates.minutesOf(time: any): number?
	if typeof(time) ~= "string" then
		return nil
	end
	local h, m = string.match(time, "^(%d%d):(%d%d)$")
	if h == nil then
		return nil
	end
	return (tonumber(h) :: number) * 60 + (tonumber(m) :: number)
end

function Dates.toDate(date: string, time: string?): number
	local base = Dates.parseIsoDate(date) :: number
	local minutes = if time then (Dates.minutesOf(time) :: number) else 0
	local parts = os.date("*t", base) :: { year: number, month: number, day: number }
	return civilLocal(parts.year, parts.month, parts.day, 0, minutes, 0) :: number
end

function Dates.addMinutes(date: string, time: string, minutes: number): { date: string, time: string }
	local t = Dates.toDate(date, time)
	local parts = os.date("*t", t) :: { year: number, month: number, day: number, hour: number, min: number }
	local nextT = civilLocal(parts.year, parts.month, parts.day, parts.hour, parts.min + minutes, 0) :: number
	return { date = Dates.isoDate(nextT), time = Dates.hhmm(nextT) }
end

function Dates.nowSeconds(nowMs: number): number
	return nowMs / 1000
end

return Dates

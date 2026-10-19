--!strict
-- Language-neutral pieces for the capture preview; the UI translates `day` keys.
-- describeWhen("2026-10-10", "15:00", "16:00", now) -> { day = "tomorrow", time = "15:00–16:00" }
-- `day` is "today" | "tomorrow" | "dd/mm" | "" (no date).
-- Instants are epoch seconds. relativeTime accepts a UTC/local ISO string or epoch.

local Dates = require("./dates.luau")

local Format = {}

-- En dash (U+2013), same glyph as v4.
local EN_DASH = "–"

function Format.describeWhen(date: any, start: any, endTime: any, now: number): { day: string, time: string }
	local day = ""
	if date then
		local today = Dates.isoDate(now)
		local tomorrow = Dates.isoDate(Dates.addDays(now, 1))
		if date == today then
			day = "today"
		elseif date == tomorrow then
			day = "tomorrow"
		else
			day = string.sub(date, 9, 10) .. "/" .. string.sub(date, 6, 7)
		end
	end
	local time = ""
	if start then
		if endTime then
			time = tostring(start) .. EN_DASH .. tostring(endTime)
		else
			time = tostring(start)
		end
	end
	return { day = day, time = time }
end

-- Parse an ISO-8601 instant to epoch seconds. Supports …Z (UTC via os.time table)
-- and offset-free local forms. Returns nil when the shape is unknown.
-- Lua patterns have no | alternation; zone is scanned by hand after the clock.
local function parseIsoInstant(iso: any): number?
	if typeof(iso) == "number" then
		return iso
	end
	if typeof(iso) ~= "string" then
		return nil
	end
	local y, mo, d, h, mi, s, rest = string.match(
		iso,
		"^(%d%d%d%d)%-(%d%d)%-(%d%d)[Tt ](%d%d):(%d%d):(%d%d)(.*)$"
	)
	if y == nil then
		-- Date-only: treat as local midnight.
		return Dates.parseIsoDate(iso)
	end
	local year = tonumber(y) :: number
	local month = tonumber(mo) :: number
	local day = tonumber(d) :: number
	local hour = tonumber(h) :: number
	local min = tonumber(mi) :: number
	local sec = tonumber(s) :: number
	rest = rest or ""
	-- Optional fractional seconds.
	if string.sub(rest, 1, 1) == "." then
		local digits, after = string.match(rest, "^%.(%d+)(.*)$")
		if digits == nil then
			return nil
		end
		rest = after or ""
	end
	local zone = rest
	if zone == "" then
		-- No zone: local civil time via Dates helpers.
		local base = Dates.toDate(
			string.format("%04d-%02d-%02d", year, month, day),
			string.format("%02d:%02d", hour, min)
		)
		return base + sec
	end
	if zone == "Z" or zone == "z" then
		-- Luau os.time({…}) is UTC.
		return os.time({ year = year, month = month, day = day, hour = hour, min = min, sec = sec })
	end
	-- Numeric offset ±HH:MM or ±HHMM.
	local sign, oh, om = string.match(zone, "^([+-])(%d%d):?(%d%d)$")
	if sign == nil then
		return nil
	end
	local asUtc = os.time({ year = year, month = month, day = day, hour = hour, min = min, sec = sec })
	if asUtc == nil then
		return nil
	end
	local offset = (tonumber(oh) :: number) * 3600 + (tonumber(om) :: number) * 60
	if sign == "+" then
		return asUtc - offset
	end
	return asUtc + offset
end

-- "now" < 1 min (or in the future), then minutes, hours, days up to 6, else the date.
function Format.relativeTime(iso: any, now: number): { unit: string, n: number, date: string? }
	local thenSecs = parseIsoInstant(iso)
	if thenSecs == nil then
		return { unit = "now", n = 0 }
	end
	local ms = (now - thenSecs) * 1000
	local min = math.floor(ms / 60000)
	if min < 1 then
		return { unit = "now", n = 0 }
	end
	if min < 60 then
		return { unit = "minutes", n = min }
	end
	local hours = math.floor(min / 60)
	if hours < 24 then
		return { unit = "hours", n = hours }
	end
	local days = math.floor(hours / 24)
	if days < 7 then
		return { unit = "days", n = days }
	end
	return { unit = "date", n = 0, date = Dates.isoDate(thenSecs) }
end

-- i18n key and replacement value for a relativeTime() result. unit "date"
-- has no key (callers show r.date directly).
function Format.relativeKey(r: any): { key: string, n: number, date: string }
	if not r or r.unit == "date" then
		return { key = "", n = 0, date = if r and r.date then r.date else "" }
	end
	return { key = "time." .. r.unit, n = r.n, date = "" }
end

return Format

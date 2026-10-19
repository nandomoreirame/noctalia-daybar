--!strict
-- Helpers over calendar events:
--   { uid, calendar, summary, start, end, location, description }
-- where start/end are UNIX timestamps in SECONDS. Read/write end as ev["end"].

local Dates = require("./dates.luau")
local Tbl = require("./tbl.luau")

local Events = {}

-- En dash (U+2013), same glyph as v4.
local EN_DASH = "–"

function Events.dayBounds(iso: string): { start: number, ["end"]: number }
	local start = Dates.parseIsoDate(iso) :: number
	return { start = start * 1000, ["end"] = Dates.addDays(start, 1) * 1000 }
end

function Events.overlapsDay(ev: { [string]: any }, iso: string): boolean
	local b = Events.dayBounds(iso)
	local s = ev.start * 1000
	local e = math.max((ev["end"] :: number) * 1000, s + 1)
	return s < b["end"] and e > b.start
end

-- All-day = starts at local midnight and lasts a whole number of days.
function Events.isAllDay(ev: { [string]: any }): boolean
	local s = ev.start :: number
	local parts = os.date("*t", s) :: { hour: number, min: number }
	local durationMs = ((ev["end"] :: number) - s) * 1000
	return parts.hour == 0 and parts.min == 0 and durationMs > 0 and durationMs % 86400000 == 0
end

-- "HH:MM" when the event starts on that day with a time, else nil.
function Events.timeOn(ev: { [string]: any }, iso: string): string?
	if Events.isAllDay(ev) then
		return nil
	end
	local s = ev.start :: number
	return if Dates.isoDate(s) == iso then Dates.hhmm(s) else nil
end

-- "HH:MM" when the event ends on that day (before midnight), else nil.
function Events.endTimeOn(ev: { [string]: any }, iso: string): string?
	if Events.isAllDay(ev) then
		return nil
	end
	local e = ev["end"] :: number
	return if Dates.isoDate(e) == iso then Dates.hhmm(e) else nil
end

-- "16:00–17:00" when the item has both times, "16:00" with only a start, else nil.
function Events.timeRange(item: { [string]: any }): string?
	if not item.time then
		return nil
	end
	if item.endTime and item.endTime ~= item.time then
		return tostring(item.time) .. EN_DASH .. tostring(item.endTime)
	end
	return item.time :: string
end

function Events.compareTime(a: string?, b: string?): number
	if a == b then
		return 0
	end
	if a == nil then
		return -1
	end
	if b == nil then
		return 1
	end
	return if a < b then -1 else 1
end

-- Events of one day, untimed (all-day or continuing) first, then by start time.
function Events.eventsOn(events: { any }?, iso: string): { any }
	local list = events or {}
	local matched = {}
	for _, ev in ipairs(list) do
		if Events.overlapsDay(ev, iso) then
			table.insert(matched, { ev = ev, time = Events.timeOn(ev, iso) })
		end
	end
	table.sort(matched, function(a, b)
		local cmp = Events.compareTime(a.time, b.time)
		if cmp ~= 0 then
			return cmp < 0
		end
		return a.ev.start < b.ev.start
	end)
	local out = {}
	for _, x in ipairs(matched) do
		table.insert(out, Tbl.merge(x.ev, { time = x.time, endTime = Events.endTimeOn(x.ev, iso) }))
	end
	return out
end

-- Today's earliest timed event that has not ended yet (an event in progress
-- counts), as { uid, summary, date, time }, or nil.
function Events.nextEvent(events: { any }?, nowSeconds: number): { [string]: any }?
	local iso = Dates.isoDate(nowSeconds)
	local dayEvents = Events.eventsOn(events, iso)
	for _, ev in ipairs(dayEvents) do
		if ev.time ~= nil and (ev["end"] :: number) > nowSeconds then
			return { uid = ev.uid, summary = ev.summary, date = iso, time = ev.time }
		end
	end
	return nil
end

return Events

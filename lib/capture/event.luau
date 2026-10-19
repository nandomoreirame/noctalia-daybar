--!strict
-- Event capture: calendar event via khal; 1h when no end is given.

local When = require("../when.luau")
local Dates = require("../dates.luau")

local Event = {}

Event.TYPE = "event"
Event.DEFAULT_MINUTES = 60

function Event.build(text: any, now: number): { [string]: any }
	local w = When.parseWhen(text, now)
	if w.title == nil or w.title == "" then
		return { ok = false, type = Event.TYPE, error = "empty-title" }
	end
	if w.date == nil or w.start == nil then
		return { ok = false, type = Event.TYPE, error = "needs-date-time" }
	end
	local endAt = if w["end"] ~= nil
		then { date = w.date, time = w["end"] }
		else Dates.addMinutes(w.date, w.start, Event.DEFAULT_MINUTES)
	return {
		ok = true,
		type = Event.TYPE,
		action = "createEvent",
		payload = {
			title = w.title,
			date = w.date,
			start = w.start,
			endDate = endAt.date,
			endTime = endAt.time,
			alarm = false,
		},
	}
end

return Event

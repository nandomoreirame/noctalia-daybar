--!strict
-- Reminder capture: 15-minute event with an alarm at start, plus a local toast.

local When = require("../when.luau")
local Dates = require("../dates.luau")

local Reminder = {}

Reminder.TYPE = "reminder"
Reminder.DURATION_MINUTES = 15

function Reminder.build(text: any, now: number): { [string]: any }
	local w = When.parseWhen(text, now)
	if w.title == nil or w.title == "" then
		return { ok = false, type = Reminder.TYPE, error = "empty-title" }
	end
	if w.start == nil then
		return { ok = false, type = Reminder.TYPE, error = "needs-time" }
	end
	-- parseWhen always fills the date when a start time is present.
	local endAt = Dates.addMinutes(w.date, w.start, Reminder.DURATION_MINUTES)
	return {
		ok = true,
		type = Reminder.TYPE,
		action = "createReminder",
		payload = {
			title = w.title,
			date = w.date,
			start = w.start,
			endDate = endAt.date,
			endTime = endAt.time,
			alarm = true,
		},
	}
end

return Reminder

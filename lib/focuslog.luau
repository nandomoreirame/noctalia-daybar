--!strict
-- Completed focus sessions per day: data.focusLog = { "YYYY-MM-DD": count }.

local Tbl = require("./tbl.luau")

local FocusLog = {}

function FocusLog.sessionsOn(data: { [string]: any }, date: string): number
	local log = data.focusLog or {}
	return tonumber(log[date]) or 0
end

function FocusLog.addSession(data: { [string]: any }, date: string): { [string]: any }
	local log = Tbl.merge(data.focusLog or {}, {})
	log[date] = FocusLog.sessionsOn(data, date) + 1
	return Tbl.merge(data, { focusLog = log })
end

-- True only for the session that reaches the goal; a zero goal is disabled.
function FocusLog.goalJustReached(count: number, goal: number): boolean
	return goal > 0 and count == goal
end

return FocusLog

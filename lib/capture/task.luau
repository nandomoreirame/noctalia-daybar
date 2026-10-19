--!strict
-- Task capture: local task; no date means today.

local When = require("../when.luau")
local Dates = require("../dates.luau")

local Task = {}

Task.TYPE = "task"

function Task.build(text: any, now: number): { [string]: any }
	local w = When.parseWhen(text, now)
	if w.title == nil or w.title == "" then
		return { ok = false, type = Task.TYPE, error = "empty-title" }
	end
	return {
		ok = true,
		type = Task.TYPE,
		action = "addTask",
		payload = { title = w.title, date = w.date or Dates.isoDate(now), time = w.start },
	}
end

return Task

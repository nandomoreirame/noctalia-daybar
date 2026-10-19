--!strict
-- Pure task and event-check operations. Every mutator returns a NEW data object
-- (or the same table when nothing changes).

local Tbl = require("./tbl.luau")

local Tasks = {}

local function withTasks(data: { [string]: any }, tasks: { any }): { [string]: any }
	return Tbl.merge(data, { tasks = tasks })
end

local function collapseTitle(title: any): string
	local s = tostring(title or "")
	s = (string.gsub(s, "%s+", " "))
	return (string.match(s, "^%s*(.-)%s*$")) or ""
end

function Tasks.addTask(
	data: { [string]: any },
	fields: { [string]: any },
	id: string,
	nowIso: string
): { [string]: any }
	local task = {
		id = id,
		title = fields.title,
		date = fields.date or nil,
		time = fields.time or nil,
		done = false,
		doneAt = nil,
		pomodoros = 0,
		source = "local",
		externalId = nil,
		createdAt = nowIso,
	}
	local tasks = Tbl.copyList(data.tasks or {})
	table.insert(tasks, task)
	return withTasks(data, tasks)
end

function Tasks.toggleTask(data: { [string]: any }, id: string, nowIso: string): { [string]: any }
	return withTasks(
		data,
		Tbl.map(data.tasks or {}, function(t)
			if t.id ~= id then
				return t
			end
			-- Assign doneAt after merge: a nil in a table literal is omitted, so
			-- Tbl.merge would keep the previous doneAt when clearing it.
			local out = Tbl.merge(t, { done = not t.done })
			out.doneAt = if t.done then nil else nowIso
			return out
		end)
	)
end

function Tasks.deleteTask(data: { [string]: any }, id: string): { [string]: any }
	return withTasks(
		data,
		Tbl.filter(data.tasks or {}, function(t)
			return t.id ~= id
		end)
	)
end

-- Keeps the task as is when the new title is blank.
function Tasks.renameTask(data: { [string]: any }, id: string, title: any): { [string]: any }
	local clean = collapseTitle(title)
	if clean == "" then
		return data
	end
	return withTasks(
		data,
		Tbl.map(data.tasks or {}, function(t)
			if t.id ~= id then
				return t
			end
			return Tbl.merge(t, { title = clean })
		end)
	)
end

function Tasks.addPomodoro(data: { [string]: any }, id: string): { [string]: any }
	return withTasks(
		data,
		Tbl.map(data.tasks or {}, function(t)
			if t.id ~= id then
				return t
			end
			return Tbl.merge(t, { pomodoros = t.pomodoros + 1 })
		end)
	)
end

function Tasks.eventKey(uid: string, date: string): string
	return uid .. "|" .. date
end

function Tasks.toggleEventCheck(data: { [string]: any }, uid: string, date: string): { [string]: any }
	local checks = Tbl.merge(data.eventChecks or {}, {})
	local key = Tasks.eventKey(uid, date)
	if checks[key] then
		checks[key] = nil
	else
		checks[key] = true
	end
	return Tbl.merge(data, { eventChecks = checks })
end

return Tasks

--!strict
-- Builds the Today checklist:
--   1. today's calendar events (untimed first, then by time)
--   2. today's tasks and overdue undone tasks, timed by time, then untimed
-- Item: { kind, id, uid, calendar, title, time, endTime, done, overdue, pomodoros, checkable }
-- Events from read-only calendars (holidays, birthdays, subscriptions) are not
-- checkable: no checkbox, never done, left out of the progress counts.

local Dates = require("./dates.luau")
local Events = require("./events.luau")
local Tasks = require("./tasks.luau")
local EventDelete = require("./eventdelete.luau")
local Tbl = require("./tbl.luau")

local Today = {}

local function eventItems(
	events: { any }?,
	data: { [string]: any },
	iso: string,
	collections: { { [string]: any } }?
): { any }
	return Tbl.map(Events.eventsOn(events, iso), function(ev)
		local checkable = not EventDelete.isReadOnlyCalendar(collections, ev.calendar)
		return {
			kind = "event",
			id = Tasks.eventKey(ev.uid, iso),
			uid = ev.uid,
			calendar = ev.calendar or "",
			title = ev.summary,
			time = ev.time,
			endTime = ev.endTime,
			done = checkable and (data.eventChecks or {})[Tasks.eventKey(ev.uid, iso)] == true,
			overdue = false,
			pomodoros = 0,
			checkable = checkable,
		}
	end)
end

local function compareTasks(a: { [string]: any }, b: { [string]: any }): boolean
	if a.time and b.time then
		if a.time ~= b.time then
			return a.time < b.time
		end
		return false
	end
	if a.time then
		return true
	end
	if b.time then
		return false
	end
	return tostring(a.createdAt or "") < tostring(b.createdAt or "")
end

local function taskItem(t: { [string]: any }, iso: string): { [string]: any }
	return {
		kind = "task",
		id = t.id,
		uid = nil,
		calendar = "",
		title = t.title,
		time = t.time,
		done = t.done,
		overdue = (t.date or iso) < iso,
		pomodoros = t.pomodoros,
		checkable = true,
	}
end

local function taskItems(data: { [string]: any }, iso: string): { any }
	local filtered = Tbl.filter(data.tasks or {}, function(t)
		local date = t.date or iso
		return date == iso or (date < iso and not t.done)
	end)
	table.sort(filtered, compareTasks)
	return Tbl.map(filtered, function(t)
		return taskItem(t, iso)
	end)
end

-- Calendar day list for any day: that day's events, then the tasks dated on it
-- (an undated task belongs to today). No overdue carry-over: that is Today's job.
function Today.dayItems(
	events: { any }?,
	data: { [string]: any },
	iso: string,
	todayIso: string,
	collections: { { [string]: any } }?
): { any }
	local tasks = Tbl.filter(data.tasks or {}, function(t)
		return (t.date or todayIso) == iso
	end)
	table.sort(tasks, compareTasks)
	local taskList = Tbl.map(tasks, function(t)
		return Tbl.merge(taskItem(t, iso), { overdue = false })
	end)
	local out = eventItems(events, data, iso, collections)
	for _, item in ipairs(taskList) do
		table.insert(out, item)
	end
	return out
end

function Today.buildToday(
	events: { any }?,
	data: { [string]: any },
	nowSeconds: number,
	collections: { { [string]: any } }?
): { any }
	local iso = Dates.isoDate(nowSeconds)
	local out = eventItems(events, data, iso, collections)
	for _, item in ipairs(taskItems(data, iso)) do
		table.insert(out, item)
	end
	return out
end

-- { done, total } of a checklist; items with checkable === false do not count.
function Today.progress(items: { any }): { done: number, total: number }
	local list = Tbl.filter(items, function(i)
		return i.checkable ~= false
	end)
	local done = 0
	for _, i in ipairs(list) do
		if i.done then
			done += 1
		end
	end
	return { done = done, total = #list }
end

-- Same list as the Today tab (events, today's and overdue tasks).
function Today.todayProgress(
	events: { any }?,
	data: { [string]: any },
	iso: string,
	collections: { { [string]: any } }?
): { done: number, total: number }
	local items = eventItems(events, data, iso, collections)
	for _, item in ipairs(taskItems(data, iso)) do
		table.insert(items, item)
	end
	return Today.progress(items)
end

-- Same list as the Calendar day list for that day.
function Today.dayProgress(
	events: { any }?,
	data: { [string]: any },
	iso: string,
	collections: { { [string]: any } }?
): { done: number, total: number }
	return Today.progress(Today.dayItems(events, data, iso, iso, collections))
end

-- "Label (done/total)", or just the label when the list is empty.
function Today.withProgress(label: string, p: { done: number, total: number }?): string
	if p and p.total > 0 then
		return label .. " (" .. tostring(p.done) .. "/" .. tostring(p.total) .. ")"
	end
	return label
end

-- "Label (n)", or just the label when there is nothing.
function Today.withCount(label: string, n: number): string
	if n > 0 then
		return label .. " (" .. tostring(n) .. ")"
	end
	return label
end

return Today

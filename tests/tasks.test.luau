local assert = require("./support/assert")
local runner = require("./support/runner")
local modules = require("./support/modules")

local describe, it = runner.describe, runner.it
local Tasks = modules.load("lib/tasks.luau")

local T0 = "2026-10-09T15:00:00.000Z"

local function createEmpty()
	return {
		version = 2,
		tasks = {},
		eventChecks = {},
		reminders = {},
		bookmarks = {},
		notes = {},
		focusLog = {},
		recentTimers = {},
		ui = { lastTab = "", clockOverlay = false },
	}
end

describe("tasks", function()
	it("adds a local task without mutating the input", function()
		local empty = createEmpty()
		local data = Tasks.addTask(empty, { title = "comprar pão", date = "2026-10-10", time = "09:00" }, "t1", T0)
		assert.same(empty.tasks, {})
		assert.same(data.tasks, {
			{
				id = "t1",
				title = "comprar pão",
				date = "2026-10-10",
				time = "09:00",
				done = false,
				doneAt = nil,
				pomodoros = 0,
				source = "local",
				externalId = nil,
				createdAt = T0,
			},
		})
	end)

	it("toggles done and doneAt", function()
		local data = Tasks.addTask(createEmpty(), { title = "x", date = "2026-10-09" }, "t1", T0)
		data = Tasks.toggleTask(data, "t1", "2026-10-09T16:00:00.000Z")
		assert.equal(data.tasks[1].done, true)
		assert.equal(data.tasks[1].doneAt, "2026-10-09T16:00:00.000Z")
		data = Tasks.toggleTask(data, "t1", "2026-10-09T17:00:00.000Z")
		assert.same({ done = data.tasks[1].done, doneAt = data.tasks[1].doneAt }, { done = false, doneAt = nil })
	end)

	it("deletes a task and counts pomodoros", function()
		local data = Tasks.addTask(createEmpty(), { title = "a", date = "2026-10-09" }, "a", T0)
		data = Tasks.addTask(data, { title = "b", date = "2026-10-09" }, "b", T0)
		data = Tasks.addPomodoro(Tasks.addPomodoro(data, "b"), "b")
		local b = nil
		for _, t in ipairs(data.tasks) do
			if t.id == "b" then
				b = t
			end
		end
		assert.equal(b.pomodoros, 2)
		local ids = {}
		for _, t in ipairs(Tasks.deleteTask(data, "a").tasks) do
			table.insert(ids, t.id)
		end
		assert.same(ids, { "b" })
	end)

	it("toggles event checks per occurrence", function()
		local data = Tasks.toggleEventCheck(createEmpty(), "uid-1", "2026-10-09")
		local key = Tasks.eventKey("uid-1", "2026-10-09")
		assert.same(data.eventChecks, { [key] = true })
		data = Tasks.toggleEventCheck(data, "uid-1", "2026-10-16")
		data = Tasks.toggleEventCheck(data, "uid-1", "2026-10-09")
		assert.same(data.eventChecks, { ["uid-1|2026-10-16"] = true })
	end)

	it("renames a task, trimming the title and keeping the rest", function()
		local data = Tasks.addTask(createEmpty(), { title = "old", date = "2026-10-10", time = "09:00" }, "t1", T0)
		local next = Tasks.renameTask(data, "t1", "  new title \n")
		assert.equal(next.tasks[1].title, "new title")
		assert.equal(data.tasks[1].title, "old")
		assert.equal(next.tasks[1].date, "2026-10-10")
		assert.equal(next.tasks[1].time, "09:00")
	end)

	it("ignores an empty title or an unknown id", function()
		local data = Tasks.addTask(createEmpty(), { title = "old", date = "2026-10-10" }, "t1", T0)
		assert.equal(Tasks.renameTask(data, "t1", "   "), data)
		assert.same(Tasks.renameTask(data, "nope", "x").tasks, data.tasks)
	end)
end)

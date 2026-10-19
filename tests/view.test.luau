local assert = require("./support/assert")
local runner = require("./support/runner")
local modules = require("./support/modules")

local describe, it = runner.describe, runner.it
local View = modules.load("lib/view.luau")

local function fixture()
	return {
		data = {
			version = 2,
			tasks = { { id = "t1", title = "x" } },
			eventChecks = {},
			reminders = {},
			bookmarks = { { id = "b1", url = "https://a.dev" }, { id = "b2", url = "https://b.dev" } },
			notes = {},
			focusLog = {},
			recentTimers = {},
			ui = { lastTab = "today", clockOverlay = false },
		},
		settings = { work_duration = 25, fetch_previews = true },
		calendar = { available = true, calendars = { "Eventos" }, events = {} },
		pomodoro = { mode = 0, running = false, remaining = 1500 },
		timer = { set = false, running = false, remaining = 0, label = "" },
	}
end

describe("view", function()
	it("builds the published view with thumb paths and settings", function()
		local f = fixture()
		local v = View.build({
			data = f.data,
			settings = f.settings,
			calendar = f.calendar,
			pomodoro = f.pomodoro,
			timer = f.timer,
			thumbExists = function(id)
				return id == "b1"
			end,
			thumbDir = "/d/thumbs",
			rev = 3,
			now = 1000,
		})
		assert.equal(v.rev, 3)
		assert.equal(v.now, 1000)
		assert.equal(v.data.bookmarks[1].thumbPath, "/d/thumbs/b1")
		assert.equal(v.data.bookmarks[2].thumbPath, nil)
		assert.equal(v.data.version, nil)
		assert.equal(v.data.tasks[1].title, "x")
		assert.equal(v.data.ui.lastTab, "today")
		assert.same(v.settings, f.settings)
		assert.same(v.calendar, f.calendar)
		assert.same(v.pomodoro, f.pomodoro)
		assert.same(v.timer, f.timer)
	end)

	it("does not mutate the source data", function()
		local f = fixture()
		View.build({ data = f.data, thumbExists = function()
			return true
		end, thumbDir = "/d/thumbs", rev = 1, now = 0 })
		assert.equal(f.data.version, 2)
		assert.equal(f.data.bookmarks[1].thumbPath, nil)
	end)

	it("fills defaults for the optional parts", function()
		local v = View.build({ data = fixture().data, rev = 1, now = 0 })
		assert.equal(v.alarmSource, "")
		assert.equal(v.focusPanel, "pomodoro")
		assert.equal(v.requestedTab, nil)
		assert.same(v.details, {})
		assert.same(v.deleting, {})
		assert.same(v.settings, {})
		assert.equal(v.data.bookmarks[1].thumbPath, nil)
	end)

	it("passes alarm, focus panel, requested tab, details and deleting through", function()
		local v = View.build({
			data = fixture().data,
			rev = 2,
			now = 0,
			alarmSource = "timer",
			focusPanel = "timer",
			requestedTab = "notes",
			details = { u1 = { location = "x" } },
			deleting = { u1 = { phase = "ready", recurring = false } },
		})
		assert.equal(v.alarmSource, "timer")
		assert.equal(v.focusPanel, "timer")
		assert.equal(v.requestedTab, "notes")
		assert.equal(v.details.u1.location, "x")
		assert.equal(v.deleting.u1.phase, "ready")
	end)

	it("tolerates missing data and bookmarks without an id", function()
		local v = View.build({ data = nil, rev = 1, now = 0 })
		assert.same(v.data, {})
		local w = View.build({
			data = { bookmarks = { { url = "https://a.dev" } } },
			thumbExists = function()
				return true
			end,
			thumbDir = "/d",
			rev = 1,
			now = 0,
		})
		assert.equal(w.data.bookmarks[1].thumbPath, nil)
	end)
	it("passes the ring directory through", function()
		assert.equal(View.build({ data = {}, ringDir = "/d/rings/ffb38a" }).ringDir, "/d/rings/ffb38a")
		assert.equal(View.build({ data = {} }).ringDir, nil)
	end)
end)

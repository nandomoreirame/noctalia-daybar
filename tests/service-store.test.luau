local assert = require("./support/assert")
local runner = require("./support/runner")
local mock = require("./support/noctalia_mock")
local H = require("./support/service_helpers")

local describe, it = runner.describe, runner.it

local V4_PATH = "~/.local/share/noctalia-daybar/data.json"
local V4_THUMB = "~/.cache/noctalia-daybar/thumbs/b1"

-- 1 task, 1 bookmark b1, 1 note, plus the dropped clockWindow flag.
local V4_DATA = [[{"version":2,"tasks":[{"id":"t1","title":"Old task","date":"2026-10-14","done":false,"pomodoros":0}],"eventChecks":{},"reminders":[],"bookmarks":[{"id":"b1","url":"https://a.dev","title":"A","description":"","image":"/old/thumbs/b1","imageUrl":"","status":"ok","token":1,"createdAt":"x","savedAt":"x"}],"notes":[{"id":"n1","text":"hello","createdAt":"x","updatedAt":"x"}],"focusLog":{},"recentTimers":[],"ui":{"lastTab":"focus","clockWindow":true,"clockOverlay":false}}]]

local V5_DATA = [[{"version":2,"tasks":[{"id":"t9","title":"Mine","date":"2026-10-15","done":false,"pomodoros":0}],"eventChecks":{},"reminders":[],"bookmarks":[],"notes":[],"focusLog":{},"recentTimers":[],"ui":{"lastTab":"today","clockOverlay":false}}]]

local function find(s: string, needle: string): boolean
	return string.find(s, needle, 1, true) ~= nil
end

describe("service store: load", function()
	it("starts empty and publishes a view when no file exists", function()
		local s = H.boot({})
		local v = H.view(s)
		assert.same(v.data.tasks, {})
		assert.equal(v.rev >= 1, true)
		assert.equal(v.data.version, nil)
		assert.equal(H.fs(s)["/data/data.json"], nil)
	end)

	it("sets a 250 ms update interval", function()
		local s = H.boot({})
		local calls = mock.calls(s.env, "noctalia.setUpdateInterval")
		assert.equal(#calls, 1)
		assert.equal(calls[1][1], 250)
	end)

	it("loads the v5 file", function()
		local s = H.boot({ fs = { ["/data/data.json"] = V5_DATA } })
		local v = H.view(s)
		assert.equal(#v.data.tasks, 1)
		assert.equal(v.data.tasks[1].title, "Mine")
		assert.equal(v.data.ui.lastTab, "today")
	end)

	it("renames a corrupt file to .bak and reports it", function()
		local s = H.boot({ fs = { ["/data/data.json"] = "{nope" } })
		assert.equal(H.fs(s)["/data/data.json.bak"], "{nope")
		assert.equal(#mock.calls(s.env, "noctalia.notifyError"), 1)
		assert.same(H.view(s).data.tasks, {})
	end)
end)

describe("service store: v4 import", function()
	it("imports the v4 file once and copies thumbnails", function()
		local s = H.boot({ fs = {
			[V4_PATH] = V4_DATA,
			[V4_THUMB] = "PNG",
		} })
		local v = H.view(s)
		assert.equal(#v.data.tasks, 1)
		assert.equal(#v.data.notes, 1)
		assert.equal(#v.data.bookmarks, 1)
		assert.equal(H.fs(s)["/data/thumbs/b1"], "PNG")
		assert.equal(v.data.bookmarks[1].thumbPath, "/data/thumbs/b1")
		assert.equal(v.data.bookmarks[1].image, "/data/thumbs/b1")
		assert.equal(v.data.ui.clockWindow, nil)
		assert.equal(H.fs(s)[V4_PATH], V4_DATA) -- untouched
		assert.equal(H.fs(s)[V4_THUMB], "PNG") -- untouched
		local notes = mock.calls(s.env, "noctalia.notify")
		assert.equal(#notes, 1)
		assert.equal(notes[1][2], "store.imported bookmarks=1 notes=1 tasks=1")
		-- the v5 file is written at once, so the next start does not import again
		assert.equal(find(H.fs(s)["/data/data.json"], '"Old task"'), true)
	end)

	it("keeps a bookmark without a v4 thumbnail on the world glyph", function()
		local s = H.boot({ fs = { [V4_PATH] = V4_DATA } })
		local b = H.view(s).data.bookmarks[1]
		assert.equal(b.thumbPath, nil)
		assert.equal(b.image, "")
		assert.equal(H.fs(s)["/data/thumbs/b1"], nil)
	end)

	it("does not import when the v5 file exists", function()
		local s = H.boot({ fs = { ["/data/data.json"] = V5_DATA, [V4_PATH] = V4_DATA } })
		local v = H.view(s)
		assert.equal(#v.data.tasks, 1)
		assert.equal(v.data.tasks[1].title, "Mine")
		assert.equal(#mock.calls(s.env, "noctalia.notify"), 0)
		for _, call in mock.calls(s.env, "noctalia.readFile") do
			assert.equal(call[1] ~= V4_PATH, true)
		end
	end)

	it("skips a corrupt v4 file without creating a .bak for it", function()
		local s = H.boot({ fs = { [V4_PATH] = "{nope" } })
		assert.same(H.view(s).data.tasks, {})
		assert.equal(#mock.calls(s.env, "noctalia.notifyError"), 1)
		assert.equal(#mock.calls(s.env, "noctalia.notify"), 0)
		assert.equal(H.fs(s)[V4_PATH .. ".bak"], nil)
		assert.equal(H.fs(s)[V4_PATH], "{nope")
		assert.equal(#mock.calls(s.env, "noctalia.renameFile"), 0)
		assert.equal(H.fs(s)["/data/data.json"], nil)
	end)
end)

describe("service store: save", function()
	it("writes atomically 500 ms after the last change", function()
		local s = H.boot({})
		local ack = H.command(s, "toolbar", "addTask", { title = "x", date = "2026-10-15" })
		assert.equal(ack.ok, true)
		assert.equal(H.fs(s)["/data/data.json"], nil)
		H.tick(s, 300)
		assert.equal(H.fs(s)["/data/data.json"], nil)
		H.tick(s, 300)
		assert.equal(H.fs(s)["/data/data.json.tmp"], nil)
		assert.equal(find(H.fs(s)["/data/data.json"], '"x"'), true)
		local renames = mock.calls(s.env, "noctalia.renameFile")
		assert.same(renames[#renames], { "/data/data.json.tmp", "/data/data.json" })
	end)

	it("restarts the debounce on every change", function()
		local s = H.boot({})
		H.command(s, "toolbar", "addTask", { title = "a", date = "2026-10-15" })
		H.tick(s, 400)
		H.command(s, "toolbar", "addTask", { title = "b", date = "2026-10-15" })
		H.tick(s, 400)
		assert.equal(H.fs(s)["/data/data.json"], nil)
		H.tick(s, 200)
		assert.equal(find(H.fs(s)["/data/data.json"], '"b"'), true)
	end)

	it("publishes a new rev with the added task", function()
		local s = H.boot({})
		local before = H.view(s).rev
		H.command(s, "toolbar", "addTask", { title = "x", date = "2026-10-15" })
		local v = H.view(s)
		assert.equal(v.rev > before, true)
		assert.equal(v.data.tasks[1].title, "x")
	end)

	it("flushes a pending write on exit", function()
		local s = H.boot({})
		H.command(s, "toolbar", "addTask", { title = "late", date = "2026-10-15" })
		s.call("onExit", 0, "shutdown")
		assert.equal(find(H.fs(s)["/data/data.json"], '"late"'), true)
	end)
end)

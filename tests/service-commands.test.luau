local assert = require("./support/assert")
local runner = require("./support/runner")
local mock = require("./support/noctalia_mock")
local H = require("./support/service_helpers")

local describe, it = runner.describe, runner.it

local TOOLBAR = "nandomoreirame/daybar:toolbar"
local CAPTURE = "nandomoreirame/daybar:capture"
local CLOCK = "nandomoreirame/daybar:clock"

local function data(s)
	return H.view(s).data
end

local function addTask(s, title)
	return H.command(s, "toolbar", "addTask", { title = title }).result.id
end

local function toggles(s, id)
	local n = 0
	for _, call in mock.calls(s.env, "noctalia.togglePanel") do
		if call[1] == id then
			n += 1
		end
	end
	return n
end

describe("service commands: tasks and checks", function()
	it("addTask without a date uses today", function()
		local s = H.boot({})
		local ack = H.command(s, "toolbar", "addTask", { title = "  buy   bread " })
		assert.equal(ack.ok, true)
		local t = data(s).tasks[1]
		assert.equal(t.title, "buy   bread")
		assert.equal(t.date, H.TODAY)
		assert.equal(t.id, ack.result.id)
	end)

	it("addTask rejects a blank title and a bad date", function()
		local s = H.boot({})
		assert.equal(H.command(s, "toolbar", "addTask", { title = "  " }).error, "empty-title")
		assert.equal(H.command(s, "toolbar", "addTask", { title = "x", date = "15/10" }).error, "invalid-date")
		assert.equal(H.command(s, "toolbar", "addTask", { title = "x", time = "9h" }).error, "invalid-time")
		assert.same(data(s).tasks, {})
	end)

	it("toggleTask sets and clears done/doneAt", function()
		local s = H.boot({})
		local id = addTask(s, "x")
		assert.equal(H.command(s, "toolbar", "toggleTask", { id = id }).ok, true)
		assert.equal(data(s).tasks[1].done, true)
		assert.equal(typeof(data(s).tasks[1].doneAt), "string")
		H.command(s, "toolbar", "toggleTask", { id = id })
		assert.equal(data(s).tasks[1].done, false)
		assert.equal(data(s).tasks[1].doneAt, nil)
	end)

	it("deleteTask removes the task", function()
		local s = H.boot({})
		local id = addTask(s, "x")
		addTask(s, "y")
		H.command(s, "toolbar", "deleteTask", { id = id })
		assert.equal(#data(s).tasks, 1)
		assert.equal(data(s).tasks[1].title, "y")
	end)

	it("renameTask sets the title and ignores a blank one", function()
		local s = H.boot({})
		local id = addTask(s, "x")
		H.command(s, "toolbar", "renameTask", { id = id, title = "new  name" })
		assert.equal(data(s).tasks[1].title, "new name")
		H.command(s, "toolbar", "renameTask", { id = id, title = " " })
		assert.equal(data(s).tasks[1].title, "new name")
	end)

	it("toggleEvent keys the check by uid and date", function()
		local s = H.boot({})
		H.command(s, "toolbar", "toggleEvent", { uid = "ev1", date = H.TODAY })
		assert.equal(data(s).eventChecks["ev1|" .. H.TODAY], true)
		H.command(s, "toolbar", "toggleEvent", { uid = "ev1", date = H.TODAY })
		assert.equal(data(s).eventChecks["ev1|" .. H.TODAY], nil)
		assert.equal(H.command(s, "toolbar", "toggleEvent", { uid = "", date = H.TODAY }).ok, false)
	end)

	it("setLastTab stores a valid tab only", function()
		local s = H.boot({})
		H.command(s, "toolbar", "setLastTab", { tab = "focus" })
		assert.equal(data(s).ui.lastTab, "focus")
		assert.equal(H.command(s, "toolbar", "setLastTab", { tab = "nope" }).error, "invalid-tab")
		assert.equal(data(s).ui.lastTab, "focus")
	end)
end)

describe("service commands: notes", function()
	it("saveNote creates a note when id is nil and updates it otherwise", function()
		local s = H.boot({})
		local ack = H.command(s, "note", "saveNote", { text = "# Title\nbody" })
		assert.equal(ack.ok, true)
		local id = ack.result.id
		assert.equal(data(s).notes[1].id, id)
		assert.equal(data(s).notes[1].text, "# Title\nbody")
		local again = H.command(s, "note", "saveNote", { id = id, text = "# Title\nchanged" })
		assert.equal(again.result.id, id)
		assert.equal(#data(s).notes, 1)
		assert.equal(data(s).notes[1].text, "# Title\nchanged")
	end)

	it("does not store a blank new note", function()
		local s = H.boot({})
		local ack = H.command(s, "note", "saveNote", { text = "   \n " })
		assert.equal(ack.ok, true)
		assert.equal(ack.result.id, nil)
		assert.same(data(s).notes, {})
	end)

	it("deleteNote removes the note", function()
		local s = H.boot({})
		local id = H.command(s, "note", "saveNote", { text = "a" }).result.id
		H.command(s, "note", "saveNote", { text = "b" })
		H.command(s, "toolbar", "deleteNote", { id = id })
		assert.equal(#data(s).notes, 1)
		assert.equal(data(s).notes[1].text, "b")
	end)
end)

describe("service commands: clipboard, links, settings", function()
	it("copyText copies as text/plain", function()
		local s = H.boot({})
		H.command(s, "toolbar", "copyText", { text = "hello" })
		assert.same(mock.calls(s.env, "noctalia.copyToClipboard")[1], { "hello", "text/plain" })
	end)

	it("openUrl runs xdg-open as argv for openable URLs only", function()
		local s = H.boot({})
		assert.equal(H.command(s, "toolbar", "openUrl", { url = "https://a.dev/x" }).ok, true)
		H.command(s, "toolbar", "openUrl", { url = "mailto:a@b.dev" })
		local ack = H.command(s, "toolbar", "openUrl", { url = "javascript:alert(1)" })
		assert.equal(ack.ok, false)
		assert.equal(ack.error, "invalid-url")
		assert.same(H.ran(s), { "xdg-open https://a.dev/x", "xdg-open mailto:a@b.dev" })
		assert.same(mock.calls(s.env, "noctalia.runAsync")[1][1], { "xdg-open", "https://a.dev/x" })
	end)

	it("setClockOverlay stores the flag and toggles the clock panel on change", function()
		local s = H.boot({})
		H.command(s, "toolbar", "setClockOverlay", { value = true })
		assert.equal(data(s).ui.clockOverlay, true)
		assert.equal(toggles(s, CLOCK), 1)
		H.command(s, "toolbar", "setClockOverlay", { value = true })
		assert.equal(toggles(s, CLOCK), 1)
		H.command(s, "clockpin", "setClockOverlay", { value = false })
		assert.equal(data(s).ui.clockOverlay, false)
		assert.equal(toggles(s, CLOCK), 2)
	end)

	it("reopens the pinned clock at start when the flag is set", function()
		local s = H.boot({ fs = { ["/data/data.json"] = '{"version":2,"ui":{"clockOverlay":true}}' } })
		assert.equal(toggles(s, CLOCK), 1)
		local plain = H.boot({})
		assert.equal(toggles(plain, CLOCK), 0)
	end)

	it("openSettings opens the plugin settings", function()
		local s = H.boot({})
		assert.equal(H.command(s, "toolbar", "openSettings", {}).ok, true)
		assert.equal(#mock.calls(s.env, "noctalia.openSettings"), 1)
	end)
end)

describe("service commands: dispatcher", function()
	it("acks an unknown command with unknown-command and logs it", function()
		local s = H.boot({})
		local ack = H.command(s, "bar", "explode", {})
		assert.equal(ack.ok, false)
		assert.equal(ack.error, "unknown-command")
		assert.equal(#mock.calls(s.env, "noctalia.log") >= 1, true)
	end)

	it("runs a command seen twice once", function()
		local s = H.boot({})
		local list = { { seq = 10, name = "addTask", args = { title = "once" } } }
		s.env.noctalia.state.set("cmd.toolbar", list)
		s.env.noctalia.state.set("cmd.toolbar", list)
		assert.equal(#data(s).tasks, 1)
		assert.equal(H.ack(s, "toolbar").seq, 10)
	end)

	it("runs new commands in seq order and keeps entries apart", function()
		local s = H.boot({})
		s.env.noctalia.state.set("cmd.toolbar", {
			{ seq = 3, name = "addTask", args = { title = "b" } },
			{ seq = 2, name = "addTask", args = { title = "a" } },
		})
		s.env.noctalia.state.set("cmd.capture", { { seq = 1, name = "addTask", args = { title = "c" } } })
		local titles = {}
		for _, t in data(s).tasks do
			table.insert(titles, t.title)
		end
		assert.same(titles, { "a", "b", "c" })
		assert.equal(H.ack(s, "toolbar").seq, 3)
		assert.equal(H.ack(s, "capture").seq, 1)
	end)

	it("rejects malformed ids without crashing", function()
		local s = H.boot({})
		local ack = H.command(s, "toolbar", "renameTask", { id = {}, title = {} })
		assert.equal(ack.ok, false)
		assert.equal(ack.error, "invalid-id")
		assert.equal(H.command(s, "toolbar", "deleteNote", { id = 5 }).error, "invalid-id")
	end)
end)

describe("service IPC", function()
	it("toggle toggles the toolbar", function()
		local s = H.boot({})
		s.call("onIpc", "toggle")
		assert.equal(toggles(s, TOOLBAR), 1)
	end)

	it("capture toggles the capture panel", function()
		local s = H.boot({})
		s.call("onIpc", "capture")
		assert.equal(toggles(s, CAPTURE), 1)
	end)

	it("open <tab> requests the tab and opens a closed toolbar", function()
		local s = H.boot({})
		s.call("onIpc", "open", "focus")
		assert.equal(H.view(s).requestedTab, "focus")
		assert.equal(toggles(s, TOOLBAR), 1)
	end)

	it("open <tab> only switches the tab when the toolbar is open", function()
		local s = H.boot({})
		s.env.noctalia.state.set("toolbar.open", true)
		s.call("onIpc", "open", "notes")
		assert.equal(H.view(s).requestedTab, "notes")
		assert.equal(toggles(s, TOOLBAR), 0)
	end)

	it("open with an invalid tab falls back to the initial tab rule", function()
		local s = H.boot({})
		H.command(s, "toolbar", "setLastTab", { tab = "bookmarks" })
		s.call("onIpc", "open", "../etc")
		assert.equal(H.view(s).requestedTab, "bookmarks")
		local fresh = H.boot({})
		fresh.call("onIpc", "open", nil)
		assert.equal(H.view(fresh).requestedTab, "today")
	end)

	it("clears the requested tab once the toolbar closes", function()
		local s = H.boot({})
		s.call("onIpc", "open", "focus")
		s.env.noctalia.state.set("toolbar.open", true)
		assert.equal(H.view(s).requestedTab, "focus")
		s.env.noctalia.state.set("toolbar.open", false)
		assert.equal(H.view(s).requestedTab, nil)
	end)

	it("ignores an unknown IPC event", function()
		local s = H.boot({})
		s.call("onIpc", "rm -rf")
		assert.equal(#mock.calls(s.env, "noctalia.togglePanel"), 0)
	end)
end)

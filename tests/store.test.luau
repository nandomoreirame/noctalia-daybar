local assert = require("./support/assert")
local runner = require("./support/runner")
local modules = require("./support/modules")
local mock = require("./support/noctalia_mock")

local describe, it = runner.describe, runner.it
local Store = modules.load("lib/store.luau")

local json = mock.new({}).noctalia.json
local mock_decode = json.decode
local mock_encode = json.encode

local function parseRaw(raw)
	local text = mock_encode(raw)
	return Store.parse(text, mock_decode)
end

local function ids(list)
	local out = {}
	for i, x in ipairs(list) do
		out[i] = x.id
	end
	return out
end

describe("store", function()
	it("creates an empty v2 store", function()
		assert.equal(Store.VERSION, 2)
		assert.same(Store.createEmpty(), {
			version = 2,
			tasks = {},
			eventChecks = {},
			reminders = {},
			bookmarks = {},
			notes = {},
			focusLog = {},
			recentTimers = {},
			ui = { lastTab = "", clockOverlay = false },
		})
	end)

	it("treats empty or missing text as a fresh store", function()
		assert.same(Store.parse("", mock_decode), { data = Store.createEmpty(), corrupt = false })
		assert.same(Store.parse("  \n", mock_decode), { data = Store.createEmpty(), corrupt = false })
		assert.same(Store.parse(nil, mock_decode), { data = Store.createEmpty(), corrupt = false })
	end)

	it("flags invalid JSON and non-object roots as corrupt", function()
		assert.equal(Store.parse("{oops", mock_decode).corrupt, true)
		assert.equal(Store.parse("[1,2]", mock_decode).corrupt, true)
		assert.equal(Store.parse("42", mock_decode).corrupt, true)
		assert.equal(Store.parse('"x"', mock_decode).corrupt, true)
		assert.same(Store.parse("{oops", mock_decode).data, Store.createEmpty())
	end)

	it("treats a decoder that throws as corruption", function()
		local r = Store.parse("{}", function()
			error("boom")
		end)
		assert.equal(r.corrupt, true)
	end)

	it("migrates an unversioned file filling defaults", function()
		local r = Store.parse('{"tasks":[{"id":"a","title":"x"},{"title":"no id"}],"eventChecks":[]}', mock_decode)
		assert.equal(r.corrupt, false)
		local data = r.data
		assert.equal(data.version, Store.VERSION)
		assert.same(data.tasks, { {
			id = "a",
			title = "x",
			done = false,
			pomodoros = 0,
			source = "local",
		} })
		assert.same(data.eventChecks, {})
		assert.same(data.bookmarks, {})
		assert.equal(data.links, nil)
		assert.same(data.focusLog, {})
	end)

	it("normalizes task fields the JS way (empty strings are null, numeric ids become strings)", function()
		local r = Store.parse(
			'{"tasks":[{"id":7,"title":"t","date":"","time":"09:00","done":1,"pomodoros":"3","doneAt":"","externalId":"e","source":"gtasks","createdAt":"c"}]}',
			mock_decode
		)
		assert.same(r.data.tasks[1], {
			id = "7",
			title = "t",
			time = "09:00",
			done = true,
			pomodoros = 3,
			source = "gtasks",
			externalId = "e",
			createdAt = "c",
		})
	end)

	it("drops v1 links and notes without migrating them", function()
		local r = Store.parse(
			'{"version":1,"links":[{"id":"l","url":"https://x.com"}],"notes":[{"id":"n","text":"x"}],"tasks":[{"id":"t","title":"keep"}]}',
			mock_decode
		)
		assert.same(r.data.bookmarks, {})
		assert.same(r.data.notes, {})
		assert.same(ids(r.data.tasks), { "t" })
		assert.equal(r.data.links, nil)
	end)

	it("keeps v2 bookmarks and notes", function()
		local b = { id = "b", url = "https://x.com", title = "x.com", description = "", image = "", imageUrl = "", status = "ok", token = 1, createdAt = "t", savedAt = "t" }
		local n = { id = "n", text = "# hi", createdAt = "t", updatedAt = "t" }
		local r = parseRaw({ version = 2, bookmarks = { b }, notes = { n } })
		assert.same(r.data.bookmarks, { b })
		assert.same(r.data.notes, { n })
	end)

	it("resets a pending bookmark fetch left over from a previous run", function()
		local b = { id = "b", url = "https://x.com", status = "pending", token = 3 }
		assert.equal(parseRaw({ version = 2, bookmarks = { b } }).data.bookmarks[1].status, "failed")
	end)

	it("keeps valid focus log counts and drops junk entries", function()
		local r = Store.parse('{"focusLog":{"2026-10-09":3,"2026-10-08":"x","oops":2,"2026-10-07":-1,"2026-10-06":1.5}}', mock_decode)
		assert.same(r.data.focusLog, { ["2026-10-09"] = 3 })
		assert.same(Store.parse('{"focusLog":[1]}', mock_decode).data.focusLog, {})
	end)

	it("normalizes ui: known last tab, boolean clock overlay flag", function()
		local function ui(rawJson)
			return Store.parse('{"ui":' .. rawJson .. "}", mock_decode).data.ui
		end
		assert.same(ui('{"lastTab":"focus","clockOverlay":true}'), { lastTab = "focus", clockOverlay = true })
		assert.same(ui('{"lastTab":"nope","clockOverlay":1}'), { lastTab = "", clockOverlay = false })
		assert.same(ui('"x"'), { lastTab = "", clockOverlay = false })
	end)

	it("drops clockWindow from ui", function()
		local r = Store.parse('{"version":2,"ui":{"clockWindow":true,"clockOverlay":true}}', mock_decode)
		assert.same(r.data.ui, { lastTab = "", clockOverlay = true })
	end)

	it("normalizes empty JSON objects in list fields to empty lists", function()
		local r = Store.parse('{"version":2,"tasks":{},"bookmarks":{}}', mock_decode)
		assert.same(r.data.tasks, {})
		assert.equal(r.corrupt, false)
	end)

	it("treats non-empty JSON objects in list fields as empty lists", function()
		local r = Store.parse('{"version":2,"tasks":{"a":{"id":"a"}},"reminders":{"x":1},"notes":"n"}', mock_decode)
		assert.same(r.data.tasks, {})
		assert.same(r.data.reminders, {})
		assert.same(r.data.notes, {})
	end)

	it("keeps valid recent timers", function()
		local r = Store.parse('{"recentTimers":[{"seconds":300,"label":"chá"},{"seconds":-1}]}', mock_decode)
		assert.same(r.data.recentTimers, { { seconds = 300, label = "chá" } })
		assert.same(Store.parse("{}", mock_decode).data.recentTimers, {})
	end)

	it("round-trips through serialize", function()
		local data = Store.createEmpty()
		table.insert(data.notes, { id = "n1", text = "olá", createdAt = "2026-10-09T15:00:00.000Z" })
		data.version = 2
		local text = Store.serialize(data, mock_encode)
		assert.equal(string.sub(text, -1), "\n")
		assert.same(Store.parse(text, mock_decode).data, data)
	end)

	it("builds ids from time and randomness", function()
		assert.equal(Store.toBase36(0), "0")
		assert.equal(Store.toBase36(35), "z")
		assert.equal(Store.toBase36(1791662400000), "mv2tj7k0")
		assert.equal(Store.makeId(1000, 0.5), "rs-" .. "89oqgw")
		assert.equal(Store.makeId(1000, 0.1) ~= Store.makeId(1000, 0.2), true)
	end)

	it("drops bookmarks and notes without an id (null entries too)", function()
		local r = Store.parse(
			'{"version":2,"bookmarks":[null,{"url":"x"},{"id":"b","url":"https://x.com","status":"ok"}],"notes":[null,{"text":"x"},{"id":"n","text":"t"}]}',
			mock_decode
		)
		assert.same(ids(r.data.bookmarks), { "b" })
		assert.same(ids(r.data.notes), { "n" })
	end)

	it("reads sparse lists (decoders that keep null holes) in index order", function()
		local r = Store.parse("{}", function()
			return { version = 2, notes = { [2] = { id = "b" }, [3] = { id = "c" } } }
		end)
		assert.same(ids(r.data.notes), { "b", "c" })
	end)
end)

describe("setUiFlag", function()
	it("sets a known flag and keeps the rest of ui", function()
		local data = Store.createEmpty()
		data.ui.lastTab = "focus"
		local nextData = Store.setUiFlag(data, "clockOverlay", true)
		assert.same(nextData.ui, { lastTab = "focus", clockOverlay = true })
		assert.equal(data.ui.clockOverlay, false)
	end)

	it("returns the same object when nothing changes or the key is unknown", function()
		local data = Store.createEmpty()
		assert.equal(Store.setUiFlag(data, "clockOverlay", false), data)
		assert.equal(Store.setUiFlag(data, "lastTab", true), data)
		assert.equal(Store.setUiFlag(data, "clockWindow", true), data)
		local older = { version = 2, ui = { lastTab = "" } }
		assert.equal(Store.setUiFlag(older, "clockOverlay", false), older)
	end)
end)

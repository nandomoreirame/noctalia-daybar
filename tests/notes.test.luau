local assert = require("./support/assert")
local runner = require("./support/runner")
local modules = require("./support/modules")

local describe, it = runner.describe, runner.it
local Notes = modules.load("lib/notes.luau")

local T0 = "2026-10-09T15:00:00.000Z"
local T1 = "2026-10-09T16:00:00.000Z"
local function ids(list)
	local out = {}
	for i, n in ipairs(list) do
		out[i] = n.id
	end
	return out
end

describe("notes derived fields", function()
	local cases = {
		{ "# Shopping list\n- milk", "Shopping list" },
		{ "\n\n  **Bold** and _it_ `code`  \nmore", "Bold and it code" },
		{ "- [x] done item", "done item" },
		{ "> quoted [link](https://x.com) ![img](a.png)", "quoted link img" },
		{ "1. first", "first" },
		{ "   \n  ", "" },
		{ "\r\n# Windows\r\nbody", "Windows" },
	}
	for _, c in ipairs(cases) do
		local text, title = c[1], c[2]
		it(string.format("titleOf(%q) = %q", text, title), function()
			assert.equal(Notes.titleOf(text), title)
		end)
	end

	it("titleOf(nil) is empty", function()
		assert.equal(Notes.titleOf(nil), "")
	end)

	it("snippets the text after the title line as one plain line, capped at 140", function()
		assert.equal(Notes.snippetOf("# Title\n\nFirst **line**\n- second"), "First line second")
		assert.equal(Notes.snippetOf("only title"), "")
		assert.equal(#Notes.snippetOf("t\n" .. string.rep("word ", 100)), 140)
	end)

	it("detects blank notes", function()
		assert.equal(Notes.isBlank("  \n\t "), true)
		assert.equal(Notes.isBlank(nil), true)
		assert.equal(Notes.isBlank("x"), false)
	end)
end)

describe("notes operations", function()
	it("adds with created and updated timestamps", function()
		local data = Notes.add({ notes = {} }, "  hello  ", "n1", T0)
		assert.same(data.notes, { { id = "n1", text = "hello", createdAt = T0, updatedAt = T0 } })
	end)

	it("updates text and timestamp, returns the same object when unchanged", function()
		local data = Notes.add({ notes = {} }, "a", "n1", T0)
		local nextData = Notes.update(data, "n1", "b", T1)
		assert.same(nextData.notes[1], { id = "n1", text = "b", createdAt = T0, updatedAt = T1 })
		assert.equal(Notes.update(nextData, "n1", "b", "2026-10-09T17:00:00.000Z"), nextData)
		assert.equal(Notes.update(nextData, "zz", "c", T1), nextData)
	end)

	it("keeps the text verbatim on update (no trim) so the editor cursor does not jump", function()
		local data = Notes.add({ notes = {} }, "a", "n1", T0)
		assert.equal(Notes.update(data, "n1", "line \n", T1).notes[1].text, "line \n")
	end)

	it("removes, sorts by last edit and searches without accents", function()
		local data = Notes.add({ notes = {} }, "Reunião", "a", T0)
		data = Notes.add(data, "Café", "b", T0)
		data = Notes.update(data, "a", "Reunião de equipe", T1)
		assert.same(ids(Notes.sorted(data.notes)), { "a", "b" })
		assert.same(ids(Notes.search(data.notes, "reuniao")), { "a" })
		assert.same(ids(Notes.remove(data, "a").notes), { "b" })
	end)
end)

describe("notes.closeAction", function()
	it("discards a note created in this window that ends blank", function()
		assert.equal(Notes.closeAction(true, "  \n "), "discard")
		assert.equal(Notes.closeAction(true, nil), "discard")
		assert.equal(Notes.closeAction(true, "x"), "save")
	end)

	it("never discards a note that existed before the window opened", function()
		assert.equal(Notes.closeAction(false, ""), "save")
	end)
end)

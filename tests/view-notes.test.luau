local assert = require("./support/assert")
local runner = require("./support/runner")
local mock = require("./support/noctalia_mock")
local modules = require("./support/modules")
local U = require("./support/ui_helpers")

local describe, it = runner.describe, runner.it

local NotesView = modules.load("views/notes.luau")

local NOW = 1792065600000

local function makeCtx()
	local env = mock.new({})
	local ctx = {
		ui = env.ui,
		tr = function(k)
			return k
		end,
		nowMs = NOW,
		st = {},
		requests = {},
		toggled = {},
		view = {
			data = {
				notes = {
					{ id = "n1", text = "# Groceries\n\n- milk", createdAt = "2026-10-14T12:00:00.000Z", updatedAt = "2026-10-14T12:00:00.000Z" },
					{ id = "n2", text = "Ideias soltas", createdAt = "2026-10-15T11:00:00.000Z", updatedAt = "2026-10-15T11:58:00.000Z" },
				},
			},
		},
	}
	ctx.state = {
		set = function(key, value)
			table.insert(ctx.requests, { key, value })
		end,
	}
	ctx.togglePanel = function(id)
		table.insert(ctx.toggled, id)
	end
	ctx.send = function() end
	ctx.render = function() end
	return ctx
end

describe("notes view", function()
	it("lists notes newest first with title, snippet and relative time", function()
		local tree = NotesView.build(makeCtx())
		local rows = U.findAll(tree, function(n)
			return n.props ~= nil and typeof(n.props.key) == "string" and string.sub(n.props.key, 1, 5) == "note-"
		end)
		assert.equal(rows[1].props.key, "note-n2")
		assert.equal(U.hasLabel(tree, "Groceries"), true)
		assert.equal(U.hasLabel(tree, "milk"), true)
		assert.equal(U.hasLabel(tree, "time.minutes"), true)
	end)

	it("searches without accents", function()
		local ctx = makeCtx()
		U.byKey(NotesView.build(ctx), "search").props.onChange("ideias")
		local tree = NotesView.build(ctx)
		assert.equal(U.hasLabel(tree, "Ideias soltas"), true)
		assert.equal(U.hasLabel(tree, "Groceries"), false)
	end)

	it("opens a note or a new one in the note panel", function()
		local ctx = makeCtx()
		U.byKey(NotesView.build(ctx), "note-n1").props.onClick()
		assert.same(ctx.requests[1], { "note.request", "n1" })
		assert.equal(ctx.toggled[1], "nandomoreirame/daybar:note")
		U.button(NotesView.build(ctx), "text", "notes.new").props.onClick()
		assert.same(ctx.requests[2], { "note.request", "new" })
	end)
end)

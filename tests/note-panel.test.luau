local assert = require("./support/assert")
local runner = require("./support/runner")
local mock = require("./support/noctalia_mock")
local entry = require("./support/entry")

local describe, it = runner.describe, runner.it

local NOW = 1792065600000

local NOTE = { id = "n1", text = "# Groceries\n\n- milk", createdAt = "2026-10-14T12:00:00.000Z", updatedAt = "2026-10-14T12:00:00.000Z" }

local function boot(request, notes)
	local p = entry.load("note.luau", { now = NOW })
	p.env.noctalia.state.set("view", { rev = 1, now = NOW, data = { notes = notes or { NOTE } } })
	p.env.noctalia.state.set("note.request", request)
	p.call("onOpen")
	return p
end

local function tree(p)
	local calls = mock.calls(p.env, "panel.render")
	return calls[#calls][1]
end

local function findAll(node, pred, out)
	out = out or {}
	if pred(node) then
		table.insert(out, node)
	end
	for _, child in node.children or {} do
		findAll(child, pred, out)
	end
	return out
end

local function ofType(p, kind)
	return findAll(tree(p), function(n)
		return n.type == kind
	end)
end

local function button(p, glyph)
	return findAll(tree(p), function(n)
		return n.type == "button" and n.props.glyph == glyph
	end)[1]
end

local function commands(p)
	return p.env.noctalia.state.get("cmd.note") or {}
end

local function ackLast(p, result)
	local list = commands(p)
	p.env.noctalia.state.set("ack.note", { seq = list[#list].seq, ok = true, result = result })
end

local function tick(p, ms)
	mock.advance(p.env, ms)
	p.call("update")
end

describe("note panel", function()
	it("opens an existing note in the preview with its title", function()
		local p = boot("n1")
		assert.equal(#ofType(p, "input"), 0)
		assert.equal(#ofType(p, "scroll"), 1)
		local labels = {}
		for _, l in ofType(p, "label") do
			labels[l.props.text] = true
		end
		assert.equal(labels["Groceries"], true)
	end)

	it("opens a new note in an empty focused editor", function()
		local p = boot("new")
		local field = ofType(p, "input")[1]
		assert.equal(field.props.focus, true)
		assert.equal(field.props.value, "")
		assert.equal(field.props.multiline, true)
	end)

	it("ctrl+e and the pencil button toggle editor and preview", function()
		local p = boot("n1")
		p.call("onKey", "ctrl+e", true)
		assert.equal(#ofType(p, "input"), 1)
		p.call("onKey", "ctrl+e", true)
		assert.equal(#ofType(p, "input"), 0)
		button(p, "pencil").props.onClick()
		assert.equal(#ofType(p, "input"), 1)
	end)

	it("saves 600 ms after the last change", function()
		local p = boot("n1")
		p.call("onKey", "ctrl+e", true)
		p.call("onChange", "# Groceries\n\n- milk\n- eggs")
		tick(p, 400)
		assert.equal(#commands(p), 0)
		tick(p, 200)
		local cmd = commands(p)[1]
		assert.equal(cmd.name, "saveNote")
		assert.same(cmd.args, { id = "n1", text = "# Groceries\n\n- milk\n- eggs" })
	end)

	it("ctrl+s saves at once and close saves pending text", function()
		local p = boot("n1")
		p.call("onChange", "edited")
		p.call("onKey", "ctrl+s", true)
		assert.equal(#commands(p), 1)
		p.call("onChange", "edited again")
		p.call("onClose")
		assert.equal(commands(p)[2].args.text, "edited again")
	end)

	it("a new note gets its id from the first save and is not created twice", function()
		local p = boot("new")
		p.call("onChange", "first")
		tick(p, 600)
		assert.same(commands(p)[1].args, { text = "first" })
		p.call("onChange", "first line")
		tick(p, 600)
		assert.equal(#commands(p), 1)
		ackLast(p, { id = "n9" })
		tick(p, 600)
		assert.same(commands(p)[1].args, { id = "n9", text = "first line" })
	end)

	it("a new note still blank on close sends nothing", function()
		local p = boot("new")
		p.call("onChange", "   ")
		p.call("onClose")
		assert.equal(#commands(p), 0)
	end)

	it("a note created here and emptied before closing is deleted", function()
		local p = boot("new")
		p.call("onChange", "x")
		p.call("onKey", "ctrl+s", true)
		ackLast(p, { id = "n9" })
		p.call("onChange", "")
		p.call("onClose")
		local last = commands(p)[#commands(p)]
		assert.equal(last.name, "deleteNote")
		assert.same(last.args, { id = "n9" })
	end)

	it("copy, delete with confirmation, and close", function()
		local p = boot("n1")
		button(p, "copy").props.onClick()
		assert.equal(commands(p)[1].name, "copyText")
		assert.equal(commands(p)[1].args.text, NOTE.text)
		button(p, "trash").props.onClick()
		assert.equal(#mock.calls(p.env, "panel.close"), 0)
		local confirm = findAll(tree(p), function(n)
			return n.type == "button" and n.props.text == "confirm.delete"
		end)[1]
		confirm.props.onClick()
		assert.equal(commands(p)[2].name, "deleteNote")
		assert.equal(#mock.calls(p.env, "panel.close"), 1)
		p.call("onClose")
		assert.equal(#commands(p), 2)
		button(p, "x").props.onClick()
		assert.equal(#mock.calls(p.env, "panel.close"), 2)
	end)

	it("shows the last edit time in the header", function()
		local p = boot("n1")
		local found = false
		for _, l in ofType(p, "label") do
			if string.find(l.props.text, "notes.edited", 1, true) then
				found = true
			end
		end
		assert.equal(found, true)
	end)
end)

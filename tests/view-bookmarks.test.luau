local assert = require("./support/assert")
local runner = require("./support/runner")
local mock = require("./support/noctalia_mock")
local modules = require("./support/modules")
local U = require("./support/ui_helpers")

local describe, it = runner.describe, runner.it

local BookmarksView = modules.load("views/bookmarks.luau")

local NOW = 1792065600000

local function makeCtx()
	local env = mock.new({})
	local sent = {}
	local ctx = {
		ui = env.ui,
		tr = function(k)
			return k
		end,
		nowMs = NOW,
		st = {},
		sent = sent,
		view = {
			data = {
				bookmarks = {
					{ id = "b1", url = "https://www.example.com/a", title = "Café com código", description = "About coffee", savedAt = "2026-10-14T12:00:00.000Z", status = "ok", thumbPath = "/data/thumbs/b1" },
					{ id = "b2", url = "https://other.dev/", title = "Other", description = "", savedAt = "2026-10-13T12:00:00.000Z", status = "pending" },
				},
			},
		},
	}
	ctx.send = function(name, args, onAck)
		table.insert(sent, { name = name, args = args, onAck = onAck })
	end
	ctx.render = function() end
	return ctx
end

describe("bookmarks view", function()
	it("adds a URL and clears the field after the ack", function()
		local ctx = makeCtx()
		local field = U.byKey(BookmarksView.build(ctx), "add-0")
		field.props.onSubmit("https://new.dev")
		assert.equal(ctx.sent[1].name, "addBookmark")
		assert.same(ctx.sent[1].args, { url = "https://new.dev" })
		ctx.sent[1].onAck({ ok = true })
		assert.equal(U.byKey(BookmarksView.build(ctx), "add-1") ~= nil, true)
	end)

	it("filters with an accent-insensitive search", function()
		local ctx = makeCtx()
		U.byKey(BookmarksView.build(ctx), "search").props.onChange("cafe")
		local tree = BookmarksView.build(ctx)
		assert.equal(U.hasLabel(tree, "Café com código"), true)
		assert.equal(U.hasLabel(tree, "Other"), false)
	end)

	it("shows the thumbnail or a world glyph, the description and domain · date", function()
		local tree = BookmarksView.build(makeCtx())
		local image = U.ofType(tree, "image")[1]
		assert.equal(image.props.path, "/data/thumbs/b1")
		assert.equal(image.props.width, 64)
		assert.equal(image.props.height, 40)
		assert.equal(#U.findAll(tree, function(n)
			return n.type == "glyph" and n.props.name == "world"
		end), 1)
		local desc = U.findAll(tree, function(n)
			return n.type == "label" and n.props.text == "About coffee"
		end)[1]
		assert.equal(desc.props.maxLines, 2)
		assert.equal(U.hasLabel(tree, "example.com · 14/10"), true)
	end)

	it("opens a row and shows its actions on hover", function()
		local ctx = makeCtx()
		local row = U.byKey(BookmarksView.build(ctx), "row-b1")
		row.props.onClick()
		assert.same(ctx.sent[1].args, { url = "https://www.example.com/a" })
		assert.equal(U.button(BookmarksView.build(ctx), "tooltip", "bookmarks.copy"), nil)
		row.props.onHover("true", "row-b1")
		local tree = BookmarksView.build(ctx)
		U.button(tree, "tooltip", "bookmarks.copy").props.onClick()
		U.button(tree, "tooltip", "bookmarks.refresh").props.onClick()
		assert.same(ctx.sent[2], { name = "copyText", args = { text = "https://www.example.com/a" }, onAck = nil })
		assert.same(ctx.sent[3].args, { id = "b1" })
	end)

	it("renames inline and deletes after confirming", function()
		local ctx = makeCtx()
		U.byKey(BookmarksView.build(ctx), "row-b1").props.onHover("true", "row-b1")
		U.button(BookmarksView.build(ctx), "tooltip", "bookmarks.rename").props.onClick()
		U.byKey(BookmarksView.build(ctx), "rename-b1").props.onSubmit("Coffee")
		assert.same(ctx.sent[1], { name = "renameBookmark", args = { id = "b1", title = "Coffee" }, onAck = nil })
		U.byKey(BookmarksView.build(ctx), "row-b1").props.onHover("true", "row-b1")
		U.button(BookmarksView.build(ctx), "tooltip", "bookmarks.delete").props.onClick()
		assert.equal(#ctx.sent, 1)
		U.button(BookmarksView.build(ctx), "text", "confirm.delete").props.onClick()
		assert.same(ctx.sent[2].args, { id = "b1" })
		assert.equal(ctx.sent[2].name, "deleteBookmark")
	end)
end)

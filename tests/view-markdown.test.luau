local assert = require("./support/assert")
local runner = require("./support/runner")
local mock = require("./support/noctalia_mock")
local modules = require("./support/modules")

local describe, it = runner.describe, runner.it

local MdView = modules.load("lib/mdview.luau")
local MarkdownView = modules.load("views/markdown.luau")

local function build(text, onLink)
	local env = mock.new({})
	return MarkdownView.build(MdView.render(text, { home = "/users/u" }), { ui = env.ui, onLink = onLink or function() end })
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

local function ofType(node, kind)
	return findAll(node, function(n)
		return n.type == kind
	end)
end

describe("markdown view", function()
	it("wraps the blocks in a scroll", function()
		assert.equal(build("hello").type, "scroll")
	end)

	it("renders headings as bold labels sized by level", function()
		local labels = ofType(build("# Big\n\n### Small"), "label")
		assert.equal(labels[1].props.text, "Big")
		assert.equal(labels[1].props.fontWeight, "bold")
		assert.equal(labels[1].props.fontSize > labels[2].props.fontSize, true)
	end)

	it("turns a link span into a ghost button that opens the URL", function()
		local opened
		local tree = build("see [site](https://x.dev) now", function(href)
			opened = href
		end)
		local button = ofType(tree, "button")[1]
		assert.equal(button.props.text, "site")
		assert.equal(button.props.variant, "ghost")
		button.props.onClick()
		assert.equal(opened, "https://x.dev")
	end)

	it("keeps a javascript link as plain text", function()
		local tree = build("[x](javascript:alert(1))")
		assert.equal(#ofType(tree, "button"), 0)
	end)

	it("shows code in a filled column with a monospace font", function()
		local tree = build("```\nlocal x = 1\n```")
		local code = findAll(tree, function(n)
			return n.type == "label" and n.props.fontFamily == "monospace"
		end)[1]
		assert.equal(code.props.text, "local x = 1")
		local filled = findAll(tree, function(n)
			return n.type == "column" and n.props.fill ~= nil
		end)
		assert.equal(#filled >= 1, true)
	end)

	it("renders local images, rules and list markers", function()
		local tree = build("![cat](~/pics/cat.png)\n\n---\n\n- a\n- [ ] c\n- [x] d\n\n1. b")
		assert.equal(ofType(tree, "image")[1].props.path, "/users/u/pics/cat.png")
		assert.equal(#ofType(tree, "separator"), 1)
		local texts = {}
		for _, l in ofType(tree, "label") do
			table.insert(texts, l.props.text)
		end
		local joined = table.concat(texts, "|")
		assert.equal(string.find(joined, "•", 1, true) ~= nil, true)
		assert.equal(string.find(joined, "1.", 1, true) ~= nil, true)
		assert.equal(string.find(joined, "☐", 1, true) ~= nil, true)
		assert.equal(string.find(joined, "☑", 1, true) ~= nil, true)
	end)
end)

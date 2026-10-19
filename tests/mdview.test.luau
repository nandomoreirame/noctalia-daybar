local assert = require("./support/assert")
local runner = require("./support/runner")
local modules = require("./support/modules")

local describe, it = runner.describe, runner.it
local MdView = modules.load("lib/mdview.luau")

local function first(text)
	return MdView.render(text)[1]
end
local function kinds(blocks)
	local out = {}
	for i, b in ipairs(blocks) do
		out[i] = b.kind
	end
	return out
end

describe("mdview inline spans", function()
	it("keeps raw HTML as inert plain text", function()
		assert.same(first("<script>alert(1)</script> & co"), {
			kind = "paragraph",
			spans = { { text = "<script>alert(1)</script> & co" } },
		})
	end)

	it("drops bold, italic, strike and code markers keeping their text", function()
		assert.same(first("**b** _i_ *j* ~~s~~ `a<b>*c*`").spans, { { text = "b i j s a<b>*c*" } })
	end)

	it("keeps underscores inside words and lone asterisks", function()
		assert.same(first("snake_case_name and 2 * 3").spans, { { text = "snake_case_name and 2 * 3" } })
	end)

	it("links only http(s) and mailto", function()
		assert.same(first("see [site](https://x.com/a?b=1&c=2) now").spans, {
			{ text = "see " },
			{ text = "site", href = "https://x.com/a?b=1&c=2" },
			{ text = " now" },
		})
		assert.same(first("[m](mailto:me@x.com)").spans, { { text = "m", href = "mailto:me@x.com" } })
		assert.same(first("<https://x.com>").spans, { { text = "https://x.com", href = "https://x.com" } })
	end)

	it("drops javascript links to plain text", function()
		local b = MdView.render("[x](javascript:alert(1))")[1]
		assert.equal(b.spans[1].href, nil)
		assert.equal(b.spans[1].text, "x")
		assert.equal(#b.spans, 1)
	end)

	it("keeps a quote in the URL inside one link span", function()
		local b = first('[x](https://x.com/"onmouseover="y)')
		assert.equal(#b.spans, 1)
		assert.equal(b.spans[1].text, "x")
	end)

	it("drops emphasis markers in link labels and across links", function()
		assert.same(first("**a [*b*](https://x.dev) c**").spans, {
			{ text = "a " },
			{ text = "b", href = "https://x.dev" },
			{ text = " c" },
		})
	end)

	it("keeps one level of parentheses in URLs", function()
		assert.same(first("[w](https://en.wikipedia.org/wiki/Foo_(bar))").spans, {
			{ text = "w", href = "https://en.wikipedia.org/wiki/Foo_(bar)" },
		})
	end)

	it("accepts a link title after the destination", function()
		assert.same(first('[t](https://x.dev "Title")').spans, { { text = "t", href = "https://x.dev" } })
	end)

	it("resolves reference-style links and leaves unknown references as text", function()
		local blocks = MdView.render("[docs][d] and [Docs] and [nope][zz]\n\n[d]: https://x.dev/docs")
		assert.equal(#blocks, 1)
		assert.same(blocks[1].spans, {
			{ text = "docs", href = "https://x.dev/docs" },
			{ text = " and [Docs] and [nope][zz]" },
		})
	end)

	it("resolves collapsed reference links", function()
		assert.same(first("[D][]\n[d]: https://x.dev").spans, { { text = "D", href = "https://x.dev" } })
	end)
end)

describe("mdview images", function()
	it("turns a remote image into a link with its alt text", function()
		local b = MdView.render("![logo](https://x.dev/l.png)")[1]
		assert.same(b.spans[1], { text = "logo", href = "https://x.dev/l.png" })
	end)

	it("uses the URL as the text of a remote image without alt", function()
		assert.same(first("![](https://x.dev/l.png)").spans, { { text = "https://x.dev/l.png", href = "https://x.dev/l.png" } })
	end)

	it("never links a remote image with a refused scheme", function()
		assert.same(first("![a](javascript:alert(1))").spans, { { text = "a" } })
		assert.same(first("![a](//x.dev/l.png)").spans, { { text = "a" } })
	end)

	it("keeps absolute local images as image blocks", function()
		assert.same(first("![l](/data/u/a.png)"), { kind = "image", path = "/data/u/a.png", alt = "l" })
		assert.same(first("![l](file:///data/u/a.png)"), { kind = "image", path = "/data/u/a.png", alt = "l" })
		assert.same(first("![l](~/pics/a.png)"), { kind = "image", path = "~/pics/a.png", alt = "l" })
	end)

	it("expands ~/ with opts.home when given", function()
		local b = MdView.render("![l](~/pics/a.png)", { home = "/h" })[1]
		assert.equal(b.path, "/h/pics/a.png")
	end)

	it("drops relative image paths to their alt text", function()
		assert.same(first("![a](rel/a.png)").spans, { { text = "a" } })
	end)

	it("splits a paragraph around a local image", function()
		local blocks = MdView.render("before ![l](/a.png) after")
		assert.same(blocks, {
			{ kind = "paragraph", spans = { { text = "before " } } },
			{ kind = "image", path = "/a.png", alt = "l" },
			{ kind = "paragraph", spans = { { text = " after" } } },
		})
	end)

	it("resolves reference-style images through the definitions", function()
		assert.same(MdView.render("![logo][r]\n\n[r]: https://t.dev/p.png")[1].spans, {
			{ text = "logo", href = "https://t.dev/p.png" },
		})
		assert.same(MdView.render("![logo][l]\n\n[l]: /data/logo.png")[1], { kind = "image", path = "/data/logo.png", alt = "logo" })
	end)
end)

describe("mdview blocks", function()
	it("renders headings with their level", function()
		local blocks = MdView.render("# Title\n## Sub\n### Third **x** ##")
		assert.same(blocks, {
			{ kind = "heading", level = 1, text = "Title" },
			{ kind = "heading", level = 2, text = "Sub" },
			{ kind = "heading", level = 3, text = "Third x" },
		})
	end)

	it("treats seven hashes or no space as a paragraph", function()
		assert.same(kinds(MdView.render("####### x\n\n#tag")), { "paragraph", "paragraph" })
	end)

	it("joins paragraph lines and separates paragraphs", function()
		assert.same(MdView.render("one\ntwo\n\nthree"), {
			{ kind = "paragraph", spans = { { text = "one two" } } },
			{ kind = "paragraph", spans = { { text = "three" } } },
		})
	end)

	it("keeps a hard line break (two trailing spaces) as a newline", function()
		assert.same(first("one  \ntwo").spans, { { text = "one\ntwo" } })
	end)

	it("keeps fenced code verbatim", function()
		local b = MdView.render("```\na  *b*\n```")[1]
		assert.same(b, { kind = "code", text = "a  *b*" })
	end)

	it("keeps fenced code with a language and tilde fences", function()
		assert.same(first("```js\nconst a = '<b>';\n**not bold**\n```"), { kind = "code", text = "const a = '<b>';\n**not bold**" })
		assert.same(first("~~~\nx\n~~~"), { kind = "code", text = "x" })
	end)

	it("runs an unclosed fence to the end of the text", function()
		assert.same(MdView.render("```\na\nb"), { { kind = "code", text = "a\nb" } })
	end)

	it("renders unordered, ordered and task lists", function()
		local blocks = MdView.render("- a\n- [x] done\n- [ ] todo\n\n1. one\n2) two")
		assert.same(blocks, {
			{
				kind = "list",
				ordered = false,
				items = {
					{ spans = { { text = "a" } }, depth = 0 },
					{ spans = { { text = "done" } }, task = true, depth = 0 },
					{ spans = { { text = "todo" } }, task = false, depth = 0 },
				},
			},
			{
				kind = "list",
				ordered = true,
				items = {
					{ spans = { { text = "one" } }, depth = 0 },
					{ spans = { { text = "two" } }, depth = 0 },
				},
			},
		})
	end)

	it("nests indented list items with a depth", function()
		local b = first("- a\n  - b\n\t- c\n- d")
		local depths = {}
		for i, item in ipairs(b.items) do
			depths[i] = item.spans[1].text .. "=" .. item.depth
		end
		assert.same(depths, { "a=0", "b=1", "c=2", "d=0" })
	end)

	it("renders blockquotes as spans", function()
		assert.same(first("> quoted **text**\n> more"), { kind = "quote", spans = { { text = "quoted text more" } } })
	end)

	it("renders GFM tables as rows of plain cells, header first", function()
		assert.same(first("| A | B |\n|---|:-:|\n| `x` | [2](https://x.dev) |\nafter"), {
			kind = "table",
			rows = { { "A", "B" }, { "x", "2" } },
		})
	end)

	it("does not read a pipe line without a separator as a table", function()
		assert.same(kinds(MdView.render("a | b\nc | d")), { "paragraph" })
	end)

	it("renders horizontal rules", function()
		assert.same(kinds(MdView.render("a\n\n---\n\n* * *\n\nb")), { "paragraph", "rule", "rule", "paragraph" })
	end)

	it("hides reference definitions", function()
		assert.same(MdView.render("[d]: https://x.dev"), {})
	end)

	it("handles CRLF line endings", function()
		assert.same(kinds(MdView.render("# T\r\n\r\nbody\r\n")), { "heading", "paragraph" })
	end)

	it("returns an empty list for empty input", function()
		assert.same(MdView.render(""), {})
		assert.same(MdView.render(nil), {})
		assert.same(MdView.render("  \n\n"), {})
	end)
end)

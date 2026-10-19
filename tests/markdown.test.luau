local assert = require("./support/assert")
local runner = require("./support/runner")
local modules = require("./support/modules")

local describe, it = runner.describe, runner.it
local Markdown = modules.load("lib/markdown.luau")
local prepare = Markdown.prepare

describe("markdown.prepare", function()
	it("turns remote images into links with their alt text", function()
		assert.equal(prepare("see ![a cat](https://x.com/cat.png) here"), "see [a cat](https://x.com/cat.png) here")
		assert.equal(prepare('![](http://x.com/a.png "t")'), "[http://x.com/a.png](http://x.com/a.png)")
	end)

	it("keeps local images", function()
		assert.equal(prepare("![local](file:///opt/u/a.png)"), "![local](file:///opt/u/a.png)")
		assert.equal(prepare("![abs](/opt/u/a.png)"), "![abs](/opt/u/a.png)")
	end)

	it("removes raw <img> tags that point to the network", function()
		assert.equal(prepare('a <img src="https://x.com/t.gif"> b'), "a  b")
		assert.equal(prepare("<IMG SRC='//x.com/t.gif'/>"), "")
	end)

	it("returns an empty string for empty input", function()
		assert.equal(prepare(""), "")
		assert.equal(prepare(nil), "")
	end)

	it("leaves plain text and links untouched", function()
		assert.equal(prepare("a [b](https://x.com) c"), "a [b](https://x.com) c")
	end)
end)

describe("markdown.isOpenableLink", function()
	local cases = {
		{ "https://x.com", true },
		{ "http://x.com/a", true },
		{ "mailto:me@x.com", true },
		{ "MAILTO:me@x.com", true },
		{ "mailto:me@x.com?subject=hi there", false },
		{ "mailto:nobody", false },
		{ "javascript:alert(1)", false },
		{ "file:///etc/passwd", false },
		{ "data:text/html,hi", false },
		{ "", false },
	}
	for _, c in ipairs(cases) do
		local url, expected = c[1], c[2]
		it(string.format("%q -> %s", url, tostring(expected)), function()
			assert.equal(Markdown.isOpenableLink(url), expected)
		end)
	end
	it("nil -> false", function()
		assert.equal(Markdown.isOpenableLink(nil), false)
	end)
end)

describe("markdown.prepare: every remote image form", function()
	local cases = {
		{ "![a](https://x/p.png 'tit')", "[a](https://x/p.png)" },
		{ "![a](https://x/p.png (tit))", "[a](https://x/p.png)" },
		{ "![a](<https://x/p.png>)", "[a](https://x/p.png)" },
		{ "![a](//x/p.png)", "[a](//x/p.png)" },
	}
	for _, c in ipairs(cases) do
		local input, expected = c[1], c[2]
		it(string.format("%q -> %q", input, expected), function()
			assert.equal(prepare(input), expected)
		end)
	end

	it("turns reference-style remote images into links", function()
		local md = "![logo][r] and ![r] and ![r][]\n\n[r]: https://tracker/pixel.png"
		assert.equal(prepare(md), "[logo][r] and [r] and [r][]\n\n[r]: https://tracker/pixel.png")
	end)

	it("keeps reference-style local images", function()
		local md = "![logo][l]\n\n[l]: /data/u/logo.png"
		assert.equal(prepare(md), md)
	end)

	it("drops any <img> that is not local, whatever the quoting", function()
		assert.equal(prepare("a <img src=https://x/t.gif> b"), "a  b")
		assert.equal(prepare('<img alt="x" src="file:///data/u/a.png">'), '<img alt="x" src="file:///data/u/a.png">')
	end)
end)

describe("markdown.prepare: remote-image bypasses", function()
	it("turns images with nested brackets in the alt text into links", function()
		assert.equal(prepare("![a [b] c](http://evil/x.png)"), "[a [b] c](http://evil/x.png)")
	end)

	it("turns angle-bracket destinations that contain spaces into links", function()
		assert.equal(prepare("![a](<http://evil/a b.png>)"), "[a](http://evil/a b.png)")
	end)

	it("drops <img> whose src is a remote URL hidden behind HTML entities", function()
		assert.equal(prepare('<img src="&#104;ttp://evil/x.png">'), "")
		assert.equal(prepare('<img src="&#x68;ttp://evil/x.png">'), "")
		assert.equal(prepare('<img src="http&colon;//evil/x.png">'), "")
		assert.equal(prepare('<img src="http:&sol;&sol;evil/x.png">'), "")
	end)

	it("drops <img> whose src hides a scheme via numeric entities without a semicolon", function()
		assert.equal(prepare('<img src="&#104ttp://evil/x.png">'), "")
		assert.equal(prepare('<img src="&#x68ttp://evil/x.png">'), "")
	end)

	it("drops <img> whose src has leading whitespace or control chars before a remote scheme", function()
		assert.equal(prepare('<img src=" http://evil/x.png">'), "")
		assert.equal(prepare('<img src="\0http://evil/x.png">'), "")
	end)

	it("drops relative and unknown-scheme <img> src; keeps absolute local paths", function()
		assert.equal(prepare('<img src="rel/a.png">'), "")
		assert.equal(prepare('<img src="/data/u/a.png">'), '<img src="/data/u/a.png">')
		assert.equal(prepare('<img src="file:///data/u/a.png">'), '<img src="file:///data/u/a.png">')
	end)

	it("drops <img> without any src", function()
		assert.equal(prepare("x<img alt='a'>y"), "xy")
	end)

	it("keeps local <img> even when the path uses an entity for an ampersand", function()
		assert.equal(prepare('<img src="/data/u/a&amp;b.png">'), '<img src="/data/u/a&amp;b.png">')
	end)

	it("keeps relative markdown images under the existing isLocalSource rule", function()
		assert.equal(prepare("![a](rel/a.png)"), "![a](rel/a.png)")
	end)
end)

describe("markdown.referenceDefinitions", function()
	it("collects labels (lowercased, trimmed) to destinations", function()
		local defs = Markdown.referenceDefinitions("x\n[Logo ]: <https://x/l.png>\n   [b]: /a.png \"t\"\n    [c]: /no.png")
		assert.same(defs, { logo = "https://x/l.png", b = "/a.png" })
	end)
end)

describe("markdown.isLocalSource", function()
	local cases = {
		{ "file:///a.png", true },
		{ "data:image/png;base64,xx", true },
		{ "/abs/a.png", true },
		{ "rel/a.png", true },
		{ "~/a.png", true },
		{ "https://x/a.png", false },
		{ "//x/a.png", false },
		{ "javascript:x", false },
	}
	for _, c in ipairs(cases) do
		it(string.format("%q -> %s", c[1], tostring(c[2])), function()
			assert.equal(Markdown.isLocalSource(c[1]), c[2])
		end)
	end
end)

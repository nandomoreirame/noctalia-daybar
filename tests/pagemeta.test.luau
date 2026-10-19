local assert = require("./support/assert")
local runner = require("./support/runner")
local modules = require("./support/modules")

local describe, it = runner.describe, runner.it
local PageMeta = modules.load("lib/pagemeta.luau")

local PAGE = "https://site.com/blog/post"

describe("pagemeta.decodeEntities", function()
	it("decodes named and numeric entities", function()
		assert.equal(
			PageMeta.decodeEntities("A &amp; B &lt;3&gt; &quot;x&quot; &#39;y&#39; &#x41;&#66; caf&eacute;"),
			'A & B <3> "x" \'y\' AB café'
		)
	end)

	it("leaves unknown entities and invalid code points alone", function()
		assert.equal(PageMeta.decodeEntities("&bogus; &#xFFFFFFFF;"), "&bogus; &#xFFFFFFFF;")
	end)
end)

describe("pagemeta.parse", function()
	it("prefers Open Graph tags", function()
		local html = [[<html><head><title>Plain</title>
      <meta property="og:title" content="OG Title">
      <meta content="OG description" property="og:description" />
      <meta property='og:image' content='/img/cover.png'>
      <meta name="description" content="Meta description"></head></html>]]
		assert.same(PageMeta.parse(html, PAGE), {
			title = "OG Title",
			description = "OG description",
			image = "https://site.com/img/cover.png",
		})
	end)

	it("falls back to twitter tags, <title> and meta description", function()
		local html = [[<TITLE>  Fallback
      title </TITLE><meta name="Description" content="Desc">
      <meta name="twitter:image" content="https://cdn.com/t.jpg">]]
		assert.same(PageMeta.parse(html, PAGE), {
			title = "Fallback title",
			description = "Desc",
			image = "https://cdn.com/t.jpg",
		})
	end)

	it("strips real tags but keeps escaped markup as literal text (shown as PlainText)", function()
		local html = [[<meta property="og:title" content="&lt;script&gt;alert(1)&lt;/script&gt; Tom &amp; Jerry">]]
		assert.equal(PageMeta.parse(html, PAGE).title, "<script>alert(1)</script> Tom & Jerry")
		assert.equal(
			PageMeta.parse([[<title>std::vector&lt;T&gt; - cppreference</title>]], PAGE).title,
			"std::vector<T> - cppreference"
		)
		assert.equal(
			PageMeta.parse([[<meta name="description" content="a &lt; b e c &gt; d">]], PAGE).description,
			"a < b e c > d"
		)
		assert.equal(PageMeta.parse([[<title><b>Bold</b> page</title>]], PAGE).title, "Bold page")
	end)

	it("caps title at 200 and description at 400 characters", function()
		local long = string.rep("x", 1000)
		local r = PageMeta.parse(
			'<meta property="og:title" content="'
				.. long
				.. '"><meta property="og:description" content="'
				.. long
				.. '">',
			PAGE
		)
		assert.equal(#r.title, 200)
		assert.equal(#r.description, 400)
		assert.equal(PageMeta.TITLE_MAX, 200)
		assert.equal(PageMeta.DESC_MAX, 400)
	end)

	it("ignores non-http images and returns empty fields for empty input", function()
		assert.equal(
			PageMeta.parse([[<meta property="og:image" content="data:image/png;base64,AAAA">]], PAGE).image,
			""
		)
		assert.same(PageMeta.parse("", PAGE), { title = "", description = "", image = "" })
		assert.same(PageMeta.parse(nil, PAGE), { title = "", description = "", image = "" })
	end)
end)

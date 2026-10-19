local assert = require("./support/assert")
local runner = require("./support/runner")
local modules = require("./support/modules")

local describe, it = runner.describe, runner.it
local Url = modules.load("lib/url.luau")

describe("url.isHttpUrl", function()
	local cases = {
		{ "https://example.com", true },
		{ "http://example.com/a?b=c#d", true },
		{ "  https://example.com/x  ", true },
		{ "ftp://example.com", false },
		{ "https://", false },
		{ "veja https://example.com", false },
		{ "javascript:alert(1)", false },
		{ "", false },
	}
	for _, c in ipairs(cases) do
		local text, expected = c[1], c[2]
		it(string.format("%q -> %s", text, tostring(expected)), function()
			assert.equal(Url.isHttpUrl(text), expected)
		end)
	end
end)

describe("url.normalizeUrl", function()
	local cases = {
		{ "https://Example.COM/Path/", "https://example.com/Path" },
		{ "https://example.com/a#section", "https://example.com/a" },
		{ "https://example.com/a?utm_source=x&id=7&UTM_medium=y", "https://example.com/a?id=7" },
		{ "https://example.com/?utm_campaign=z", "https://example.com" },
		{ "  http://example.com  ", "http://example.com" },
	}
	for _, c in ipairs(cases) do
		local input, expected = c[1], c[2]
		it(string.format("%q -> %q", input, expected), function()
			assert.equal(Url.normalizeUrl(input), expected)
		end)
	end

	it("returns an empty string for non-http input", function()
		assert.equal(Url.normalizeUrl("javascript:alert(1)"), "")
		assert.equal(Url.normalizeUrl(""), "")
	end)
end)

describe("url.domainOf", function()
	it("returns the host without www and port", function()
		assert.equal(Url.domainOf("https://www.GitHub.com/a"), "github.com")
		assert.equal(Url.domainOf("http://localhost:8080/x"), "localhost")
		assert.equal(Url.domainOf("not a url"), "")
	end)

	it("strips userinfo before taking the host", function()
		assert.equal(Url.domainOf("http://x@www.site.com:8080/p"), "site.com")
	end)
end)

describe("url.resolveUrl", function()
	local page = "https://site.com/blog/post.html?x=1"
	local cases = {
		{ "https://cdn.com/a.png", "https://cdn.com/a.png" },
		{ "//cdn.com/a.png", "https://cdn.com/a.png" },
		{ "/img/a.png", "https://site.com/img/a.png" },
		{ "a.png", "https://site.com/blog/a.png" },
		{ "  /x.png  ", "https://site.com/x.png" },
		{ "data:image/png;base64,AAA", "" },
		{ "javascript:alert(1)", "" },
		{ "", "" },
	}
	for _, c in ipairs(cases) do
		local ref, expected = c[1], c[2]
		it(string.format("%q -> %q", ref, expected), function()
			assert.equal(Url.resolveUrl(ref, page), expected)
		end)
	end
end)

describe("url.isPublicHttpUrl", function()
	local cases = {
		{ "https://example.com/a.png", true },
		{ "http://cdn.example.org/x", true },
		{ "https://1.2.3.4/a.png", true },
		{ "https://localhost/a.png", false },
		{ "http://foo.localhost/x", false },
		{ "http://127.0.0.1/a", false },
		{ "http://127.1.2.3/a", false },
		{ "http://0.0.0.0/a", false },
		{ "http://10.0.0.1/a", false },
		{ "http://10.255.255.255/a", false },
		{ "http://172.16.0.1/a", false },
		{ "http://172.31.255.1/a", false },
		{ "http://172.15.0.1/a", true },
		{ "http://172.32.0.1/a", true },
		{ "http://192.168.1.1/a", false },
		{ "http://169.254.1.1/a", false },
		{ "http://[::1]/a", false },
		{ "http://[fc00::1]/a", false },
		{ "http://[fd12::1]/a", false },
		{ "http://[fe80::1]/a", false },
		{ "http://[2001:db8::1]/a", true },
		{ "http://intranet/a", false },
		{ "http://my-box/a", false },
		{ "ftp://example.com/a", false },
		{ "javascript:alert(1)", false },
		{ "", false },
		{ "not a url", false },
		-- Non-canonical / decimal / hex IPv4 forms curl still accepts
		{ "http://127.1/a", false },
		{ "http://2130706433/a", false },
		{ "http://0x7f.0.0.1/a", false },
		{ "http://0177.0.0.1/a", false },
		{ "http://0x7f000001/a", false },
		-- Trailing dot on host
		{ "http://localhost./a", false },
		{ "http://10.0.0.1./a", false },
		-- IPv6 unspecified, loopback expansions, IPv4-mapped
		{ "http://[::]/a", false },
		{ "http://[0:0:0:0:0:0:0:1]/a", false },
		{ "http://[::ffff:127.0.0.1]/a", false },
		{ "http://[::ffff:7f00:1]/a", false },
		{ "http://[::ffff:10.0.0.1]/a", false },
		-- Extra private / reserved IPv4 ranges
		{ "http://100.64.0.1/a", false },
		{ "http://100.127.255.255/a", false },
		{ "http://198.18.0.1/a", false },
		{ "http://198.19.255.255/a", false },
		{ "http://224.0.0.1/a", false },
		{ "http://255.255.255.255/a", false },
		-- Extra from plan (inbox REQ-004)
		{ "file:///etc/passwd", false },
		-- Userinfo must not hide a private host (SSRF)
		{ "http://x@127.0.0.1/a", false },
		{ "http://user:pass@10.0.0.1/", false },
		{ "http://a@b@192.168.1.1/", false },
		{ "http://x@[::1]/", false },
		{ "http://x@example.com/i.png", true },
	}
	for _, c in ipairs(cases) do
		local url, expected = c[1], c[2]
		it(string.format("%q -> %s", url, tostring(expected)), function()
			assert.equal(Url.isPublicHttpUrl(url), expected)
		end)
	end
end)

describe("url.isPublicHttpUrl: hex-letter domains are real domains", function()
	local public = {
		"https://cafe.de/x.png",
		"https://bad.de/a.png",
		"https://ace.be/i.jpg",
		"https://dead.beef.com/i.png",
	}
	for _, u in ipairs(public) do
		it(u .. " is public", function()
			assert.equal(Url.isPublicHttpUrl(u), true)
		end)
	end

	local private = {
		"http://127.1/",
		"http://0x7f.0.0.1/",
		"http://0177.0.0.1/",
		"http://2130706433/",
		"http://0x7f000001/",
	}
	for _, u in ipairs(private) do
		it(u .. " stays private", function()
			assert.equal(Url.isPublicHttpUrl(u), false)
		end)
	end
end)

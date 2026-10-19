local assert = require("./support/assert")
local runner = require("./support/runner")
local mock = require("./support/noctalia_mock")
local H = require("./support/service_helpers")

local describe, it = runner.describe, runner.it

local PAGE = [[<html><head><title>Example page</title>
<meta name="description" content="A page about things">
<meta property="og:image" content="https://cdn.example.com/i.png">
</head></html>]]

local function bookmarks(s)
	return H.view(s).data.bookmarks
end

local function https(s)
	return mock.calls(s.env, "noctalia.http")
end

local function add(s, url)
	return H.command(s, "toolbar", "addBookmark", { url = url })
end

describe("service bookmarks", function()
	it("stores at once as pending with the domain title, then fetches once", function()
		local s = H.boot({})
		local ack = add(s, "https://www.example.com/post")
		assert.equal(ack.ok, true)
		local b = bookmarks(s)[1]
		assert.equal(b.title, "example.com")
		assert.equal(b.status, "pending")
		assert.equal(b.id, ack.result.id)
		local calls = https(s)
		assert.equal(#calls, 1)
		assert.equal(calls[1][1].url, "https://www.example.com/post")
		assert.equal(calls[1][1].method, "GET")
		assert.equal(calls[1][1].follow_redirects, true)
	end)

	it("keeps at most three requests in flight", function()
		local s = H.boot({})
		for i = 1, 4 do
			add(s, "https://site" .. i .. ".com/")
		end
		assert.equal(#https(s), 3)
		mock.resolveHttp(s.env, 1, { ok = true, status = 404, body = "" })
		assert.equal(#https(s), 4)
		assert.equal(https(s)[4][1].url, "https://site4.com/")
	end)

	it("applies the page metadata and downloads a public og:image", function()
		local s = H.boot({})
		local id = add(s, "https://example.com/post").result.id
		mock.resolveHttp(s.env, 1, { ok = true, status = 200, body = PAGE })
		local b = bookmarks(s)[1]
		assert.equal(b.status, "ok")
		assert.equal(b.title, "Example page")
		assert.equal(b.description, "A page about things")
		local dl = mock.calls(s.env, "noctalia.download")
		assert.equal(#dl, 1)
		assert.equal(dl[1][1], "https://cdn.example.com/i.png")
		assert.equal(dl[1][2], H.DATA .. "/thumbs/" .. id)
		mock.resolveDownload(s.env, 1, true)
		assert.equal(bookmarks(s)[1].thumbPath, H.DATA .. "/thumbs/" .. id)
	end)

	it("never downloads an og:image on a private host", function()
		local s = H.boot({})
		add(s, "https://example.com/post")
		local page = string.gsub(PAGE, "https://cdn.example.com/i.png", "http://192.168.0.1/i.png")
		mock.resolveHttp(s.env, 1, { ok = true, status = 200, body = page })
		assert.equal(#mock.calls(s.env, "noctalia.download"), 0)
		assert.equal(bookmarks(s)[1].status, "ok")
	end)

	it("never requests a private-network URL", function()
		local s = H.boot({})
		assert.equal(add(s, "http://192.168.0.10/admin").ok, true)
		assert.equal(#https(s), 0)
		assert.equal(bookmarks(s)[1].status, "failed")
	end)

	it("drops an answer that arrives after eight seconds", function()
		local s = H.boot({})
		add(s, "https://example.com/post")
		H.tick(s, 9000)
		assert.equal(bookmarks(s)[1].status, "failed")
		mock.resolveHttp(s.env, 1, { ok = true, status = 200, body = PAGE })
		assert.equal(bookmarks(s)[1].status, "failed")
		assert.equal(bookmarks(s)[1].title, "example.com")
	end)

	it("a failed answer marks the bookmark failed", function()
		local s = H.boot({})
		add(s, "https://example.com/post")
		mock.resolveHttp(s.env, 1, { ok = false, status = 0, error = "dns" })
		assert.equal(bookmarks(s)[1].status, "failed")
	end)

	it("does not fetch when fetch_previews is off", function()
		local s = H.boot({ config = { fetch_previews = false } })
		add(s, "https://example.com/post")
		assert.equal(bookmarks(s)[1].status, "off")
		assert.equal(#https(s), 0)
	end)

	it("a duplicate URL replaces the old row, keeps its id and refetches", function()
		local s = H.boot({})
		local id = add(s, "https://example.com/post").result.id
		add(s, "https://other.com/")
		local again = add(s, "https://EXAMPLE.com/post/?utm_source=x")
		assert.equal(again.result.id, id)
		assert.equal(#bookmarks(s), 2)
		assert.equal(bookmarks(s)[1].id, id)
		-- The refetch waits for the request of the same id still in flight,
		-- whose answer is then stale (older token) and ignored.
		assert.equal(#https(s), 2)
		mock.resolveHttp(s.env, 1, { ok = true, status = 200, body = PAGE })
		assert.equal(#https(s), 3)
		assert.equal(bookmarks(s)[1].status, "pending")
	end)

	it("rejects a non-http URL", function()
		local s = H.boot({})
		assert.equal(add(s, "javascript:alert(1)").error, "invalid-url")
		assert.same(bookmarks(s), {})
	end)

	it("deleteBookmark removes the row and its thumbnail", function()
		local s = H.boot({})
		local id = add(s, "https://example.com/post").result.id
		assert.equal(H.command(s, "toolbar", "deleteBookmark", { id = id }).ok, true)
		assert.same(bookmarks(s), {})
		assert.equal(mock.calls(s.env, "noctalia.removeFile")[1][1], H.DATA .. "/thumbs/" .. id)
	end)

	it("refreshBookmark refetches and renameBookmark sets the title", function()
		local s = H.boot({})
		local id = add(s, "https://example.com/post").result.id
		mock.resolveHttp(s.env, 1, { ok = true, status = 200, body = PAGE })
		assert.equal(H.command(s, "toolbar", "refreshBookmark", { id = id }).ok, true)
		assert.equal(#https(s), 2)
		assert.equal(bookmarks(s)[1].status, "pending")
		assert.equal(H.command(s, "toolbar", "renameBookmark", { id = id, title = "Mine" }).ok, true)
		assert.equal(bookmarks(s)[1].title, "Mine")
		assert.equal(H.command(s, "toolbar", "refreshBookmark", { id = "nope" }).error, "not-found")
	end)

	it("a link capture adds a bookmark", function()
		local s = H.boot({})
		assert.equal(H.command(s, "capture", "commit", { text = "https://example.com/post" }).ok, true)
		assert.equal(#bookmarks(s), 1)
	end)
end)

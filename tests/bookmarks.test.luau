local assert = require("./support/assert")
local runner = require("./support/runner")
local modules = require("./support/modules")

local describe, it = runner.describe, runner.it
local Bookmarks = modules.load("lib/bookmarks.luau")

local T0 = "2026-10-09T15:00:00.000Z"
local T1 = "2026-10-09T16:00:00.000Z"
local function empty()
	return { bookmarks = {} }
end
local function ids(list)
	local out = {}
	for i, b in ipairs(list) do
		out[i] = b.id
	end
	return out
end

describe("bookmarks.add", function()
	it("saves at once with the domain as title, pending when fetching is on", function()
		local r = Bookmarks.add(empty(), " https://www.site.com/a ", "b1", T0, true)
		assert.equal(r.replaced, false)
		assert.same(r.bookmark, {
			id = "b1",
			url = "https://www.site.com/a",
			title = "site.com",
			description = "",
			image = "",
			imageUrl = "",
			status = "pending",
			token = 1,
			createdAt = T0,
			savedAt = T0,
		})
		assert.same(r.data.bookmarks, { r.bookmark })
	end)

	it("marks the bookmark 'off' when fetching is disabled", function()
		assert.equal(Bookmarks.add(empty(), "https://site.com", "b1", T0, false).bookmark.status, "off")
	end)

	it("rejects non-http input", function()
		assert.equal(Bookmarks.add(empty(), "javascript:alert(1)", "b1", T0, true), nil)
		assert.equal(Bookmarks.add(empty(), nil, "b1", T0, true), nil)
	end)

	it("replaces a duplicate: same id, moved to top, refetched with a new token", function()
		local data = Bookmarks.add(empty(), "https://site.com/a?utm_source=x", "b1", T0, true).data
		data = Bookmarks.add(data, "https://other.com", "b2", T0, true).data
		data = Bookmarks.rename(data, "b1", "My title")
		local r = Bookmarks.add(data, "https://site.com/a/#top", "b3", T1, true)
		assert.equal(r.replaced, true)
		local b = r.bookmark
		assert.equal(b.id, "b1")
		assert.equal(b.url, "https://site.com/a/#top")
		assert.equal(b.title, "site.com")
		assert.equal(b.status, "pending")
		assert.equal(b.token, 2)
		assert.equal(b.createdAt, T0)
		assert.equal(b.savedAt, T1)
		assert.same(ids(r.data.bookmarks), { "b1", "b2" })
	end)

	it("does not mutate the input data", function()
		local data = empty()
		Bookmarks.add(data, "https://site.com", "b1", T0, true)
		assert.same(data, { bookmarks = {} })
	end)
end)

describe("bookmarks preview results", function()
	local function base()
		return Bookmarks.add(empty(), "https://site.com/a", "b1", T0, true).data
	end

	it("applies metadata for the current token", function()
		local data = Bookmarks.applyPreview(base(), "b1", 1, { title = "Title", description = "Desc", image = "https://cdn.com/i.png" })
		local b = data.bookmarks[1]
		assert.equal(b.title, "Title")
		assert.equal(b.description, "Desc")
		assert.equal(b.imageUrl, "https://cdn.com/i.png")
		assert.equal(b.status, "ok")
	end)

	it("keeps the domain when the page has no title", function()
		assert.equal(Bookmarks.applyPreview(base(), "b1", 1, { title = "", description = "", image = "" }).bookmarks[1].title, "site.com")
		assert.equal(Bookmarks.applyPreview(base(), "b1", 1, {}).bookmarks[1].title, "site.com")
	end)

	it("ignores stale tokens and unknown ids (same object back)", function()
		local data = base()
		assert.equal(Bookmarks.applyPreview(data, "b1", 7, { title = "x", description = "", image = "" }), data)
		assert.equal(Bookmarks.applyPreview(data, "zz", 1, { title = "x", description = "", image = "" }), data)
		assert.equal(Bookmarks.setImage(data, "b1", 7, "/t/b1"), data)
		assert.equal(Bookmarks.markFailed(data, "b1", 7), data)
	end)

	it("sets the cached image path and marks failures", function()
		assert.equal(Bookmarks.setImage(base(), "b1", 1, "/t/b1").bookmarks[1].image, "/t/b1")
		local failed = Bookmarks.markFailed(base(), "b1", 1).bookmarks[1]
		assert.equal(failed.status, "failed")
		assert.equal(failed.title, "site.com")
	end)
end)

describe("bookmarks edits and queries", function()
	it("renames (trimmed, blank ignored) and removes", function()
		local data = Bookmarks.add(empty(), "https://site.com", "b1", T0, true).data
		assert.equal(Bookmarks.rename(data, "b1", "  New  title ").bookmarks[1].title, "New title")
		assert.equal(Bookmarks.rename(data, "b1", "  "), data)
		assert.equal(Bookmarks.rename(data, "b1", nil), data)
		assert.same(Bookmarks.remove(data, "b1").bookmarks, {})
	end)

	it("sorts newest saved first and searches title, description and URL without accents", function()
		local data = Bookmarks.add(empty(), "https://a.com", "a", T0, true).data
		data = Bookmarks.add(data, "https://b.com", "b", T1, true).data
		data = Bookmarks.applyPreview(data, "a", 1, { title = "Ação rápida", description = "Notícias", image = "" })
		assert.same(ids(Bookmarks.sorted(data.bookmarks)), { "b", "a" })
		assert.same(ids(Bookmarks.search(data.bookmarks, "acao")), { "a" })
		assert.same(ids(Bookmarks.search(data.bookmarks, "noticias")), { "a" })
		assert.same(ids(Bookmarks.search(data.bookmarks, "b.com")), { "b" })
		assert.equal(#Bookmarks.search(data.bookmarks, ""), 2)
	end)

	it("sorted does not reorder the input list", function()
		local data = Bookmarks.add(empty(), "https://a.com", "a", T0, true).data
		data = Bookmarks.add(data, "https://b.com", "b", T1, true).data
		local before = ids(data.bookmarks)
		Bookmarks.sorted(data.bookmarks)
		assert.same(ids(data.bookmarks), before)
	end)

	it("prefills only http URLs that are not saved yet (normalized)", function()
		local data = Bookmarks.add(empty(), "https://site.com/a", "b1", T0, true).data
		assert.equal(Bookmarks.hasUrl(data, "https://site.com/a/"), true)
		assert.equal(Bookmarks.prefillFromClipboard("https://site.com/a#x", data), "")
		assert.equal(Bookmarks.prefillFromClipboard(" https://new.com ", data), "https://new.com")
		assert.equal(Bookmarks.prefillFromClipboard("hello", data), "")
		assert.equal(Bookmarks.prefillFromClipboard("see https://new.com", data), "")
		assert.equal(Bookmarks.prefillFromClipboard(nil, data), "")
	end)
end)

describe("bookmarks fetch bookkeeping", function()
	local function base()
		return Bookmarks.add(empty(), "https://site.com/a", "b1", T0, true).data
	end

	it("marks a dropped fetch as off for the current token only", function()
		assert.equal(Bookmarks.markOff(base(), "b1", 1).bookmarks[1].status, "off")
		local data = base()
		assert.equal(Bookmarks.markOff(data, "b1", 9), data)
	end)

	it("knows whether a job still matches a live bookmark", function()
		local data = base()
		assert.equal(Bookmarks.isCurrent(data, "b1", 1), true)
		assert.equal(Bookmarks.isCurrent(data, "b1", 2), false)
		assert.equal(Bookmarks.isCurrent(Bookmarks.remove(data, "b1"), "b1", 1), false)
	end)
end)

describe("bookmarks.refresh and customTitle", function()
	it("bumps the token and sets pending without clearing title, description or image", function()
		local data = Bookmarks.add(empty(), "https://site.com/a", "b1", T0, true).data
		data = Bookmarks.applyPreview(data, "b1", 1, { title = "Title", description = "Desc", image = "https://cdn.com/i.png" })
		data = Bookmarks.setImage(data, "b1", 1, "/t/b1")
		local r = Bookmarks.refresh(data, "b1", T1, true)
		local b = r.bookmark
		assert.equal(b.id, "b1")
		assert.equal(b.title, "Title")
		assert.equal(b.description, "Desc")
		assert.equal(b.image, "/t/b1")
		assert.equal(b.imageUrl, "https://cdn.com/i.png")
		assert.equal(b.status, "pending")
		assert.equal(b.token, 2)
		assert.equal(b.savedAt, T0)
		assert.equal(b.createdAt, T0)
		assert.same(ids(r.data.bookmarks), { "b1" })
	end)

	it("keeps everything and returns the same bookmark when fetching is off", function()
		local data = Bookmarks.add(empty(), "https://site.com/a", "b1", T0, false).data
		data = Bookmarks.rename(data, "b1", "Mine")
		local r = Bookmarks.refresh(data, "b1", T1, false)
		assert.equal(r.bookmark.title, "Mine")
		assert.equal(r.bookmark.status, "off")
		assert.equal(r.bookmark.token, 1)
		assert.equal(r.data.bookmarks[1].title, "Mine")
	end)

	it("returns nil for an unknown id", function()
		assert.equal(Bookmarks.refresh(empty(), "zz", T1, true), nil)
	end)

	it("rename sets customTitle and applyPreview keeps that title", function()
		local data = Bookmarks.add(empty(), "https://site.com/a", "b1", T0, true).data
		data = Bookmarks.rename(data, "b1", "My title")
		assert.equal(data.bookmarks[1].customTitle, true)
		data = Bookmarks.applyPreview(data, "b1", 1, { title = "Page Title", description = "D", image = "" })
		assert.equal(data.bookmarks[1].title, "My title")
		assert.equal(data.bookmarks[1].description, "D")
	end)

	it("a duplicate save clears customTitle and replaces as before", function()
		local data = Bookmarks.add(empty(), "https://site.com/a", "b1", T0, true).data
		data = Bookmarks.rename(data, "b1", "Mine")
		local r = Bookmarks.add(data, "https://site.com/a", "b9", T1, true)
		assert.equal(r.replaced, true)
		assert.equal(not r.bookmark.customTitle, true)
		assert.equal(r.bookmark.title, "site.com")
	end)
end)

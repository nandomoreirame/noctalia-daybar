--!strict
-- Bookmark operations. Pure; every function returns a NEW data table (or the
-- same one when nothing changes). `token` increases on every (re)save so results
-- from a superseded fetch are ignored.
-- bookmark: { id, url, title, description, image, imageUrl, status, token,
--             createdAt, savedAt, customTitle? }
-- status: "pending" (fetch queued/running), "ok", "failed", "off" (fetching disabled)

local Url = require("./url.luau")
local Text = require("./text.luau")
local Tbl = require("./tbl.luau")

local Bookmarks = {}

local function trim(s: string): string
	return (string.match(s, "^%s*(.-)%s*$") :: string)
end

local function str(value: any): string
	if value == nil then
		return ""
	end
	return tostring(value)
end

local function withBookmarks(data: any, list: { any }): any
	return Tbl.merge(data, { bookmarks = list })
end

function Bookmarks.findByUrl(data: any, url: any): any
	local key = Url.normalizeUrl(url)
	if key == "" then
		return nil
	end
	for _, b in ipairs(data.bookmarks) do
		if Url.normalizeUrl(b.url) == key then
			return b
		end
	end
	return nil
end

function Bookmarks.hasUrl(data: any, url: any): boolean
	return Bookmarks.findByUrl(data, url) ~= nil
end

-- Returns { data, bookmark, replaced } or nil for an invalid URL.
function Bookmarks.add(data: any, rawUrl: any, id: string, nowIso: string, fetchEnabled: boolean): any
	local url = trim(str(rawUrl))
	if not Url.isHttpUrl(url) then
		return nil
	end
	local existing = Bookmarks.findByUrl(data, url)
	local bookmark = {
		id = if existing then existing.id else id,
		url = url,
		title = Url.domainOf(url),
		description = "",
		image = "",
		imageUrl = "",
		status = if fetchEnabled then "pending" else "off",
		token = if existing then existing.token + 1 else 1,
		createdAt = if existing then existing.createdAt else nowIso,
		savedAt = nowIso,
	}
	local list = { bookmark }
	for _, b in ipairs(data.bookmarks) do
		if b.id ~= bookmark.id then
			table.insert(list, b)
		end
	end
	return { data = withBookmarks(data, list), bookmark = bookmark, replaced = existing ~= nil }
end

local function update(data: any, id: string, token: number?, patch: (any) -> { [string]: any }): any
	local target = Tbl.find(data.bookmarks, function(b)
		return b.id == id
	end)
	if target == nil or (token ~= nil and target.token ~= token) then
		return data
	end
	return withBookmarks(
		data,
		Tbl.map(data.bookmarks, function(b)
			if b.id ~= id then
				return b
			end
			return Tbl.merge(b, patch(b))
		end)
	)
end

function Bookmarks.applyPreview(data: any, id: string, token: number, meta: any): any
	return update(data, id, token, function(b)
		local patch: { [string]: any } = {
			description = meta.description or "",
			imageUrl = meta.image or "",
			status = "ok",
		}
		if not b.customTitle then
			local title = meta.title
			patch.title = if title ~= nil and title ~= "" then title else Url.domainOf(b.url)
		end
		return patch
	end)
end

function Bookmarks.setImage(data: any, id: string, token: number, path: string): any
	return update(data, id, token, function()
		return { image = path }
	end)
end

function Bookmarks.markFailed(data: any, id: string, token: number): any
	return update(data, id, token, function()
		return { status = "failed" }
	end)
end

-- A queued fetch dropped because fetching was turned off.
function Bookmarks.markOff(data: any, id: string, token: number): any
	return update(data, id, token, function()
		return { status = "off" }
	end)
end

-- True while a fetch job still belongs to a live bookmark (not deleted or re-saved).
function Bookmarks.isCurrent(data: any, id: string, token: number): boolean
	for _, b in ipairs(data.bookmarks) do
		if b.id == id and b.token == token then
			return true
		end
	end
	return false
end

-- Refresh bumps the token and requeues a fetch without clearing title /
-- description / image and without moving the bookmark to the top.
function Bookmarks.refresh(data: any, id: string, _nowIso: string, fetchEnabled: boolean): any
	local target = Tbl.find(data.bookmarks, function(b)
		return b.id == id
	end)
	if target == nil then
		return nil
	end
	if not fetchEnabled then
		return { data = data, bookmark = target }
	end
	local bookmark = Tbl.merge(target, { status = "pending", token = target.token + 1 })
	return {
		data = withBookmarks(
			data,
			Tbl.map(data.bookmarks, function(b)
				return if b.id == id then bookmark else b
			end)
		),
		bookmark = bookmark,
	}
end

function Bookmarks.rename(data: any, id: string, title: any): any
	local clean = trim((string.gsub(str(title), "%s+", " ")))
	if clean == "" then
		return data
	end
	return update(data, id, nil, function()
		return { title = clean, customTitle = true }
	end)
end

function Bookmarks.remove(data: any, id: string): any
	return withBookmarks(
		data,
		Tbl.filter(data.bookmarks, function(b)
			return b.id ~= id
		end)
	)
end

-- Newest saved first; stable for equal savedAt.
function Bookmarks.sorted(list: { any }): { any }
	local indexed: { { i: number, b: any } } = {}
	for i, b in ipairs(list) do
		indexed[i] = { i = i, b = b }
	end
	table.sort(indexed, function(x: any, y: any): boolean
		if x.b.savedAt ~= y.b.savedAt then
			return x.b.savedAt > y.b.savedAt
		end
		return x.i < y.i
	end)
	return Tbl.map(indexed, function(e)
		return e.b
	end)
end

function Bookmarks.search(list: { any }, query: any): { any }
	return Tbl.filter(list, function(b)
		return Text.matches({ b.title, b.description, b.url }, query)
	end)
end

-- Clipboard text to prefill the capture field with: a new lone http(s) URL, else "".
function Bookmarks.prefillFromClipboard(clip: any, data: any): string
	local s = trim(str(clip))
	if Url.isHttpUrl(s) and not Bookmarks.hasUrl(data, s) then
		return s
	end
	return ""
end

return Bookmarks

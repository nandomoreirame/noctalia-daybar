--!strict
-- Link capture: an http(s) URL saved as a bookmark (preview fetched later).

local Url = require("../url.luau")

local Link = {}

Link.TYPE = "link"

function Link.isLink(text: any): boolean
	return Url.isHttpUrl(text)
end

function Link.build(text: any): { [string]: any }
	local raw = if text == nil then "" else tostring(text)
	local url = string.match(raw, "^%s*(.-)%s*$") or ""
	if not Url.isHttpUrl(url) then
		return { ok = false, type = Link.TYPE, error = "invalid-url" }
	end
	return { ok = true, type = Link.TYPE, action = "addBookmark", payload = { url = url } }
end

return Link

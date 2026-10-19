--!strict
-- Extracts { title, description, image } from untrusted page HTML. Results are
-- plain text (tags stripped, entities decoded, length capped); the UI must still
-- render them as PlainText.

local Url = require("./url.luau")

local PageMeta = {}

PageMeta.TITLE_MAX = 200
PageMeta.DESC_MAX = 400

local NAMED: { [string]: string } = {
	amp = "&",
	lt = "<",
	gt = ">",
	quot = '"',
	apos = "'",
	nbsp = " ",
	eacute = "é",
	aacute = "á",
	oacute = "ó",
	iacute = "í",
	uacute = "ú",
	atilde = "ã",
	otilde = "õ",
	ccedil = "ç",
	ecirc = "ê",
	acirc = "â",
	ocirc = "ô",
	agrave = "à",
	hellip = "…",
	mdash = "—",
	ndash = "–",
	rsquo = "’",
	lsquo = "‘",
	rdquo = "”",
	ldquo = "“",
}

function PageMeta.decodeEntities(text: any): string
	local s = tostring(text or "")
	local out = {}
	local i = 1
	local len = #s
	while i <= len do
		local amp = string.find(s, "&", i, true)
		if amp == nil then
			table.insert(out, string.sub(s, i))
			break
		end
		if amp > i then
			table.insert(out, string.sub(s, i, amp - 1))
		end
		local semi = string.find(s, ";", amp + 1, true)
		if semi == nil then
			table.insert(out, string.sub(s, amp))
			break
		end
		local body = string.sub(s, amp + 1, semi - 1)
		local replacement: string? = nil
		if string.sub(body, 1, 1) == "#" then
			local code: number? = nil
			if string.lower(string.sub(body, 2, 2)) == "x" then
				code = tonumber(string.sub(body, 3), 16)
			else
				code = tonumber(string.sub(body, 2), 10)
			end
			if code ~= nil and code > 0 and code <= 0x10ffff then
				local ok, ch = pcall(utf8.char, code)
				if ok then
					replacement = ch
				end
			end
		else
			replacement = NAMED[string.lower(body)]
		end
		if replacement ~= nil then
			table.insert(out, replacement)
		else
			table.insert(out, string.sub(s, amp, semi))
		end
		i = semi + 1
	end
	return table.concat(out)
end

-- Tags are stripped BEFORE decoding, so escaped text such as "vector&lt;T&gt;"
-- survives as "vector<T>"; the UI renders the result as PlainText.
local function clean(text: any, maxLen: number): string
	local raw = tostring(text or "")
	-- Strip tags: replace <...> with a space.
	local stripped = {}
	local i = 1
	local len = #raw
	while i <= len do
		local lt = string.find(raw, "<", i, true)
		if lt == nil then
			table.insert(stripped, string.sub(raw, i))
			break
		end
		if lt > i then
			table.insert(stripped, string.sub(raw, i, lt - 1))
		end
		local gt = string.find(raw, ">", lt + 1, true)
		if gt == nil then
			table.insert(stripped, string.sub(raw, lt))
			break
		end
		table.insert(stripped, " ")
		i = gt + 1
	end
	local plain = PageMeta.decodeEntities(table.concat(stripped))
	plain = (string.gsub(plain, "%s+", " "))
	plain = (string.gsub(plain, "^%s+", ""))
	plain = (string.gsub(plain, "%s+$", ""))
	if #plain > maxLen then
		return string.sub(plain, 1, maxLen)
	end
	return plain
end

-- Parse attributes from a single tag string. Names lowercased; values keep case.
local function attributes(tag: string): { [string]: string }
	local attrs: { [string]: string } = {}
	local i = 1
	local len = #tag
	while i <= len do
		-- Find next name= start.
		local nameStart, nameEnd, name = string.find(tag, "([%a_:][-%w_:.]*)%s*=%s*", i)
		if nameStart == nil then
			break
		end
		local pos = (nameEnd :: number) + 1
		local value: string? = nil
		local ch = string.sub(tag, pos, pos)
		if ch == '"' then
			local close = string.find(tag, '"', pos + 1, true)
			if close then
				value = string.sub(tag, pos + 1, close - 1)
				i = close + 1
			else
				break
			end
		elseif ch == "'" then
			local close = string.find(tag, "'", pos + 1, true)
			if close then
				value = string.sub(tag, pos + 1, close - 1)
				i = close + 1
			else
				break
			end
		else
			local vend = string.find(tag, "[%s\"'>]", pos)
			if vend then
				value = string.sub(tag, pos, vend - 1)
				i = vend
			else
				value = string.sub(tag, pos)
				i = len + 1
			end
		end
		if value ~= nil and name ~= nil then
			attrs[string.lower(name)] = value
		end
	end
	return attrs
end

-- Content of the first <meta property|name="key">, or "".
local function metaContent(html: string, keys: { string }): string
	-- Walk keys in order so preference is preserved.
	for _, key in ipairs(keys) do
		local i = 1
		while true do
			local start = string.find(string.lower(html), "<meta", i, true)
			if start == nil then
				break
			end
			local gt = string.find(html, ">", start, true)
			if gt == nil then
				break
			end
			local tag = string.sub(html, start, gt)
			local a = attributes(tag)
			local id = string.lower(tostring(a.property or a.name or ""))
			if id == key and a.content and a.content ~= "" then
				return a.content
			end
			i = gt + 1
		end
	end
	return ""
end

function PageMeta.parse(html: any, pageUrl: any): { title: string, description: string, image: string }
	local source = tostring(html or "")
	if source == "" then
		return { title = "", description = "", image = "" }
	end

	local titleTag: string? = nil
	do
		local lower = string.lower(source)
		local ts = string.find(lower, "<title", 1, true)
		if ts then
			local gt = string.find(source, ">", ts, true)
			if gt then
				local close = string.find(lower, "</title>", gt, true)
				if close then
					titleTag = string.sub(source, gt + 1, close - 1)
				end
			end
		end
	end

	local title = metaContent(source, { "og:title", "twitter:title" })
	if title == "" and titleTag then
		title = titleTag
	end
	local description = metaContent(source, { "og:description", "twitter:description", "description" })
	local image = metaContent(source, { "og:image", "og:image:url", "og:image:secure_url", "twitter:image" })

	return {
		title = clean(title, PageMeta.TITLE_MAX),
		description = clean(description, PageMeta.DESC_MAX),
		image = Url.resolveUrl(PageMeta.decodeEntities(image), pageUrl),
	}
end

return PageMeta

--!strict
-- Markdown safety helpers. A note never loads anything from the network by
-- itself: every image whose source is not local (inline, reference-style or raw
-- <img>) becomes a link or is dropped. Links are opened by the UI only when
-- isOpenableLink(). Regexes from the original rules are hand-written scanners
-- here (Lua patterns have no alternation or backtracking groups).

local Url = require("./url.luau")

local Markdown = {}

local function str(value: any): string
	if value == nil then
		return ""
	end
	return tostring(value)
end

local function trim(s: string): string
	return (string.match(s, "^%s*(.-)%s*$") :: string)
end

local function startsWithCi(s: string, prefix: string): boolean
	return string.lower(string.sub(s, 1, #prefix)) == prefix
end

local function isWordChar(c: string): boolean
	return string.match(c, "^[%w_]$") ~= nil
end

local function isSpace(c: string): boolean
	return c ~= "" and string.match(c, "^%s$") ~= nil
end

-- Case-insensitive Lua pattern for a literal ASCII word.
local function ci(word: string): string
	return (string.gsub(word, "%a", function(ch: string): string
		return "[" .. string.lower(ch) .. string.upper(ch) .. "]"
	end))
end

local function codeToChar(n: number?): string
	if n == nil or n > 0x10FFFF then
		return ""
	end
	local ok, ch = pcall(utf8.char, n :: number)
	return if ok then ch else ""
end

-- Decode a few HTML entities that can hide a scheme in <img src> values.
-- Numeric forms are accepted with or without a trailing semicolon.
function Markdown.decodeEntities(src: any): string
	local s = str(src)
	s = (string.gsub(s, "&#[xX](%x+);?", function(h: string): string
		return codeToChar(tonumber(h, 16))
	end))
	s = (string.gsub(s, "&#(%d+);?", function(d: string): string
		return codeToChar(tonumber(d, 10))
	end))
	s = (string.gsub(s, "&" .. ci("colon") .. ";", ":"))
	s = (string.gsub(s, "&" .. ci("sol") .. ";", "/"))
	s = (string.gsub(s, "&" .. ci("amp") .. ";", "&"))
	return s
end

-- Strip ASCII whitespace and controls so " http://" / "\0http://" cannot
-- sneak past the local-source checks.
function Markdown.scrubSrc(src: any): string
	return (string.gsub(str(src), "[\0-\32]+", ""))
end

-- Local = file:// URL, data: URI, or a path with no scheme and no "//" host.
-- Used for Markdown image syntax.
function Markdown.isLocalSource(src: any): boolean
	local s = trim(str(src))
	if startsWithCi(s, "file://") or startsWithCi(s, "data:") then
		return true
	end
	if string.match(string.lower(s), "^[a-z][a-z0-9%+%.%-]*:") then
		return false
	end
	return string.sub(s, 1, 2) ~= "//"
end

-- Strict local check for raw <img> tags only: file://, data:image/, or an
-- absolute path starting with a single "/".
function Markdown.isStrictLocalImgSrc(src: any): boolean
	local s = Markdown.scrubSrc(Markdown.decodeEntities(src))
	if startsWithCi(s, "file://") or startsWithCi(s, "data:image/") then
		return true
	end
	return string.sub(s, 1, 1) == "/" and string.sub(s, 2, 2) ~= "/"
end

-- [label]: destination  (link reference definitions; later ones win).
function Markdown.referenceDefinitions(text: any): { [string]: string }
	local s = str(text)
	local defs: { [string]: string } = {}
	local lineStart = 1
	local consumedTo = 0
	while lineStart <= #s do
		if lineStart > consumedTo then
			local rest = string.sub(s, lineStart)
			local spaces, label, dest, stop = string.match(rest, "^( *)%[([^%]]+)%]:%s*<?([^%s>]+)()")
			if spaces ~= nil and #(spaces :: string) <= 3 then
				defs[string.lower(trim(label :: string))] = dest :: string
				consumedTo = lineStart + (stop :: number) - 2
			end
		end
		local nl = string.find(s, "\n", lineStart, true)
		if nl == nil then
			break
		end
		lineStart = nl + 1
	end
	return defs
end

-- Scans `![alt]` with one level of nested brackets in alt, starting at the
-- "!" at i. Returns alt and the index just past "]", or nil.
local function scanImageAlt(s: string, i: number): (string?, number?)
	if string.sub(s, i, i + 1) ~= "![" then
		return nil, nil
	end
	local j = i + 2
	local n = #s
	while j <= n do
		local c = string.sub(s, j, j)
		if c == "]" then
			return string.sub(s, i + 2, j - 1), j + 1
		elseif c == "[" then
			local close = string.find(s, "[%[%]]", j + 1)
			if close == nil or string.sub(s, close, close) ~= "]" then
				return nil, nil
			end
			j = close + 1
		else
			j += 1
		end
	end
	return nil, nil
end

local function skipSpaces(s: string, j: number): number
	while isSpace(string.sub(s, j, j)) do
		j += 1
	end
	return j
end

-- Optional link title: " ", ' ' or ( ). Returns the index past it, or nil.
local function scanTitle(s: string, j: number): number?
	local open = string.sub(s, j, j)
	local closer = if open == '"' then '"' elseif open == "'" then "'" elseif open == "(" then ")" else nil
	if closer == nil then
		return nil
	end
	local close = string.find(s, closer, j + 1, true)
	if close == nil then
		return nil
	end
	return close + 1
end

-- Inline image destination after "](": returns src and index past ")", or nil.
local function scanInlineDest(s: string, j: number): (string?, number?)
	j = skipSpaces(s, j)
	local src: string
	if string.sub(s, j, j) == "<" then
		local close = string.find(s, ">", j + 1, true)
		if close == nil or close == j + 1 then
			return nil, nil
		end
		src = string.sub(s, j + 1, close - 1)
		j = close + 1
	else
		local bare = string.match(s, "^[^%s%)>]+", j)
		if bare == nil then
			return nil, nil
		end
		src = bare
		j += #bare
	end
	-- With a title.
	local afterSpace = skipSpaces(s, j)
	if afterSpace > j then
		local afterTitle = scanTitle(s, afterSpace)
		if afterTitle ~= nil then
			local k = skipSpaces(s, afterTitle)
			if string.sub(s, k, k) == ")" then
				return src, k + 1
			end
		end
	end
	-- Without a title.
	local k = skipSpaces(s, j)
	if string.sub(s, k, k) == ")" then
		return src, k + 1
	end
	return nil, nil
end

local function replaceInlineImages(s: string): string
	local out = {}
	local i = 1
	local n = #s
	while i <= n do
		local alt, afterAlt = scanImageAlt(s, i)
		if alt ~= nil and string.sub(s, afterAlt :: number, afterAlt :: number) == "(" then
			local src, stop = scanInlineDest(s, (afterAlt :: number) + 1)
			if src ~= nil then
				if Markdown.isLocalSource(src) then
					table.insert(out, string.sub(s, i, (stop :: number) - 1))
				else
					local label = if alt ~= "" then alt else src
					table.insert(out, "[" .. (label :: string) .. "](" .. src .. ")")
				end
				i = stop :: number
				continue
			end
		end
		table.insert(out, string.sub(s, i, i))
		i += 1
	end
	return table.concat(out)
end

local function replaceReferenceImages(s: string, remoteRef: (string) -> boolean): string
	local out = {}
	local i = 1
	local n = #s
	while i <= n do
		local alt, afterAlt = scanImageAlt(s, i)
		if alt ~= nil and string.sub(s, afterAlt :: number, afterAlt :: number) == "[" then
			local close = string.find(s, "]", (afterAlt :: number) + 1, true)
			if close ~= nil then
				local ref = string.sub(s, (afterAlt :: number) + 1, close - 1)
				local label = if ref ~= "" then ref else alt :: string
				local whole = string.sub(s, i, close)
				table.insert(out, if remoteRef(label) then string.sub(whole, 2) else whole)
				i = close + 1
				continue
			end
		end
		table.insert(out, string.sub(s, i, i))
		i += 1
	end
	return table.concat(out)
end

local function replaceShortcutImages(s: string, remoteRef: (string) -> boolean): string
	local out = {}
	local i = 1
	local n = #s
	while i <= n do
		if string.sub(s, i, i + 1) == "![" then
			local close = string.find(s, "]", i + 2, true)
			if close ~= nil and close > i + 2 then
				local nextChar = string.sub(s, close + 1, close + 1)
				if nextChar ~= "(" and nextChar ~= "[" then
					local whole = string.sub(s, i, close)
					local label = string.sub(s, i + 2, close - 1)
					table.insert(out, if remoteRef(label) then string.sub(whole, 2) else whole)
					i = close + 1
					continue
				end
			end
		end
		table.insert(out, string.sub(s, i, i))
		i += 1
	end
	return table.concat(out)
end

-- First src attribute value of a raw tag (double, single or unquoted), or nil.
local function srcOf(tag: string): string?
	local lower = string.lower(tag)
	local from = 1
	while true do
		local at = string.find(lower, "src", from, true)
		if at == nil then
			return nil
		end
		from = at + 1
		local before = if at > 1 then string.sub(tag, at - 1, at - 1) else ""
		if before == "" or not isWordChar(before) then
			local j = skipSpaces(tag, at + 3)
			if string.sub(tag, j, j) == "=" then
				j = skipSpaces(tag, j + 1)
				local q = string.sub(tag, j, j)
				if q == '"' or q == "'" then
					local close = string.find(tag, q, j + 1, true)
					if close ~= nil then
						return string.sub(tag, j + 1, close - 1)
					end
				end
				local bare = string.match(tag, "^[^%s>]+", j)
				if bare ~= nil then
					return bare
				end
			end
		end
	end
end

local function replaceRawImages(s: string): string
	local lower = string.lower(s)
	local out = {}
	local i = 1
	local n = #s
	while i <= n do
		if string.sub(lower, i, i + 3) == "<img" and not isWordChar(string.sub(s, i + 4, i + 4)) then
			local close = string.find(s, ">", i + 4, true)
			if close ~= nil then
				local tag = string.sub(s, i, close)
				local raw = srcOf(tag)
				if raw ~= nil and raw ~= "" and Markdown.isStrictLocalImgSrc(raw) then
					table.insert(out, tag)
				end
				i = close + 1
				continue
			end
		end
		table.insert(out, string.sub(s, i, i))
		i += 1
	end
	return table.concat(out)
end

function Markdown.prepare(text: any): string
	local source = str(text)
	local defs = Markdown.referenceDefinitions(source)
	local function remoteRef(label: string): boolean
		local url = defs[string.lower(trim(label))]
		return url ~= nil and not Markdown.isLocalSource(url)
	end
	local s = replaceInlineImages(source)
	s = replaceReferenceImages(s, remoteRef)
	s = replaceShortcutImages(s, remoteRef)
	s = replaceRawImages(s)
	return s
end

function Markdown.isOpenableLink(url: any): boolean
	local s = trim(str(url))
	if Url.isHttpUrl(s) then
		return true
	end
	if not startsWithCi(s, "mailto:") then
		return false
	end
	return string.match(string.sub(s, 8), "^[^%s@]+@[^%s@]+$") ~= nil
end

return Markdown

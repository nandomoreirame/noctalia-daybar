--!strict
-- Markdown notes. The title is derived from the first non-empty line.
-- note: { id, text, createdAt, updatedAt }

local Text = require("./text.luau")
local Tbl = require("./tbl.luau")

local Notes = {}

Notes.SNIPPET_MAX = 140

local function str(value: any): string
	if value == nil then
		return ""
	end
	return tostring(value)
end

local function trim(s: string): string
	return (string.match(s, "^%s*(.-)%s*$") :: string)
end

-- Block prefix of a Markdown line: up to 3 leading spaces, then a heading
-- marker, a quote marker, a bullet (with optional task box) or an ordered
-- number. Returns the line without it, or the line unchanged.
local function stripPrefix(line: string): string
	local lead = string.match(line, "^%s*") :: string
	if #lead > 3 then
		lead = string.sub(lead, 1, 3)
	end
	-- Retry with fewer leading spaces, as the regex would backtrack.
	for n = #lead, 0, -1 do
		local rest = string.sub(line, n + 1)
		local after = string.match(rest, "^#+%s+()")
		if after ~= nil then
			local hashes = #(string.match(rest, "^#+") :: string)
			if hashes <= 6 then
				return string.sub(rest, after :: number)
			end
		end
		after = string.match(rest, "^>%s*()")
		if after ~= nil then
			return string.sub(rest, after :: number)
		end
		after = string.match(rest, "^[%-%*%+]%s+()")
		if after ~= nil then
			local body = string.sub(rest, after :: number)
			local boxEnd = string.match(body, "^%[[ xX]%]%s+()")
			if boxEnd ~= nil then
				return string.sub(body, boxEnd :: number)
			end
			return body
		end
		after = string.match(rest, "^%d+[%.%)]%s+()")
		if after ~= nil then
			return string.sub(rest, after :: number)
		end
	end
	return line
end

-- Markdown markup removed for list display (not a renderer).
function Notes.stripMarkup(line: any): string
	local s = stripPrefix(str(line))
	s = (string.gsub(s, "!%[([^%]]*)%]%([^%)]*%)", "%1"))
	s = (string.gsub(s, "%[([^%]]*)%]%([^%)]*%)", "%1"))
	s = (string.gsub(s, "~~", ""))
	s = (string.gsub(s, "[%*_`]", ""))
	s = (string.gsub(s, "%s+", " "))
	return trim(s)
end

local function lines(text: any): { string }
	local s = str(text)
	local out = {}
	for line in string.gmatch(s .. "\n", "(.-)\r?\n") do
		table.insert(out, line)
	end
	return out
end

local function titleIndex(all: { string }): number?
	for i, line in ipairs(all) do
		if trim(line) ~= "" then
			return i
		end
	end
	return nil
end

function Notes.titleOf(text: any): string
	local all = lines(text)
	local i = titleIndex(all)
	if i == nil then
		return ""
	end
	return Notes.stripMarkup(all[i])
end

-- First `max` UTF-8 characters of s.
local function capChars(s: string, max: number): string
	local count = utf8.len(s)
	if count == nil then
		return string.sub(s, 1, max)
	end
	if count <= max then
		return s
	end
	local cut = utf8.offset(s, max + 1) :: number
	return string.sub(s, 1, cut - 1)
end

function Notes.snippetOf(text: any): string
	local all = lines(text)
	local i = titleIndex(all)
	if i == nil then
		return ""
	end
	local parts = {}
	for j = i + 1, #all do
		local plain = Notes.stripMarkup(all[j])
		if plain ~= "" then
			table.insert(parts, plain)
		end
	end
	return capChars(table.concat(parts, " "), Notes.SNIPPET_MAX)
end

function Notes.isBlank(text: any): boolean
	return trim(str(text)) == ""
end

-- What closing the note window does: a note created in this window that ends
-- blank is discarded (REQ-015); anything else is saved.
function Notes.closeAction(createdHere: boolean, text: any): string
	if createdHere and Notes.isBlank(text) then
		return "discard"
	end
	return "save"
end

function Notes.add(data: any, text: any, id: string, nowIso: string): any
	local note = { id = id, text = trim(str(text)), createdAt = nowIso, updatedAt = nowIso }
	local list = Tbl.copyList(data.notes)
	table.insert(list, note)
	return Tbl.merge(data, { notes = list })
end

function Notes.update(data: any, id: string, text: string, nowIso: string): any
	local target = Tbl.find(data.notes, function(n)
		return n.id == id
	end)
	if target == nil or target.text == text then
		return data
	end
	return Tbl.merge(data, {
		notes = Tbl.map(data.notes, function(n)
			if n.id ~= id then
				return n
			end
			return Tbl.merge(n, { text = text, updatedAt = nowIso })
		end),
	})
end

function Notes.remove(data: any, id: string): any
	return Tbl.merge(data, {
		notes = Tbl.filter(data.notes, function(n)
			return n.id ~= id
		end),
	})
end

-- Last edit first; stable for equal updatedAt.
function Notes.sorted(list: { any }): { any }
	local indexed: { { i: number, n: any } } = {}
	for i, n in ipairs(list) do
		indexed[i] = { i = i, n = n }
	end
	table.sort(indexed, function(x: any, y: any): boolean
		if x.n.updatedAt ~= y.n.updatedAt then
			return x.n.updatedAt > y.n.updatedAt
		end
		return x.i < y.i
	end)
	return Tbl.map(indexed, function(e)
		return e.n
	end)
end

function Notes.search(list: { any }, query: any): { any }
	return Tbl.filter(list, function(n)
		return Text.matches({ n.text }, query)
	end)
end

return Notes

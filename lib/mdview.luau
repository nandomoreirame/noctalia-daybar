--!strict
-- Markdown to plain view blocks for the note preview (no `ui` here; the view
-- maps blocks to nodes). A CommonMark/GFM subset, line based:
--   { kind = "heading", level, text }
--   { kind = "paragraph", spans }          span = { text, href? }
--   { kind = "list", ordered, items }      item = { spans, task = nil|true|false, depth }
--   { kind = "quote", spans }
--   { kind = "code", text }
--   { kind = "rule" }
--   { kind = "table", rows }               rows of plain cell strings, header first
--   { kind = "image", path, alt }          local images only
-- Safety: text is never interpreted as markup by the view; a span keeps `href`
-- only when Markdown.isOpenableLink(href); a remote image becomes a link span
-- (nothing loads from the network); only local images (file://, absolute or ~/)
-- become image blocks.

local Markdown = require("./markdown.luau")

local MdView = {}

type Span = { text: string, href: string? }
type Piece = { text: string, href: string?, image: { path: string, alt: string }? }
type Opts = { home: string? }

-- Slot delimiter for already-parsed inline pieces; stripped from the input.
local P = "\0"

local function str(value: any): string
	if value == nil then
		return ""
	end
	return tostring(value)
end

local function trim(s: string): string
	return (string.match(s, "^%s*(.-)%s*$") :: string)
end

local function isSpace(c: string): boolean
	return c ~= "" and string.match(c, "^%s$") ~= nil
end

local function isWord(c: string): boolean
	return c ~= "" and string.match(c, "^[%w_]$") ~= nil
end

local function startsWithCi(s: string, prefix: string): boolean
	return string.lower(string.sub(s, 1, #prefix)) == prefix
end

local function skipSpaces(s: string, j: number): number
	while isSpace(string.sub(s, j, j)) do
		j += 1
	end
	return j
end

-- ---------------------------------------------------------------------------
-- Emphasis: drop paired markers, keep the text between them.
-- ---------------------------------------------------------------------------

type PairRule = { marker: string, bound: boolean, single: boolean }

local PAIR_RULES: { PairRule } = {
	{ marker = "**", bound = false, single = false },
	{ marker = "__", bound = true, single = false },
	{ marker = "~~", bound = false, single = false },
	{ marker = "*", bound = false, single = true },
	{ marker = "_", bound = true, single = true },
}

local function findClose(s: string, rule: PairRule, from: number): number?
	local m = rule.marker
	local j = from
	local n = #s
	while j <= n do
		if string.sub(s, j, j + #m - 1) == m then
			local before = string.sub(s, j - 1, j - 1)
			local after = string.sub(s, j + #m, j + #m)
			local okBefore = not isSpace(before) and (not rule.single or before ~= m)
			local okAfter = (not rule.bound or not isWord(after)) and (not rule.single or after ~= m)
			if okBefore and okAfter then
				return j
			end
			if rule.single then
				-- The inner text of a single-marker span cannot hold the marker.
				return nil
			end
		end
		j += 1
	end
	return nil
end

local function stripPair(s: string, rule: PairRule): string
	local m = rule.marker
	local out = {}
	local i = 1
	local n = #s
	while i <= n do
		if string.sub(s, i, i + #m - 1) == m then
			local before = string.sub(s, i - 1, i - 1)
			local first = string.sub(s, i + #m, i + #m)
			local okOpen = first ~= ""
				and not isSpace(first)
				and (not rule.bound or not isWord(before))
				and (not rule.single or (before ~= m and first ~= m))
			if okOpen then
				local close = findClose(s, rule, i + #m + 1)
				if close ~= nil then
					table.insert(out, string.sub(s, i + #m, close - 1))
					i = close + #m
					continue
				end
			end
		end
		table.insert(out, string.sub(s, i, i))
		i += 1
	end
	return table.concat(out)
end

local function stripEmphasis(s: string): string
	for _, rule in ipairs(PAIR_RULES) do
		s = stripPair(s, rule)
	end
	return s
end

-- ---------------------------------------------------------------------------
-- Inline scanners
-- ---------------------------------------------------------------------------

-- Link destination: no spaces, one level of balanced parentheses.
-- Returns dest and the index past the closing ")", or nil.
local function scanDest(s: string, j: number): (string?, number?)
	j = skipSpaces(s, j)
	if string.sub(s, j, j) == "<" then
		j += 1
	end
	local start = j
	local n = #s
	while j <= n do
		local c = string.sub(s, j, j)
		if c == "(" then
			local k = j + 1
			while k <= n and not string.match(string.sub(s, k, k), "^[%(%)%s]$") do
				k += 1
			end
			if string.sub(s, k, k) ~= ")" then
				break
			end
			j = k + 1
		elseif c == ")" or c == "<" or c == ">" or isSpace(c) then
			break
		else
			j += 1
		end
	end
	if j == start then
		return nil, nil
	end
	local dest = string.sub(s, start, j - 1)
	if string.sub(s, j, j) == ">" then
		j += 1
	end
	-- Optional "title" / 'title'.
	local afterSpace = skipSpaces(s, j)
	if afterSpace > j then
		local q = string.sub(s, afterSpace, afterSpace)
		if q == '"' or q == "'" then
			local close = string.find(s, q, afterSpace + 1, true)
			if close ~= nil then
				local k = skipSpaces(s, close + 1)
				if string.sub(s, k, k) == ")" then
					return dest, k + 1
				end
			end
		end
	end
	local k = skipSpaces(s, j)
	if string.sub(s, k, k) == ")" then
		return dest, k + 1
	end
	return nil, nil
end

-- `[label]` starting at i (label without "]"; may be empty when allowEmpty).
-- Returns label and the index past "]".
local function scanBracket(s: string, i: number, allowEmpty: boolean): (string?, number?)
	if string.sub(s, i, i) ~= "[" then
		return nil, nil
	end
	local close = string.find(s, "]", i + 1, true)
	if close == nil or (not allowEmpty and close == i + 1) then
		return nil, nil
	end
	return string.sub(s, i + 1, close - 1), close + 1
end

type Ctx = { slots: { Piece }, defs: { [string]: string }, opts: Opts }

local function keep(ctx: Ctx, piece: Piece): string
	table.insert(ctx.slots, piece)
	return P .. tostring(#ctx.slots) .. P
end

-- Label text with earlier slots replaced by their plain text.
local function resolveText(ctx: Ctx, s: string): string
	return (string.gsub(s, P .. "(%d+)" .. P, function(d: string): string
		local slot = ctx.slots[tonumber(d) :: number]
		return if slot then slot.text else ""
	end))
end

local function lookup(ctx: Ctx, label: string): string?
	return ctx.defs[string.lower(trim(label))]
end

local function imagePiece(ctx: Ctx, alt: string, src: string): Piece
	local s = trim(src)
	local path: string? = nil
	if startsWithCi(s, "file://") then
		path = string.sub(s, 8)
	elseif string.sub(s, 1, 1) == "/" and string.sub(s, 2, 2) ~= "/" then
		path = s
	elseif string.sub(s, 1, 2) == "~/" then
		local home = ctx.opts.home
		path = if home ~= nil and home ~= "" then home .. string.sub(s, 2) else s
	end
	if path ~= nil and path ~= "" then
		return { text = alt, image = { path = path, alt = alt } }
	end
	local label = if alt ~= "" then alt else s
	-- Remote (or unresolvable) image: a link at most, never a fetch.
	if Markdown.isOpenableLink(s) then
		return { text = label, href = s }
	end
	return { text = label }
end

local function linkPiece(ctx: Ctx, label: string, url: string): Piece
	local text = stripEmphasis(resolveText(ctx, label))
	if Markdown.isOpenableLink(url) then
		return { text = text, href = trim(url) }
	end
	return { text = text }
end

-- Runs `try(s, i)` at every index; a non-nil result (replacement, nextIndex)
-- replaces s[i, nextIndex - 1].
local function scan(s: string, try: (string, number) -> (string?, number?)): string
	local out = {}
	local i = 1
	local n = #s
	while i <= n do
		local rep, nextIndex = try(s, i)
		if rep ~= nil then
			table.insert(out, rep)
			i = nextIndex :: number
		else
			table.insert(out, string.sub(s, i, i))
			i += 1
		end
	end
	return table.concat(out)
end

local function inlinePieces(text: string, ctx: Ctx): { Piece }
	local s = (string.gsub(text, P, ""))
	-- Code spans.
	s = scan(s, function(src, i)
		if string.sub(src, i, i) ~= "`" then
			return nil, nil
		end
		local close = string.find(src, "`", i + 1, true)
		if close == nil or close == i + 1 then
			return nil, nil
		end
		return keep(ctx, { text = string.sub(src, i + 1, close - 1) }), close + 1
	end)
	-- Inline images ![alt](dest "title").
	s = scan(s, function(src, i)
		if string.sub(src, i, i) ~= "!" then
			return nil, nil
		end
		local alt, after = scanBracket(src, i + 1, true)
		if alt == nil or string.sub(src, after :: number, after :: number) ~= "(" then
			return nil, nil
		end
		local dest, stop = scanDest(src, (after :: number) + 1)
		if dest == nil then
			return nil, nil
		end
		return keep(ctx, imagePiece(ctx, resolveText(ctx, alt :: string), dest :: string)), stop
	end)
	-- Reference images ![alt][ref] and ![alt][].
	s = scan(s, function(src, i)
		if string.sub(src, i, i) ~= "!" then
			return nil, nil
		end
		local alt, after = scanBracket(src, i + 1, true)
		if alt == nil then
			return nil, nil
		end
		local ref, stop = scanBracket(src, after :: number, true)
		if ref == nil then
			return nil, nil
		end
		local url = lookup(ctx, if ref ~= "" then ref :: string else alt :: string)
		if url == nil then
			return nil, nil
		end
		return keep(ctx, imagePiece(ctx, resolveText(ctx, alt :: string), url)), stop
	end)
	-- Inline links [label](dest "title").
	s = scan(s, function(src, i)
		local label, after = scanBracket(src, i, false)
		if label == nil or string.sub(src, after :: number, after :: number) ~= "(" then
			return nil, nil
		end
		local dest, stop = scanDest(src, (after :: number) + 1)
		if dest == nil then
			return nil, nil
		end
		return keep(ctx, linkPiece(ctx, label :: string, dest :: string)), stop
	end)
	-- Reference links [label][ref] and [label][].
	s = scan(s, function(src, i)
		local label, after = scanBracket(src, i, false)
		if label == nil then
			return nil, nil
		end
		local ref, stop = scanBracket(src, after :: number, true)
		if ref == nil then
			return nil, nil
		end
		local url = lookup(ctx, if ref ~= "" then ref :: string else label :: string)
		if url == nil then
			return nil, nil
		end
		return keep(ctx, linkPiece(ctx, label :: string, url)), stop
	end)
	-- Autolinks <https://...> and <mailto:...>.
	s = scan(s, function(src, i)
		if string.sub(src, i, i) ~= "<" then
			return nil, nil
		end
		local rest = string.sub(src, i + 1)
		if not (startsWithCi(rest, "http://") or startsWithCi(rest, "https://") or startsWithCi(rest, "mailto:")) then
			return nil, nil
		end
		local url = string.match(rest, "^[^%s>]+")
		if url == nil or string.sub(rest, #url + 1, #url + 1) ~= ">" then
			return nil, nil
		end
		return keep(ctx, linkPiece(ctx, url, url)), i + #url + 2
	end)

	s = stripEmphasis(s)

	local pieces: { Piece } = {}
	local pos = 1
	for startCap, d, stopCap in string.gmatch(s, "()" .. P .. "(%d+)" .. P .. "()") do
		local startAt = tonumber(startCap) :: number
		if startAt > pos then
			table.insert(pieces, { text = string.sub(s, pos, startAt - 1) })
		end
		local slot = ctx.slots[tonumber(d) :: number]
		if slot ~= nil then
			table.insert(pieces, slot)
		end
		pos = tonumber(stopCap) :: number
	end
	if pos <= #s then
		table.insert(pieces, { text = string.sub(s, pos) })
	end
	return pieces
end

-- Pieces to spans: images become their alt text, adjacent plain text merges.
local function toSpans(pieces: { Piece }): { Span }
	local spans: { Span } = {}
	for _, p in ipairs(pieces) do
		local text = p.text
		if text ~= "" then
			local last = spans[#spans]
			if p.href == nil and last ~= nil and last.href == nil then
				last.text ..= text
			elseif p.href ~= nil then
				table.insert(spans, { text = text, href = p.href })
			else
				table.insert(spans, { text = text })
			end
		end
	end
	return spans
end

local function plainText(spans: { Span }): string
	local parts = {}
	for _, sp in ipairs(spans) do
		table.insert(parts, sp.text)
	end
	return table.concat(parts)
end

-- ---------------------------------------------------------------------------
-- Block patterns
-- ---------------------------------------------------------------------------

local function leadOk(line: string): (boolean, string)
	local lead = string.match(line, "^%s*") :: string
	return #lead <= 3, string.sub(line, #lead + 1)
end

local function fenceOf(line: string): string?
	local ok, rest = leadOk(line)
	if not ok then
		return nil
	end
	local head = string.sub(rest, 1, 3)
	if head == "```" or head == "~~~" then
		return head
	end
	return nil
end

local function headingOf(line: string): (number?, string?)
	local ok, rest = leadOk(line)
	if not ok then
		return nil, nil
	end
	local hashes, content = string.match(rest, "^(#+)%s+(.*)$")
	if hashes == nil or #(hashes :: string) > 6 then
		return nil, nil
	end
	local c = string.gsub(content :: string, "%s*$", "")
	c = string.gsub(c, "#*$", "")
	c = string.gsub(c, "%s*$", "")
	return #(hashes :: string), c
end

local function isRule(line: string): boolean
	local ok, rest = leadOk(line)
	if not ok then
		return false
	end
	local compact = string.gsub(rest, "%s", "")
	local c = string.sub(compact, 1, 1)
	if c ~= "-" and c ~= "*" and c ~= "_" then
		return false
	end
	if #compact < 3 then
		return false
	end
	return string.match(compact, "^%" .. c .. "+$") ~= nil
end

local function quoteOf(line: string): string?
	local ok, rest = leadOk(line)
	if not ok or string.sub(rest, 1, 1) ~= ">" then
		return nil
	end
	local inner = string.sub(rest, 2)
	if string.sub(inner, 1, 1) == " " or string.sub(inner, 1, 1) == "\t" then
		inner = string.sub(inner, 2)
	end
	return inner
end

type ListLine = { indent: number, ordered: boolean, text: string }

local function listOf(line: string): ListLine?
	local lead, marker, text = string.match(line, "^(%s*)([%-%*%+])%s+(.*)$")
	if lead == nil then
		lead, marker, text = string.match(line, "^(%s*)(%d+[%.%)])%s+(.*)$")
	end
	if lead == nil then
		return nil
	end
	local indent = #(string.gsub(lead :: string, "\t", "    "))
	return { indent = indent, ordered = string.match(marker :: string, "%d") ~= nil, text = text :: string }
end

local function cells(line: string): { string }
	local s = trim(line)
	s = (string.gsub(s, "^|", ""))
	s = (string.gsub(s, "|$", ""))
	local out = {}
	for cell in string.gmatch(s .. "|", "([^|]*)|") do
		table.insert(out, trim(cell))
	end
	return out
end

local function isTableSep(line: string): boolean
	if string.find(line, "-", 1, true) == nil then
		return false
	end
	for _, c in ipairs(cells(line)) do
		if string.match(c, "^:?%-+:?$") == nil then
			return false
		end
	end
	return true
end

local function isDefLine(line: string): boolean
	local lead = string.match(line, "^%s*") :: string
	if #lead > 3 then
		return false
	end
	return string.match(string.sub(line, #lead + 1), "^%[[^%]]+%]:%s*%S") ~= nil
end

-- ---------------------------------------------------------------------------
-- Render
-- ---------------------------------------------------------------------------

local function splitLines(text: string): { string }
	local out = {}
	for line in string.gmatch(text .. "\n", "(.-)\r?\n") do
		table.insert(out, line)
	end
	-- "a\n" yields a trailing empty line; harmless (blank).
	return out
end

function MdView.render(text: any, opts: Opts?): { { [string]: any } }
	local source = str(text)
	local ctx: Ctx = { slots = {}, defs = Markdown.referenceDefinitions(source), opts = opts or {} }
	local lines = splitLines(source)
	local out: { any } = {}
	local para: { string } = {}

	local function spansOf(s: string): { Span }
		return toSpans(inlinePieces(s, ctx))
	end

	local function flush()
		if #para == 0 then
			return
		end
		local buf = {}
		for k, l in ipairs(para) do
			table.insert(buf, trim(l))
			if k < #para then
				table.insert(buf, if string.match(l, "  +$") then "\n" else " ")
			end
		end
		para = {}
		local pending: { Piece } = {}
		local function push()
			local spans = toSpans(pending)
			if #spans > 0 then
				table.insert(out, { kind = "paragraph", spans = spans })
			end
			pending = {}
		end
		for _, piece in ipairs(inlinePieces(table.concat(buf), ctx)) do
			if piece.image ~= nil then
				push()
				table.insert(out, { kind = "image", path = piece.image.path, alt = piece.image.alt })
			else
				table.insert(pending, piece)
			end
		end
		push()
	end

	local i = 1
	local n = #lines
	while i <= n do
		local line = lines[i]
		if trim(line) == "" or isDefLine(line) then
			flush()
			i += 1
			continue
		end
		local fence = fenceOf(line)
		if fence ~= nil then
			flush()
			local code = {}
			i += 1
			while i <= n and string.sub(trim(lines[i]), 1, 3) ~= fence do
				table.insert(code, lines[i])
				i += 1
			end
			i += 1
			table.insert(out, { kind = "code", text = table.concat(code, "\n") })
			continue
		end
		local level, content = headingOf(line)
		if level ~= nil then
			flush()
			table.insert(out, { kind = "heading", level = level, text = plainText(spansOf(content :: string)) })
			i += 1
			continue
		end
		if isRule(line) then
			flush()
			table.insert(out, { kind = "rule" })
			i += 1
			continue
		end
		if string.find(line, "|", 1, true) ~= nil and i + 1 <= n and isTableSep(lines[i + 1]) then
			flush()
			local rows = {}
			local function row(l: string)
				local r = {}
				for _, c in ipairs(cells(l)) do
					table.insert(r, plainText(spansOf(c)))
				end
				table.insert(rows, r)
			end
			row(line)
			i += 2
			while i <= n and string.find(lines[i], "|", 1, true) ~= nil and trim(lines[i]) ~= "" do
				row(lines[i])
				i += 1
			end
			table.insert(out, { kind = "table", rows = rows })
			continue
		end
		if quoteOf(line) ~= nil then
			flush()
			local inner = {}
			while i <= n and quoteOf(lines[i]) ~= nil do
				local q = trim(quoteOf(lines[i]) :: string)
				if q ~= "" then
					table.insert(inner, q)
				end
				i += 1
			end
			table.insert(out, { kind = "quote", spans = spansOf(table.concat(inner, " ")) })
			continue
		end
		local firstItem = listOf(line)
		if firstItem ~= nil then
			flush()
			local items = {}
			local stack: { number } = {}
			while i <= n and listOf(lines[i]) ~= nil do
				local li = listOf(lines[i]) :: ListLine
				while #stack > 0 and stack[#stack] > li.indent do
					table.remove(stack)
				end
				if #stack == 0 or li.indent > stack[#stack] then
					table.insert(stack, li.indent)
				end
				local body = li.text
				local task: boolean? = nil
				local box, rest = string.match(body, "^%[([ xX])%]%s+(.*)$")
				if box ~= nil then
					task = box ~= " "
					body = rest :: string
				end
				table.insert(items, { spans = spansOf(body), task = task, depth = #stack - 1 })
				i += 1
			end
			table.insert(out, { kind = "list", ordered = firstItem.ordered, items = items })
			continue
		end
		table.insert(para, line)
		i += 1
	end
	flush()
	return out
end

return MdView

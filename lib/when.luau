--!strict
-- Natural-language "when" parser for pt-BR capture text.
-- Tokenizer over whitespace-separated words with folded lookup tables.

local Dates = require("./dates.luau")
local Text = require("./text.luau")

local When = {}

local PREPOSITIONS: { [string]: boolean } = {
	na = true,
	no = true,
	para = true,
	pra = true,
	em = true,
	de = true,
	["as"] = true,
	a = true,
}

-- Folded key -> day offset from today.
local RELATIVE_DAYS: { [string]: number } = {
	hoje = 0,
	amanha = 1,
	["depois de amanha"] = 2,
}

-- Folded weekday stem -> { dow (JS Sunday=0), ordinalCapable }.
local WEEKDAYS: { [string]: { dow: number, ordinal: boolean } } = {
	domingo = { dow = 0, ordinal = false },
	segunda = { dow = 1, ordinal = true },
	terca = { dow = 2, ordinal = true },
	quarta = { dow = 3, ordinal = true },
	quinta = { dow = 4, ordinal = true },
	sexta = { dow = 5, ordinal = true },
	sabado = { dow = 6, ordinal = false },
}

type Word = {
	raw: string,
	folded: string,
	core: string, -- folded without trailing punctuation
	punct: string, -- trailing ,.;!? if any
	feira: boolean, -- core ended with -feira before strip
}

local function splitWords(text: string): { Word }
	local words: { Word } = {}
	local trimmed = string.match(text, "^%s*(.-)%s*$") or ""
	for raw in string.gmatch(trimmed, "%S+") do
		local folded = Text.fold(raw)
		local core, punct = string.match(folded, "^(.-)([,.;!?]+)$")
		if core == nil then
			core = folded
			punct = ""
		end
		local feira = false
		local stem = core
		if string.sub(core, -6) == "-feira" then
			feira = true
			stem = string.sub(core, 1, #core - 6)
		end
		table.insert(words, {
			raw = raw,
			folded = folded,
			core = stem,
			punct = punct,
			feira = feira,
		})
	end
	return words
end

local function isPrep(w: Word): boolean
	-- "às" folds to "as"; also accept raw fold of à.
	return PREPOSITIONS[w.core] == true and w.punct == "" and not w.feira
end

local function jsWeekday(epoch: number): number
	-- os.date wday: Sunday=1 .. Saturday=7; JS getDay: Sunday=0 .. Saturday=6.
	local parts = os.date("*t", epoch) :: { wday: number }
	return parts.wday - 1
end

local function toTime(hours: number, minutes: number): string?
	if hours > 23 or minutes > 59 then
		return nil
	end
	return Dates.pad2(hours) .. ":" .. Dates.pad2(minutes)
end

-- Parse a time token like "9h", "9h30", "15:00", "16h30". Returns HH:MM or nil.
local function parseTimeToken(token: string): string?
	local h, m = string.match(token, "^(%d%d?)h(%d%d)$")
	if h ~= nil then
		return toTime(tonumber(h) :: number, tonumber(m) :: number)
	end
	local hOnly = string.match(token, "^(%d%d?)h$")
	if hOnly ~= nil then
		return toTime(tonumber(hOnly) :: number, 0)
	end
	local ch, cm = string.match(token, "^(%d%d?):(%d%d)$")
	if ch ~= nil then
		return toTime(tonumber(ch) :: number, tonumber(cm) :: number)
	end
	return nil
end

-- Bare hour number ("10") used only as a range end at end of text.
local function parseBareHour(token: string): string?
	local h = string.match(token, "^(%d%d?)$")
	if h == nil then
		return nil
	end
	return toTime(tonumber(h) :: number, 0)
end

local function parseDateToken(core: string, todayEpoch: number, todayParts: { year: number }): string?
	local d, m, y = string.match(core, "^(%d%d?)/(%d%d?)/(%d%d%d?%d?)$")
	if d == nil then
		d, m = string.match(core, "^(%d%d?)/(%d%d?)$")
		y = nil
	end
	if d == nil then
		return nil
	end
	local day = tonumber(d) :: number
	local month = tonumber(m) :: number
	local year: number
	if y ~= nil then
		year = tonumber(y) :: number
		if #y == 2 then
			year = 2000 + year
		end
	else
		year = todayParts.year
	end
	if month < 1 or month > 12 or day < 1 or day > 31 then
		return nil
	end
	local iso = string.format("%04d-%02d-%02d", year, month, day)
	local t = Dates.parseIsoDate(iso)
	if t == nil then
		return nil
	end
	if y == nil then
		local todayMid = Dates.parseIsoDate(Dates.isoDate(todayEpoch)) :: number
		if t < todayMid then
			iso = string.format("%04d-%02d-%02d", year + 1, month, day)
			t = Dates.parseIsoDate(iso)
			if t == nil then
				return nil
			end
		end
	end
	return iso
end

local function nextWeekday(todayEpoch: number, dow: number): string
	local todayDow = jsWeekday(todayEpoch)
	local diff = (dow - todayDow + 7) % 7
	if diff == 0 then
		diff = 7
	end
	return Dates.isoDate(Dates.addDays(todayEpoch, diff))
end

local function weekdayFollowOk(words: { Word }, index: number, entry: { dow: number, ordinal: boolean }, feira: boolean): boolean
	if not entry.ordinal or feira or index == 1 then
		return true
	end
	-- JS LEAD folds a leading preposition into the match at index 0, so
	-- "na segunda revisar PR" counts as opening the text.
	if index == 2 and isPrep(words[1]) then
		return true
	end
	-- After this word: end, only punctuation left on it, or next word starts a time.
	local w = words[index]
	if w.punct ~= "" then
		return true
	end
	local nextW = words[index + 1]
	if nextW == nil then
		return true
	end
	-- JS WEEKDAY_FOLLOW looks at rest after the match: `\s+\d{1,2}(?:h|:)`
	local nextToken = nextW.folded
	if string.match(nextToken, "^%d%d?[h:]") then
		return true
	end
	return false
end

type State = {
	words: { Word },
	used: { boolean },
}

local function markUsed(state: State, from: number, toInclusive: number)
	for i = from, toInclusive do
		state.used[i] = true
	end
end

local function tryTakePrep(state: State, index: number): number
	if index >= 1 and not state.used[index] and isPrep(state.words[index]) then
		return index
	end
	return 0
end

local function parseDay(state: State, todayEpoch: number): string?
	local words = state.words
	local todayParts = os.date("*t", todayEpoch) :: { year: number }

	-- "depois de amanhã" (3 tokens: depois, de, amanha)
	for i = 1, #words - 2 do
		if state.used[i] or state.used[i + 1] or state.used[i + 2] then
			continue
		end
		local phrase = words[i].core .. " " .. words[i + 1].core .. " " .. words[i + 2].core
		if RELATIVE_DAYS[phrase] ~= nil and words[i].punct == "" and words[i + 1].punct == "" then
			local prepAt = tryTakePrep(state, i - 1)
			local offset = RELATIVE_DAYS[phrase]
			markUsed(state, if prepAt > 0 then prepAt else i, i + 2)
			return Dates.isoDate(Dates.addDays(todayEpoch, offset))
		end
	end

	for i, w in ipairs(words) do
		if state.used[i] then
			continue
		end
		local offset = RELATIVE_DAYS[w.core]
		if offset ~= nil and not w.feira then
			local prepAt = tryTakePrep(state, i - 1)
			markUsed(state, if prepAt > 0 then prepAt else i, i)
			return Dates.isoDate(Dates.addDays(todayEpoch, offset))
		end
	end

	for i, w in ipairs(words) do
		if state.used[i] then
			continue
		end
		local entry = WEEKDAYS[w.core]
		if entry ~= nil then
			if not weekdayFollowOk(words, i, entry, w.feira) then
				continue
			end
			local prepAt = tryTakePrep(state, i - 1)
			markUsed(state, if prepAt > 0 then prepAt else i, i)
			return nextWeekday(todayEpoch, entry.dow)
		end
	end

	for i, w in ipairs(words) do
		if state.used[i] then
			continue
		end
		local iso = parseDateToken(w.core, todayEpoch, todayParts)
		if iso ~= nil then
			local prepAt = tryTakePrep(state, i - 1)
			markUsed(state, if prepAt > 0 then prepAt else i, i)
			return iso
		end
	end

	return nil
end

local function isRangeSep(w: Word): boolean
	local c = w.core
	return (c == "-" or c == "ate" or c == "as") and w.punct == "" and not w.feira
end

-- Next unused word after `from` (inclusive search from from+1), or nil.
local function nextUnusedWord(state: State, from: number): Word?
	for n = from + 1, #state.words do
		if not state.used[n] then
			return state.words[n]
		end
	end
	return nil
end

-- Bare end ("às 10") followed by an unused non-digit word is a quantity.
local function bareEndBlocked(state: State, endIndex: number): boolean
	local w = state.words[endIndex]
	if w.punct ~= "" then
		return false
	end
	local nextW = nextUnusedWord(state, endIndex)
	return nextW ~= nil and not string.match(nextW.folded, "^%d")
end

local function parseTimes(state: State): { start: string?, ["end"]: string? }
	local words = state.words

	-- Range forms: TIME RANGE_SEP TIME_OPT
	-- 1) single token "15h-16h", "15h-16:00", "9h-10"
	for i, w in ipairs(words) do
		if state.used[i] then
			continue
		end
		local dashAt = string.find(w.core, "-", 1, true)
		if dashAt == nil then
			continue
		end
		local left = string.sub(w.core, 1, dashAt - 1)
		local right = string.sub(w.core, dashAt + 1)
		if left == "" or right == "" then
			continue
		end
		local start = parseTimeToken(left)
		if start == nil then
			continue
		end
		local ending = parseTimeToken(right)
		local bareEnd = false
		if ending == nil then
			ending = parseBareHour(right)
			bareEnd = ending ~= nil
		end
		if ending == nil then
			continue
		end
		if bareEnd and bareEndBlocked(state, i) then
			continue
		end
		local sm = Dates.minutesOf(start) :: number
		local em = Dates.minutesOf(ending) :: number
		if em > sm then
			local prepAt = tryTakePrep(state, i - 1)
			markUsed(state, if prepAt > 0 then prepAt else i, i)
			return { start = start, ["end"] = ending }
		end
		-- Invalid range (end not after start): keep scanning for a later simple time.
	end

	-- 2) "15h às 16h30" or "12:00 - 13:00" across words
	for i = 1, #words do
		if state.used[i] then
			continue
		end
		local start = parseTimeToken(words[i].core)
		if start == nil then
			start = parseTimeToken(words[i].folded)
		end
		if start == nil then
			continue
		end
		local j = i + 1
		if j <= #words and not state.used[j] and isRangeSep(words[j]) then
			local k = j + 1
			if k <= #words and not state.used[k] then
				local ending = parseTimeToken(words[k].core) or parseTimeToken(words[k].folded)
				local bareEnd = false
				if ending == nil then
					ending = parseBareHour(words[k].core)
					bareEnd = ending ~= nil
				end
				if ending ~= nil and bareEnd and bareEndBlocked(state, k) then
					ending = nil
				end
				if ending ~= nil then
					local sm = Dates.minutesOf(start) :: number
					local em = Dates.minutesOf(ending) :: number
					if em > sm then
						local prepAt = tryTakePrep(state, i - 1)
						markUsed(state, if prepAt > 0 then prepAt else i, k)
						return { start = start, ["end"] = ending }
					end
					-- Invalid range: keep scanning for a later simple time.
				end
			end
		end
	end

	-- Single start time
	for i, w in ipairs(words) do
		if state.used[i] then
			continue
		end
		local start = parseTimeToken(w.core) or parseTimeToken(w.folded)
		if start ~= nil then
			local prepAt = tryTakePrep(state, i - 1)
			-- Only consume "às"/"as"/"a" style preps before times; "de" etc. already in PREPOSITIONS.
			markUsed(state, if prepAt > 0 then prepAt else i, i)
			return { start = start, ["end"] = nil }
		end
	end

	return { start = nil, ["end"] = nil }
end

local function rebuildTitle(state: State): string
	local parts: { string } = {}
	for i, w in ipairs(state.words) do
		if state.used[i] then
			-- Used weekday with trailing punct: JS keeps the comma in the title.
			if w.punct ~= "" then
				table.insert(parts, w.punct)
			end
		else
			table.insert(parts, w.raw)
		end
	end
	local title = table.concat(parts, " ")
	title = (string.gsub(title, "%s+", " "))
	title = string.match(title, "^%s*(.-)%s*$") or ""
	return title
end

function When.parseWhen(text: any, now: number): { [string]: any }
	local raw = if text == nil then "" else tostring(text)
	local words = splitWords(raw)
	local state: State = { words = words, used = {} }
	for i = 1, #words do
		state.used[i] = false
	end

	local todayIso = Dates.isoDate(now)
	local todayEpoch = Dates.parseIsoDate(todayIso) :: number

	local date = parseDay(state, todayEpoch)
	local times = parseTimes(state)
	if date == nil and times.start ~= nil then
		local nowParts = os.date("*t", now) :: { hour: number, min: number }
		local nowMinutes = nowParts.hour * 60 + nowParts.min
		local startMinutes = Dates.minutesOf(times.start) :: number
		local past = startMinutes <= nowMinutes
		date = Dates.isoDate(if past then Dates.addDays(todayEpoch, 1) else todayEpoch)
	end

	return {
		title = rebuildTitle(state),
		date = date,
		start = times.start,
		["end"] = times["end"],
	}
end

return When

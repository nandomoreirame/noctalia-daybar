--!strict
-- data.json schema, parsing and migration. Pure: file I/O and the JSON codec
-- live in the service (the decoder/encoder are passed in).
-- Tasks carry `source`/`externalId` so a future Google Tasks sync can map them.
-- v2: links were replaced by bookmarks; v1 links/notes are dropped (test data).

local Tabs = require("./tabs.luau")
local Timers = require("./timers.luau")
local Tbl = require("./tbl.luau")

local Store = {}

Store.VERSION = 2

-- Clock forms that reopen after a restart.
local UI_FLAGS = { "clockOverlay" }

function Store.createEmpty(): { [string]: any }
	return {
		version = Store.VERSION,
		tasks = {},
		eventChecks = {},
		reminders = {},
		bookmarks = {},
		notes = {},
		focusLog = {},
		recentTimers = {},
		ui = { lastTab = "", clockOverlay = false },
	}
end

-- JS truthiness: nil, false, "", 0 and NaN are falsy.
local function truthy(v: any): boolean
	if v == nil or v == false or v == "" or v == 0 then
		return false
	end
	if typeof(v) == "number" and v ~= v then
		return false
	end
	return true
end

local function orNil(v: any): any
	return if truthy(v) then v else nil
end

-- A JSON array as a 1-based sequence. JSON objects (an empty `{}` is how an
-- empty list round-trips through the encoder) and scalars become {}. Holes left
-- by null entries are skipped, keeping index order.
local function list(value: any): { any }
	if typeof(value) ~= "table" then
		return {}
	end
	local keys = {}
	for k in value :: { [any]: any } do
		if typeof(k) ~= "number" or k ~= math.floor(k) or k < 1 then
			return {}
		end
		table.insert(keys, k)
	end
	table.sort(keys)
	local out = {}
	for _, k in ipairs(keys) do
		table.insert(out, (value :: { [any]: any })[k])
	end
	return out
end

-- True for a table with no positive integer keys (a JSON object, possibly empty).
local function isObject(value: any): boolean
	if typeof(value) ~= "table" then
		return false
	end
	for k in value :: { [any]: any } do
		if typeof(k) ~= "string" then
			return false
		end
	end
	return true
end

local function toNumber(v: any): number
	if typeof(v) == "boolean" then
		return if v then 1 else 0
	end
	local n = tonumber(v)
	if n == nil or n ~= n then
		return 0
	end
	return n
end

local function normalizeTask(t: any): { [string]: any }
	return {
		id = tostring(t.id),
		title = if truthy(t.title) then tostring(t.title) else "",
		date = orNil(t.date),
		time = orNil(t.time),
		done = truthy(t.done),
		doneAt = orNil(t.doneAt),
		pomodoros = toNumber(t.pomodoros),
		source = if truthy(t.source) then t.source else "local",
		externalId = orNil(t.externalId),
		createdAt = orNil(t.createdAt),
	}
end

-- Keeps only "YYYY-MM-DD": positive integer pairs.
local function normalizeFocusLog(log: any): { [string]: number }
	local out: { [string]: number } = {}
	if not isObject(log) then
		return out
	end
	for date, n in log :: { [string]: any } do
		if
			string.match(date, "^%d%d%d%d%-%d%d%-%d%d$")
			and typeof(n) == "number"
			and n == math.floor(n)
			and n > 0
			and n ~= math.huge
		then
			out[date] = n
		end
	end
	return out
end

local function normalizeUi(ui: any): { [string]: any }
	local src = if typeof(ui) == "table" then ui else {}
	local out: { [string]: any } = { lastTab = if Tabs.isTab(src.lastTab) then src.lastTab else "" }
	for _, key in ipairs(UI_FLAGS) do
		out[key] = src[key] == true
	end
	return out
end

-- Same table back when nothing changes, so toggling to the current state does not
-- schedule a write. A missing flag counts as false.
function Store.setUiFlag(data: { [string]: any }, key: string, value: any): { [string]: any }
	if not Tbl.contains(UI_FLAGS, key) then
		return data
	end
	local ui = data.ui or {}
	local v = truthy(value)
	if truthy(ui[key]) == v then
		return data
	end
	return Tbl.merge(data, { ui = Tbl.merge(ui, { [key] = v }) })
end

-- A fetch cannot survive a restart; a bookmark still "pending" on load failed.
local function normalizeBookmark(b: any): any
	if b.status == "pending" then
		return Tbl.merge(b, { status = "failed" })
	end
	return b
end

local function hasId(item: any): boolean
	return typeof(item) == "table" and item.id ~= nil
end

local function migrate(raw: { [string]: any }): { [string]: any }
	local isV2 = typeof(raw.version) == "number" and raw.version >= 2
	local tasks = {}
	for _, t in ipairs(list(raw.tasks)) do
		if typeof(t) == "table" and t.id ~= nil then
			table.insert(tasks, normalizeTask(t))
		end
	end
	local bookmarks = {}
	local notes = {}
	if isV2 then
		for _, b in ipairs(list(raw.bookmarks)) do
			if hasId(b) then
				table.insert(bookmarks, normalizeBookmark(b))
			end
		end
		notes = Tbl.filter(list(raw.notes), hasId)
	end
	return {
		version = Store.VERSION,
		tasks = tasks,
		eventChecks = if isObject(raw.eventChecks) then raw.eventChecks else {},
		reminders = list(raw.reminders),
		bookmarks = bookmarks,
		notes = notes,
		focusLog = normalizeFocusLog(raw.focusLog),
		recentTimers = Timers.normalizeRecent(list(raw.recentTimers)),
		ui = normalizeUi(raw.ui),
	}
end

-- Returns { data, corrupt }. Empty/missing text is a fresh store, not corruption.
-- `decode` is the host JSON decoder: value, or nil plus an error.
function Store.parse(text: any, decode: (string) -> (any, string?)): { data: { [string]: any }, corrupt: boolean }
	if text == nil or string.match(tostring(text), "^%s*$") then
		return { data = Store.createEmpty(), corrupt = false }
	end
	local ok, raw = pcall(decode, tostring(text))
	if not ok or not isObject(raw) then
		return { data = Store.createEmpty(), corrupt = true }
	end
	return { data = migrate(raw), corrupt = false }
end

-- `encode` is the host JSON encoder (value, pretty) -> string.
function Store.serialize(data: { [string]: any }, encode: (any, boolean?) -> (string?, string?)): string
	local text, err = encode(data, true)
	if text == nil then
		error("store: cannot encode data: " .. tostring(err), 2)
	end
	return text .. "\n"
end

local DIGITS = "0123456789abcdefghijklmnopqrstuvwxyz"

-- Non-negative integer in base 36 (fraction dropped).
function Store.toBase36(n: number): string
	local v = math.floor(math.max(n, 0))
	if v == 0 then
		return "0"
	end
	local out = {}
	while v > 0 do
		local d = v % 36
		table.insert(out, 1, string.sub(DIGITS, d + 1, d + 1))
		v = math.floor(v / 36)
	end
	return table.concat(out)
end

-- Collision-resistant id: time base36 + random base36. `rand` is injectable for tests.
function Store.makeId(nowMs: number, rand: number): string
	return Store.toBase36(nowMs) .. "-" .. Store.toBase36(math.floor(rand * 1e9))
end

return Store

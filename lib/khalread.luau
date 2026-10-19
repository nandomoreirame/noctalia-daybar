--!strict
-- `khal list --json ...` output (one JSON array per line, see Khal.listArgs)
-- to calendar events in the shared Event shape:
--   { uid, calendar, summary, start, ["end"], allDay, location, url, description, repeats }
-- start/end are epoch seconds in local time; an all-day end is exclusive (next midnight).
-- `decode` is the host JSON decoder, passed in so lib stays host-free.

local Dates = require("./dates.luau")

local KhalRead = {}

local function str(value: any): string
	if value == nil then
		return ""
	end
	return tostring(value)
end

local function trim(s: string): string
	return (string.match(s, "^%s*(.-)%s*$") :: string)
end

local function isSequence(value: any): boolean
	if typeof(value) ~= "table" then
		return false
	end
	for k in value :: { [any]: any } do
		if typeof(k) ~= "number" then
			return false
		end
	end
	return true
end

local function isAllDay(value: any): boolean
	return value == true or string.lower(str(value)) == "true"
end

local function validTime(value: any): boolean
	return Dates.minutesOf(value) ~= nil
end

-- One khal item to an Event, or nil when it lacks a uid or a readable start.
local function toEvent(item: any): { [string]: any }?
	if typeof(item) ~= "table" then
		return nil
	end
	local uid = str(item.uid)
	if uid == "" then
		return nil
	end
	local startDate = str(item["start-date"])
	if Dates.parseIsoDate(startDate) == nil then
		return nil
	end
	local endDate = str(item["end-date"])
	if Dates.parseIsoDate(endDate) == nil then
		endDate = startDate
	end
	local allDay = isAllDay(item["all-day"])
	local start: number
	local endsAt: number
	if allDay then
		start = Dates.parseIsoDate(startDate) :: number
		endsAt = Dates.addDays(Dates.parseIsoDate(endDate) :: number, 1)
	else
		local startTime = str(item["start-time"])
		if not validTime(startTime) then
			return nil
		end
		start = Dates.toDate(startDate, startTime)
		local endTime = str(item["end-time"])
		endsAt = if validTime(endTime) then Dates.toDate(endDate, endTime) else start
	end
	return {
		uid = uid,
		calendar = str(item.calendar),
		summary = str(item.title),
		start = start,
		["end"] = endsAt,
		allDay = allDay,
		location = str(item.location),
		url = str(item.url),
		description = str(item.description),
		repeats = trim(str(item["repeat-symbol"])) ~= "",
	}
end

function KhalRead.parse(stdout: any, decode: (string) -> (any, string?)): { { [string]: any } }
	local events: { { order: number, ev: { [string]: any } } } = {}
	local seen: { [string]: boolean } = {}
	for line in string.gmatch(str(stdout), "[^\n]+") do
		if trim(line) ~= "" then
			local ok, items = pcall(decode, line)
			if ok and isSequence(items) then
				for _, item in ipairs(items :: { any }) do
					local ev = toEvent(item)
					if ev ~= nil then
						local key = ev.uid .. "|" .. tostring(ev.start)
						if not seen[key] then
							seen[key] = true
							table.insert(events, { order = #events + 1, ev = ev })
						end
					end
				end
			end
		end
	end
	table.sort(events, function(a: any, b: any): boolean
		if a.ev.start ~= b.ev.start then
			return a.ev.start < b.ev.start
		end
		return a.order < b.order
	end)
	local out = {}
	for i, e in ipairs(events) do
		out[i] = e.ev
	end
	return out
end

return KhalRead

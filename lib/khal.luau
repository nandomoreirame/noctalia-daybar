--!strict
-- argv builders for khal/vdirsyncer. Always a sequence (noctalia.runAsync argv
-- form), never a shell string, so user text cannot inject commands or options.
-- Requires khal's [locale] formats set to ISO (see README):
--   dateformat = %Y-%m-%d, timeformat = %H:%M, datetimeformat = %Y-%m-%d %H:%M

local Khal = {}

-- Fields requested from `khal list --json`, in output order.
Khal.LIST_FIELDS = {
	"uid",
	"title",
	"calendar",
	"all-day",
	"start-date",
	"start-time",
	"end-date",
	"end-time",
	"location",
	"url",
	"description",
	"repeat-symbol",
}

local function str(value: any): string
	if value == nil then
		return ""
	end
	return tostring(value)
end

local function trim(s: string): string
	return (string.match(s, "^%s*(.-)%s*$") :: string)
end

function Khal.sanitizeSummary(title: any): string
	local s = (string.gsub(str(title), "::+", ":"))
	s = (string.gsub(s, "%s+", " "))
	return trim(s)
end

-- ev: { calendar, date, start, endDate, endTime, title, alarm }
function Khal.newEventArgs(ev: { [string]: any }): { string }
	local args = { "khal", "new" }
	if ev.calendar ~= nil and ev.calendar ~= "" then
		table.insert(args, "-a")
		table.insert(args, tostring(ev.calendar))
	end
	if ev.alarm then
		table.insert(args, "--alarms")
		table.insert(args, "0m")
	end
	table.insert(args, "--")
	table.insert(args, str(ev.date) .. " " .. str(ev.start))
	table.insert(args, str(ev.endDate) .. " " .. str(ev.endTime))
	table.insert(args, Khal.sanitizeSummary(ev.title))
	return args
end

-- `khal list` over [from, to] ("YYYY-MM-DD"), one JSON array per line.
function Khal.listArgs(from: string, to: string): { string }
	local args = { "khal", "list" }
	for _, field in ipairs(Khal.LIST_FIELDS) do
		table.insert(args, "--json")
		table.insert(args, field)
	end
	table.insert(args, from)
	table.insert(args, to)
	return args
end

function Khal.syncArgs(): { string }
	return { "vdirsyncer", "sync" }
end

function Khal.printCalendarsArgs(): { string }
	return { "khal", "printcalendars" }
end

-- `khal printcalendars` prints one calendar name per line.
function Khal.parseCalendars(stdout: any): { string }
	local out = {}
	for line in string.gmatch(str(stdout), "[^\n]+") do
		local name = trim(line)
		if name ~= "" then
			table.insert(out, name)
		end
	end
	return out
end

return Khal

--!strict
-- Deleting a synced event = removing its .ics file from the khal/vdirsyncer vdir,
-- then syncing. Pure helpers; the service runs the commands (argv arrays only).
-- Delete itself uses noctalia.removeFile; read uses noctalia.readFile.

local Tbl = require("./tbl.luau")

local EventDelete = {}

function EventDelete.expandHome(path: any, home: string): string
	local p = tostring(path or "")
	if string.sub(p, 1, 2) == "~/" then
		return home .. string.sub(p, 2)
	end
	if string.sub(p, 1, 6) == "$HOME/" then
		return home .. string.sub(p, 6)
	end
	if string.sub(p, 1, 8) == "${HOME}/" then
		return home .. string.sub(p, 8)
	end
	return p
end

local function normalizeRootPath(raw: any, home: string): string
	local p = tostring(raw or "")
	p = (string.gsub(p, "^['\"]", ""))
	p = (string.gsub(p, "['\"]$", ""))
	p = EventDelete.expandHome(p, home)
	-- Trailing slashes first so "dir/*/" becomes "dir/*", then strip /*, then
	-- trailing slashes again.
	p = (string.gsub(p, "/+$", ""))
	p = (string.gsub(p, "/%*$", ""))
	p = (string.gsub(p, "/+$", ""))
	return p
end

-- Roots from every `path = ...` line of the khal config ("~" / $HOME expanded,
-- "/*" stripped).
function EventDelete.calendarRoots(configText: any, home: string): { string }
	local roots: { string } = {}
	for line in string.gmatch(tostring(configText or "") .. "\n", "(.-)\r?\n") do
		local value = string.match(line, "^%s*path%s*=%s*(.-)%s*$")
		if value then
			local p = normalizeRootPath(value, home)
			if string.sub(p, 1, 1) == "/" and not Tbl.contains(roots, p) then
				table.insert(roots, p)
			end
		end
	end
	return roots
end

-- [[name]] sections under [calendars]: [{ name, path, type }].
function EventDelete.calendarSections(configText: any, home: string): { { [string]: any } }
	local sections: { { [string]: any } } = {}
	local current: { [string]: any }? = nil
	for line in string.gmatch(tostring(configText or "") .. "\n", "(.-)\r?\n") do
		local name = string.match(line, "^%s*%[%[([^%]]+)%]%]%s*$")
		if name then
			current = { name = name, path = "", type = "" }
			table.insert(sections, current)
		elseif current then
			local path = string.match(line, "^%s*path%s*=%s*(.-)%s*$")
			if path then
				current.path = normalizeRootPath(path, home)
			else
				local typeVal = string.match(line, "^%s*type%s*=%s*(.-)%s*$")
				if typeVal then
					typeVal = (string.gsub(typeVal, "^['\"]", ""))
					typeVal = (string.gsub(typeVal, "['\"]$", ""))
					typeVal = (string.match(typeVal, "^%s*(.-)%s*$")) or typeVal
					current.type = typeVal
				end
			end
		end
	end
	return Tbl.filter(sections, function(s)
		return string.sub(tostring(s.path), 1, 1) == "/"
	end)
end

function EventDelete.collectionsArgs(roots: { string }): { string }
	local args = { "grep", "-rH", "--include=displayname", "", "--" }
	for _, r in ipairs(roots) do
		table.insert(args, r)
	end
	return args
end

-- "<dir>/displayname:<name>" lines -> [{ dir, id, name }]. When a collection
-- dir equals a type=calendar section path, the section name wins.
function EventDelete.parseCollections(stdout: any, sections: { { [string]: any } }?): { { [string]: any } }
	local out: { { [string]: any } } = {}
	local byDir: { [string]: { [string]: any } } = {}
	for line in string.gmatch(tostring(stdout or "") .. "\n", "(.-)\n") do
		local i = string.find(line, "/displayname:", 1, true)
		if i and i > 1 then
			local dir = string.sub(line, 1, i - 1)
			local slash = string.find(dir, "/[^/]*$")
			local id = if slash then string.sub(dir, slash + 1) else dir
			local col = {
				dir = dir,
				id = id,
				name = string.sub(line, i + #"/displayname:"),
			}
			col.name = (string.match(col.name, "^%s*(.-)%s*$")) or col.name
			table.insert(out, col)
			byDir[dir] = col
		end
	end
	local list = sections or {}
	for _, s in ipairs(list) do
		if s.type == "calendar" then
			local existing = byDir[s.path]
			if existing then
				existing.name = s.name
			else
				local slash = string.find(s.path, "/[^/]*$")
				local id = if slash then string.sub(s.path :: string, slash + 1) else s.path
				local col = { dir = s.path, id = id, name = s.name }
				table.insert(out, col)
				byDir[s.path] = col
			end
		end
	end
	return out
end

-- Google's generated calendars (holidays, birthdays, ICS subscriptions, shared
-- group calendars) reject writes.
function EventDelete.isReadOnlyCollection(id: any): boolean
	local s = tostring(id or "")
	if string.match(string.lower(s), "@virtual$") then
		return true
	end
	if string.find(string.lower(s), "#holiday", 1, true) then
		return true
	end
	if string.find(string.lower(s), "#contacts@group.v.calendar.google.com", 1, true) then
		return true
	end
	if string.match(string.lower(s), "@import%.calendar%.google%.com$") then
		return true
	end
	if string.match(string.lower(s), "@group%.v%.calendar%.google%.com$") then
		return true
	end
	return false
end

function EventDelete.isWritableCalendar(collections: { { [string]: any } }, calendarName: string): boolean
	for _, c in ipairs(collections) do
		if c.name == calendarName and not EventDelete.isReadOnlyCollection(c.id) then
			return true
		end
	end
	return false
end

-- True only when the name is known and every collection carrying it is read-only;
-- unknown calendars (collections not loaded, no khal config) stay writable.
function EventDelete.isReadOnlyCalendar(collections: { { [string]: any } }?, calendarName: string): boolean
	local matching = Tbl.filter(collections or {}, function(c)
		return c.name == calendarName
	end)
	if #matching == 0 then
		return false
	end
	for _, c in ipairs(matching) do
		if not EventDelete.isReadOnlyCollection(c.id) then
			return false
		end
	end
	return true
end

function EventDelete.escapeRegex(text: any): string
	return (string.gsub(tostring(text), "([%^%$%(%)%%%.%[%]%*%+%-%?])", "\\%1"))
end

-- Fixed-string grep for the UID property value (REQ-019 / grep -rlF).
function EventDelete.findArgs(uid: string, roots: { string }): { string }
	local args = { "grep", "-rlF", "--include=*.ics", "--", "UID:" .. uid }
	for _, r in ipairs(roots) do
		table.insert(args, r)
	end
	return args
end

function EventDelete.parsePaths(stdout: any): { string }
	local out: { string } = {}
	for line in string.gmatch(tostring(stdout or "") .. "\n", "(.-)\n") do
		local trimmed = (string.match(line, "^%s*(.-)%s*$")) or line
		if string.match(trimmed, "^/.+%.ics$") then
			table.insert(out, trimmed)
		end
	end
	return out
end

local function dirOf(path: string): string
	local slash = string.find(path, "/[^/]*$")
	if slash then
		return string.sub(path, 1, slash - 1)
	end
	return path
end

-- Require the file's directory to be a collection whose name equals the event's
-- calendar; refuse read-only collections. One or many grep hits share this rule.
function EventDelete.pickFile(
	paths: { string },
	collections: { { [string]: any } },
	calendarName: string
): { [string]: any }
	if #paths == 0 then
		return { ok = false, error = "not-found" }
	end
	local matching = Tbl.filter(collections, function(c)
		return c.name == calendarName
	end)
	local dirs = Tbl.map(matching, function(c)
		return c.dir
	end)
	local hits = Tbl.filter(paths, function(p)
		return Tbl.contains(dirs, dirOf(p))
	end)
	if #hits ~= 1 then
		return { ok = false, error = "ambiguous" }
	end
	local col = Tbl.find(matching, function(c)
		return c.dir == dirOf(hits[1])
	end)
	if col and EventDelete.isReadOnlyCollection(col.id) then
		return { ok = false, error = "read-only" }
	end
	return { ok = true, path = hits[1] }
end

-- Like pickFile, for reading only: read-only calendars are fine. `self` is the
-- collection id, which for Google calendars is the owner's address.
function EventDelete.pickReadable(
	paths: { string },
	collections: { { [string]: any } },
	calendarName: string
): { [string]: any }
	if #paths == 0 then
		return { ok = false, error = "not-found" }
	end
	local matching = Tbl.filter(collections, function(c)
		return c.name == calendarName
	end)
	local hits = Tbl.filter(paths, function(p)
		local d = dirOf(p)
		for _, c in ipairs(matching) do
			if c.dir == d then
				return true
			end
		end
		return false
	end)
	if #hits ~= 1 then
		return { ok = false, error = "ambiguous" }
	end
	local col = Tbl.find(matching, function(c)
		return c.dir == dirOf(hits[1])
	end)
	return { ok = true, path = hits[1], self = col.id }
end

-- Property names start a line inside a VEVENT; RRULE in VTIMEZONE must not count.
function EventDelete.isRecurring(icsText: any): boolean
	local text = tostring(icsText or "")
	local pos = 1
	while true do
		local beginAt = string.find(string.upper(string.sub(text, pos)), "BEGIN:VEVENT", 1, true)
		if not beginAt then
			break
		end
		beginAt = pos + beginAt - 1
		local afterBegin = beginAt + #"BEGIN:VEVENT"
		local endRel = string.find(string.upper(string.sub(text, afterBegin)), "END:VEVENT", 1, true)
		if not endRel then
			break
		end
		local block = string.sub(text, afterBegin, afterBegin + endRel - 2)
		-- Match ^(RRULE|RECURRENCE-ID)[;:] at line start.
		for line in string.gmatch(block .. "\n", "(.-)\r?\n") do
			local upper = string.upper(line)
			if string.match(upper, "^RRULE[;:]") or string.match(upper, "^RECURRENCE%-ID[;:]") then
				return true
			end
		end
		pos = afterBegin + endRel + #"END:VEVENT" - 1
	end
	return false
end

-- Resolve . and .. segments; return nil when the path escapes above root or has NUL.
local function normalizePath(path: string): string?
	if string.find(path, "\0", 1, true) then
		return nil
	end
	if string.sub(path, 1, 1) ~= "/" then
		return nil
	end
	local parts: { string } = {}
	for seg in string.gmatch(path, "[^/]+") do
		if seg == ".." then
			if #parts == 0 then
				return nil
			end
			table.remove(parts)
		elseif seg ~= "." then
			table.insert(parts, seg)
		end
	end
	return "/" .. table.concat(parts, "/")
end

function EventDelete.isDeletablePath(path: any, roots: { string }): boolean
	local p = tostring(path or "")
	if not string.match(p, "%.ics$") then
		return false
	end
	if string.find(p, "\0", 1, true) then
		return false
	end
	-- Reject literal dot segments before normalize (parity with v4).
	if string.find(p, "/%.%./") or string.find(p, "/%./") or string.match(p, "^%.%./") or string.match(p, "/%.%.$") then
		return false
	end
	if string.match(p, "^%./") or p == ".." or p == "." then
		return false
	end
	local normalized = normalizePath(p)
	if normalized == nil then
		return false
	end
	-- Also require the raw path to sit under a root (no prefix tricks).
	for _, r in ipairs(roots) do
		if string.sub(p, 1, #r + 1) == r .. "/" then
			local normRoot = normalizePath(r)
			if normRoot and string.sub(normalized, 1, #normRoot + 1) == normRoot .. "/" then
				return true
			end
		end
	end
	return false
end

-- Checks are keyed by uid only (no calendar on the check record).
function EventDelete.removeEventChecks(data: { [string]: any }, uid: string): { [string]: any }
	local checks: { [string]: any } = {}
	local prefix = uid .. "|"
	for key, value in data.eventChecks or {} do
		if string.sub(tostring(key), 1, #prefix) ~= prefix then
			checks[key] = value
		end
	end
	return Tbl.merge(data, { eventChecks = checks })
end

function EventDelete.eventKey(uid: any, calendar: any): string
	return tostring(uid or "") .. "\u{0001}" .. tostring(calendar or "")
end

-- Same array back when nothing is hidden, so bindings do not churn. Keys are
-- eventKey(uid, calendar); an event is hidden only when both match.
function EventDelete.hideEvents(events: { any }?, hiddenKeys: { string }): { any }
	if not events then
		return {}
	end
	if #hiddenKeys == 0 then
		return events
	end
	return Tbl.filter(events, function(ev)
		return not Tbl.contains(hiddenKeys, EventDelete.eventKey(ev.uid, ev.calendar))
	end)
end

return EventDelete

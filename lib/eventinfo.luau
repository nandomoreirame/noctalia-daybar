--!strict
-- Details that the calendar service does not pass on, read from the event's
-- .ics file: who is in it, the Meet link and the location.
-- -> { people: [{ name, email, status }], meetUrl, location }

local EventInfo = {}

-- RFC 5545 folding: a line break followed by a space or tab continues the line.
function EventInfo.unfold(text: any): string
	local s = tostring(text or "")
	s = (string.gsub(s, "\r\n[ \t]", ""))
	s = (string.gsub(s, "\n[ \t]", ""))
	return s
end

local function unescapeText(value: string): string
	local s = (string.gsub(value, "\\[Nn]", " "))
	s = (string.gsub(s, "\\([,;\\])", "%1"))
	s = (string.match(s, "^%s*(.-)%s*$")) or s
	return s
end

-- "NAME;P1=a;P2=\"b, c\":value" -> { name, params, value }; the value starts at the
-- first colon outside quotes, since quoted parameters may contain colons.
local function parseLine(line: string): { name: string, params: { [string]: string }, value: string }
	local inQuote = false
	local i = 0
	local len = #line
	while i < len do
		i += 1
		local ch = string.sub(line, i, i)
		if ch == '"' then
			inQuote = not inQuote
		elseif ch == ":" and not inQuote then
			break
		end
	end
	local head = string.sub(line, 1, i - 1)
	local value = string.sub(line, i + 1)
	-- Split on ; outside quotes (same as /(?:[^;"]|"[^"]*")+/g).
	local parts: { string } = {}
	do
		local pos = 1
		local headLen = #head
		while pos <= headLen do
			local chunk = ""
			while pos <= headLen do
				local ch = string.sub(head, pos, pos)
				if ch == '"' then
					local close = string.find(head, '"', pos + 1, true)
					if close then
						chunk ..= string.sub(head, pos, close)
						pos = close + 1
					else
						chunk ..= string.sub(head, pos)
						pos = headLen + 1
					end
				elseif ch == ";" then
					pos += 1
					break
				else
					chunk ..= ch
					pos += 1
				end
			end
			if chunk ~= "" then
				table.insert(parts, chunk)
			end
		end
	end
	local params: { [string]: string } = {}
	for idx = 2, #parts do
		local part = parts[idx]
		local eq = string.find(part, "=", 1, true)
		if eq and eq > 1 then
			local key = string.upper(string.sub(part, 1, eq - 1))
			local val = string.sub(part, eq + 1)
			val = (string.gsub(val, '^"(.*)"$', "%1"))
			params[key] = val
		end
	end
	local name = string.upper(parts[1] or "")
	return { name = name, params = params, value = value }
end

local function isHttpsUrl(url: string): boolean
	-- Mirrors /^https:\/\/\S+$/
	if string.sub(url, 1, 8) ~= "https://" then
		return false
	end
	local rest = string.sub(url, 9)
	if rest == "" then
		return false
	end
	if string.find(rest, "%s") then
		return false
	end
	return true
end

-- People are the organizer and the attendees, once each, without the calendar owner
-- (selfEmail) and without rooms or resources.
function EventInfo.parseEventInfo(icsText: any, selfEmail: any): { [string]: any }
	local info: { [string]: any } = { people = {}, meetUrl = "", location = "" }
	local unfolded = EventInfo.unfold(icsText)
	local beginAt = string.find(string.upper(unfolded), "BEGIN:VEVENT", 1, true)
	if not beginAt then
		return info
	end
	local afterBegin = beginAt + #"BEGIN:VEVENT"
	local endRel = string.find(string.upper(string.sub(unfolded, afterBegin)), "END:VEVENT", 1, true)
	if not endRel then
		return info
	end
	local block = string.sub(unfolded, afterBegin, afterBegin + endRel - 2)
	local selfAddr = string.lower(tostring(selfEmail or ""))
	local seen: { [string]: boolean } = {}
	for raw in string.gmatch(block .. "\n", "(.-)\r?\n") do
		if raw ~= "" then
			local line = parseLine(raw)
			if line.name == "ORGANIZER" or line.name == "ATTENDEE" then
				local email = (string.gsub(line.value, "^[Mm][Aa][Ii][Ll][Tt][Oo]:", ""))
				email = (string.match(email, "^%s*(.-)%s*$")) or email
				local key = string.lower(email)
				local kind = string.upper(line.params.CUTYPE or "INDIVIDUAL")
				if email ~= "" and key ~= selfAddr and not seen[key] and (kind == "INDIVIDUAL" or kind == "GROUP") then
					seen[key] = true
					local status = line.params.PARTSTAT
						or (if line.name == "ORGANIZER" then "ACCEPTED" else "NEEDS-ACTION")
					table.insert(info.people, {
						name = line.params.CN or email,
						email = email,
						status = string.lower(status),
					})
				end
			elseif line.name == "X-GOOGLE-CONFERENCE" then
				local url = (string.match(line.value, "^%s*(.-)%s*$")) or line.value
				if isHttpsUrl(url) then
					info.meetUrl = url
				end
			elseif line.name == "LOCATION" then
				info.location = unescapeText(line.value)
			end
		end
	end
	return info
end

return EventInfo

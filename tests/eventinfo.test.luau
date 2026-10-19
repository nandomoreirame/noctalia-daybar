local assert = require("./support/assert")
local runner = require("./support/runner")
local modules = require("./support/modules")

local describe, it = runner.describe, runner.it
local EventInfo = modules.load("lib/eventinfo.luau")

local ics = table.concat({
	"BEGIN:VCALENDAR",
	"BEGIN:VEVENT",
	"DTSTART;TZID=America/Sao_Paulo:20261013T160000",
	"ORGANIZER;CN=Ana Souza:mailto:ana@acme.com",
	"ATTENDEE;CUTYPE=INDIVIDUAL;ROLE=REQ-PARTICIPANT;PARTSTAT=ACCEPTED;CN=Ana Souza:mailto:ana@acme.com",
	"ATTENDEE;CUTYPE=INDIVIDUAL;ROLE=REQ-PARTICIPANT;PARTSTAT=ACCEPTED;CN=me@x.com:mailto:me@x.com",
	"ATTENDEE;CUTYPE=INDIVIDUAL;PARTSTAT=DECLINED;CN=\"Silva, Bruno\";X-NUM-GUESTS=0:mailto:bruno@acme.com",
	"ATTENDEE;CUTYPE=INDIVIDUAL;PARTSTAT=NEEDS-ACTION;CN=carla@acme.com:mailto:carla@acme.com",
	"ATTENDEE;CUTYPE=RESOURCE;PARTSTAT=ACCEPTED;CN=Sala 3:mailto:sala3@resource.calendar.google.com",
	"X-GOOGLE-CONFERENCE:https://meet.google.com/abc-defg-hij",
	"LOCATION:Escritório\\, sala 2",
	"END:VEVENT",
	"END:VCALENDAR",
}, "\r\n")

describe("unfold", function()
	it("joins folded lines (CRLF or LF followed by a space or tab)", function()
		assert.equal(
			EventInfo.unfold("ATTENDEE;CN=Very Long\r\n  Name:mailto:x@y.z\nNEXT:1"),
			"ATTENDEE;CN=Very Long Name:mailto:x@y.z\nNEXT:1"
		)
	end)
end)

describe("parseEventInfo", function()
	it("lists organizer and attendees once, without the calendar owner or rooms", function()
		assert.same(EventInfo.parseEventInfo(ics, "ME@x.com").people, {
			{ name = "Ana Souza", email = "ana@acme.com", status = "accepted" },
			{ name = "Silva, Bruno", email = "bruno@acme.com", status = "declined" },
			{ name = "carla@acme.com", email = "carla@acme.com", status = "needs-action" },
		})
	end)

	it("reads the Meet link and the location", function()
		local info = EventInfo.parseEventInfo(ics, "me@x.com")
		assert.equal(info.meetUrl, "https://meet.google.com/abc-defg-hij")
		assert.equal(info.location, "Escritório, sala 2")
	end)

	it("drops a conference value that is not an https link", function()
		local bad = (string.gsub(ics, "https://meet.google.com/abc%-defg%-hij", "javascript:alert(1)", 1))
		assert.equal(EventInfo.parseEventInfo(bad, "me@x.com").meetUrl, "")
	end)

	it("reads only the first VEVENT and copes with empty input", function()
		local two = (string.gsub(
			ics,
			"END:VCALENDAR",
			"BEGIN:VEVENT\r\nORGANIZER;CN=Zé:mailto:ze@acme.com\r\nEND:VEVENT\r\nEND:VCALENDAR",
			1
		))
		local emails = {}
		for _, p in ipairs(EventInfo.parseEventInfo(two, "me@x.com").people) do
			table.insert(emails, p.email)
		end
		local hasZe = false
		for _, e in ipairs(emails) do
			if e == "ze@acme.com" then
				hasZe = true
			end
		end
		assert.equal(hasZe, false)
		assert.same(EventInfo.parseEventInfo("", "me@x.com"), { people = {}, meetUrl = "", location = "" })
		assert.same(EventInfo.parseEventInfo(nil, ""), { people = {}, meetUrl = "", location = "" })
	end)
end)

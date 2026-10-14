import { describe, it, expect } from "vitest";
import { parseEventInfo, unfold } from "../utils/eventinfo.js";

const ics = [
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
  "END:VCALENDAR"
].join("\r\n");

describe("unfold", () => {
  it("joins folded lines (CRLF or LF followed by a space or tab)", () => {
    expect(unfold("ATTENDEE;CN=Very Long\r\n  Name:mailto:x@y.z\nNEXT:1")).toBe("ATTENDEE;CN=Very Long Name:mailto:x@y.z\nNEXT:1");
  });
});

describe("parseEventInfo", () => {
  it("lists organizer and attendees once, without the calendar owner or rooms", () => {
    expect(parseEventInfo(ics, "ME@x.com").people).toEqual([
      { name: "Ana Souza", email: "ana@acme.com", status: "accepted" },
      { name: "Silva, Bruno", email: "bruno@acme.com", status: "declined" },
      { name: "carla@acme.com", email: "carla@acme.com", status: "needs-action" }
    ]);
  });

  it("reads the Meet link and the location", () => {
    const info = parseEventInfo(ics, "me@x.com");
    expect(info.meetUrl).toBe("https://meet.google.com/abc-defg-hij");
    expect(info.location).toBe("Escritório, sala 2");
  });

  it("drops a conference value that is not an https link", () => {
    const bad = ics.replace("https://meet.google.com/abc-defg-hij", "javascript:alert(1)");
    expect(parseEventInfo(bad, "me@x.com").meetUrl).toBe("");
  });

  it("reads only the first VEVENT and copes with empty input", () => {
    const two = ics.replace("END:VCALENDAR", "BEGIN:VEVENT\r\nORGANIZER;CN=Zé:mailto:ze@acme.com\r\nEND:VEVENT\r\nEND:VCALENDAR");
    expect(parseEventInfo(two, "me@x.com").people.map((p) => p.email)).not.toContain("ze@acme.com");
    expect(parseEventInfo("", "me@x.com")).toEqual({ people: [], meetUrl: "", location: "" });
    expect(parseEventInfo(null, "")).toEqual({ people: [], meetUrl: "", location: "" });
  });
});

--!strict
-- Builds the plain `view` value the service publishes on noctalia.state (REQ-010).
-- Data goes out without `version`; bookmarks carry `thumbPath` when the thumb file
-- exists. The source tables are never mutated.

local Tbl = require("./tbl.luau")

local View = {}

local function bookmarksWithThumbs(
	bookmarks: any,
	thumbExists: ((string) -> boolean)?,
	thumbDir: string?
): any
	if typeof(bookmarks) ~= "table" then
		return bookmarks
	end
	local out = {}
	for i, b in ipairs(bookmarks) do
		local copy = Tbl.merge(b, nil)
		copy.thumbPath = nil
		local id = copy.id
		if thumbExists ~= nil and thumbDir ~= nil and typeof(id) == "string" and id ~= "" and thumbExists(id) then
			copy.thumbPath = thumbDir .. "/" .. id
		end
		out[i] = copy
	end
	return out
end

function View.build(opts: { [string]: any }): { [string]: any }
	local data = Tbl.merge(if typeof(opts.data) == "table" then opts.data else nil, nil)
	data.version = nil
	if data.bookmarks ~= nil then
		data.bookmarks = bookmarksWithThumbs(data.bookmarks, opts.thumbExists, opts.thumbDir)
	end
	return {
		rev = opts.rev,
		now = opts.now,
		data = data,
		settings = opts.settings or {},
		calendar = opts.calendar or {},
		pomodoro = opts.pomodoro or {},
		timer = opts.timer or {},
		alarmSource = opts.alarmSource or "",
		focusPanel = opts.focusPanel or "pomodoro",
		requestedTab = opts.requestedTab,
		details = opts.details or {},
		deleting = opts.deleting or {},
		ringDir = opts.ringDir,
	}
end

return View

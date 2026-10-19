--!strict
-- Local reminder schedule. A reminder that became due while the shell was down
-- fires only if it is at most GRACE_MINUTES late; older ones expire silently.

local Dates = require("./dates.luau")
local Tbl = require("./tbl.luau")

local Reminders = {}

local GRACE_MINUTES = 10

function Reminders.addReminder(
	data: { [string]: any },
	fields: { [string]: any },
	id: string
): { [string]: any }
	local reminder = {
		id = id,
		title = fields.title,
		date = fields.date,
		time = fields.time,
		fired = false,
	}
	local reminders = Tbl.copyList(data.reminders or {})
	table.insert(reminders, reminder)
	return Tbl.merge(data, { reminders = reminders })
end

-- Returns { fire: [reminder], expire: [reminder] } for reminders not fired yet.
-- nowSeconds is epoch seconds (v5; v4 took a Date).
function Reminders.dueReminders(data: { [string]: any }, nowSeconds: number): { fire: { any }, expire: { any } }
	local fire = {}
	local expire = {}
	local graceSec = GRACE_MINUTES * 60
	for _, r in ipairs(data.reminders or {}) do
		if not r.fired then
			local at = Dates.toDate(r.date, r.time)
			if at <= nowSeconds then
				if nowSeconds - at <= graceSec then
					table.insert(fire, r)
				else
					table.insert(expire, r)
				end
			end
		end
	end
	return { fire = fire, expire = expire }
end

function Reminders.markFired(data: { [string]: any }, ids: { string }): { [string]: any }
	return Tbl.merge(data, {
		reminders = Tbl.map(data.reminders or {}, function(r)
			if Tbl.indexOf(ids, r.id) == nil then
				return r
			end
			return Tbl.merge(r, { fired = true })
		end),
	})
end

return Reminders

--!strict
-- Command outbox (AD-202). Each entry keeps an ordered queue of { seq, name, args }
-- published on `cmd.<entry>`; the service runs every seq it has not seen once, in
-- order, and answers on `ack.<entry>`; the entry trims what was acknowledged.
-- seq is seeded from nowMs * 1000 so a reopened entry never reuses an old seq.

local Outbox = {}

export type Command = { seq: number, name: string, args: { [string]: any } }
export type Client = { nextSeq: number, items: { Command } }
export type Server = { seen: { [string]: number } }

function Outbox.newClient(nowMs: number): Client
	return { nextSeq = nowMs * 1000, items = {} }
end

function Outbox.push(q: Client, name: string, args: { [string]: any }?): Command
	q.nextSeq += 1
	local cmd: Command = { seq = q.nextSeq, name = name, args = args or {} }
	table.insert(q.items, cmd)
	return cmd
end

-- Copy of the queue, ready to publish on `cmd.<entry>`.
function Outbox.pending(q: Client): { Command }
	local out = {}
	for i, cmd in ipairs(q.items) do
		out[i] = cmd
	end
	return out
end

-- Drops every command up to ack.seq (the service runs them in order). Returns
-- true when something was trimmed.
function Outbox.ack(q: Client, ack: any): boolean
	if typeof(ack) ~= "table" or typeof(ack.seq) ~= "number" then
		return false
	end
	local kept = {}
	for _, cmd in ipairs(q.items) do
		if cmd.seq > ack.seq then
			table.insert(kept, cmd)
		end
	end
	local trimmed = #kept ~= #q.items
	q.items = kept
	return trimmed
end

function Outbox.newServer(): Server
	return { seen = {} }
end

function Outbox.lastSeen(s: Server, entry: string): number
	return s.seen[entry] or 0
end

-- Commands in `list` not seen yet for `entry`, sorted by seq; remembers the highest.
-- Items without a numeric seq or a string name are skipped.
function Outbox.take(s: Server, entry: string, list: any): { any }
	if typeof(list) ~= "table" then
		return {}
	end
	local last = Outbox.lastSeen(s, entry)
	local fresh = {}
	for _, cmd in ipairs(list) do
		if typeof(cmd) == "table" and typeof(cmd.seq) == "number" and typeof(cmd.name) == "string" and cmd.seq > last then
			table.insert(fresh, cmd)
		end
	end
	table.sort(fresh, function(a, b)
		return a.seq < b.seq
	end)
	local out = {}
	for _, cmd in ipairs(fresh) do
		if cmd.seq > last then
			table.insert(out, cmd)
			last = cmd.seq
		end
	end
	s.seen[entry] = last
	return out
end

return Outbox

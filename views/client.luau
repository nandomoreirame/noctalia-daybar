--!strict
-- Entry side of the command outbox (AD-202). An entry pushes commands to
-- `cmd.<entry>`; the service answers on `ack.<entry>`, which trims the outbox and
-- calls the per-command callback. `state` is noctalia.state, `nowMs` the clock;
-- both come from the entry because modules do not see host globals.

local Outbox = require("../lib/outbox.luau")

local Client = {}

export type Client = {
	send: (name: string, args: { [string]: any }?, onAck: ((any) -> ())?) -> (),
}

function Client.new(state: any, nowMs: number, entryName: string): Client
	local q = Outbox.newClient(nowMs)
	local callbacks: { [number]: (any) -> () } = {}
	local cmdKey = "cmd." .. entryName

	state.watch("ack." .. entryName, function(ack: any)
		if typeof(ack) ~= "table" or typeof(ack.seq) ~= "number" then
			return
		end
		local cb = callbacks[ack.seq]
		callbacks[ack.seq] = nil
		if Outbox.ack(q, ack) then
			state.set(cmdKey, Outbox.pending(q))
		end
		if cb ~= nil then
			cb(ack)
		end
	end)

	return {
		send = function(name: string, args: { [string]: any }?, onAck: ((any) -> ())?)
			local cmd = Outbox.push(q, name, args)
			if onAck ~= nil then
				callbacks[cmd.seq] = onAck
			end
			state.set(cmdKey, Outbox.pending(q))
		end,
	}
end

return Client

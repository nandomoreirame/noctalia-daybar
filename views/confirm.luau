--!strict
-- Inline confirmation rows. A row in confirm state replaces its actions with the
-- question and Delete / Cancel; only Delete runs the destructive command.

local ConfirmView = {}

-- spec: { key, question, onConfirm, onCancel, enabled? }
function ConfirmView.row(ctx: any, spec: { [string]: any }): any
	local ui = ctx.ui
	return ui.row({ key = spec.key, gap = 8, align = "center" }, {
		ui.label({ text = spec.question, flexGrow = 1, maxLines = 2 }),
		ui.button({ text = ctx.tr("confirm.cancel"), variant = "ghost", controlSize = "sm", onClick = spec.onCancel }),
		ui.button({
			text = ctx.tr("confirm.delete"),
			variant = "destructive",
			controlSize = "sm",
			enabled = spec.enabled ~= false,
			onClick = spec.onConfirm,
		}),
	})
end

-- Event delete: locate first (the service finds the .ics), then confirm.
-- st.confirm holds "event:<uid>" while the row asks.
function ConfirmView.startEventDelete(ctx: any, uid: string, calendar: string)
	ctx.st.confirm = "event:" .. uid
	ctx.send("locateEvent", { uid = uid, calendar = calendar })
	ctx.render()
end

function ConfirmView.eventRow(ctx: any, uid: string, calendar: string): any
	local state = ((ctx.view or {}).deleting or {})[uid]
	local question
	local enabled = false
	if state == nil or state.phase == "locating" then
		question = ctx.tr("events.locating")
	elseif state.phase == "error" then
		question = ctx.tr("events.error." .. tostring(state.error or "failed"))
	else
		enabled = true
		question = ctx.tr(if state.recurring then "events.confirm-delete-recurring" else "events.confirm-delete")
	end
	return ConfirmView.row(ctx, {
		key = "confirm-" .. uid,
		question = question,
		enabled = enabled,
		onConfirm = function()
			ctx.st.confirm = nil
			ctx.send("deleteEvent", { uid = uid, calendar = calendar })
			ctx.render()
		end,
		onCancel = function()
			ctx.st.confirm = nil
			ctx.send("cancelDelete", { uid = uid })
			ctx.render()
		end,
	})
end

return ConfirmView

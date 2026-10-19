--!strict
-- Today tab (REQ-021, REQ-022): today's events, then today's and overdue tasks.
-- ctx: { ui, tr, view, nowMs, send(name, args, onAck), st, render }
-- st: { addRev, renaming = task id, confirm = "task:<id>" | "event:<uid>" }

local Today = require("../lib/today.luau")
local TaskCapture = require("../lib/capture/task.luau")
local ConfirmView = require("./confirm.luau")

local TodayView = {}

local function nowSec(ctx: any): number
	return math.floor(ctx.nowMs / 1000)
end

local function checkButton(ctx: any, item: any): any
	return ctx.ui.button({
		key = "check-" .. item.id,
		glyph = if item.done then "square-check" else "square",
		variant = "ghost",
		controlSize = "sm",
		onClick = function()
			if item.kind == "task" then
				ctx.send("toggleTask", { id = item.id })
			else
				ctx.send("toggleEvent", { uid = item.uid, date = string.sub(item.id, #item.uid + 2) })
			end
		end,
	})
end

local function taskRow(ctx: any, item: any): any
	local ui = ctx.ui
	local st = ctx.st
	if st.confirm == "task:" .. item.id then
		return ConfirmView.row(ctx, {
			key = "confirm-" .. item.id,
			question = ctx.tr("today.delete"),
			onConfirm = function()
				st.confirm = nil
				ctx.send("deleteTask", { id = item.id })
				ctx.render()
			end,
			onCancel = function()
				st.confirm = nil
				ctx.render()
			end,
		})
	end
	if st.renaming == item.id then
		return ui.row({ key = "row-" .. item.id, gap = 6, align = "center" }, {
			ui.input({
				key = "rename-" .. item.id,
				value = item.title,
				focus = true,
				flexGrow = 1,
				controlSize = "sm",
				onSubmit = function(value: string)
					st.renaming = nil
					ctx.send("renameTask", { id = item.id, title = value })
					ctx.render()
				end,
			}),
			ui.button({ text = ctx.tr("confirm.cancel"), variant = "ghost", controlSize = "sm", onClick = function()
				st.renaming = nil
				ctx.render()
			end }),
		})
	end
	local children = { checkButton(ctx, item) }
	if item.time ~= nil then
		table.insert(children, ui.label({ text = item.time, color = "on_surface_variant", fontSize = 12 }))
	end
	table.insert(children, ui.label({ text = item.title, flexGrow = 1, maxLines = 1, opacity = if item.done then 0.6 else 1 }))
	if item.overdue then
		table.insert(children, ui.label({ text = ctx.tr("today.overdue"), color = "error", fontSize = 11 }))
	end
	table.insert(children, ui.button({
		glyph = "player-play",
		variant = "ghost",
		controlSize = "sm",
		tooltip = ctx.tr("today.focus"),
		onClick = function()
			ctx.send("linkTask", { id = item.id })
		end,
	}))
	table.insert(children, ui.button({
		glyph = "pencil",
		variant = "ghost",
		controlSize = "sm",
		tooltip = ctx.tr("today.rename"),
		onClick = function()
			st.renaming = item.id
			ctx.render()
		end,
	}))
	table.insert(children, ui.button({
		glyph = "trash",
		variant = "ghost",
		controlSize = "sm",
		tooltip = ctx.tr("today.delete"),
		onClick = function()
			st.confirm = "task:" .. item.id
			ctx.render()
		end,
	}))
	return ui.row({ key = "row-" .. item.id, gap = 6, align = "center" }, children)
end

local function eventRow(ctx: any, item: any): any
	local ui = ctx.ui
	if ctx.st.confirm == "event:" .. item.uid then
		return ConfirmView.eventRow(ctx, item.uid, item.calendar)
	end
	local children = {}
	if item.checkable then
		table.insert(children, checkButton(ctx, item))
	else
		table.insert(children, ui.glyph({ name = "calendar-event", size = 16 }))
	end
	local range = if item.time == nil
		then ctx.tr("calendar.all-day")
		elseif item.endTime ~= nil then item.time .. "–" .. item.endTime
		else item.time
	table.insert(children, ui.label({ text = range, color = "on_surface_variant", fontSize = 12 }))
	table.insert(children, ui.label({ text = tostring(item.title), flexGrow = 1, maxLines = 1, opacity = if item.done then 0.6 else 1 }))
	table.insert(children, ui.button({
		glyph = "trash",
		variant = "ghost",
		controlSize = "sm",
		tooltip = ctx.tr("events.delete"),
		onClick = function()
			ConfirmView.startEventDelete(ctx, item.uid, item.calendar)
		end,
	}))
	return ui.row({ key = "row-" .. item.id, gap = 6, align = "center" }, children)
end

function TodayView.build(ctx: any): any
	local ui = ctx.ui
	local st = ctx.st
	st.addRev = st.addRev or 0
	local v = ctx.view or {}
	local items = Today.buildToday((v.calendar or {}).events, v.data or {}, nowSec(ctx), nil)
	local rows = {}
	for _, item in ipairs(items) do
		table.insert(rows, if item.kind == "task" then taskRow(ctx, item) else eventRow(ctx, item))
	end
	if #rows == 0 then
		table.insert(rows, ui.label({ text = ctx.tr("today.empty-title"), color = "on_surface_variant" }))
	end
	return ui.column({ gap = 8, flexGrow = 1 }, {
		ui.scroll({ gap = 4, flexGrow = 1 }, rows),
		ui.input({
			key = "add-" .. st.addRev,
			placeholder = ctx.tr("today.add-placeholder"),
			controlSize = "sm",
			onSubmit = function(value: string)
				local r = TaskCapture.build(value, nowSec(ctx))
				if not r.ok then
					return
				end
				ctx.send("addTask", r.payload, function(ack: any)
					if ack.ok then
						st.addRev += 1
						ctx.render()
					end
				end)
			end,
		}),
	})
end

return TodayView

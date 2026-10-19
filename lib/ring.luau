--!strict
-- Progress ring drawn as SVG (the ui.* toolkit has no arc). The service writes
-- one file per percent per theme color; entries show the file for the current
-- percent with ui.image, one path per step so the host's image cache never
-- serves a stale ring.

local Ring = {}

Ring.STEPS = 100
Ring.SIZE = 200
Ring.STROKE = 10
Ring.RADIUS = (Ring.SIZE - Ring.STROKE) / 2

-- 0..1 progress -> 0..100 step.
function Ring.step(progress: number): number
	local n = math.floor(progress * Ring.STEPS + 0.5)
	return math.max(0, math.min(Ring.STEPS, n))
end

-- "#RRGGBB" -> "rrggbb"; nil for anything else.
function Ring.dirName(hex: any): string?
	if typeof(hex) ~= "string" or not string.match(hex, "^#%x%x%x%x%x%x$") then
		return nil
	end
	return string.lower(string.sub(hex, 2))
end

-- Track circle at 20% opacity, plus an arc from 12 o'clock covering `step`%.
function Ring.svg(step: number, hex: string): string
	local c = Ring.SIZE / 2
	local r = Ring.RADIUS
	local circumference = 2 * math.pi * r
	local parts = {
		string.format('<svg xmlns="http://www.w3.org/2000/svg" width="%d" height="%d" viewBox="0 0 %d %d">', Ring.SIZE, Ring.SIZE, Ring.SIZE, Ring.SIZE),
		string.format(
			'<circle cx="%g" cy="%g" r="%g" fill="none" stroke="%s" stroke-opacity="0.2" stroke-width="%d"/>',
			c,
			c,
			r,
			hex,
			Ring.STROKE
		),
	}
	if step > 0 then
		local dash = circumference * step / Ring.STEPS
		table.insert(
			parts,
			string.format(
				'<circle cx="%g" cy="%g" r="%g" fill="none" stroke="%s" stroke-width="%d" stroke-linecap="round" stroke-dasharray="%.3f %.3f" transform="rotate(-90 %g %g)"/>',
				c,
				c,
				r,
				hex,
				Ring.STROKE,
				dash,
				circumference,
				c,
				c
			)
		)
	end
	table.insert(parts, "</svg>\n")
	return table.concat(parts)
end

return Ring

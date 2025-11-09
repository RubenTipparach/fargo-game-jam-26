--[[pod_format="raw",created="2024-11-09 00:00:00",modified="2024-11-09 00:00:00",revision=0]]
-- Arc UI Module
-- Handles drawing the heading arc for ship navigation

local ArcUI = {}

-- Draw the heading arc between current and target directions
-- @param ship_heading_dir: current heading direction vector {x, z}
-- @param target_heading_dir: target heading direction vector {x, z}
-- @param angle_diff: angle difference between current and target headings
-- @param camera: camera object with view matrix
-- @param config: global config object
-- @param utilities: object containing dir_to_quat and quat_to_dir functions
function ArcUI.draw_heading_arc(ship_heading_dir, target_heading_dir, angle_diff, camera, config, utilities)
	-- Draw compass if ship is moving or if there's a significant heading difference
	-- Lowered thresholds from 0.01 to 0.001 for easier testing
	if angle_diff > 0.001 then
		local ship_x = config.ship.position.x
		local ship_z = config.ship.position.z
		local ship_y = config.ship.position.y  -- Raise arc above ship for visibility
		local arc_radius = config.ship.heading_arc_radius
		local segments = config.ship.heading_arc_segments

		-- Draw current ship heading line (blue/cyan)
		local current_x = ship_x + ship_heading_dir.x * arc_radius
		local current_z = ship_z + ship_heading_dir.z * arc_radius
		utilities.draw_line_3d(ship_x, ship_y, ship_z, current_x, ship_y, current_z, camera, 13)  -- Blue (cyan)

		-- Determine turn direction using left dot product
		-- Rotate current direction 90 degrees left (counter-clockwise): (x, z) -> (-z, x)
		local current_left_x = -ship_heading_dir.z
		local current_left_z = ship_heading_dir.x

		-- Dot product with target direction
		local left_dot = current_left_x * target_heading_dir.x + current_left_z * target_heading_dir.z
		local turn_left = left_dot > 0  -- If positive, we need to turn left

		-- Draw arc by interpolating between current and target directions
		local arc_color = 10  -- Yellow

		-- Convert to quaternions once, outside the loop
		local q_current = utilities.dir_to_quat(ship_heading_dir)
		local q_target = utilities.dir_to_quat(target_heading_dir)

		-- Ensure we take the shortest path by checking quaternion dot product
		local q_dot = q_current.w * q_target.w + q_current.x * q_target.x + q_current.y * q_target.y + q_current.z * q_target.z
		if q_dot < 0 then
			-- Negate target quaternion to take the shorter path
			q_target.w = -q_target.w
			q_target.x = -q_target.x
			q_target.y = -q_target.y
			q_target.z = -q_target.z
		end

		for i = 0, segments - 1 do
			local t1 = i / segments
			local t2 = (i + 1) / segments

			-- If turning left, reverse the interpolation direction
			if turn_left then
				t1 = 1 - t1
				t2 = 1 - t2
			end

			-- Linear quaternion interpolation between current and target
			-- Simple lerp: q = q1 + t * (q2 - q1), then normalize
			local q_arc1 = {
				w = q_current.w + t1 * (q_target.w - q_current.w),
				x = q_current.x + t1 * (q_target.x - q_current.x),
				y = q_current.y + t1 * (q_target.y - q_current.y),
				z = q_current.z + t1 * (q_target.z - q_current.z)
			}
			local q_arc2 = {
				w = q_current.w + t2 * (q_target.w - q_current.w),
				x = q_current.x + t2 * (q_target.x - q_current.x),
				y = q_current.y + t2 * (q_target.y - q_current.y),
				z = q_current.z + t2 * (q_target.z - q_current.z)
			}

			-- Normalize quaternions
			local len1 = sqrt(q_arc1.w*q_arc1.w + q_arc1.x*q_arc1.x + q_arc1.y*q_arc1.y + q_arc1.z*q_arc1.z)
			if len1 > 0.0001 then
				q_arc1.w = q_arc1.w / len1
				q_arc1.x = q_arc1.x / len1
				q_arc1.y = q_arc1.y / len1
				q_arc1.z = q_arc1.z / len1
			end

			local len2 = sqrt(q_arc2.w*q_arc2.w + q_arc2.x*q_arc2.x + q_arc2.y*q_arc2.y + q_arc2.z*q_arc2.z)
			if len2 > 0.0001 then
				q_arc2.w = q_arc2.w / len2
				q_arc2.x = q_arc2.x / len2
				q_arc2.y = q_arc2.y / len2
				q_arc2.z = q_arc2.z / len2
			end

			local dir1 = utilities.quat_to_dir(q_arc1)
			local dir2 = utilities.quat_to_dir(q_arc2)

			-- Calculate 3D positions on the arc
			local x1 = ship_x + dir1.x * arc_radius
			local z1 = ship_z + dir1.z * arc_radius
			local x2 = ship_x + dir2.x * arc_radius
			local z2 = ship_z + dir2.z * arc_radius

			-- Project to screen and draw line
			utilities.draw_line_3d(x1, ship_y, z1, x2, ship_y, z2, camera, arc_color)
		end

		-- Draw target heading line (bright yellow)
		local target_x = ship_x + target_heading_dir.x * arc_radius
		local target_z = ship_z + target_heading_dir.z * arc_radius
		utilities.draw_line_3d(ship_x, ship_y, ship_z, target_x, ship_y, target_z, camera, 11)  -- Bright yellow
	end
end

return ArcUI

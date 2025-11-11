--[[pod_format="raw",created="2025-11-10 00:00:00",modified="2025-11-10 00:00:00",revision=0]]
-- Ship Selection UI Module
-- Draws selection boxes around targetable ships (satellites and Grabons)

local ShipSelection = {}

-- Draw selection boxes for all enemy ships
-- @param enemy_ships: array of enemy ship objects
-- @param current_selected_target: currently selected target
-- @param hovered_target: currently hovered target
-- @param ship_pos: player ship position {x, y, z}
-- @param camera: camera object
-- @param project_point: function to project 3D point to screen space
function ShipSelection.draw_selection_boxes(enemy_ships, current_selected_target, hovered_target, ship_pos, camera, project_point)
	for _, enemy in ipairs(enemy_ships) do
		if (enemy.type == "satellite" or enemy.type == "grabon") and enemy.position and not enemy.is_destroyed then
			local sat_collider = enemy.config.collider
			local sat_pos = enemy.position

			-- Project all 8 corners of the collider to screen space
			local corners = {
				{sat_pos.x - sat_collider.half_size.x, sat_pos.y - sat_collider.half_size.y, sat_pos.z - sat_collider.half_size.z},
				{sat_pos.x + sat_collider.half_size.x, sat_pos.y - sat_collider.half_size.y, sat_pos.z - sat_collider.half_size.z},
				{sat_pos.x - sat_collider.half_size.x, sat_pos.y + sat_collider.half_size.y, sat_pos.z - sat_collider.half_size.z},
				{sat_pos.x + sat_collider.half_size.x, sat_pos.y + sat_collider.half_size.y, sat_pos.z - sat_collider.half_size.z},
				{sat_pos.x - sat_collider.half_size.x, sat_pos.y - sat_collider.half_size.y, sat_pos.z + sat_collider.half_size.z},
				{sat_pos.x + sat_collider.half_size.x, sat_pos.y - sat_collider.half_size.y, sat_pos.z + sat_collider.half_size.z},
				{sat_pos.x - sat_collider.half_size.x, sat_pos.y + sat_collider.half_size.y, sat_pos.z + sat_collider.half_size.z},
				{sat_pos.x + sat_collider.half_size.x, sat_pos.y + sat_collider.half_size.y, sat_pos.z + sat_collider.half_size.z},
			}

			-- Find min/max screen coordinates
			local min_screen_x = 999
			local max_screen_x = 0
			local min_screen_y = 999
			local max_screen_y = 0

			for _, corner in ipairs(corners) do
				local sx, sy = project_point(corner[1], corner[2], corner[3], camera)
				if sx and sy then
					min_screen_x = min(min_screen_x, sx)
					max_screen_x = max(max_screen_x, sx)
					min_screen_y = min(min_screen_y, sy)
					max_screen_y = max(max_screen_y, sy)
				end
			end

			-- Draw AABB outline if we have valid screen coordinates (at least partially on screen)
			-- Allow for off-screen boxes as long as they intersect with screen bounds (0-480 x 0-270)
			if max_screen_x > 0 and min_screen_x < 480 and max_screen_y > 0 and min_screen_y < 270 then
				local is_targeted = current_selected_target and current_selected_target == enemy
				local is_hovered = hovered_target and hovered_target == enemy
				local box_color = (is_targeted or is_hovered) and enemy.config.bounding_box_color_hover or enemy.config.bounding_box_color_default

				-- Draw AABB outline (4 lines forming a rectangle)
				line(min_screen_x, min_screen_y, max_screen_x, min_screen_y, box_color)
				line(max_screen_x, min_screen_y, max_screen_x, max_screen_y, box_color)
				line(max_screen_x, max_screen_y, min_screen_x, max_screen_y, box_color)
				line(min_screen_x, max_screen_y, min_screen_x, min_screen_y, box_color)

				-- Calculate distance from ship to enemy
				local dx = enemy.position.x - ship_pos.x
				local dy = enemy.position.y - ship_pos.y
				local dz = enemy.position.z - ship_pos.z
				local distance = sqrt(dx * dx + dy * dy + dz * dz)
				local distance_text = string.format("%.1f", distance)

				-- Draw distance label below bounding box
				local label_x = (min_screen_x + max_screen_x) / 2 - 10  -- Center the text roughly
				local label_y = max_screen_y + 3  -- Below the box
				print(distance_text, label_x, label_y, box_color)
			end
		end
	end
end

-- Draw target health bar and name above selected target
-- @param current_selected_target: currently selected target (can be nil)
-- @param camera: camera object
-- @param project_point: function to project 3D point to screen space
function ShipSelection.draw_target_health(current_selected_target, camera, project_point)
	-- Draw target health bar and indicator if satellite/Grabon is targeted (hovering above target in screen space)
	-- Hide health bar if satellite/Grabon is destroyed
	if current_selected_target and (current_selected_target.type == "satellite" or current_selected_target.type == "grabon") and current_selected_target.position and not current_selected_target.is_destroyed then
		-- Project satellite position to screen to draw health bar above it
		local sat_pos = current_selected_target.position
		local screen_x, screen_y = project_point(sat_pos.x, sat_pos.y + 4, sat_pos.z, camera)

		if screen_x and screen_y then
			-- Draw health bar above the target
			local bar_width = 60
			local bar_height = 8
			local bar_x = screen_x - (bar_width / 2)  -- Center bar on target
			local bar_y = screen_y - 15  -- Offset above target

			-- Target health bar background (black with border)
			rectfill(bar_x - 1, bar_y - 1, bar_x + bar_width + 1, bar_y + bar_height + 1, 0)  -- Dark border

			-- Target health bar fill (green -> red based on health)
			local target_health_percent = current_selected_target.current_health / current_selected_target.max_health
			local target_fill_width = bar_width * target_health_percent
			local target_health_color = target_health_percent > 0.5 and 11 or (target_health_percent > 0.25 and 10 or 8)
			if target_fill_width > 0 then
				rectfill(bar_x, bar_y, bar_x + target_fill_width, bar_y + bar_height, target_health_color)
			end

			-- Target health bar border (bright)
			rect(bar_x, bar_y, bar_x + bar_width, bar_y + bar_height, 11)

			-- Target name below health bar
			local target_name = current_selected_target.id
			local name_x = bar_x + (bar_width / 2) - (#target_name * 2)
			local name_y = bar_y + bar_height + 2
			print(target_name, name_x, name_y, 11)  -- Bright color for name
		end
	end
end

return ShipSelection

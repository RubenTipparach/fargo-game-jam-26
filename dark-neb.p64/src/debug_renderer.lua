--[[pod_format="raw",created="2024-11-08 00:00:00",modified="2024-11-08 00:00:00",revision=0]]
-- Debug Renderer Module
-- Handles all debug visualization (physics wireframes, UI overlays, etc)

local DebugRenderer = {}

-- Draw wireframe box for debug
function DebugRenderer.draw_box_wireframe(min_x, min_y, min_z, max_x, max_y, max_z, camera, color)
	-- 8 corners of the box
	local corners = {
		{min_x, min_y, min_z}, {max_x, min_y, min_z},
		{max_x, max_y, min_z}, {min_x, max_y, min_z},
		{min_x, min_y, max_z}, {max_x, min_y, max_z},
		{max_x, max_y, max_z}, {min_x, max_y, max_z},
	}

	-- 12 edges of the box
	local edges = {
		{1,2}, {2,3}, {3,4}, {4,1},  -- Front face
		{5,6}, {6,7}, {7,8}, {8,5},  -- Back face
		{1,5}, {2,6}, {3,7}, {4,8},  -- Connecting edges
	}

	for _, edge in ipairs(edges) do
		local c1 = corners[edge[1]]
		local c2 = corners[edge[2]]
		draw_line_3d(c1[1], c1[2], c1[3], c2[1], c2[2], c2[3], camera, color)
	end
end

-- Draw wireframe sphere for debug (3 rings for each axis)
function DebugRenderer.draw_sphere_wireframe(draw_line_3d_fn, cx, cy, cz, radius, camera, color)
	local segments = 16

	-- XZ ring (horizontal, around Y axis)
	for seg = 0, segments do
		local t1 = seg / segments
		local t2 = (seg + 1) / segments

		local x1 = cx + cos(t1 * 2) * radius
		local z1 = cz + sin(t1 * 2) * radius
		local x2 = cx + cos(t2 * 2) * radius
		local z2 = cz + sin(t2 * 2) * radius

		draw_line_3d_fn(x1, cy, z1, x2, cy, z2, camera, color)
	end

	-- XY ring (vertical, around Z axis)
	for seg = 0, segments do
		local t1 = seg / segments
		local t2 = (seg + 1) / segments

		local x1 = cx + cos(t1 * 2) * radius
		local y1 = cy + sin(t1 * 2) * radius
		local x2 = cx + cos(t2 * 2) * radius
		local y2 = cy + sin(t2 * 2) * radius

		draw_line_3d_fn(x1, y1, cz, x2, y2, cz, camera, color)
	end

	-- YZ ring (vertical, around X axis)
	for seg = 0, segments do
		local t1 = seg / segments
		local t2 = (seg + 1) / segments

		local y1 = cy + cos(t1 * 2) * radius
		local z1 = cz + sin(t1 * 2) * radius
		local y2 = cy + cos(t2 * 2) * radius
		local z2 = cz + sin(t2 * 2) * radius

		draw_line_3d_fn(cx, y1, z1, cx, y2, z2, camera, color)
	end
end

-- Draw physics debug overlays
function DebugRenderer.draw_physics_debug(Config, camera)
	-- Draw ship collider wireframe
	local ship_collider = Config.ship.collider
	local ship_pos = Config.ship.position
	local ship_box_min_x = ship_pos.x - ship_collider.half_size.x
	local ship_box_min_y = ship_pos.y - ship_collider.half_size.y
	local ship_box_min_z = ship_pos.z - ship_collider.half_size.z
	local ship_box_max_x = ship_pos.x + ship_collider.half_size.x
	local ship_box_max_y = ship_pos.y + ship_collider.half_size.y
	local ship_box_max_z = ship_pos.z + ship_collider.half_size.z
	DebugRenderer.draw_box_wireframe(ship_box_min_x, ship_box_min_y, ship_box_min_z,
	                   ship_box_max_x, ship_box_max_y, ship_box_max_z, camera, 3)  -- Cyan box

	-- Draw planet collider wireframe
	local planet_collider = Config.planet.collider
	local planet_pos = Config.planet.position
	DebugRenderer.draw_sphere_wireframe(planet_pos.x, planet_pos.y, planet_pos.z, planet_collider.radius, camera, 11)  -- Yellow sphere
end

-- Draw health bar at top left
function DebugRenderer.draw_health_bar(Config, current_health)
	local health_config = Config.health
	local health_bar_x = health_config.health_bar_x
	local health_bar_y = health_config.health_bar_y
	local health_bar_width = health_config.health_bar_width
	local health_bar_height = health_config.health_bar_height

	-- Health bar background (black)
	rectfill(health_bar_x, health_bar_y, health_bar_x + health_bar_width, health_bar_y + health_bar_height, 0)

	-- Health bar fill (green -> red based on health)
	local health_percent = current_health / Config.health.max_health
	local fill_width = health_bar_width * health_percent
	local health_color
	if health_percent > 0.5 then
		health_color = 11  -- Bright green/cyan
	elseif health_percent > 0.25 then
		health_color = 10  -- Yellow
	else
		health_color = 8  -- Red
	end
	if fill_width > 0 then
		rectfill(health_bar_x, health_bar_y, health_bar_x + fill_width, health_bar_y + health_bar_height, health_color)
	end

	-- Health bar border (white)
	rect(health_bar_x, health_bar_y, health_bar_x + health_bar_width, health_bar_y + health_bar_height, 7)

	-- Health text
	local health_display = flr(current_health)
	print("hp: " .. health_display, health_bar_x + health_bar_width + 10, health_bar_y, 7)
end

-- Draw death screen with restart prompt
function DebugRenderer.draw_death_screen(Config, is_dead, death_time)
	if is_dead then
		-- Box dimensions (centered on 480x270 screen)
		local box_width = 200
		local box_height = 100
		local box_x = (480 - box_width) / 2
		local box_y = (270 - box_height) / 2

		-- Draw black background box
		rectfill(box_x, box_y, box_x + box_width, box_y + box_height, 0)

		-- Draw white border
		rect(box_x, box_y, box_x + box_width, box_y + box_height, 7)

		-- Death message (centered in box)
		print("YOU DIED", box_x + 75, box_y + 25, 8)  -- Red text

		-- Restart prompt (only show after delay)
		if death_time >= Config.health.death_screen_delay then
			print("Press R to restart", box_x + 40, box_y + 65, 7)  -- White text
		end
	end
end

-- Draw camera debug info
function DebugRenderer.draw_camera_debug(camera, x, y)
	x = x or 2
	y = y or 2
	local line_height = 8

	print("camera pos: (" .. flr(camera.x*10)/10 .. ", " .. flr(camera.y*10)/10 .. ", " .. flr(camera.z*10)/10 .. ")", x, y, 7)
	print("camera rot: rx=" .. flr(camera.rx*100)/100 .. " ry=" .. flr(camera.ry*100)/100, x, y + line_height, 7)
	print("camera dist: " .. flr(camera.distance*10)/10, x, y + line_height*2, 7)
end

-- Draw raycast debug info
function DebugRenderer.draw_raycast_debug(raycast_x, raycast_z, ship_x, ship_z, x, y)
	x = x or 2
	y = y or 34
	local line_height = 8

	if raycast_x and raycast_z then
		print("raycast: (" .. flr(raycast_x*10)/10 .. ", " .. flr(raycast_z*10)/10 .. ")", x, y, 7)
		local dx = raycast_x - ship_x
		local dz = raycast_z - ship_z
		local dist = sqrt(dx*dx + dz*dz)
		print("raycast dist: " .. flr(dist*10)/10, x, y + line_height, 7)
	else
		print("raycast: FAILED", x, y, 8)
	end
end

-- Draw ship debug info
function DebugRenderer.draw_ship_debug(ship_pos, ship_heading_dir, ship_speed, max_speed, x, y)
	x = x or 2
	y = y or 50
	local line_height = 8

	print("ship pos: (" .. flr(ship_pos.x*10)/10 .. ", " .. flr(ship_pos.y*10)/10 .. ", " .. flr(ship_pos.z*10)/10 .. ")", x, y, 7)
	print("ship heading: (" .. flr(ship_heading_dir.x*100)/100 .. ", " .. flr(ship_heading_dir.z*100)/100 .. ")", x, y + line_height, 7)
	print("ship speed: " .. flr(ship_speed * max_speed * 10) / 10 .. " / " .. max_speed, x, y + line_height*2, 7)
end

-- Draw test sprite grid (palette reference)
function DebugRenderer.draw_test_sprites(x, y, sprites_per_row)
	x = x or 300
	y = y or 10
	sprites_per_row = sprites_per_row or 16

	print("sprites (0-63):", x, y, 7)
	for i = 0, 63 do
		local row = flr(i / sprites_per_row)
		local col = i % sprites_per_row
		local sx = x + col * 18
		local sy = y + 10 + row * 18

		-- Draw sprite
		spr(i, sx, sy)

		-- Draw sprite number below (small, wrapping at edges)
		if i < 10 then
			print(i, sx + 6, sy + 10, 7)
		else
			print(flr(i/10) .. (i%10), sx + 3, sy + 10, 7)
		end
	end
end

-- Draw all debug info when debug flag is enabled
function DebugRenderer.draw_all_debug(Config, camera, raycast_x, raycast_z, ship_pos, ship_heading_dir, ship_speed)
	if Config.debug then
		-- Camera info (top left)
		DebugRenderer.draw_camera_debug(camera, 2, 2)

		-- Raycast info
		DebugRenderer.draw_raycast_debug(raycast_x, raycast_z, ship_pos.x, ship_pos.z, 2, 34)

		-- Ship info
		DebugRenderer.draw_ship_debug(ship_pos, ship_heading_dir, ship_speed, Config.ship.max_speed, 2, 50)

		-- Test sprites (palette reference)
		DebugRenderer.draw_test_sprites(300, 10, 16)
	end
end

return DebugRenderer

--[[pod_format="raw",created="2024-11-07 20:00:00",modified="2024-11-07 20:00:00",revision=0]]
-- Debug Visualization Module
-- Handles all debug drawing including UI hitboxes, camera info, lighting arrows, and palette displays

local DebugVisualization = {}

-- Draw weapons UI debug hitboxes
function DebugVisualization.draw_weapon_hitboxes(WeaponsUI, Config, mx, my)
	local weapon_hitboxes = WeaponsUI.get_weapon_hitboxes(Config)
	for _, hb in ipairs(weapon_hitboxes) do
		rect(hb.x, hb.y, hb.x + hb.width, hb.y + hb.height, 3)  -- Cyan outline
	end
	local toggle_hitboxes = WeaponsUI.get_toggle_hitboxes(Config)
	for _, hb in ipairs(toggle_hitboxes) do
		rect(hb.x, hb.y, hb.x + hb.size, hb.y + hb.size, 3)  -- Cyan outline
	end
	print("mx: " .. mx .. " my: " .. my, 320 - 50, 10, 7)
end

-- Draw camera and ship direction debug info
function DebugVisualization.draw_camera_info(camera, ship_heading_dir, target_heading_dir, raycast_x, raycast_z)
	-- Camera angles display
	print("cam pitch: " .. flr(camera.rx * 100) / 100, 2, 2, 7)
	print("cam yaw: " .. flr(camera.ry * 100) / 100, 2, 10, 7)
	print("ship dir: (" .. flr(ship_heading_dir.x * 100) / 100 .. "," .. flr(ship_heading_dir.z * 100) / 100 .. ")", 2, 18, 7)
	print("target dir: (" .. flr(target_heading_dir.x * 100) / 100 .. "," .. flr(target_heading_dir.z * 100) / 100 .. ")", 2, 26, 7)

	-- Raycast debug display
	if raycast_x and raycast_z then
		print("raycast x: " .. flr(raycast_x * 10) / 10, 2, 34, 7)
		print("raycast z: " .. flr(raycast_z * 10) / 10, 2, 42, 7)
	else
		print("raycast: nil", 2, 34, 8)
	end
end

-- Draw lighting debug visualization (3D arrow showing light direction)
function DebugVisualization.draw_lighting_debug(light_yaw, light_pitch, get_light_direction, draw_line_3d, camera)
	-- Light rotation info
	print("light yaw: " .. flr(light_yaw * 100) / 100, 2, 2, 7)
	print("light pitch: " .. flr(light_pitch * 100) / 100, 2, 10, 7)

	-- Draw 3D light direction arrow in world space
	local light_dir = get_light_direction()
	local arrow_origin_x = 0
	local arrow_origin_y = 5  -- Above center
	local arrow_origin_z = 0
	local arrow_len = 8

	-- Arrow endpoint (pointing in light direction)
	local arrow_end_x = arrow_origin_x + light_dir.x * arrow_len
	local arrow_end_y = arrow_origin_y + light_dir.y * arrow_len
	local arrow_end_z = arrow_origin_z + light_dir.z * arrow_len

	-- Draw arrow shaft (yellow)
	draw_line_3d(arrow_origin_x, arrow_origin_y, arrow_origin_z,
	             arrow_end_x, arrow_end_y, arrow_end_z, camera, 10)

	-- Calculate perpendicular vectors for arrowhead
	local right_x, right_y, right_z = -light_dir.z, 0, light_dir.x
	local len_right = sqrt(right_x * right_x + right_y * right_y + right_z * right_z)
	if len_right > 0.001 then
		right_x, right_y, right_z = right_x / len_right, right_y / len_right, right_z / len_right
	else
		right_x, right_y, right_z = 1, 0, 0
	end

	-- Cross product to get up vector
	local up_x = light_dir.y * right_z - light_dir.z * right_y
	local up_y = light_dir.z * right_x - light_dir.x * right_z
	local up_z = light_dir.x * right_y - light_dir.y * right_x

	local head_back = 2.0  -- How far back from tip
	local head_size = 0.8  -- Arrowhead width

	-- Arrowhead points
	local base_x = arrow_end_x - light_dir.x * head_back
	local base_y = arrow_end_y - light_dir.y * head_back
	local base_z = arrow_end_z - light_dir.z * head_back

	local tip1_x = base_x + right_x * head_size
	local tip1_y = base_y + right_y * head_size
	local tip1_z = base_z + right_z * head_size

	local tip2_x = base_x - right_x * head_size
	local tip2_y = base_y - right_y * head_size
	local tip2_z = base_z - right_z * head_size

	local tip3_x = base_x + up_x * head_size
	local tip3_y = base_y + up_y * head_size
	local tip3_z = base_z + up_z * head_size

	local tip4_x = base_x - up_x * head_size
	local tip4_y = base_y - up_y * head_size
	local tip4_z = base_z - up_z * head_size

	-- Draw arrowhead lines (yellow)
	draw_line_3d(arrow_end_x, arrow_end_y, arrow_end_z, tip1_x, tip1_y, tip1_z, camera, 10)
	draw_line_3d(arrow_end_x, arrow_end_y, arrow_end_z, tip2_x, tip2_y, tip2_z, camera, 10)
	draw_line_3d(arrow_end_x, arrow_end_y, arrow_end_z, tip3_x, tip3_y, tip3_z, camera, 10)
	draw_line_3d(arrow_end_x, arrow_end_y, arrow_end_z, tip4_x, tip4_y, tip4_z, camera, 10)
end

-- Draw full debug UI (control hints, face count, sprite system, palette)
function DebugVisualization.draw_full_debug_ui(all_faces, RendererLit)
	-- Control hints
	print("mouse: orbit camera", 2, 18, 7)
	print("wasd: rotate light", 2, 26, 7)
	print("faces: " .. #all_faces, 2, 34, 7)

	-- Show sprite system (texture + brightness masks)
	local debug_x = 320
	local debug_y = 10

	-- Show texture sprite (sprite 1 only)
	print("texture:", debug_x - 60, debug_y, 7)
	spr(1, debug_x, debug_y + 8)
	print("1", debug_x + 6, debug_y + 26, 7)

	-- Show generated brightness sprites for sprite 1
	local brightness_levels = RendererLit.BRIGHTNESS_LEVELS or 4
	print("sprite 1 brightness (0-" .. (brightness_levels - 1) .. "):", debug_x - 60, debug_y + 40, 7)

	-- Display sprites with wrapping (8 per row max to fit on screen)
	local sprites_per_row = 8
	for level = 0, brightness_levels - 1 do
		local row = flr(level / sprites_per_row)
		local col = level % sprites_per_row
		local x = debug_x + col * 18
		local y = debug_y + 48 + row * 24

		local cached_sprite_index = RendererLit.get_brightness_sprite(1, level)
		spr(cached_sprite_index, x, y)
		print(level, x + (level < 10 and 6 or 3), y + 18, 7)
	end

	-- Show all 64 palette colors
	print("palette colors (0-63):", 2, 200, 7)
	for i = 0, 63 do
		local x = 2 + (i % 32) * 4
		local y = 208 + flr(i / 32) * 4
		rectfill(x, y, x + 3, y + 3, i)
	end
end

-- Draw physics debug wireframes (colliders, heading arrows)
function DebugVisualization.draw_physics_debug(ship_pos, show_planet, spawned_spheres, enemy_ships, Config, camera, draw_box_wireframe, draw_line_3d, DebugRenderer, angle_to_dir)
	-- Draw ship collider wireframe
	local ship_collider = Config.ship.collider
	local ship_box_min_x = ship_pos.x - ship_collider.half_size.x
	local ship_box_min_y = ship_pos.y - ship_collider.half_size.y
	local ship_box_min_z = ship_pos.z - ship_collider.half_size.z
	local ship_box_max_x = ship_pos.x + ship_collider.half_size.x
	local ship_box_max_y = ship_pos.y + ship_collider.half_size.y
	local ship_box_max_z = ship_pos.z + ship_collider.half_size.z
	draw_box_wireframe(ship_box_min_x, ship_box_min_y, ship_box_min_z,
	                   ship_box_max_x, ship_box_max_y, ship_box_max_z, camera, 3)  -- Cyan box

	-- Draw planet collider wireframe using DebugRenderer (only if planet is active in mission)
	if show_planet then
		local planet_collider = Config.planet.collider
		local planet_pos = Config.planet.position
		DebugRenderer.draw_sphere_wireframe(draw_line_3d, planet_pos.x, planet_pos.y, planet_pos.z, planet_collider.radius, camera, 11)  -- Yellow sphere
	end

	-- Draw bounding boxes for all spawned spheres
	for _, sphere_pos in ipairs(spawned_spheres) do
		local s = 0.5  -- half-size
		local quad_min_x = sphere_pos.x - s
		local quad_min_y = sphere_pos.y - s
		local quad_min_z = sphere_pos.z - s
		local quad_max_x = sphere_pos.x + s
		local quad_max_y = sphere_pos.y + s
		local quad_max_z = sphere_pos.z + s
		draw_box_wireframe(quad_min_x, quad_min_y, quad_min_z,
		                   quad_max_x, quad_max_y, quad_max_z, camera, 8)  -- Red box
	end

	-- Draw enemy ship heading arrows
	for _, enemy in ipairs(enemy_ships) do
		if enemy.type == "grabon" and enemy.position and not enemy.is_destroyed then
			local arrow_length = 15
			local grabon_dir = angle_to_dir(enemy.heading)
			local arrow_end_x = enemy.position.x + grabon_dir.x * arrow_length
			local arrow_end_z = enemy.position.z + grabon_dir.z * arrow_length
			draw_line_3d(enemy.position.x, enemy.position.y, enemy.position.z,
			             arrow_end_x, enemy.position.y, arrow_end_z, camera, 10)  -- Yellow arrow
		end
	end
end

return DebugVisualization

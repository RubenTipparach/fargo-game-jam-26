--[[pod_format="raw",created="2024-11-07 20:00:00",modified="2024-11-07 20:00:00",revision=0]]
-- 3D Model Viewer with Flat Shading
-- Features:
-- - Loads shippy.obj
-- - Flat shading with lighting based on angle from light
-- - Base color (dark) with dithered lighting layer
-- - Mouse orbit camera controls (Y axis up)

-- Require polyfill for Picotron
local _modules = {}

function require(name)
	if _modules[name] == nil then
		_modules[name] = include(name:gsub('%.', '/') .. '.lua')
	end
	return _modules[name]
end

-- Load modules (use include like ld58 does)
Lighting = include("src/lighting.lua")
Renderer = include("src/engine/renderer.lua")
RendererLit = include("src/engine/renderer_lit.lua")
RenderFlat = include("src/engine/render_flat.lua")
Config = include("config.lua")

-- ============================================
-- SCENE CONFIGURATION
-- ============================================

-- Camera settings (from config)
local camera = {
	x = 0,
	y = 0,
	z = 0,
	rx = Config.camera.rx,
	ry = Config.camera.ry,
	distance = Config.camera.distance,
}

-- Mouse orbit state
local mouse_drag = false
local last_mouse_x = 0
local last_mouse_y = 0

-- Light settings (from config)
local light_yaw = Config.lighting.yaw
local light_pitch = Config.lighting.pitch
local light_brightness = Config.lighting.brightness
local ambient = Config.lighting.ambient

-- Generate random stars for background
local star_positions = nil  -- Userdata storing star positions and colors
function generate_stars()

	-- Helper function to pick color based on probabilities
	local function pick_star_color()
		local rand = rnd()
		local cumulative = 0
		for color_cfg in all(Config.stars.colors) do
			cumulative = cumulative + color_cfg.probability
			if rand <= cumulative then
				return color_cfg.color
			end
		end
		-- Fallback to first color
		return Config.stars.colors[1].color
	end

	-- Create userdata for star positions and colors
	-- 4 columns x star_count rows (x, y, z, color per star)
	star_positions = userdata("f64", 4, Config.stars.count)

	for i = 1, Config.stars.count do
		local range = Config.stars.range
		local x = rnd(range.x.max - range.x.min) + range.x.min
		local y = rnd(range.y.max - range.y.min) + range.y.min
		local z = rnd(range.z.max - range.z.min) + range.z.min
		local color = pick_star_color()

		-- Store in userdata (0-indexed, so i-1)
		-- Each row is: x, y, z, color
		star_positions:set(0, i-1, x)
		star_positions:set(1, i-1, y)
		star_positions:set(2, i-1, z)
		star_positions:set(3, i-1, color)  -- Store color in 4th column
	end
end

-- Calculate light direction from yaw and pitch
function get_light_direction()
	local cy, sy = cos(light_yaw), sin(light_yaw)
	local cp, sp = cos(light_pitch), sin(light_pitch)
	return {
		x = cy * cp,
		y = sp,
		z = sy * cp
	}
end

-- Project a 3D point to screen space
function project_point(x, y, z, camera)
	local cam_dist = camera.distance or 5
	local tan_half_fov = 0.7002075
	local proj_scale = 270 / tan_half_fov

	-- Apply camera rotation (same as renderer)
	local sin_ry, cos_ry = sin(camera.ry), cos(camera.ry)
	local sin_rx, cos_rx = sin(camera.rx), cos(camera.rx)

	local x1 = x * cos_ry - z * sin_ry
	local z1 = x * sin_ry + z * cos_ry
	local y2 = y * cos_rx - z1 * sin_rx
	local z2 = y * sin_rx + z1 * cos_rx

	local x3 = -x1
	local y3 = -y2
	local z3 = y * sin_rx + z2 * cos_rx + cam_dist

	-- Project to screen
	if z3 > 0.01 then
		local inv_z = 1 / z3
		local px = -x1 * inv_z * proj_scale + 240
		local py = -y2 * inv_z * proj_scale + 135
		return px, py, z3
	end
	return nil, nil, nil
end

-- Build camera transformation matrix (3x4 for matmul3d)
function build_camera_matrix(cam)
	local sin_ry, cos_ry = sin(cam.ry), cos(cam.ry)
	local sin_rx, cos_rx = sin(cam.rx), cos(cam.rx)

	-- Create 3x4 transformation matrix (3 rows, 4 columns)
	local mat = userdata("f64", 4, 3)

	-- Row 0: x transformation (yaw rotation affects x)
	mat:set(0, 0, cos_ry)
	mat:set(1, 0, 0)
	mat:set(2, 0, -sin_ry)
	mat:set(3, 0, 0)

	-- Row 1: y transformation (pitch rotation)
	mat:set(0, 1, sin_ry * sin_rx)
	mat:set(1, 1, cos_rx)
	mat:set(2, 1, cos_ry * sin_rx)
	mat:set(3, 1, 0)

	-- Row 2: z transformation (combined rotation + distance)
	mat:set(0, 2, sin_ry * cos_rx)
	mat:set(1, 2, -sin_rx)
	mat:set(2, 2, cos_ry * cos_rx)
	mat:set(3, 2, cam.distance or 30)

	return mat
end

-- Draw stars in background (fixed in world space)
function draw_stars()
	if not star_positions then return end

	-- Draw each star using project_point (simpler, rotates with camera)
	for i = 0, Config.stars.count - 1 do
		local x = star_positions:get(0, i)
		local y = star_positions:get(1, i)
		local z = star_positions:get(2, i)
		local color = star_positions:get(3, i)

		-- Project star to screen space
		local px, py, pz = project_point(x, y, z, camera)
		if px and py and pz > 0 then
			pset(px, py, color)
		end
	end
end

-- Draw a 3D line in world space
function draw_line_3d(x1, y1, z1, x2, y2, z2, camera, color)
	local px1, py1, pz1 = project_point(x1, y1, z1, camera)
	local px2, py2, pz2 = project_point(x2, y2, z2, camera)

	if px1 and px2 and pz1 > 0 and pz2 > 0 then
		line(px1, py1, px2, py2, color)
	end
end

-- Model data
local model_shippy = nil
local model_sphere = nil
local model_planet = nil
local planet_rotation = 0



-- Create a low-poly sphere mesh (from lounge.p64)
function create_sphere(radius, segments, stacks, sprite_id, sprite_w, sprite_h)
	local verts = {}
	local faces = {}

	stacks = stacks or segments  -- Default stacks to segments if not provided
	sprite_id = sprite_id or 1
	sprite_w = sprite_w or 16
	sprite_h = sprite_h or 16

	-- Generate vertices
	for stack = 0, stacks do
		local phi = (stack / stacks) * 0.5  -- 0 to 0.5 (0 to 180 degrees in Picotron)
		local y = radius * cos(phi)
		local ring_radius = radius * sin(phi)

		for seg = 0, segments do
			local theta = seg / segments  -- 0 to 1 (full circle in Picotron)
			local x = ring_radius * cos(theta)
			local z = ring_radius * sin(theta)
			add(verts, vec(x, y, z))
		end
	end

	-- Generate faces (triangles with correct winding) with UV mapping
	for stack = 0, stacks - 1 do
		for seg = 0, segments - 1 do
			local current = stack * (segments + 1) + seg + 1
			local next_stack = current + segments + 1

			-- Calculate UV coordinates for spherical mapping
			local u0 = (seg / segments) * sprite_w
			local u1 = ((seg + 1) / segments) * sprite_w
			local v0 = (stack / stacks) * sprite_h
			local v1 = ((stack + 1) / stacks) * sprite_h

			-- Two triangles per quad (flipped winding for outward-facing normals)
			add(faces, {
				current, current + 1, next_stack,
				sprite_id,
				vec(u0, v0), vec(u1, v0), vec(u0, v1)
			})

			add(faces, {
				next_stack, current + 1, next_stack + 1,
				sprite_id,
				vec(u0, v1), vec(u1, v0), vec(u1, v1)
			})
		end
	end

	return {verts = verts, faces = faces, name = "sphere"}
end

function _init()
	-- Initialize color table for lit rendering
	RendererLit.init_color_table()

	-- Generate background stars
	generate_stars()

	-- Create a low-poly sphere (from config)
	local sphere_cfg = Config.sphere
	model_sphere = create_sphere(sphere_cfg.radius, sphere_cfg.segments, sphere_cfg.stacks)
	printh("Sphere created: " .. #model_sphere.verts .. " vertices, " .. #model_sphere.faces .. " faces")

	-- Create a textured planet sphere (from config)
	local planet_cfg = Config.planet
	model_planet = create_sphere(
		planet_cfg.radius,
		planet_cfg.segments,
		planet_cfg.stacks,
		planet_cfg.sprite_id,
		64,  -- Sprite width (64x32 for sprite 24)
		32   -- Sprite height
	)
	printh("Planet created: " .. #model_planet.verts .. " vertices, " .. #model_planet.faces .. " faces")

	-- Try to load the shippy model (from config)
	local load_obj = require("src.engine.obj_loader")
	model_shippy = load_obj(Config.ship.model_file)

	if model_shippy then
		printh("Shippy loaded: " .. #model_shippy.verts .. " vertices, " .. #model_shippy.faces .. " faces")
	else
		printh("WARNING: Failed to load " .. Config.ship.model_file)
	end
end

function _update()
	-- Mouse orbit controls
	local mx, my, mb = mouse()

	if mb & 1 == 1 then  -- Left mouse button
		if not mouse_drag then
			-- Start dragging
			mouse_drag = true
			last_mouse_x = mx
			last_mouse_y = my
		else
			-- Continue dragging
			local dx = mx - last_mouse_x
			local dy = my - last_mouse_y

			-- Update camera rotation (Y axis up)
			camera.ry = camera.ry + dx * Config.camera.orbit_sensitivity  -- yaw (rotate around Y)
			camera.rx = camera.rx + dy * Config.camera.orbit_sensitivity  -- pitch (rotate around X)

			-- Clamp pitch to avoid gimbal lock
			camera.rx = mid(-1.5, camera.rx, 1.5)

			last_mouse_x = mx
			last_mouse_y = my
		end
	else
		mouse_drag = false
	end

	-- WASD controls for light rotation
	local light_rotation_speed = Config.lighting.rotation_speed
	if keyp("left") or keyp("a") then
		light_yaw = light_yaw - light_rotation_speed
	end
	if keyp("right") or keyp("d") then
		light_yaw = light_yaw + light_rotation_speed
	end
	if keyp("up") or keyp("w") then
		light_pitch = light_pitch - light_rotation_speed
	end
	if keyp("down") or keyp("s") then
		light_pitch = light_pitch + light_rotation_speed
	end

	-- Clamp light pitch to reasonable range
	light_pitch = mid(-1.5, light_pitch, 1.5)

	-- Update planet rotation
	planet_rotation = planet_rotation + Config.planet.spin_speed
end


function _draw()
	cls(0)  -- Clear to dark blue

	-- Draw stars first (before everything else)
	draw_stars()

	if not model_shippy then
		print("no model loaded!", 10, 50, 8)
		return
	end

	local all_faces = {}

	-- Calculate current light direction from yaw and pitch
	local light_dir = get_light_direction()

	-- Render planet with lit shader (same as ship)
	if model_planet then
		local planet_pos = Config.planet.position
		local planet_rot = Config.planet.rotation

		local planet_faces = RendererLit.render_mesh(
			model_planet.verts, model_planet.faces, camera,
			planet_pos.x, planet_pos.y, planet_pos.z,
			nil,  -- sprite override (use sprite from model = sprite 24)
			light_dir,  -- light direction (directional light)
			nil,  -- light radius (unused for directional)
			light_brightness,  -- light brightness
			ambient,  -- ambient light
			false,  -- is_ground
			planet_rot.pitch, planet_rotation, planet_rot.roll,  -- Use planet_rotation for yaw
			Config.rendering.render_distance
		)

		-- Add planet faces to all_faces
		for i = 1, #planet_faces do
			add(all_faces, planet_faces[i])
		end
	end

	-- Render ship (from config)
	if model_shippy then
		local ship_pos = Config.ship.position
		local ship_rot = Config.ship.rotation
		local shippy_faces = RendererLit.render_mesh(
			model_shippy.verts, model_shippy.faces, camera,
			ship_pos.x, ship_pos.y, ship_pos.z,
			nil,  -- sprite override (use sprite from model = sprite 1)
			light_dir,  -- light direction (directional light)
			nil,  -- light radius (unused for directional)
			light_brightness,  -- light brightness
			ambient,  -- ambient light
			false,  -- is_ground
			ship_rot.pitch, ship_rot.yaw, ship_rot.roll,
			Config.rendering.render_distance
		)

		-- Add all faces
		for i = 1, #shippy_faces do
			add(all_faces, shippy_faces[i])
		end
	end

	-- Sort all faces by depth
	RendererLit.sort_faces(all_faces)

	-- Draw faces using lit rendering with color tables
	RendererLit.draw_faces(all_faces)

	-- CPU usage (always visible if Config.show_cpu is true)
	if Config.show_cpu then
		local cpu = stat(1) * 100
		print("cpu: " .. flr(cpu) .. "%", 380, 2, cpu > 80 and 8 or 7)
	end

	-- Debug UI (only visible when Config.debug is true)
	if Config.debug then
		-- Control hints
		print("mouse: orbit camera", 2, 2, 7)
		print("wasd: rotate light", 2, 10, 7)
		print("faces: " .. #all_faces, 2, 18, 7)

		-- Light rotation info
		print("light yaw: " .. flr(light_yaw * 100) / 100, 2, 26, 7)
		print("light pitch: " .. flr(light_pitch * 100) / 100, 2, 34, 7)

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
end

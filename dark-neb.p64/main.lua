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
	y = Config.camera.height or 0,  -- Camera elevation above ground
	z = 0,
	rx = Config.camera.rx,
	ry = Config.camera.ry,
	distance = Config.camera.distance,
}

-- Target camera rotation (for smoothing)
local target_rx = Config.camera.rx
local target_ry = Config.camera.ry

-- Mouse orbit state
local mouse_drag = false
local last_mouse_x = 0
local last_mouse_y = 0

-- Ship speed control
local ship_speed = Config.ship.speed
local target_ship_speed = Config.ship.speed

-- Speed slider state
local slider_dragging = false
local slider_x = 450  -- Right side of screen
local slider_y = 50   -- Top position
local slider_height = 150
local slider_width = 10
local slider_handle_height = 20

-- Light settings (from config)
local light_yaw = Config.lighting.yaw
local light_pitch = Config.lighting.pitch
local light_brightness = Config.lighting.brightness
local ambient = Config.lighting.ambient

-- Ship heading control
local ship_heading = Config.ship.heading
local target_heading = Config.ship.target_heading

-- Raycast intersection for visualization
local raycast_x = nil
local raycast_z = nil

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
-- Uses simplified transformation (NOT camera-relative) for raycast compatibility
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

-- Raycast from screen coordinates to horizontal plane (y=0, normal 0,1,0)
-- Inverts the simplified project_point transformation
-- Returns world x,z coordinates where ray intersects the plane, or nil if no intersection
function raycast_to_ground_plane(screen_x, screen_y, camera)
	local cam_dist = camera.distance or 5
	local tan_half_fov = 0.7002075
	local proj_scale = 270 / tan_half_fov

	-- Camera rotation
	local sin_ry, cos_ry = sin(camera.ry), cos(camera.ry)
	local sin_rx, cos_rx = sin(camera.rx), cos(camera.rx)

	-- Unproject screen to view space at arbitrary depth
	-- From: px = -x1 / z3 * proj_scale + 240
	--       py = -y2 / z3 * proj_scale + 135
	local z3 = cam_dist + 10
	local neg_x1 = (screen_x - 240) / proj_scale * z3
	local neg_y2 = (screen_y - 135) / proj_scale * z3
	local x1 = -neg_x1
	local y2 = -neg_y2

	-- Invert pitch rotation
	-- Forward was: y2 = y * cos_rx - z1 * sin_rx
	--              z2 = y * sin_rx + z1 * cos_rx
	-- Inverse (rotation matrix transpose):
	local z2 = z3 - cam_dist
	local y = y2 * cos_rx - z2 * sin_rx
	local z1 = y2 * sin_rx + z2 * cos_rx

	-- Invert yaw rotation
	-- x1 = x * cos_ry - z * sin_ry
	-- z1 = x * sin_ry + z * cos_ry
	local x = x1 * cos_ry + z1 * sin_ry
	local z = -x1 * sin_ry + z1 * cos_ry

	-- Ray direction from origin (0,0,0) through (x, y, z)
	local ray_len = sqrt(x*x + y*y + z*z)
	if ray_len < 0.0001 then
		return nil, nil
	end
	local ray_x = x / ray_len
	local ray_y = y / ray_len
	local ray_z = z / ray_len

	-- Intersect with y=0 plane
	if abs(ray_y) < 0.0001 then
		return nil, nil
	end

	local t = -y / ray_y
	if t < 0 then
		return nil, nil
	end

	return t * ray_x, t * ray_z
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

-- Transformed star positions (created once, reused each frame)
local star_transformed = nil

-- Draw stars in background using batch matrix multiplication
function draw_stars()
	if not star_positions then return end

	-- Create transformed positions userdata if needed (reuse each frame)
	if not star_transformed then
		star_transformed = userdata("f64", 4, Config.stars.count)
	end

	-- Build camera transformation matrix for batch processing
	-- Negate camera rotation to make stars rotate opposite to camera (fixed background)
	local sin_ry, cos_ry = sin(-camera.ry), cos(-camera.ry)
	local sin_rx, cos_rx = sin(-camera.rx), cos(-camera.rx)
	local cam_dist = camera.distance or 30

	-- Create 3x4 transformation matrix for matmul3d (3 columns, 4 rows)
	-- This matches the transformation in project_point()
	local mat = userdata("f64", 3, 4)

	-- Column 0 (x output = -x1 = -(x*cos_ry - z*sin_ry))
	mat:set(0, 0, -cos_ry)
	mat:set(0, 1, 0)
	mat:set(0, 2, sin_ry)
	mat:set(0, 3, 0)

	-- Column 1 (y output = -y2 = -(y*cos_rx - z1*sin_rx))
	mat:set(1, 0, sin_ry * sin_rx)
	mat:set(1, 1, -cos_rx)
	mat:set(1, 2, cos_ry * sin_rx)
	mat:set(1, 3, 0)

	-- Column 2 (z output = z1*cos_rx + y*sin_rx + cam_dist)
	mat:set(2, 0, sin_ry * cos_rx)
	mat:set(2, 1, sin_rx)
	mat:set(2, 2, cos_ry * cos_rx)
	mat:set(2, 3, cam_dist)

	-- Batch transform all stars at once
	-- star_positions is 4 columns × N rows (x,y,z,color per column)
	-- Copy original data, then transform in place
	star_transformed:copy(star_positions, true)
	star_transformed:matmul3d(mat, star_transformed, 1)

	-- Project and draw stars
	local tan_half_fov = 0.7002075
	local proj_scale = 270 / tan_half_fov

	for i = 0, Config.stars.count - 1 do
		local x = star_transformed:get(0, i)
		local y = star_transformed:get(1, i)
		local z = star_transformed:get(2, i)
		local color = star_positions:get(3, i)  -- Color unchanged from original

		-- Project to screen (perspective divide)
		if z > 0.01 then
			local inv_z = 1 / z
			local px = -x * inv_z * proj_scale + 240
			local py = -y * inv_z * proj_scale + 135
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



-- Create a UV-mapped sphere (from ld58.p64)
-- Uses proper UV wrapping for 64x32 texture sprites
function create_sphere(radius, segments, stacks, sprite_id, sprite_w, sprite_h)
	local verts = {}
	local faces = {}

	-- Use ld58 parameters if not provided
	local rings = stacks or 6  -- 6 height segments (latitude)
	segments = segments or 8  -- 8 sides (longitude)
	sprite_id = sprite_id or 1
	sprite_w = sprite_w or 64
	sprite_h = sprite_h or 32

	-- Generate vertices in rings from top to bottom
	-- Top vertex (north pole)
	add(verts, vec(0, radius, 0))

	-- Middle rings (latitude)
	for ring = 1, rings - 1 do
		local v = ring / rings  -- Vertical position (0 to 1)
		local angle_v = v * 0.5  -- Angle from top (0 to 0.5 turns)
		local y = cos(angle_v) * radius
		local ring_radius = sin(angle_v) * radius

		-- Vertices around the ring (longitude)
		for seg = 0, segments - 1 do
			local angle_h = seg / segments  -- Horizontal angle (0 to 1 turn)
			local x = cos(angle_h) * ring_radius
			local z = sin(angle_h) * ring_radius
			add(verts, vec(x, y, z))
		end
	end

	-- Bottom vertex (south pole)
	add(verts, vec(0, -radius, 0))

	-- UV scale for sprite
	local uv_scale_u = sprite_w
	local uv_scale_v = sprite_h
	local uv_offset = -uv_scale_v  -- Slide UVs down by half

	-- Generate faces
	-- Top cap (connect first ring to top vertex)
	for seg = 0, segments - 1 do
		local next_seg = (seg + 1) % segments
		local v1 = 1  -- Top vertex
		local v2 = 2 + seg
		local v3 = 2 + next_seg

		-- UV coordinates (shifted down by half, inverted Y axis)
		local u1 = (seg + 0.5) / segments * uv_scale_u
		local u2 = seg / segments * uv_scale_u
		local u3 = (seg + 1) / segments * uv_scale_u
		local v_top = uv_scale_v - (0 + uv_offset)
		local v_ring1 = uv_scale_v - ((1 / rings) * uv_scale_v + uv_offset)

		-- Reverse winding order: v1, v3, v2 instead of v1, v2, v3
		add(faces, {v1, v3, v2, sprite_id,
			vec(u1, v_top), vec(u3, v_ring1), vec(u2, v_ring1)})
	end

	-- Middle rings
	for ring = 0, rings - 3 do
		local ring_start = 2 + ring * segments
		local next_ring_start = 2 + (ring + 1) * segments

		for seg = 0, segments - 1 do
			local next_seg = (seg + 1) % segments

			-- Two triangles per quad
			local v1 = ring_start + seg
			local v2 = ring_start + next_seg
			local v3 = next_ring_start + next_seg
			local v4 = next_ring_start + seg

			-- UV coordinates (shifted down by half, inverted Y axis)
			local u1 = seg / segments * uv_scale_u
			local u2 = (seg + 1) / segments * uv_scale_u
			local v1_uv = uv_scale_v - ((ring + 1) / rings * uv_scale_v + uv_offset)
			local v2_uv = uv_scale_v - ((ring + 2) / rings * uv_scale_v + uv_offset)

			-- First triangle
			add(faces, {v1, v2, v3, sprite_id,
				vec(u1, v1_uv), vec(u2, v1_uv), vec(u2, v2_uv)})
			-- Second triangle
			add(faces, {v1, v3, v4, sprite_id,
				vec(u1, v1_uv), vec(u2, v2_uv), vec(u1, v2_uv)})
		end
	end

	-- Bottom cap (connect last ring to bottom vertex)
	local last_ring_start = 2 + (rings - 2) * segments
	local bottom_vertex = #verts
	for seg = 0, segments - 1 do
		local next_seg = (seg + 1) % segments
		local v1 = last_ring_start + seg
		local v2 = last_ring_start + next_seg
		local v3 = bottom_vertex

		-- UV coordinates (shifted down by half, inverted Y axis)
		local u1 = seg / segments * uv_scale_u
		local u2 = (seg + 1) / segments * uv_scale_u
		local u_center = (seg + 0.5) / segments * uv_scale_u

		add(faces, {v1, v2, v3, sprite_id,
			vec(u1, uv_scale_v - (uv_scale_v * (rings - 1) / rings + uv_offset)),
			vec(u2, uv_scale_v - (uv_scale_v * (rings - 1) / rings + uv_offset)),
			vec(u_center, uv_scale_v - (uv_scale_v + uv_offset))})
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

	-- Check if mouse is over slider
	local over_slider = mx >= slider_x - 5 and mx <= slider_x + slider_width + 5 and
	                    my >= slider_y and my <= slider_y + slider_height

	if mb & 1 == 1 then  -- Left mouse button
		if over_slider then
			-- Drag slider
			slider_dragging = true
			-- Calculate target speed from mouse Y position
			local slider_pos = mid(0, (my - slider_y) / slider_height, 1)
			target_ship_speed = (1 - slider_pos)  -- Inverted (top = max speed)
		elseif not slider_dragging then
			-- Camera orbit
			if not mouse_drag then
				-- Start dragging
				mouse_drag = true
				last_mouse_x = mx
				last_mouse_y = my
			else
				-- Continue dragging
				local dx = mx - last_mouse_x
				local dy = my - last_mouse_y

				-- Update target camera rotation (Y axis up)
				target_ry = target_ry + dx * Config.camera.orbit_sensitivity  -- yaw (rotate around Y)
				target_rx = target_rx + dy * Config.camera.orbit_sensitivity  -- pitch (rotate around X)

				-- Clamp target pitch to avoid gimbal lock
				target_rx = mid(-1.5, target_rx, 1.5)

				last_mouse_x = mx
				last_mouse_y = my
			end
		end
	else
		mouse_drag = false
		slider_dragging = false
	end

	-- Always update raycast position for crosshair visualization
	raycast_x, raycast_z = raycast_to_ground_plane(mx, my, camera)

	-- Right-click to set ship heading
	if mb & 2 == 2 and not (mb & 1 == 1) then  -- Right mouse button only (not both)
		-- Log camera state
		printh("Camera: pos(" .. flr(camera.x*10)/10 .. "," .. flr(camera.y*10)/10 .. "," .. flr(camera.z*10)/10 .. ") rot(" .. flr(camera.rx*100)/100 .. "," .. flr(camera.ry*100)/100 .. ")")
		printh("Mouse: (" .. mx .. "," .. my .. ")")

		if raycast_x and raycast_z then
			printh("Raycast SUCCESS: world(" .. flr(raycast_x*10)/10 .. "," .. flr(raycast_z*10)/10 .. ")")

			-- Verify raycast by projecting back to screen
			local verify_px, verify_py = project_point(raycast_x, 0, raycast_z, camera)
			if verify_px then
				printh("  Verification: projects back to screen (" .. flr(verify_px) .. "," .. flr(verify_py) .. ")")
				printh("  Error: dx=" .. flr(verify_px - mx) .. " dy=" .. flr(verify_py - my))
			end

			-- Calculate direction from ship to target point
			local ship_x = Config.ship.position.x
			local ship_z = Config.ship.position.z
			local dx = raycast_x - ship_x
			local dz = raycast_z - ship_z

			-- Calculate target heading (atan2 gives angle in turns, 0-1 range)
			-- We want 0 = +Z axis, so we use atan2(dx, dz)
			-- atan2 in Picotron returns turns (0-1), not radians
			target_heading = atan2(dx, dz)
		else
			printh("Raycast FAILED: returned nil")
		end
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

	-- Smooth camera rotation (lerp towards target)
	local smoothing = 0.2  -- Lower = smoother (0.1-0.3 range)
	camera.rx = camera.rx + (target_rx - camera.rx) * smoothing
	camera.ry = camera.ry + (target_ry - camera.ry) * smoothing

	-- Smooth ship speed (lerp towards target)
	ship_speed = ship_speed + (target_ship_speed - ship_speed) * Config.ship.speed_smoothing

	-- Smooth ship heading rotation towards target
	-- Calculate shortest rotation direction (handle wrap-around)
	-- Normalize both angles to [0, 1) first
	local normalized_target = target_heading % 1.0
	local normalized_current = ship_heading % 1.0

	-- Calculate difference and wrap to [-0.5, 0.5] for shortest path
	local heading_diff = normalized_target - normalized_current
	if heading_diff > 0.5 then
		heading_diff = heading_diff - 1.0
	elseif heading_diff < -0.5 then
		heading_diff = heading_diff + 1.0
	end

	-- Apply turn rate (limit rotation speed)
	local turn_amount = mid(-Config.ship.turn_rate, heading_diff, Config.ship.turn_rate)
	ship_heading = (ship_heading + turn_amount) % 1.0

	-- Move ship in direction of heading based on speed
	if ship_speed > 0.01 then
		local move_speed = ship_speed * Config.ship.max_speed * 0.1  -- Scale for reasonable movement
		Config.ship.position.x = Config.ship.position.x + sin(ship_heading) * move_speed
		Config.ship.position.z = Config.ship.position.z + cos(ship_heading) * move_speed
	end

	-- Camera follows ship (focus point tracks ship position)
	camera.x = Config.ship.position.x
	camera.z = Config.ship.position.z
	-- Keep camera height from config
	camera.y = Config.camera.height or 0

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
			ship_rot.pitch, ship_heading, ship_rot.roll,  -- Use ship_heading for yaw
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

	-- Draw raycast crosshair (shows where mouse points on ground plane)
	if raycast_x and raycast_z then
		local cross_size = 0.5  -- Size of crosshair arms
		-- Draw crosshair on the ground plane (y=0)
		draw_line_3d(raycast_x - cross_size, 0, raycast_z, raycast_x + cross_size, 0, raycast_z, camera, 12)  -- Horizontal line (red)
		draw_line_3d(raycast_x, 0, raycast_z - cross_size, raycast_x, 0, raycast_z + cross_size, camera, 12)  -- Vertical line (red)
	end

	-- Draw heading arc (shows ship's turn path)
	-- Use same shortest-path calculation as movement
	local normalized_target = target_heading % 1.0
	local normalized_current = ship_heading % 1.0
	local heading_diff = normalized_target - normalized_current
	if heading_diff > 0.5 then
		heading_diff = heading_diff - 1.0
	elseif heading_diff < -0.5 then
		heading_diff = heading_diff + 1.0
	end

	-- Only draw arc if there's a significant heading difference (0.01 turns ≈ 3.6 degrees)
	if abs(heading_diff) > 0.01 then
		local ship_x = Config.ship.position.x
		local ship_z = Config.ship.position.z
		local arc_radius = Config.ship.heading_arc_radius
		local segments = Config.ship.heading_arc_segments

		-- Draw arc from current heading to target heading
		local start_angle = ship_heading
		local arc_color = 10  -- Yellow

		for i = 0, segments - 1 do
			local t1 = i / segments
			local t2 = (i + 1) / segments

			-- Interpolate angle
			local angle1 = start_angle + heading_diff * t1
			local angle2 = start_angle + heading_diff * t2

			-- Calculate 3D positions on the arc
			local x1 = ship_x + sin(angle1) * arc_radius
			local z1 = ship_z + cos(angle1) * arc_radius
			local x2 = ship_x + sin(angle2) * arc_radius
			local z2 = ship_z + cos(angle2) * arc_radius

			-- Project to screen and draw line
			draw_line_3d(x1, 0, z1, x2, 0, z2, camera, arc_color)
		end

		-- Draw target heading line
		local target_x = ship_x + sin(target_heading) * arc_radius
		local target_z = ship_z + cos(target_heading) * arc_radius
		draw_line_3d(ship_x, 0, ship_z, target_x, 0, target_z, camera, 11)  -- Bright yellow
	end

	-- Draw speed slider
	-- Slider track (background)
	rectfill(slider_x, slider_y, slider_x + slider_width, slider_y + slider_height, 1)

	-- Current speed fill (shows actual ship speed - acceleration progress)
	local speed_fill_height = ship_speed * slider_height
	local speed_fill_y = slider_y + slider_height - speed_fill_height
	if speed_fill_height > 0 then
		rectfill(slider_x, speed_fill_y, slider_x + slider_width, slider_y + slider_height, 11)  -- Bright cyan fill
	end

	-- Slider border
	rect(slider_x, slider_y, slider_x + slider_width, slider_y + slider_height, 7)

	-- Slider handle (position based on target speed)
	local handle_y = slider_y + (1 - target_ship_speed) * slider_height - slider_handle_height / 2
	handle_y = mid(slider_y, handle_y, slider_y + slider_height - slider_handle_height)
	rectfill(slider_x - 2, handle_y, slider_x + slider_width + 2, handle_y + slider_handle_height, 7)
	rect(slider_x - 2, handle_y, slider_x + slider_width + 2, handle_y + slider_handle_height, 6)

	-- Speed value text
	local speed_display = flr(ship_speed * Config.ship.max_speed * 10) / 10
	print("speed: " .. speed_display, slider_x - 30, slider_y + slider_height + 10, 7)

	-- CPU usage (always visible if Config.show_cpu is true)
	if Config.show_cpu then
		local cpu = stat(1) * 100
		print("cpu: " .. flr(cpu) .. "%", 380, 2, cpu > 80 and 8 or 7)
	end

	-- Camera angles display
	print("cam pitch: " .. flr(camera.rx * 100) / 100, 2, 2, 7)
	print("cam yaw: " .. flr(camera.ry * 100) / 100, 2, 10, 7)
	print("ship heading: " .. flr(ship_heading * 100) / 100, 2, 18, 7)
	print("target heading: " .. flr(target_heading * 100) / 100, 2, 26, 7)

	-- Raycast debug display
	if raycast_x and raycast_z then
		print("raycast x: " .. flr(raycast_x * 10) / 10, 2, 34, 7)
		print("raycast z: " .. flr(raycast_z * 10) / 10, 2, 42, 7)
	else
		print("raycast: nil", 2, 34, 8)
	end

	-- Lighting debug (only visible when Config.debug_lighting is true)
	if Config.debug_lighting then
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

	-- Full debug UI (only visible when Config.debug is true)
	if Config.debug then
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
end

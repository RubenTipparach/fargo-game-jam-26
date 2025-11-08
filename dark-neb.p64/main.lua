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
Quat = include("src/engine/quaternion.lua")
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

-- Ship heading control - using direction vectors instead of angles
-- Initialize heading as direction vector (start facing +Z)
local ship_heading_dir = {x = 0, z = 1}  -- Start facing +Z
local target_heading_dir = {x = 0, z = 1}
local rotation_start_dir = {x = 0, z = 1}  -- Starting direction when rotation begins
local rotation_progress = 0  -- Accumulator for SLERP (0 to 1)

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
-- Transforms from world space to screen space accounting for camera position and rotation
function project_point(x, y, z, camera)
	local cam_dist = camera.distance or 5
	local tan_half_fov = 0.7002075
	local proj_scale = 270 / tan_half_fov

	-- Translate to camera space (relative to focus point)
	local cx = x - camera.x
	local cy = y - camera.y
	local cz = z - camera.z

	-- Apply camera rotation
	local sin_ry, cos_ry = sin(camera.ry), cos(camera.ry)
	local sin_rx, cos_rx = sin(camera.rx), cos(camera.rx)

	-- Yaw rotation (around Y axis)
	local x1 = cx * cos_ry - cz * sin_ry
	local z1 = cx * sin_ry + cz * cos_ry

	-- Pitch rotation (around X axis)
	local y2 = cy * cos_rx - z1 * sin_rx
	local z2 = cy * sin_rx + z1 * cos_rx

	-- Add camera distance and negate for view space
	local x3 = -x1
	local y3 = -y2
	local z3 = z2 + cam_dist

	-- Project to screen
	if z3 > 0.01 then
		local inv_z = 1 / z3
		local px = x3 * inv_z * proj_scale + 240
		local py = y3 * inv_z * proj_scale + 135
		return px, py, z3
	end
	return nil, nil, nil
end

-- Unproject a screen point to world space at a given view space depth
local function unproject_point(screen_x, screen_y, view_z, camera)
	local cam_dist = camera.distance or 5
	local tan_half_fov = 0.7002075
	local proj_scale = 270 / tan_half_fov

	-- Camera rotation
	local sin_ry, cos_ry = sin(camera.ry), cos(camera.ry)
	local sin_rx, cos_rx = sin(camera.rx), cos(camera.rx)

	-- Unproject screen to view space
	-- From: px = x3 / z3 * proj_scale + 240
	--       py = y3 / z3 * proj_scale + 135
	local z3 = view_z
	local x3 = (screen_x - 240) / proj_scale * z3
	local y3 = (screen_y - 135) / proj_scale * z3

	-- Invert negation: x3 = -x1, y3 = -y2
	local x1 = -x3
	local y2 = -y3

	-- Invert camera distance: z3 = z2 + cam_dist
	local z2 = z3 - cam_dist

	-- Invert pitch rotation (transpose of rotation matrix)
	local cy = y2 * cos_rx + z2 * sin_rx
	local z1 = -y2 * sin_rx + z2 * cos_rx

	-- Invert yaw rotation (transpose of rotation matrix)
	local cx = x1 * cos_ry + z1 * sin_ry
	local cz = -x1 * sin_ry + z1 * cos_ry

	-- cx, cy, cz are in camera space (relative to focus point)
	-- Convert to world space by adding focus point
	local world_x = cx + camera.x
	local world_y = cy + camera.y
	local world_z = cz + camera.z

	return world_x, world_y, world_z
end

-- Raycast from screen coordinates to horizontal plane (y=0, normal 0,1,0)
-- Returns world x,z coordinates where ray intersects the plane, or nil if no intersection
function raycast_to_ground_plane(screen_x, screen_y, camera)
	-- Unproject at two depths to get ray origin and direction
	-- Use near and far points in view space
	local near_x, near_y, near_z = unproject_point(screen_x, screen_y, 0.1, camera)
	local far_x, far_y, far_z = unproject_point(screen_x, screen_y, 100, camera)

	-- Ray origin is the near point
	local ray_origin_x = near_x
	local ray_origin_y = near_y
	local ray_origin_z = near_z

	-- Ray direction is from near to far
	local ray_x = far_x - near_x
	local ray_y = far_y - near_y
	local ray_z = far_z - near_z

	-- Normalize ray direction
	local ray_len = sqrt(ray_x*ray_x + ray_y*ray_y + ray_z*ray_z)
	if ray_len < 0.0001 then
		return nil, nil
	end
	ray_x = ray_x / ray_len
	ray_y = ray_y / ray_len
	ray_z = ray_z / ray_len

	-- Intersect with y=0 plane
	-- Ray: P = origin + t * dir
	-- Plane: y = 0
	-- origin_y + t * ray_y = 0
	if abs(ray_y) < 0.0001 then
		return nil, nil
	end

	local t = -ray_origin_y / ray_y

	if t < 0 then
		return nil, nil
	end

	local hit_x = ray_origin_x + t * ray_x
	local hit_z = ray_origin_z + t * ray_z
	return hit_x, hit_z
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

-- Quaternion-based rotation system
-- Convert direction vector (2D on XZ plane) to quaternion (rotation around Y axis)
local function dir_to_quat(dir)
	-- Normalize direction
	local len = sqrt(dir.x * dir.x + dir.z * dir.z)
	if len < 0.0001 then
		-- Default to identity (no rotation, facing +Z)
		return {w = 1, x = 0, y = 0, z = 0}
	end
	local norm_x = dir.x / len
	local norm_z = dir.z / len

	-- Quaternion for rotation around Y axis
	-- For direction (x, z), we need rotation from (0, 1) to (x, z)
	-- Using half-angle formula for Y-axis rotation quaternion:
	-- q = (cos(θ/2), 0, sin(θ/2), 0) where θ is angle from +Z axis

	-- cos(θ) = dot product with +Z = norm_z
	-- sin(θ) = cross product with +Z = norm_x (for Y component)

	-- Half-angle formulas:
	-- cos(θ/2) = sqrt((1 + cos(θ)) / 2)
	-- sin(θ/2) = sign(sin(θ)) * sqrt((1 - cos(θ)) / 2)

	local cos_theta = norm_z
	local sin_theta = norm_x

	local half_cos = sqrt((1 + cos_theta) / 2)
	local half_sin = (sin_theta >= 0 and 1 or -1) * sqrt((1 - cos_theta) / 2)

	return {
		w = half_cos,
		x = 0,
		y = half_sin,  -- Rotation around Y axis
		z = 0
	}
end

-- Convert quaternion back to direction vector (2D on XZ plane)
local function quat_to_dir(q)
	-- For Y-axis rotation, extract direction by rotating (0, 0, 1) by quaternion
	-- Using quaternion rotation formula: v' = q * v * q^-1
	-- For unit quaternion and v = (0, 0, 1):
	-- x' = 2(xz + wy)
	-- z' = 1 - 2(x² + y²)

	local x = 2 * (q.x * q.z + q.w * q.y)
	local z = 1 - 2 * (q.x * q.x + q.y * q.y)

	-- Normalize to ensure unit vector (handles floating point errors)
	local len = sqrt(x * x + z * z)
	if len > 0.0001 then
		x = x / len
		z = z / len
	end

	return {x = x, z = z}
end

-- Convert direction vector to angle (in turns, 0-1 range)
-- For rendering AND verification - used to check rotation progress
local function dir_to_angle(dir)
	-- atan2(y, x) in Picotron returns angle in turns (0-1 range)
	return atan2(dir.x, dir.z)
end

-- Calculate angle difference between two directions (in turns, 0-1 range)
-- Returns the shortest angular distance between two directions
local function angle_difference(dir1, dir2)
	local angle1 = dir_to_angle(dir1)
	local angle2 = dir_to_angle(dir2)

	-- Calculate difference and wrap to [-0.5, 0.5] range (shortest path)
	local diff = angle2 - angle1
	if diff > 0.5 then
		diff = diff - 1
	elseif diff < -0.5 then
		diff = diff + 1
	end

	-- Return absolute value
	if diff < 0 then
		return -diff
	else
		return diff
	end
end

-- Quaternion SLERP with max turn rate
local function quat_slerp(q1, q2, max_turn_rate)
	-- Calculate dot product
	local dot = q1.w * q2.w + q1.x * q2.x + q1.y * q2.y + q1.z * q2.z

	-- If dot < 0, negate q2 to take shorter path
	if dot < 0 then
		q2 = {w = -q2.w, x = -q2.x, y = -q2.y, z = -q2.z}
		dot = -dot
	end

	-- Clamp dot to valid range
	if dot > 1 then dot = 1 end
	if dot < -1 then dot = -1 end

	-- Calculate angle between quaternions (in turns)
	-- acos(dot) gives angle in turns (Picotron's acos equivalent)
	-- We need: theta = acos(dot)
	-- Using: acos(x) = atan2(sqrt(1-x²), x)
	local theta = atan2(sqrt(1 - dot * dot), dot)

	-- Limit to max turn rate
	if theta > max_turn_rate then
		theta = max_turn_rate
	end

	-- Calculate full angle for interpolation factor
	local full_theta = atan2(sqrt(1 - dot * dot), dot)

	-- If already at target, return q1
	if full_theta < 0.00001 then
		return {w = q1.w, x = q1.x, y = q1.y, z = q1.z}
	end

	local t = theta / full_theta

	-- Perform SLERP
	local sin_full = sin(full_theta)
	if abs(sin_full) < 0.0001 then
		-- Linear interpolation fallback
		local result_w = q1.w + t * (q2.w - q1.w)
		local result_x = q1.x + t * (q2.x - q1.x)
		local result_y = q1.y + t * (q2.y - q1.y)
		local result_z = q1.z + t * (q2.z - q1.z)
		-- Normalize
		local len = sqrt(result_w*result_w + result_x*result_x + result_y*result_y + result_z*result_z)
		return {w = result_w/len, x = result_x/len, y = result_y/len, z = result_z/len}
	end

	local a = sin((1 - t) * full_theta) / sin_full
	local b = sin(t * full_theta) / sin_full

	return {
		w = a * q1.w + b * q2.w,
		x = a * q1.x + b * q2.x,
		y = a * q1.y + b * q2.y,
		z = a * q1.z + b * q2.z
	}
end

-- Model data
local model_shippy = nil
local model_sphere = nil
local model_planet = nil
local planet_rotation = 0

-- Particle trails (speedlines) - simple array of line segments
local particle_trails = {}  -- Array of {x1, z1, x2, z2, age, lifetime}



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

			-- Calculate direction from ship to target point (normalized)
			local ship_x = Config.ship.position.x
			local ship_z = Config.ship.position.z
			local dir_x = raycast_x - ship_x
			local dir_z = raycast_z - ship_z

			-- Normalize direction vector
			local len = sqrt(dir_x * dir_x + dir_z * dir_z)
			if len > 0.0001 then
				target_heading_dir = {x = dir_x / len, z = dir_z / len}
				rotation_start_dir = {x = ship_heading_dir.x, z = ship_heading_dir.z}  -- Store current as start
				rotation_progress = 0  -- Reset accumulator when target changes

				-- Log heading directions and positions for debugging
				printh("  Ship heading dir: (" .. flr(ship_heading_dir.x*1000)/1000 .. "," .. flr(ship_heading_dir.z*1000)/1000 .. ")")
				printh("  Target heading dir: (" .. flr(target_heading_dir.x*1000)/1000 .. "," .. flr(target_heading_dir.z*1000)/1000 .. ")")

				-- Calculate and log the current heading position (blue line)
				local current_heading_x = ship_x + ship_heading_dir.x * Config.ship.heading_arc_radius
				local current_heading_z = ship_z + ship_heading_dir.z * Config.ship.heading_arc_radius
				printh("  Current heading pos (blue): (" .. flr(current_heading_x*10)/10 .. "," .. flr(current_heading_z*10)/10 .. ")")

				-- Calculate and log the planned heading position (yellow line)
				local planned_x = ship_x + target_heading_dir.x * Config.ship.heading_arc_radius
				local planned_z = ship_z + target_heading_dir.z * Config.ship.heading_arc_radius
				printh("  Planned heading pos (yellow): (" .. flr(planned_x*10)/10 .. "," .. flr(planned_z*10)/10 .. ")")

				-- Calculate dot product to show how different they are
				local dot = ship_heading_dir.x * target_heading_dir.x + ship_heading_dir.z * target_heading_dir.z
				printh("  Heading dot product: " .. flr(dot * 1000) / 1000)
			end
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

	-- Simple rotation: rotate direction vector at constant angular velocity
	-- Calculate angle to target using atan2 (returns angle in turns, 0-1 range)
	local current_angle = atan2(ship_heading_dir.x, ship_heading_dir.z)
	local target_angle = atan2(target_heading_dir.x, target_heading_dir.z)

	-- Calculate shortest angular difference (wraps around 0/1 boundary)
	local angle_diff = target_angle - current_angle
	if angle_diff > 0.5 then
		angle_diff = angle_diff - 1
	elseif angle_diff < -0.5 then
		angle_diff = angle_diff + 1
	end

	-- Only rotate if not already at target (tolerance: 0.0001 turns)
	if abs(angle_diff) > 0.0001 then
		-- Always rotate at constant turn_rate
		-- Determine direction: positive or negative
		local rotation_amount = angle_diff > 0 and Config.ship.turn_rate or -Config.ship.turn_rate

		-- If we're very close, clamp to exact target to avoid overshoot
		-- if abs(angle_diff) < abs(rotation_amount) then
		-- 	rotation_amount = angle_diff
		-- end


		-- Apply rotation to current angle
		local new_angle = current_angle + rotation_amount
		
		-- Convert back to direction vector
		ship_heading_dir.x = cos(new_angle)
		ship_heading_dir.z = sin(new_angle)

		-- Normalize to ensure unit vector (handle floating point drift)
		local len = sqrt(ship_heading_dir.x * ship_heading_dir.x + ship_heading_dir.z * ship_heading_dir.z)
		if len > 0.0001 then
			ship_heading_dir.x = ship_heading_dir.x / len
			ship_heading_dir.z = ship_heading_dir.z / len
		end
	end

	-- Move ship in direction of heading based on speed
	if ship_speed > 0.01 then
		local move_speed = ship_speed * Config.ship.max_speed * 0.1  -- Scale for reasonable movement
		Config.ship.position.x = Config.ship.position.x + ship_heading_dir.x * move_speed
		Config.ship.position.z = Config.ship.position.z + ship_heading_dir.z * move_speed
	end

	-- Update particle cubes (remove expired ones)
	local i = 1
	while i <= #particle_trails do
		local cube = particle_trails[i]
		cube.age = cube.age + 1/60
		if cube.age >= cube.lifetime then
			table.remove(particle_trails, i)
		else
			i = i + 1
		end
	end

	-- Spawn new particle cubes around ship position
	if ship_speed > 0.01 then
		local spawn_interval = Config.particles.spawn_rate
		-- Store spawn timer in a way that persists
		if not _spawn_timer then _spawn_timer = 0 end
		_spawn_timer = _spawn_timer + 1/60

		if _spawn_timer >= spawn_interval then
			-- Spawn a line representing velocity at this point in space
			local scatter_radius = 30

			-- Random point in sphere using uniform distribution
			-- Simple uniform random in box approach
			local scatter_x = (rnd(2) - 1) * scatter_radius
			local scatter_y = (rnd(2) - 1) * scatter_radius
			local scatter_z = (rnd(2) - 1) * scatter_radius

			-- Normalize to sphere surface and scale by random radius
			local dist_sq = scatter_x * scatter_x + scatter_y * scatter_y + scatter_z * scatter_z
			local dist = sqrt(dist_sq)
			if dist > 0.01 then
				local scale = (rnd(1) ^ (1/3)) * scatter_radius / dist  -- uniform distribution in sphere
				scatter_x = scatter_x * scale
				scatter_y = scatter_y * scale
				scatter_z = scatter_z * scale
			end

			-- Spawn position in world space
			local spawn_x = Config.ship.position.x + scatter_x
			local spawn_y = Config.ship.position.y + scatter_y
			local spawn_z = Config.ship.position.z + scatter_z

			-- Velocity direction (ship's heading) and magnitude scaled by speed
			local line_length = ship_speed * 3
			local vel_x = ship_heading_dir.x * line_length
			local vel_y = 0
			local vel_z = ship_heading_dir.z * line_length

			-- Line end point
			local end_x = spawn_x + vel_x
			local end_y = spawn_y + vel_y
			local end_z = spawn_z + vel_z

			table.insert(particle_trails, {
				x1 = spawn_x,
				y1 = spawn_y,
				z1 = spawn_z,
				x2 = end_x,
				y2 = end_y,
				z2 = end_z,
				age = 0,
				lifetime = Config.particles.lifetime
			})
			_spawn_timer = 0
		end
	end

	-- Camera follows ship (focus point tracks ship position)
	camera.x = Config.ship.position.x
	camera.z = Config.ship.position.z
	-- Keep camera height from config
	camera.y = Config.camera.height or 0

	-- Update planet rotation
	planet_rotation = planet_rotation + Config.planet.spin_speed
end

-- Draw sun as a billboard sprite positioned opposite to light direction
-- Renders as a skybox element (always in background)
local function draw_sun()
	-- Get light direction
	local light_dir = get_light_direction()

	-- Position sun opposite to light (at far distance to appear in skybox)
	local sun_distance = Config.sun.distance
	local sun_x = camera.x - light_dir.x * sun_distance
	local sun_y = camera.y - light_dir.y * sun_distance
	local sun_z = camera.z - light_dir.z * sun_distance

	-- Project sun position to screen space
	local screen_x, screen_y, view_z = project_point(sun_x, sun_y, sun_z, camera)

	-- Only draw if sun is in front of camera
	if screen_x and screen_y and view_z > 0 then
		-- Set color 0 as transparent for the sun sprite
		palt(0, true)

		-- Draw sprite centered at screen position
		-- Sprite 25 is 128x128 pixels = 16x16 cells (8x8 pixels per cell)
		-- Scale to desired screen size in pixels, then convert to cells
		local sprite_width_cells = Config.sun.size / 8  -- Convert pixels to cells
		local sprite_height_cells = Config.sun.size / 8
		local half_size = Config.sun.size / 2
		spr(Config.sun.sprite_id, screen_x - half_size, screen_y - half_size, sprite_width_cells, sprite_height_cells)

		-- Reset transparency (restore default palt)
		palt()
	end
end

function _draw()
	cls(0)  -- Clear to dark blue

	-- Draw stars first (before everything else)
	draw_stars()

	-- Draw sun after stars, but before all 3D objects
	draw_sun()

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
		local ship_yaw = dir_to_angle(ship_heading_dir) + 0.25  -- Convert direction to angle, add 90° offset for model alignment
		local shippy_faces = RendererLit.render_mesh(
			model_shippy.verts, model_shippy.faces, camera,
			ship_pos.x, ship_pos.y, ship_pos.z,
			Config.ship.sprite_id,  -- sprite override (use sprite from config = sprite 5)
			light_dir,  -- light direction (directional light)
			nil,  -- light radius (unused for directional)
			light_brightness,  -- light brightness
			ambient,  -- ambient light
			false,  -- is_ground
			ship_rot.pitch, ship_yaw, ship_rot.roll,  -- Use direction-derived yaw
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
		-- Only show crosshair if it's within configured distance from ship on the XZ plane
		local dx = raycast_x - Config.ship.position.x
		local dz = raycast_z - Config.ship.position.z
		local dist_on_plane = sqrt(dx * dx + dz * dz)

		if dist_on_plane < Config.crosshair.max_distance then
			local cross_size = 0.5  -- Size of crosshair arms
			-- Draw crosshair on the ground plane (y=0)
			draw_line_3d(raycast_x - cross_size, 0, raycast_z, raycast_x + cross_size, 0, raycast_z, camera, 8)  -- Horizontal line (red)
			draw_line_3d(raycast_x, 0, raycast_z - cross_size, raycast_x, 0, raycast_z + cross_size, camera, 8)  -- Vertical line (red)
		end
	end

	-- Draw heading compass (arc, heading lines) only when not at target
	-- Calculate angle difference to see if we need to draw the compass
	local angle_diff = angle_difference(ship_heading_dir, target_heading_dir)

	-- Only draw compass if there's a significant difference (tolerance 0.01 turns)
	if angle_diff > 0.01 then
		local ship_x = Config.ship.position.x
		local ship_z = Config.ship.position.z
		local arc_radius = Config.ship.heading_arc_radius
		local segments = Config.ship.heading_arc_segments

		-- Draw current ship heading line (blue/cyan)
		local current_x = ship_x + ship_heading_dir.x * arc_radius
		local current_z = ship_z + ship_heading_dir.z * arc_radius
		draw_line_3d(ship_x, 0, ship_z, current_x, 0, current_z, camera, 13)  -- Blue (cyan)

		-- Draw arc by interpolating between current and target directions
		local arc_color = 10  -- Yellow

		for i = 0, segments - 1 do
			local t1 = i / segments
			local t2 = (i + 1) / segments

			-- SLERP between current and target for smooth arc
			local q1_current = dir_to_quat(ship_heading_dir)
			local q1_target = dir_to_quat(target_heading_dir)
			local q_arc1 = quat_slerp(q1_current, q1_target, t1 * 100)  -- Large multiplier to get full path
			local q_arc2 = quat_slerp(q1_current, q1_target, t2 * 100)

			local dir1 = quat_to_dir(q_arc1)
			local dir2 = quat_to_dir(q_arc2)

			-- Calculate 3D positions on the arc
			local x1 = ship_x + dir1.x * arc_radius
			local z1 = ship_z + dir1.z * arc_radius
			local x2 = ship_x + dir2.x * arc_radius
			local z2 = ship_z + dir2.z * arc_radius

			-- Project to screen and draw line
			draw_line_3d(x1, 0, z1, x2, 0, z2, camera, arc_color)
		end

		-- Draw target heading line (bright yellow)
		local target_x = ship_x + target_heading_dir.x * arc_radius
		local target_z = ship_z + target_heading_dir.z * arc_radius
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
	print("ship dir: (" .. flr(ship_heading_dir.x * 100) / 100 .. "," .. flr(ship_heading_dir.z * 100) / 100 .. ")", 2, 18, 7)
	print("target dir: (" .. flr(target_heading_dir.x * 100) / 100 .. "," .. flr(target_heading_dir.z * 100) / 100 .. ")", 2, 26, 7)

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

	-- Draw velocity lines on top of everything (stationary in world space)
	-- Reset drawing state to ensure lines render with correct colors
	fillp()
	palt()

	for _, line_segment in ipairs(particle_trails) do
		-- Calculate distance from ship to line start point
		local dx = line_segment.x1 - Config.ship.position.x
		local dy = line_segment.y1 - Config.ship.position.y
		local dz = line_segment.z1 - Config.ship.position.z
		local dist_from_ship = sqrt(dx * dx + dy * dy + dz * dz)

		-- Color based on distance from ship using discrete palette
		-- Palette: {28, 12, 7, 6, 13, 1} from closest to farthest
		local palette = Config.particles.color_palette
		local palette_size = #palette
		local max_dist = Config.particles.max_dist

		-- Map distance to palette index (0-1 normalized, then to palette index)
		local dist_factor = min(1, max(0, dist_from_ship / max_dist))
		local palette_index = flr(dist_factor * palette_size) + 1
		palette_index = min(palette_size, palette_index)

		local color = palette[palette_index]

		-- Draw the velocity line (draws on top of model since it's after model rendering)
		draw_line_3d(line_segment.x1, line_segment.y1, line_segment.z1,
		             line_segment.x2, line_segment.y2, line_segment.z2, camera, color)
	end
end

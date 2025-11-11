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
MathUtils = include("src/engine/math_utils.lua")
DebugRenderer = include("src/debug_renderer.lua")
ExplosionRenderer = include("src/engine/explosion_renderer.lua")
Explosion = include("src/particles/explosion.lua")
RotateSprites = include("src/engine/rotate_sprites.lua")
UIRenderer = include("src/ui/ui_renderer.lua")
Panel = include("src/ui/panel.lua")
Button = include("src/ui/button.lua")
ArcUI = include("src/ui/arc_ui.lua")
WeaponsUI = include("src/ui/weapons_ui.lua")
ShipSelection = include("src/ui/ship_selection.lua")
WeaponEffects = include("src/systems/weapon_effects.lua")
Missions = include("src/systems/missions.lua")
ShipSystems = include("src/systems/ship_systems.lua")
Minimap = include("src/minimap.lua")
Menu = include("src/menu.lua")
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
local last_mouse_button_state = false  -- Track previous frame's button state for click detection
local mission_success_time = 0  -- Timer for mission success scene

-- Ship speed control
local ship_speed = Config.ship.speed
local target_ship_speed = Config.ship.speed

-- Speed slider state
local slider_speed_desired = Config.ship.speed  -- What the slider is set to (independent of impulse)
local slider_dragging = false
local slider_x = Config.slider.x
local slider_y = Config.slider.y
local slider_height = Config.slider.height
local slider_width = Config.slider.width
local slider_handle_height = Config.slider.handle_height

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

-- Camera heading control - using direction vectors for yaw (XZ plane, like ship)
local camera_heading_dir = {x = 0, z = 1}  -- Current camera yaw direction
local camera_target_heading_dir = {x = 0, z = 1}  -- Target camera yaw direction

-- Raycast intersection for visualization
local raycast_x = nil
local raycast_z = nil

-- Game state
local current_health = Config.health.max_health
local is_dead = false
local destroyed_enemies = {}  -- Track which enemy ships have been destroyed (by ID)
local death_time = 0
local game_state = "menu"  -- "menu", "playing", "out_of_bounds", "game_over"
local out_of_bounds_time = 0  -- Time spent out of bounds
local is_out_of_bounds = false

-- Player health wrapper for smoke spawner registration
-- This allows the smoke spawner to track player health dynamically
local player_health_obj = {
	id = "player_ship",
	current_health = Config.health.max_health,
	max_health = Config.health.max_health,
	armor = Config.ship.armor,
}

-- Explosions
local active_explosions = {}

-- Spawned spheres (persistent objects)
local spawned_spheres = {}

-- Energy system state
local energy_system = {
	weapons = Config.energy.systems.weapons.allocated,
	impulse = Config.energy.systems.impulse.allocated,
	shields = Config.energy.systems.shields.allocated,
	tractor_beam = Config.energy.systems.tractor_beam.allocated,
	sensors = Config.energy.systems.sensors.allocated,
}

-- No energy message feedback
local no_energy_message = {
	visible = false,
	x = 0,
	y = 0,
	duration = 0,
	max_duration = 1.0  -- Show for 1 second
}

-- Shield charging state
local shield_charge = {
	boxes = {},  -- {1: charge_amount, 2: charge_amount, 3: charge_amount}
	charge_time = Config.energy.systems.shields.charge_time,  -- From config
}

-- Initialize shield charges
for i = 1, 3 do
	shield_charge.boxes[i] = 0
end

-- Cached position variables for efficiency
local ship_pos = nil  -- Current ship position (updated each frame)

-- Ship object for collision tracking
local ship = {
	id = "player_ship",
	type = "ship",
	armor = Config.ship.armor,
	collision_cooldown = 0,  -- Cooldown since last collision
}

-- Track colliding pairs to apply damage only once per contact
local collision_pairs = {}  -- {ship_id1 = {ship_id2 = true}}

-- Weapon selection and charging state
local selected_weapon = nil  -- Currently selected weapon (1 or 2)
local weapon_states = {}  -- Charging and auto-fire state for each weapon

-- Initialize weapon states
function init_weapon_states()
	weapon_states = {}
	for i = 1, #Config.weapons do
		weapon_states[i] = {
			charge = 0,  -- Charging progress (0 to 1)
			auto_fire = false,  -- Auto-fire toggle
			hovering = false,  -- Hovering over weapon button
		}
	end
end

init_weapon_states()

-- Check if a weapon is ready to fire (charged and has a target)
-- @param weapon_id: weapon index (1-based)
-- @param target: target object to check (passed explicitly to avoid global issues)
-- @return: true if weapon is fully charged and target is selected, false otherwise
function is_weapon_ready(weapon_id, target)
	local state = weapon_states[weapon_id]

	if not target then
		return false  -- No target selected
	end

	if state.charge < 0.999 then
		return false  -- Weapon not fully charged
	end

	-- Add more conditions here as needed (e.g., cooldown, overheat, etc.)
	return true
end

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

-- Convert angle (in turns, 0-1 range) to direction vector
-- Inverse of dir_to_angle
local function angle_to_dir(angle)
	return {x = cos(angle), z = sin(angle)}
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

-- ============================================
-- PHYSICS AND COLLISION
-- ============================================

-- Draw wireframe box for debug
local function draw_box_wireframe(min_x, min_y, min_z, max_x, max_y, max_z, camera, color)
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

-- Draw 2D screen-space bounding box around a 3D object
-- Projects the object center and draws a rectangle on screen
local function draw_2d_selection_box(world_x, world_y, world_z, camera, color, size)
	size = size or 20  -- Default size in pixels
	local screen_x, screen_y = project_point(world_x, world_y, world_z, camera)
	if screen_x and screen_y then
		-- Draw rectangle around the projected point
		rect(screen_x - size, screen_y - size, size * 2, size * 2, color)
	end
end

-- Box vs Sphere collision detection
-- Returns true if colliding
local function check_box_sphere_collision(box_min, box_max, sphere_center, sphere_radius)
	-- Find closest point on box to sphere center
	local closest_x = max(box_min.x, min(sphere_center.x, box_max.x))
	local closest_y = max(box_min.y, min(sphere_center.y, box_max.y))
	local closest_z = max(box_min.z, min(sphere_center.z, box_max.z))

	-- Calculate distance between sphere center and closest point
	local dx = sphere_center.x - closest_x
	local dy = sphere_center.y - closest_y
	local dz = sphere_center.z - closest_z
	local distance = sqrt(dx * dx + dy * dy + dz * dz)

	return distance < sphere_radius
end

-- Model data
local model_shippy = nil
local model_sphere = nil
local model_planet = nil
local model_satellite = nil
local planet_rotation = 0

-- Particle trails (speedlines) - simple array of line segments
local particle_trails = {}  -- Array of {x1, z1, x2, z2, age, lifetime}

-- Targeting and weapons
local hovered_target = nil  -- Currently hovered target object (satellite, planet, enemy ship, etc)
local current_selected_target = nil  -- Currently selected target object for firing/tracking
local photon_beams = {}  -- Array of active photon beams
local auto_fire_timer = 0  -- Timer for auto-fire
local camera_locked_to_target = false  -- Whether camera is locked to target or free rotating
local camera_pitch_before_targeting = nil  -- Store pitch value before targeting for restoration

-- Enemy ships array - holds all targetable enemy objects
-- Structure per object: {
--   id = "satellite_1", "satellite_2", etc,
--   type = "satellite" | "planet" | "enemy_ship",
--   position = {x, y, z},  -- Current position (can be updated dynamically)
--   config = reference to Config object (satellite, planet, etc),
--   model = model data (model_satellite, model_planet, etc),
--   is_destroyed = boolean,
--   health = current_health (mirrors config.current_health)
-- }
local enemy_ships = {}  -- Array of all enemy ships/satellites in the level



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

-- Create billboard-facing quad vertices based on camera orientation
function create_billboard_quad(half_size, camera)
	-- Camera forward vector (direction camera is looking)
	local forward_x = sin(camera.ry) * cos(camera.rx)
	local forward_y = sin(camera.rx)  -- Inverted pitch
	local forward_z = cos(camera.ry) * cos(camera.rx)

	-- Camera right vector (perpendicular to forward, in XZ plane)
	local right_x = cos(camera.ry)
	local right_y = 0
	local right_z = -sin(camera.ry)

	-- Camera up vector (cross product of forward and right, inverted)
	local up_x = -(forward_y * right_z - forward_z * right_y)
	local up_y = -(forward_z * right_x - forward_x * right_z)
	local up_z = -(forward_x * right_y - forward_y * right_x)

	-- Build quad vertices using right and up vectors
	local verts = {
		vec(-right_x * half_size + up_x * half_size, -right_y * half_size + up_y * half_size, -right_z * half_size + up_z * half_size),  -- Top-left
		vec(right_x * half_size + up_x * half_size, right_y * half_size + up_y * half_size, right_z * half_size + up_z * half_size),    -- Top-right
		vec(right_x * half_size - up_x * half_size, right_y * half_size - up_y * half_size, right_z * half_size - up_z * half_size),    -- Bottom-right
		vec(-right_x * half_size - up_x * half_size, -right_y * half_size - up_y * half_size, -right_z * half_size - up_z * half_size),  -- Bottom-left
	}

	return verts
end

-- Create a billboard quad mesh (64x64 unlit, camera-facing)
function create_quad(width, height, sprite_id, sprite_w, sprite_h, camera)
	sprite_id = sprite_id or 1
	sprite_w = sprite_w or 64
	sprite_h = sprite_h or 64

	-- For billboards, store half-size and mark as billboard - vertices will be generated each frame
	local hw = width / 2
	local hh = height / 2

	-- Create dummy vertices (will be regenerated every frame for billboards)
	local verts = {
		vec(-hw, -hh, 0),
		vec(hw, -hh, 0),
		vec(hw, hh, 0),
		vec(-hw, hh, 0),
	}

	-- Create 2 triangles to form the quad
	local faces = {
		-- First triangle (1, 2, 3)
		{1, 2, 3, sprite_id,
			vec(0, sprite_h), vec(sprite_w, sprite_h), vec(sprite_w, 0)},
		-- Second triangle (1, 3, 4)
		{1, 3, 4, sprite_id,
			vec(0, sprite_h), vec(sprite_w, 0), vec(0, 0)},
	}

	return {verts = verts, faces = faces, name = "quad", unlit = true, is_billboard = true, half_size = hw}
end

-- Spawn a billboard quad at the given position (faces camera)
-- lifetime: optional duration in seconds before quad is removed (nil = infinite)
-- dither_enabled: optional boolean to enable dither fading based on lifetime
function spawn_quad(x, y, z, width, height, sprite_id, sprite_w, sprite_h, camera_obj, lifetime, dither_enabled)
	local quad_mesh = create_quad(width or 10, height or 10, sprite_id or 19, sprite_w, sprite_h, camera_obj or camera)
	local hw = (width or 10) / 2
	local obj = {
		x = x, y = y, z = z,
		mesh = quad_mesh,
		mesh_half_size = hw,
		lifetime = lifetime,  -- Lifetime in seconds (nil = infinite)
		age = 0,  -- Current age in seconds
		dither_enabled = dither_enabled or false,  -- Enable dither fading
		scale = 1.0,  -- Current scale multiplier
		explosion_opacity = 1.0  -- Opacity controlled by explosion
	}
	add(spawned_spheres, obj)
	return obj
end

function _init()
	-- Initialize color table for lit rendering
	RendererLit.init_color_table()

	-- Initialize weapon effects with config
	WeaponEffects.setup(Config)

	-- Initialize missions system
	Missions.init(Config)

	-- Initialize menu with available missions
	Menu.init(Config)

	-- Initialize UI renderer
	UIRenderer.init(
		{panel = Panel, button = Button, minimap = Minimap, menu = Menu},
		Config,
		{
			on_restart = function()
				-- Return to menu without restarting
				game_state = "menu"
				is_dead = false
				death_time = 0
			end,
			on_menu = function()
				game_state = "menu"
				out_of_bounds_time = 0
				is_out_of_bounds = false
			end
		}
	)

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

	-- Initialize enemy_ships array from mission config satellites
	enemy_ships = {}
	local mission = Config.missions.mission_1

	if mission.satellites and #mission.satellites > 0 then
		-- Load satellite model from first satellite config
		local first_sat_config = mission.satellites[1]
		model_satellite = load_obj(first_sat_config.model_file)

		if model_satellite then
			printh("Satellite loaded: " .. #model_satellite.verts .. " vertices, " .. #model_satellite.faces .. " faces")
		else
			printh("WARNING: Failed to load " .. first_sat_config.model_file)
		end

		-- Create enemy ship objects from mission satellites
		for i, sat_config in ipairs(mission.satellites) do
			-- Create position reference
			local sat_position = {
				x = sat_config.position.x,
				y = sat_config.position.y,
				z = sat_config.position.z
			}

			-- Create enemy ship object
			local enemy = {
				id = sat_config.id,
				type = "satellite",
				position = sat_position,
				config = sat_config,
				model = model_satellite,
				is_destroyed = false,
				health = sat_config.current_health,
			current_health = sat_config.current_health,  -- For damage system
			max_health = sat_config.max_health,  -- For damage system
			armor = sat_config.armor,  -- Armor rating (0-1): lower = takes more collision damage
			collision_cooldown = 0,  -- Cooldown since last collision with another ship
			}

			table.insert(enemy_ships, enemy)

		end
	end
end

-- Load satellites for current mission
function reload_mission_satellites()
	local current_mission_num = Missions.get_current_mission().id
	local mission = current_mission_num == 1 and Config.missions.mission_1 or (current_mission_num == 2 and Config.missions.mission_2) or (current_mission_num == 3 and Config.missions.mission_3) or Config.missions.mission_4

	-- Reset enemy ships list
	enemy_ships = {}
	destroyed_enemies = {}

	local load_obj_func = require("src.engine.obj_loader")

	-- Load satellites for Mission 1 & 2
	if mission.satellites and #mission.satellites > 0 then
		-- Load satellite model from first satellite config
		local first_sat_config = mission.satellites[1]
		model_satellite = load_obj_func(first_sat_config.model_file)

		if model_satellite then
			printh("Satellite loaded: " .. #model_satellite.verts .. " vertices, " .. #model_satellite.faces .. " faces")
		else
			printh("WARNING: Failed to load " .. first_sat_config.model_file)
		end

		-- Create enemy ship objects from mission satellites
		for i, sat_config in ipairs(mission.satellites) do
			-- Create position reference
			local sat_position = {
				x = sat_config.position.x,
				y = sat_config.position.y,
				z = sat_config.position.z
			}

			-- Create enemy ship object
			local enemy = {
				id = sat_config.id,
				type = "satellite",
				position = sat_position,
				config = sat_config,
				model = model_satellite,
				is_destroyed = false,
				health = sat_config.current_health,
				current_health = sat_config.current_health,  -- For damage system
				max_health = sat_config.max_health,  -- For damage system
				armor = sat_config.armor,  -- Armor rating (0-1): lower = takes more collision damage
				collision_cooldown = 0,  -- Cooldown since last collision with another ship
			}

			table.insert(enemy_ships, enemy)
		end
	end

	-- Load Grabon enemies for Mission 3
	if mission.enemies and #mission.enemies > 0 then
		for i, enemy_config in ipairs(mission.enemies) do
			-- Load model
			local model_grabon = load_obj_func(enemy_config.model_file)
			if not model_grabon then
				printh("WARNING: Failed to load " .. enemy_config.model_file)
				model_grabon = model_satellite  -- Fallback to satellite model
			end

			-- Create position reference
			local enemy_position = {
				x = enemy_config.position.x,
				y = enemy_config.position.y,
				z = enemy_config.position.z
			}

			-- Create Grabon enemy object with AI
			local enemy = {
				id = enemy_config.id,
				type = "grabon",
				position = enemy_position,
				config = enemy_config,
				model = model_grabon,
				is_destroyed = false,
				health = enemy_config.current_health,
				current_health = enemy_config.current_health,
				max_health = enemy_config.max_health,
				armor = enemy_config.armor,
				collision_cooldown = 0,
				-- Movement state
				heading = enemy_config.heading or 0,
				speed = enemy_config.ai.speed or 0.3,
				-- AI state
				ai_target = nil,  -- Will be set to player ship
				ai_target_detected = false,
				ai_last_weapon_fire_time = {0, 0},  -- Track fire time for each weapon
			}

			table.insert(enemy_ships, enemy)
		end
	end

	-- Load planet position from mission config if available
	if mission.planet_start then
		Config.planet.position = {
			x = mission.planet_start.x,
			y = mission.planet_start.y,
			z = mission.planet_start.z
		}
	end
end

-- Update Grabon AI for Mission 3
-- Handles movement, rotation, target detection, and weapon firing
function update_grabon_ai()
	for _, enemy in ipairs(enemy_ships) do
		if enemy.type == "grabon" and not enemy.is_destroyed then
			local ai = enemy.config.ai

			-- Detect player target
			if not enemy.ai_target_detected then
				-- Detect if player within sensor range
				if ShipSystems.is_in_range(enemy.position, ship_pos, ai.target_detection_range) then
					enemy.ai_target_detected = true
					enemy.ai_target = ship_pos
				end
			end

			if enemy.ai_target_detected then
				-- Update target position (follow player)
				enemy.ai_target = ship_pos

				-- Calculate direction to target
				local dx = enemy.ai_target.x - enemy.position.x
				local dz = enemy.ai_target.z - enemy.position.z
				local target_distance = math.sqrt(dx*dx + dz*dz)

				if target_distance > 0 then
					-- Calculate target heading (0-1 turns)
					local target_heading = atan2(dx, dz) / (2 * math.pi)
					if target_heading < 0 then target_heading = target_heading + 1 end

					-- Smoothly rotate towards target
					local heading_diff = target_heading - enemy.heading
					-- Normalize heading difference to -0.5 to 0.5 range
					if heading_diff > 0.5 then
						heading_diff = heading_diff - 1
					elseif heading_diff < -0.5 then
						heading_diff = heading_diff + 1
					end

					-- Apply turn rate
					enemy.heading = enemy.heading + heading_diff * ai.turn_rate
					-- Normalize heading to 0-1 range
					if enemy.heading < 0 then enemy.heading = enemy.heading + 1 end
					if enemy.heading >= 1 then enemy.heading = enemy.heading - 1 end
				end

				-- Initialize velocity if needed
			if not enemy.velocity then
				enemy.velocity = {x = 0, z = 0}
			end

			-- Determine if Grabon should retreat (health below 40%)
			local should_retreat = enemy.current_health < (enemy.max_health * 0.4)

			-- Convert heading (0-1 turns) to direction vector
			local forward_dir = angle_to_dir(enemy.heading)

			-- Determine desired acceleration direction based on AI state
			local desired_accel = 0  -- Default: no acceleration
			local max_speed = ai.speed * 0.1  -- Scale down max speed significantly

			if should_retreat and target_distance < 200 then
				-- Retreat away from player - accelerate backward
				desired_accel = -0.05  -- Small acceleration value for backward
			elseif target_distance > ai.attack_range then
				-- Move towards target - accelerate forward
				desired_accel = 0.05  -- Small acceleration value for forward
			else
				-- Within attack range - maintain current speed or decelerate slightly
				desired_accel = 0
			end

			-- Check for obstacles and adjust acceleration if colliding
			local collision_threshold = 5.0
			local collision_detected = false

			-- Check collision with player
			if target_distance < collision_threshold then
				collision_detected = true
			end

			-- Check collision with other enemies/satellites
			for _, other_enemy in ipairs(enemy_ships) do
				if other_enemy.id ~= enemy.id and other_enemy.position then
					local odx = other_enemy.position.x - enemy.position.x
					local odz = other_enemy.position.z - enemy.position.z
					local other_distance = math.sqrt(odx*odx + odz*odz)
					if other_distance < collision_threshold then
						collision_detected = true
						break
					end
				end
			end

			-- Check collision with spawned objects (asteroids, planets)
			for _, obj in ipairs(spawned_spheres) do
				if obj.x and obj.z then
					local odx = obj.x - enemy.position.x
					local odz = obj.z - enemy.position.z
					local obj_distance = math.sqrt(odx*odx + odz*odz)
					if obj_distance < collision_threshold then
						collision_detected = true
						break
					end
				end
			end

			-- If collision detected, reduce acceleration to avoid obstacle
			if collision_detected then
				-- Reduce desired acceleration by 50% to try to navigate around obstacles
				desired_accel = desired_accel * 0.5
			end

			-- Apply acceleration to velocity (similar to player ship physics)
			local accel_rate = 0.02  -- Acceleration rate per frame (slower acceleration)
			local current_forward_speed = enemy.velocity.x * forward_dir.x + enemy.velocity.z * forward_dir.z
			local new_forward_speed = current_forward_speed + desired_accel * accel_rate

			-- Clamp speed to max_speed
			if new_forward_speed > max_speed then
				new_forward_speed = max_speed
			elseif new_forward_speed < -max_speed * 0.5 then  -- Allow backward movement at half speed
				new_forward_speed = -max_speed * 0.5
			end

			-- Apply friction when no acceleration (deceleration)
			if desired_accel == 0 then
				new_forward_speed = new_forward_speed * 0.95  -- Friction
			end

			-- Update current speed for movement (like player ship)
			if not enemy.current_speed then enemy.current_speed = 0 end
			if not enemy.target_speed then enemy.target_speed = new_forward_speed end
			enemy.target_speed = new_forward_speed
			enemy.current_speed = enemy.current_speed + (enemy.target_speed - enemy.current_speed) * 0.08

			-- Apply movement only in the direction Grabon is facing
			if abs(enemy.current_speed) > 0.01 then
				local move_speed = enemy.current_speed * ai.speed * 0.1
				enemy.position.x = enemy.position.x + forward_dir.x * move_speed
				enemy.position.z = enemy.position.z + forward_dir.z * move_speed
			end

						-- Fire weapons if in range and in firing arc
				if ShipSystems.is_in_range(enemy.position, ship_pos, ai.attack_range) and not is_dead then
					-- Check if in firing arc
					if ShipSystems.is_in_firing_arc(enemy.position, forward_dir, ship_pos, ai.firing_arc_start, ai.firing_arc_end) then
						-- Fire weapons on interval
						for w = 1, #ai.weapons do
							local weapon = ai.weapons[w]
							local current_time = t()  -- Get current elapsed time (Picotron API)

							if not enemy.ai_last_weapon_fire_time then
								enemy.ai_last_weapon_fire_time = {}
							end

							if not enemy.ai_last_weapon_fire_time[w] then
								enemy.ai_last_weapon_fire_time[w] = 0
							end

							-- Fire if enough time has passed
							if current_time - enemy.ai_last_weapon_fire_time[w] > weapon.fire_rate then
								-- Fire beam from Grabon towards player
								-- Calculate muzzle position using weapon offset
								local muzzle_offset = weapon.muzzle_offset or {x = 0, y = 0, z = 0}
								local muzzle_pos = {
									x = enemy.position.x + muzzle_offset.x,
									y = enemy.position.y + muzzle_offset.y,
									z = enemy.position.z + muzzle_offset.z,
								}
								WeaponEffects.fire_beam(muzzle_pos, ship_pos, 12)  -- Sprite 12 for Grabon disruptor beams
								-- Apply shield absorption first
								local health_before = player_health_obj.current_health
								local shield_absorbed = apply_shield_absorption()
								if not shield_absorbed then
									-- Shields didn't absorb, apply damage to health
									WeaponEffects.spawn_explosion(ship_pos, player_health_obj)
									-- Sync current_health with player_health_obj
									current_health = player_health_obj.current_health
									-- Check if player died
									if current_health <= 0 then
										is_dead = true
										death_time = 0
										-- Spawn explosion at ship position when player dies
										if Config.explosion.enabled then
											table.insert(active_explosions, Explosion.new(Config.ship.position.x, Config.ship.position.y, Config.ship.position.z, Config.explosion))
											sfx(3)
										end
									end
									-- Reset shield charge progress when hit without shields
									for i = 1, 3 do
										shield_charge.boxes[i] = 0
									end
									-- Spawn additional damage effects when player takes health damage
									if player_health_obj.current_health < health_before then
										WeaponEffects.spawn_smoke(ship_pos)
									end
								else
									printh("Shield absorbed Grabon attack!")
								end
								-- Track firing time
								enemy.ai_last_weapon_fire_time[w] = current_time
							end
						end
					end
				end
			end
		end
	end
end

-- Apply shield absorption to damage before applying to health
-- Shields absorb damage, and fully charged shields are consumed on hit
-- Only FULLY charged shields (>= 1.0) can absorb damage
function apply_shield_absorption()
	-- Count how many fully charged shields we have available
	local charged_shields = 0
	for i = 1, 3 do
		if shield_charge.boxes[i] >= 1.0 then
			charged_shields = charged_shields + 1
		end
	end

	-- If we have charged shields, consume one of them
	if charged_shields > 0 then
		-- Find and consume the first fully charged shield
		for i = 1, 3 do
			if shield_charge.boxes[i] >= 1.0 then
				shield_charge.boxes[i] = 0  -- Consume the shield
				printh("SHIELD ACTIVATED: Shield " .. i .. " absorbed damage!")
				return true  -- Damage was absorbed
			end
		end
	end

	-- No fully charged shields available - player takes full damage
	-- Also reset any partial shield charging progress
	for i = 1, 3 do
		if shield_charge.boxes[i] > 0 and shield_charge.boxes[i] < 1.0 then
			shield_charge.boxes[i] = 0  -- Reset partial shields
		end
	end

	return false  -- No shields available, damage goes through
end

-- Track energy block hit boxes for interactive allocation
local energy_block_hitboxes = {}

-- Build energy block hitboxes (called during update so clicks can use them)
function build_energy_hitboxes()
	local energy_cfg = Config.energy
	local systems_list = {"weapons", "impulse", "shields", "tractor_beam", "sensors"}

	-- Clear hitboxes from last frame
	energy_block_hitboxes = {}

	local display_index = 0  -- Track actual display position (skipping hidden systems)
	for _, system_name in ipairs(systems_list) do
		local system_cfg = energy_cfg.systems[system_name]

		-- Skip hidden systems (but keep position for consistency with drawing)
		if system_cfg.hidden then
			goto skip_hitbox
		end

		display_index = display_index + 1

		local allocated = energy_system[system_name]
		local capacity = system_cfg.capacity

		-- Calculate position for this system's energy bar (use display_index to match draw_energy_bars)
		local bar_y = energy_cfg.ui_y + (display_index - 1) * energy_cfg.system_spacing
		local bar_x = energy_cfg.ui_x + energy_cfg.system_bar_x_offset
		local padding = energy_cfg.hitbox.padding

		-- Create hitboxes for each energy unit
		for j = 1, capacity do
			local rect_x = bar_x + (j - 1) * (energy_cfg.bar_width + energy_cfg.bar_spacing)
			local rect_y = bar_y
			local rect_x2 = rect_x + energy_cfg.bar_width
			local rect_y2 = rect_y + energy_cfg.bar_height

			-- Store hitbox for this block with padding for easier clicking
			if energy_block_hitboxes[system_name] == nil then
				energy_block_hitboxes[system_name] = {}
			end
			energy_block_hitboxes[system_name][j] = {
				x1 = rect_x - padding, y1 = rect_y - padding,
				x2 = rect_x2 + padding, y2 = rect_y2 + padding,
				is_filled = (j <= allocated),
				-- Store original bounds for reference
				orig_x1 = rect_x, orig_y1 = rect_y,
				orig_x2 = rect_x2, orig_y2 = rect_y2
			}
		end

		::skip_hitbox::
	end
end

-- Draw energy bars for each system
function draw_energy_bars()
	local energy_cfg = Config.energy
	local systems_list = {"weapons", "impulse", "shields", "tractor_beam", "sensors"}

	-- Draw vertical total energy bar on the left
	draw_total_energy_bar()

	local display_index = 0  -- Track actual display position (skipping hidden systems)
	for _, system_name in ipairs(systems_list) do
		local system_cfg = energy_cfg.systems[system_name]

		-- Skip hidden systems (but keep position for consistency with hitboxes)
		if system_cfg.hidden then
			goto skip_draw
		end

		display_index = display_index + 1

		local allocated = energy_system[system_name]
		local capacity = system_cfg.capacity

		-- Calculate position for this system's energy bar (use display_index to remove gaps)
		local bar_y = energy_cfg.ui_y + (display_index - 1) * energy_cfg.system_spacing
		local bar_x = energy_cfg.ui_x + energy_cfg.system_bar_x_offset

		-- Draw discrete rectangles for each energy unit
		for j = 1, capacity do
			local rect_x = bar_x + (j - 1) * (energy_cfg.bar_width + energy_cfg.bar_spacing)
			local rect_y = bar_y
			local rect_x2 = rect_x + energy_cfg.bar_width
			local rect_y2 = rect_y + energy_cfg.bar_height

			-- Determine color: full if j <= allocated, empty otherwise
			local color = j <= allocated and system_cfg.color_full or system_cfg.color_empty

			-- Draw filled rectangle
			rectfill(rect_x, rect_y, rect_x2, rect_y2, color)

			-- Draw border (read from config)
			rect(rect_x, rect_y, rect_x2, rect_y2, energy_cfg.box.border_color)
		end

		-- Draw system name label with label offset from config
		local label_x = bar_x + capacity * (energy_cfg.bar_width + energy_cfg.bar_spacing) + system_cfg.label_offset
		print(system_name, label_x, bar_y, energy_cfg.label.text_color)

		-- Draw sensor damage boost text if enabled in config
		if system_name == "sensors" and system_cfg.damage_boost and system_cfg.damage_boost.enabled then
			local damage_bonus = 0
			if allocated == 1 then
				damage_bonus = system_cfg.damage_boost.one_box_bonus
			elseif allocated >= 2 then
				damage_bonus = system_cfg.damage_boost.two_plus_bonus
			end
			if damage_bonus > 0 then
				local bonus_text = "+" .. flr(damage_bonus * 100) .. "% dmg"
				local bonus_x = bar_x + system_cfg.damage_boost.text_x_offset
				local bonus_y = bar_y + energy_cfg.bar_height + system_cfg.damage_boost.text_y_offset
				print(bonus_text, bonus_x, bonus_y, 10)  -- Yellow text
			end
		end

		::skip_draw::
	end
end

-- Draw the vertical total energy bar
function draw_total_energy_bar()
	local energy_cfg = Config.energy
	local bar_x = energy_cfg.ui_x
	local bar_y = energy_cfg.ui_y
	local total_bars = energy_cfg.max_total
	local bar_width = energy_cfg.bar_width
	local bar_height = energy_cfg.bar_height
	local spacing = energy_cfg.bar_spacing

	-- Calculate total allocated energy
	local total_allocated = energy_system.weapons + energy_system.impulse +
	                        energy_system.shields + energy_system.tractor_beam +
	                        energy_system.sensors

	-- Draw vertical stack of energy blocks
	for i = 1, total_bars do
		local rect_y = bar_y + (i - 1) * (bar_height + spacing)
		local rect_y2 = rect_y + bar_height
		-- Use config colors: full for allocated, empty for unallocated
		local color = i <= total_allocated and energy_cfg.total_bar.color_full or energy_cfg.total_bar.color_empty

		-- Draw filled rectangle
		rectfill(bar_x, rect_y, bar_x + bar_width, rect_y2, color)

		-- Draw border (read from config)
		rect(bar_x, rect_y, bar_x + bar_width, rect_y2, energy_cfg.total_bar.border_color)
	end

	-- Draw "E" label above total energy bar; we dont need this right now.
	--print("E", bar_x - 3, bar_y - 6, 7)
end

-- Handle energy allocation/deallocation clicks
function handle_energy_clicks(mx, my)
	-- Check if clicking on a system energy block
	for system_name, blocks in pairs(energy_block_hitboxes) do
		for block_num, hitbox in pairs(blocks) do
			if mx >= hitbox.x1 and mx <= hitbox.x2 and my >= hitbox.y1 and my <= hitbox.y2 then
				-- Clicked on a block - recalculate is_filled from current energy_system state
				local is_filled = block_num <= energy_system[system_name]

				if is_filled then
					-- Block is filled: deallocate all energy down to and including this block
					-- First block clicked deallocates 1 energy, second deallocates 1 more, etc
					energy_system[system_name] = block_num - 1
				else
					-- Block is empty: allocate energy to fill up to this block
					local total_allocated = energy_system.weapons + energy_system.impulse +
					                        energy_system.shields + energy_system.tractor_beam +
					                        energy_system.sensors
					local available = Config.energy.max_total - total_allocated
					local system_cfg = Config.energy.systems[system_name]

					-- Calculate how much to allocate
					local current = energy_system[system_name]
					local to_allocate = block_num - current  -- How many blocks to fill

					if available >= to_allocate then
						energy_system[system_name] = block_num
					else
						-- No energy available - show feedback message
						if available <= 0 then
							no_energy_message.visible = true
							no_energy_message.x = mx
							no_energy_message.y = my
							no_energy_message.duration = no_energy_message.max_duration
							printh("No energy available!")
							return true
						end
						-- Only allocate as much as available
						energy_system[system_name] = min(current + available, system_cfg.capacity)
					end
				end
				-- Sync the Config energy with the local energy_system
				Config.energy.systems[system_name].allocated = energy_system[system_name]
				printh("Energy allocated: " .. system_name .. " = " .. energy_system[system_name])

				-- Reset shield charges if shield allocation changed
				if system_name == "shields" then
					local new_allocated = energy_system[system_name]
					-- Reset charges for shields beyond the new allocation
					for i = new_allocated + 1, 3 do
						shield_charge.boxes[i] = 0
					end
					printh("Shield allocation changed to " .. new_allocated .. ", resetting excess shields")
				end

				return true
			end
		end
	end
	return false
end

local _update_frame_counter = 0

function _update()
	_update_frame_counter = _update_frame_counter + 1

	-- Update no energy message duration
	if no_energy_message.visible then
		no_energy_message.duration = no_energy_message.duration - 0.016  -- ~60fps frame time
		if no_energy_message.duration <= 0 then
			no_energy_message.visible = false
		end
	end

	-- Mouse input (used for menu and gameplay)
	mx, my, mb = mouse()



	-- Handle menu input
	if game_state == "menu" then
		local input = {
			select = keyp("return") or keyp("z"),
		}
		-- Block menu clicks for one frame after returning from mission
		local mouse_click = ((mb & 1) == 1) and not skip_next_menu_click
		if skip_next_menu_click then
			skip_next_menu_click = false  -- Reset flag for next frame
		end

		if Menu.update(input, mx, my, mouse_click) then
			-- Campaign selected, start game
			game_state = "playing"
			is_dead = false
			current_health = Config.health.max_health
			death_time = 0
			out_of_bounds_time = 0
			is_out_of_bounds = false

			-- Reset player health wrapper
			player_health_obj.current_health = current_health

			-- Reset player ship state
			Config.ship.position = {x = 0, y = 0, z = 0}
			Config.ship.heading = 0
			ship_speed = Config.ship.speed
			target_ship_speed = Config.ship.speed
			slider_speed_desired = Config.ship.speed

			-- Reset mission camera tracking first
			Missions.init(Config)  -- Initialize missions with all state reset

			-- Get selected mission and set it
			local selected_mission = Menu.get_selected_mission()
			if selected_mission then
				-- Load mission 2 if selected
				if selected_mission.id == "mission_2" then
					Missions.advance_mission()  -- Switch to mission 2
					-- Disable all subsystems for Mission 2 tutorial
					Config.energy.systems.impulse.allocated = 0
					Config.energy.systems.weapons.allocated = 0
					Config.energy.systems.shields.allocated = 0
					Config.energy.systems.sensors.allocated = 0
					Config.energy.systems.tractor_beam.allocated = 0
					-- Reset local energy_system table to match
					energy_system.weapons = 0
					energy_system.impulse = 0
					energy_system.shields = 0
					energy_system.sensors = 0
					energy_system.tractor_beam = 0
				elseif selected_mission.id == "mission_3" then
					-- Load mission 3
					Missions.advance_mission()  -- Switch to mission 2
					Missions.advance_mission()  -- Switch to mission 3
					-- Mission 3: Focus on combat (impulse and weapons)
					Config.energy.systems.impulse.allocated = 2
					Config.energy.systems.weapons.allocated = 4
					Config.energy.systems.shields.allocated = 0
					Config.energy.systems.sensors.allocated = 0  -- Sensors disabled for Mission 3
					Config.energy.systems.tractor_beam.allocated = 0
					-- Reset local energy_system table to match
					energy_system.weapons = 4
					energy_system.impulse = 2
					energy_system.shields = 0
					energy_system.sensors = 0  -- Sensors disabled for Mission 3
					energy_system.tractor_beam = 0
				elseif selected_mission.id == "mission_4" then
					-- Load mission 4
					Missions.advance_mission()  -- Switch to mission 2
					Missions.advance_mission()  -- Switch to mission 3
					Missions.advance_mission()  -- Switch to mission 4
					-- Mission 4: Focus on combat (impulse and weapons, shields for defense)
					Config.energy.systems.impulse.allocated = 2
					Config.energy.systems.weapons.allocated = 4
					Config.energy.systems.shields.allocated = 2  -- Shields to defend against two enemies
					Config.energy.systems.sensors.allocated = 0  -- Sensors disabled for Mission 4
					Config.energy.systems.tractor_beam.allocated = 0
					-- Reset local energy_system table to match
					energy_system.weapons = 4
					energy_system.impulse = 2
					energy_system.shields = 2
					energy_system.sensors = 0  -- Sensors disabled for Mission 4
					energy_system.tractor_beam = 0
				end
			end

			-- Load satellites for the selected mission
			reload_mission_satellites()

			-- Load and play music based on mission
			local current_mission = Missions.get_current_mission()
			if current_mission then
				local music_config
				if current_mission.id == 1 or current_mission.id == 2 then
					music_config = Config.music.missions_1_2
				elseif current_mission.id == 3 or current_mission.id == 4 then
					music_config = Config.music.missions_3_4
				end

				if music_config then
					-- Load music file into memory and play
					fetch(music_config.sfx_file):poke(music_config.memory_address)
					music(music_config.pattern, nil, nil, music_config.memory_address)
					-- Set music volume to 50% (0x20 = 0x40 / 2)
					poke(0x5539, 0x20)
				end
			end

			-- Register autonomous smoke spawners for player and satellite
			-- Player ship: spawn smoke when health < 30%
			WeaponEffects.register_smoke_spawner(
				player_health_obj,
				0.5,  -- Spawn smoke when below 30% health
				function() return {x = 0, y = 0, z = 0} end  -- Spawn at ship origin
			)

		-- Register smoke spawners for all enemy ships
		for _, enemy in ipairs(enemy_ships) do
			WeaponEffects.register_smoke_spawner(
				enemy,
				0.5,  -- Spawn smoke when below 30% health
				function() return {x = enemy.position.x, y = enemy.position.y, z = enemy.position.z} end
			)
		end
		return  -- Skip gameplay updates while in menu
	end  -- Close if Menu.update(...)
	end  -- Close if game_state == "menu"

	-- Cache ship position at start of update
	ship_pos = Config.ship.position

	-- Check for objective panel toggle click (top-right corner of dialog panel)
	local panel_toggle_x = Config.mission_ui.dialog_panel_x + Config.mission_ui.dialog_toggle_x_offset
	local panel_toggle_y = Config.mission_ui.dialog_panel_y + Config.mission_ui.dialog_toggle_y_offset
	local panel_toggle_size = Config.mission_ui.dialog_toggle_size
	if (mb & 1 == 1) and not last_mouse_button_state then  -- Click detected
		if mx >= panel_toggle_x and mx <= panel_toggle_x + panel_toggle_size and my >= panel_toggle_y and my <= panel_toggle_y + panel_toggle_size then
			Missions.toggle_objective_panel()
		end
	end

	-- Mouse orbit controls (only in gameplay)

	-- Check if mouse is over slider
	local over_slider = mx >= slider_x - 5 and mx <= slider_x + slider_width + 5 and
	                    my >= slider_y and my <= slider_y + slider_height

	-- Check if mouse is over energy UI area (but not weapons UI or help panel)
	-- Help panel is at (180, 10) with width 200, so it extends to x=380
	-- Energy UI extends from ui_x to system_bar_x_offset + (max_capacity * bar_width + spacing)
	-- Vertically: from ui_y to ui_y + (num_visible_systems - 1) * system_spacing + bar_height
	local energy_cfg = Config.energy
	local num_visible_systems = 0
	for _, system_name in ipairs({"weapons", "impulse", "shields", "tractor_beam", "sensors"}) do
		if not energy_cfg.systems[system_name].hidden then
			num_visible_systems = num_visible_systems + 1
		end
	end
	local energy_max_x = energy_cfg.ui_x + energy_cfg.system_bar_x_offset + (4 * (energy_cfg.bar_width + energy_cfg.bar_spacing))  -- Max 4 boxes per system
	local energy_max_y = energy_cfg.ui_y + (num_visible_systems - 1) * energy_cfg.system_spacing + energy_cfg.bar_height + 5  -- +5 padding
	local over_energy_ui = mx >= energy_cfg.ui_x and mx < energy_max_x and my >= energy_cfg.ui_y and my < energy_max_y

	-- Check if button is newly pressed this frame (was not pressed last frame, is pressed now)
	local button_pressed = (mb & 1 == 1) and not last_mouse_button_state
	local button_held = (mb & 1 == 1)

	if button_held then  -- Left mouse button
		if over_slider then
			-- Drag slider
			slider_dragging = true
			-- Calculate desired speed from mouse Y position
			local slider_pos = mid(0, (my - slider_y) / slider_height, 1)
			slider_speed_desired = (1 - slider_pos)  -- Inverted (top = max speed)
		elseif over_energy_ui and button_pressed then
			-- Handle energy block clicks ONLY on initial press, not while held
			build_energy_hitboxes()
			handle_energy_clicks(mx, my)
		elseif button_pressed then
			-- Check for mission OK button click first
			if Missions.check_ok_button_click(mx, my, button_pressed, Config) then
				-- OK button was clicked on mission success screen, return to menu
				game_state = "menu"
				Missions.init(Config)  -- Reset missions for next playthrough
				-- Skip the next menu click to prevent clicking mission buttons while mouse is held
				skip_next_menu_click = true
			-- Check for show arcs toggle click
			elseif WeaponsUI.is_show_arcs_toggle_clicked(mx, my) then
				Config.show_firing_arcs = not Config.show_firing_arcs
				printh("Show firing arcs: " .. (Config.show_firing_arcs and "ON" or "OFF"))
			else
				-- Check for weapon selection clicks on main button
				local weapon_id = WeaponsUI.get_weapon_at_point(mx, my, Config)
				if weapon_id then
					-- Fire weapon if charged and has energy
					local weapon = Config.weapons[weapon_id]
					local state = weapon_states[weapon_id]
					local has_energy = energy_system.weapons >= weapon.energy_cost
					local is_charged = has_energy and state.charge >= 1.0

					if is_charged and current_selected_target then
						-- Fire beam at selected target
						local target_pos = nil
						local target_ref = nil

						if current_selected_target and current_selected_target.type == "satellite" and model_satellite and current_selected_target.position then
							target_pos = current_selected_target.position
							target_ref = current_selected_target  -- Pass enemy object, not config
						elseif current_selected_target and current_selected_target.type == "grabon" and current_selected_target.position then
							target_pos = current_selected_target.position
							target_ref = current_selected_target  -- Pass Grabon enemy object
						elseif current_selected_target and current_selected_target.type == "planet" and model_planet then
							target_pos = Config.planet.position
							target_ref = Config.planet
						end

						if target_pos and target_ref then
							-- Check if target is in range and in firing arc
							local in_range = ShipSystems.is_in_range(ship_pos, target_pos, weapon.range)
							local in_arc = ShipSystems.is_in_firing_arc(ship_pos, ship_heading_dir, target_pos, weapon.arc_start, weapon.arc_end)

							if in_range and in_arc then
								-- Fire beam
								WeaponEffects.fire_beam(ship_pos, target_pos)

								-- Spawn explosion at target (damage is applied in spawn_explosion)
								WeaponEffects.spawn_explosion(target_pos, target_ref)

								-- Check if target should spawn smoke (health > 70% damaged = health < 30%)
								if target_ref.current_health and target_ref.max_health then
									local health_percent = target_ref.current_health / target_ref.max_health
									if health_percent < 0.3 then  -- Damage is > 70%
										-- Try to spawn smoke at target location with slight random offset
										local smoke_offset_x = (math.random() - 0.5) * 4
										local smoke_offset_z = (math.random() - 0.5) * 4
										local smoke_pos = {
											x = target_pos.x + smoke_offset_x,
											y = target_pos.y + 2,
											z = target_pos.z + smoke_offset_z
										}
										WeaponEffects.spawn_smoke(smoke_pos, {x = 0, y = 0.3, z = 0})
									end
								end

								-- Reset charge after firing
								state.charge = 0
								printh("Weapon " .. weapon_id .. " fired! Damage: " .. (target_ref.current_health or "N/A"))
							else
								-- Cannot fire - out of range or out of arc
								printh("Weapon " .. weapon_id .. " cannot fire: " .. (not in_range and "out of range" or "out of arc"))
							end
						end
					else
						-- Just select weapon for reference
						selected_weapon = weapon_id
						printh("Weapon " .. weapon_id .. " selected (not ready)")
					end
				else
					-- Check for auto-fire toggle clicks
					local toggle_id = WeaponsUI.get_toggle_at_point(mx, my, Config)
					if toggle_id then
						weapon_states[toggle_id].auto_fire = not weapon_states[toggle_id].auto_fire
						printh("Weapon " .. toggle_id .. " auto-fire toggled: " .. (weapon_states[toggle_id].auto_fire and "ON" or "OFF"))
					end
				end
			end
		elseif not slider_dragging then
			-- If camera is locked to target, left-click unsnaps it
			if camera_locked_to_target then
				camera_locked_to_target = false
				printh("Camera unsnapped from target!")
			end
			-- Camera orbit (free rotate when not locked)
			if not camera_locked_to_target then
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
					-- Enable pitch rotation with mouse Y movement
					target_rx = target_rx + dy * Config.camera.orbit_sensitivity  -- pitch (rotate around X)

					-- Clamp target pitch to avoid gimbal lock
					target_rx = mid(-1.5, target_rx, 1.5)

					last_mouse_x = mx
					last_mouse_y = my
				end
			end
		end
	else
		mouse_drag = false
		slider_dragging = false
	end

	-- Always update raycast position for crosshair visualization
	raycast_x, raycast_z = raycast_to_ground_plane(mx, my, camera)

	-- Check if mouse is hovering over any satellite bounding box
	hovered_target = nil
	for _, enemy in ipairs(enemy_ships) do
		if enemy.position and not enemy.is_destroyed then
			if enemy.type == "satellite" or enemy.type == "grabon" then
				local pos = enemy.position
				local collider = enemy.config and enemy.config.collider or {width = 10, height = 10}

				-- Project center to screen and check if mouse is in the box
				-- Simple check: if we can project the center and it's close to mouse, consider it hovered
				local center_px, center_py = project_point(pos.x, pos.y, pos.z, camera)
				if center_px and center_py then
					-- Simple radius check (rough approximation)
					local dx = mx - center_px
					local dy = my - center_py
					local dist = sqrt(dx * dx + dy * dy)
					if dist < 20 then  -- Hover radius in pixels
						-- Set hovered target to this enemy ship
						hovered_target = enemy
						break  -- Only hover over the closest one
					end
				end
			end
		end
	end

	-- Right-click to set ship heading or select satellite/Grabon target
	if mb & 2 == 2 and not (mb & 1 == 1) then  -- Right mouse button only (not both)
		-- If satellite or Grabon is hovered, select it as target instead of setting heading
		if hovered_target and (hovered_target.type == "satellite" or hovered_target.type == "grabon") then
			current_selected_target = hovered_target
			camera_locked_to_target = true
			camera_pitch_before_targeting = camera.rx  -- Save current pitch
			printh(hovered_target.type .. " selected as target! ID=" .. current_selected_target.id)
			printh("DEBUG: current_selected_target IS SET after right-click")
		elseif raycast_x and raycast_z then
			-- Only set ship heading if we have a valid crosshair (raycast succeeded)
			-- printh("Raycast SUCCESS: world(" .. flr(raycast_x*10)/10 .. "," .. flr(raycast_z*10)/10 .. ")")

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
				-- printh("  Ship heading dir: (" .. flr(ship_heading_dir.x*1000)/1000 .. "," .. flr(ship_heading_dir.z*1000)/1000 .. ")")
				-- printh("  Target heading dir: (" .. flr(target_heading_dir.x*1000)/1000 .. "," .. flr(target_heading_dir.z*1000)/1000 .. ")")
			end
		end
	end

	-- Mobile controls: Z button (button 4) to cycle through enemies
	if btnp(4) then  -- Z button / button 4
		-- Get list of valid targets (satellites and grabons that are not destroyed)
		local valid_targets = {}
		for _, enemy in ipairs(enemy_ships) do
			if not enemy.is_destroyed and (enemy.type == "satellite" or enemy.type == "grabon") then
				add(valid_targets, enemy)
			end
		end

		if #valid_targets > 0 then
			-- Find current target index
			local current_index = 0
			if current_selected_target then
				for i, enemy in ipairs(valid_targets) do
					if enemy.id == current_selected_target.id then
						current_index = i
						break
					end
				end
			end

			-- Cycle to next target
			local next_index = (current_index % #valid_targets) + 1
			current_selected_target = valid_targets[next_index]
			camera_locked_to_target = true
			camera_pitch_before_targeting = camera.rx  -- Save current pitch
			printh("BUTTON 4 (Z): Cycled to target " .. current_selected_target.id)
		end
	end

	-- Mobile controls: Arrow keys (buttons 0/1) to rotate ship
	--if not Config.debug_lighting then  -- Only when not in debug mode
	if btn(1) then  -- Left arrow / button 0
		-- Rotate left: rotate the current heading left
		local current_angle = atan2(target_heading_dir.x, target_heading_dir.z)
		local new_angle = current_angle - Config.ship.arrow_key_rotation_speed  -- Rotate counter-clockwise
		target_heading_dir = {
			x = cos(new_angle),
			z = sin(new_angle)
		}
	end

	if btn(0) then  -- Right arrow / button 1
		-- Rotate right: rotate the current heading right
		local current_angle = atan2(target_heading_dir.x, target_heading_dir.z)
		local new_angle = current_angle + Config.ship.arrow_key_rotation_speed  -- Rotate clockwise
		target_heading_dir = {
			x = cos(new_angle),
			z = sin(new_angle)
		}
	end
	--end

	-- WASD controls for light rotation (only when debug_lighting is enabled)
	if Config.debug_lighting then
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
	end

	-- X key to fire debug beam (VFX only, no damage logic)
	if Config.enable_x_button and keyp("x") then
		printh("X KEY PRESSED - FIRING DEBUG BEAM!")

		-- Fire beam to satellite or planet
		local target_pos = nil
		if #enemy_ships > 0 and model_satellite then
			target_pos = enemy_ships[1].position
		elseif model_planet then
			target_pos = Config.planet.position
		end

		if target_pos then
			-- Fire beam from ship to target
			WeaponEffects.fire_beam(ship_pos, target_pos)
			printh("Beam fired from (" .. flr(ship_pos.x*10)/10 .. "," .. flr(ship_pos.y*10)/10 .. "," .. flr(ship_pos.z*10)/10 .. ") to (" .. flr(target_pos.x*10)/10 .. "," .. flr(target_pos.y*10)/10 .. "," .. flr(target_pos.z*10)/10 .. ")")
		end
	end

	-- Debug smoke spawn (old Z key binding - now used for enemy cycling)
	if false and keyp("z") then
		printh("Z KEY PRESSED - SPAWNING DEBUG SMOKE!")
		local target_pos = nil
		if #enemy_ships > 0 and model_satellite then
			target_pos = enemy_ships[1].position
		elseif model_planet then
			target_pos = Config.planet.position
		end

		if target_pos then
			WeaponEffects.spawn_smoke(target_pos)
			printh("Smoke spawned at (" .. flr(target_pos.x*10)/10 .. "," .. flr(target_pos.y*10)/10 .. "," .. flr(target_pos.z*10)/10 .. ")")
		end
	end

	-- Handle photon beam button clicks (only during gameplay)
	if game_state == "playing" and Config.photon_beam.enabled then
		local button_x = 390  -- slider_x - 60
		local button_y = slider_y + slider_height + 60
		local button_width = 50
		local button_height = 15
		local toggle_x = button_x
		local toggle_y = button_y + 20
		local toggle_size = 10

		-- Check fire button click
		if mb & 1 == 1 then
			if mx >= button_x and mx <= button_x + button_width and my >= button_y and my <= button_y + button_height then
				if current_selected_target and (current_selected_target.type == "satellite" or current_selected_target.type == "grabon") and current_selected_target.position then
					-- Check if we have enough weapons energy to fire (need 2 bars)
					if energy_system.weapons >= 2 then
						-- Fire photon beam at satellite
						local beam = {
							x = Config.ship.position.x,
							y = Config.ship.position.y,
							z = Config.ship.position.z,
							target_x = current_selected_target.position.x,
							target_y = current_selected_target.position.y,
							target_z = current_selected_target.position.z,
							age = 0,
							lifetime = Config.photon_beam.beam_lifetime
						}
						table.insert(photon_beams, beam)
						-- Consume 2 energy from weapons system
						energy_system.weapons = energy_system.weapons - 2
						printh("Photon beam fired! Weapons energy: " .. energy_system.weapons)
					else
						printh("Not enough weapons energy! Need 2 bars, have " .. energy_system.weapons)
					end
				end
			end
			-- Check auto toggle click
			if mx >= toggle_x and mx <= toggle_x + toggle_size and my >= toggle_y and my <= toggle_y + toggle_size then
				Config.photon_beam.auto_fire = not Config.photon_beam.auto_fire
				printh("Auto fire toggled: " .. (Config.photon_beam.auto_fire and "ON" or "OFF"))
			end
		end
	end

	-- Update weapon charging (weapons auto-charge continuously if energy available)
	for i = 1, #Config.weapons do
		local weapon = Config.weapons[i]
		local state = weapon_states[i]
		local has_energy = energy_system.weapons >= weapon.energy_cost

		-- Charge the weapon if energy is available
		if has_energy then
			state.charge = state.charge + 1/60 / weapon.charge_time  -- 60fps framerate
			if state.charge > 1.0 then
				state.charge = 1.0
			end
		else
			-- Stop charging if no energy
			state.charge = 0
		end
	end

	-- Update shield charging (shields charge sequentially based on allocated energy)
	-- Each allocated shield box takes 15 seconds to charge sequentially
	local allocated_shields = energy_system.shields
	for i = 1, 3 do
		if i <= allocated_shields then
			-- This shield box should be charging
			-- Check if previous box is fully charged (allow sequential charging)
			local previous_box_charged = (i == 1) or (shield_charge.boxes[i-1] >= 1.0)

			if previous_box_charged then
				-- Charge this box
				shield_charge.boxes[i] = shield_charge.boxes[i] + 1/60 / shield_charge.charge_time  -- 60fps framerate
				if shield_charge.boxes[i] > 1.0 then
					shield_charge.boxes[i] = 1.0
				end
			end
		else
			-- This shield box is not allocated, reset it
			shield_charge.boxes[i] = 0
		end
	end

	-- Handle auto-fire for weapons with auto-fire enabled
	for i = 1, #Config.weapons do
		local state = weapon_states[i]
		if state.auto_fire and is_weapon_ready(i, current_selected_target) then
			-- printh("FIRE CHECK: Weapon " .. i .. " is ready!")
			-- Fire the weapon
			local target_pos = nil
			local target_ref = nil

			if current_selected_target and current_selected_target.type == "satellite" and model_satellite and current_selected_target.position then
				target_pos = current_selected_target.position
				target_ref = current_selected_target  -- Pass enemy object, not config
			elseif current_selected_target and current_selected_target.type == "grabon" and current_selected_target.position then
				target_pos = current_selected_target.position
				target_ref = current_selected_target  -- Pass Grabon enemy object
			elseif current_selected_target and current_selected_target.type == "planet" and model_planet then
				target_pos = Config.planet.position
				target_ref = Config.planet
			end

			if target_pos and target_ref and ship_pos then
				-- Check if target is in range and in firing arc
				local weapon = Config.weapons[i]
				local in_range = ShipSystems.is_in_range(ship_pos, target_pos, weapon.range)
				local in_arc = ShipSystems.is_in_firing_arc(ship_pos, ship_heading_dir, target_pos, weapon.arc_start, weapon.arc_end)

				if in_range and in_arc then
					-- Fire beam
					WeaponEffects.fire_beam(ship_pos, target_pos)

					-- Spawn explosion at target (damage is applied in spawn_explosion)
					WeaponEffects.spawn_explosion(target_pos, target_ref)

					-- Reset weapon charge after firing
					state.charge = 0

					-- printh("Auto-fire: Weapon " .. i .. " fired at target")
				else
					-- Cannot fire - out of range or out of arc
					local abc = ""
					-- printh("Auto-fire: Weapon " .. i .. " cannot fire: " .. (not in_range and "out of range" or "out of arc"))
				end
			end
		end
	end

	-- MUST BE HERE TO ALLOW DEBUG DRAW TO WORK
	-- Sync camera_heading_dir from camera.ry at start of each frame (camera.ry is the actual camera position)
	camera_heading_dir = {x = sin(camera.ry), z = cos(camera.ry)}
	-- printh("SYNC: camera.ry = " .. flr(camera.ry*10000)/10000)

	-- Smooth camera rotation (using direction vectors like the ship)
	-- If target is selected, aim camera at it instead of free rotation
	if camera_locked_to_target and current_selected_target then
		local target_pos = nil

		-- Get position from current selected target object
		if current_selected_target.type == "satellite" and current_selected_target.position then
			target_pos = current_selected_target.position
		elseif current_selected_target.type == "grabon" and current_selected_target.position then
			target_pos = current_selected_target.position
		elseif current_selected_target.type == "planet" then
			target_pos = Config.planet.position
		end

		if target_pos then
			-- Calculate target direction from ship to target (normalized)
			local dx = target_pos.x - ship_pos.x
			local dz = target_pos.z - ship_pos.z
			local direction = MathUtils.normalize(vec(dx, 0, dz))
			camera_target_heading_dir = {x = direction.x, z = direction.z}
		end

		-- Rotate camera heading toward target using dot product for alignment
		-- and 90-degree rotated direction for left/right determination
		-- camera_heading_dir is the persistent source of truth

		-- Dot product: tells us how aligned we are (1 = perfectly aligned, -1 = opposite)
		local dot = camera_heading_dir.x * camera_target_heading_dir.x +
		            camera_heading_dir.z * camera_target_heading_dir.z

		-- Rotate both directions 90 degrees for precise alignment check
		-- Rotate counter-clockwise: (x, z) -> (-z, x)
		local camera_left_dir = {x = -camera_heading_dir.z, z = camera_heading_dir.x}
		local target_left_dir = {x = -camera_target_heading_dir.z, z = camera_target_heading_dir.x}

		-- Dot product with left direction: tells us if we need to turn left (positive) or right (negative)
		local left_dot = camera_left_dir.x * camera_target_heading_dir.x +
		                 camera_left_dir.z * camera_target_heading_dir.z

		-- Alignment check: dot product of both rotated vectors should be close to 0 when aligned
		local alignment_check = camera_left_dir.x * target_left_dir.x +
		                        camera_left_dir.z * target_left_dir.z

		-- DEBUG OUTPUT
		-- printh("=== CAMERA TARGET LOCK ===")
		-- printh("target_dir: (" .. flr(camera_target_heading_dir.x*1000)/1000 .. "," .. flr(camera_target_heading_dir.z*1000)/1000 .. ")")
		-- printh("current_dir: (" .. flr(camera_heading_dir.x*1000)/1000 .. "," .. flr(camera_heading_dir.z*1000)/1000 .. ")")
		-- printh("dot: " .. flr(dot*10000)/10000)
		-- printh("alignment_check: " .. flr(alignment_check*10000)/10000)
		-- printh("left_dot: " .. flr(left_dot*10000)/10000)

		-- Only rotate if not already at target (alignment_check < 0.001 means perfectly aligned)
		if abs(alignment_check) > 0.001 then
			-- Determine rotation direction from left_dot sign
			local turn_rate = 0.01 -- Turn rate in turns per frame
			local rotation_direction = left_dot > 0 and turn_rate or -turn_rate

			-- Apply smoothing based on how far off we are from target
			-- Smooth out the rotation as we get closer to alignment
			local smoothed_rotation = left_dot * turn_rate

			-- printh("rotation_direction: " .. flr(rotation_direction*10000)/10000)
			-- printh("smoothed_rotation: " .. flr(smoothed_rotation*10000)/10000)

			-- Update camera.ry with smoothed rotation
			camera.ry = camera.ry + smoothed_rotation

			-- printh("new_camera.ry: " .. flr(camera.ry*10000)/10000)
		end

		-- Preserve pitch from before targeting
		target_ry = camera.ry
		target_rx = camera_pitch_before_targeting or 0
	end

	-- Apply camera smoothing (but skip yaw if locked to target, since it's handled directly above)
	local smoothing = 0.2  -- Default smoothing for free look (0.1-0.3 range)

	camera.rx = camera.rx + (target_rx - camera.rx) * smoothing

	-- Only apply yaw smoothing if NOT locked to target (target lock handles rotation directly)
	if not camera_locked_to_target then
		camera.ry = camera.ry + (target_ry - camera.ry) * smoothing
	end

	-- Calculate impulse energy multiplier
	-- 0 energy = 0x multiplier, 1 energy = 0.25x, 2 energy = 0.5x, 3 energy = 0.75x, 4 energy = 1.0x
	-- This multiplies the slider-controlled speed
	local impulse_multiplier = energy_system.impulse / Config.energy.systems.impulse.capacity

	-- Apply impulse multiplier to desired slider speed to get actual target speed
	-- slider_speed_desired is independent and set only by the slider
	-- impulse_multiplier reduces how much of the slider speed actually gets used
	target_ship_speed = slider_speed_desired * impulse_multiplier

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

		-- Sync heading to Config for use in weapon calculations
		Config.ship.heading = new_angle
	end

	-- Move ship in direction of heading based on speed (only if alive)
	if not is_dead and ship_speed > 0.01 then
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

	-- Spawn new particle cubes around ship position (only if alive)
	if not is_dead and ship_speed > 0.01 then
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

	-- Check collisions with planet (only if not already dead)
	if not is_dead then
		local ship_collider = Config.ship.collider
		local planet_collider = Config.planet.collider

		-- Calculate ship box bounds (world space)
		local ship_box_min = {
			x = ship_pos.x - ship_collider.half_size.x,
			y = ship_pos.y - ship_collider.half_size.y,
			z = ship_pos.z - ship_collider.half_size.z,
		}
		local ship_box_max = {
			x = ship_pos.x + ship_collider.half_size.x,
			y = ship_pos.y + ship_collider.half_size.y,
			z = ship_pos.z + ship_collider.half_size.z,
		}

		-- Calculate planet sphere center
		local planet_pos = Config.planet.position
		local planet_center = {
			x = planet_pos.x,
			y = planet_pos.y,
			z = planet_pos.z,
		}

		-- Check collision
		if check_box_sphere_collision(ship_box_min, ship_box_max, planet_center, planet_collider.radius) then
			-- Collision detected!
			current_health = 0
			player_health_obj.current_health = current_health
			is_dead = true
			death_time = 0

		-- Spawn explosion at ship position
		if Config.explosion.enabled then
			table.insert(active_explosions, Explosion.new(Config.ship.position.x, Config.ship.position.y, Config.ship.position.z, Config.explosion))
			sfx(3)
		end

		end
	end

	-- Update Grabon AI for Mission 3 and Mission 4
	if Missions.get_current_mission().id == 3 or Missions.get_current_mission().id == 4 then
		update_grabon_ai()
	end

	-- Check collisions between player ship and enemy ships
	if not is_dead then
		local ship_collider = Config.ship.collider
		local ship_box_min = {
			x = ship_pos.x - ship_collider.half_size.x,
			y = ship_pos.y - ship_collider.half_size.y,
			z = ship_pos.z - ship_collider.half_size.z,
		}
		local ship_box_max = {
			x = ship_pos.x + ship_collider.half_size.x,
			y = ship_pos.y + ship_collider.half_size.y,
			z = ship_pos.z + ship_collider.half_size.z,
		}

		-- Check against each enemy ship
		for _, enemy in ipairs(enemy_ships) do
			if not enemy.is_destroyed then
				local enemy_collider = enemy.config.collider
				local enemy_box_min = {
					x = enemy.position.x - enemy_collider.half_size.x,
					y = enemy.position.y - enemy_collider.half_size.y,
					z = enemy.position.z - enemy_collider.half_size.z,
				}
				local enemy_box_max = {
					x = enemy.position.x + enemy_collider.half_size.x,
					y = enemy.position.y + enemy_collider.half_size.y,
					z = enemy.position.z + enemy_collider.half_size.z,
				}

				-- Check AABB-AABB collision
				local collision = (ship_box_min.x < enemy_box_max.x and ship_box_max.x > enemy_box_min.x) and
					(ship_box_min.y < enemy_box_max.y and ship_box_max.y > enemy_box_min.y) and
					(ship_box_min.z < enemy_box_max.z and ship_box_max.z > enemy_box_min.z)

				if collision then
					-- Initialize collision pair tracking if needed
					if not collision_pairs[ship.id] then
						collision_pairs[ship.id] = {}
					end

					local was_colliding = collision_pairs[ship.id][enemy.id]

					-- Apply damage if this is a new collision or ongoing
					if not was_colliding then
						printh("COLLISION: Player ship <> " .. enemy.id)
					end

					-- Apply damage based on armor
					-- First check if shields can absorb damage
					local shield_absorbed = apply_shield_absorption()
					if not shield_absorbed then
						-- Shields didn't absorb, apply damage to health
						WeaponEffects.apply_collision_damage(player_health_obj)
						-- Reset shield charge progress when hit without shields
						for i = 1, 3 do
							shield_charge.boxes[i] = 0
						end
					else
						printh("Shield absorbed incoming damage!")
					end
					WeaponEffects.apply_collision_damage(enemy)

					-- Sync player health back from player_health_obj
					current_health = player_health_obj.current_health
					-- Check if player died from collision
					if current_health <= 0 then
						is_dead = true
						death_time = 0
						-- Spawn explosion at ship position when player dies
						if Config.explosion.enabled then
							table.insert(active_explosions, Explosion.new(Config.ship.position.x, Config.ship.position.y, Config.ship.position.z, Config.explosion))
							sfx(3)
						end
					end

					-- Mark this pair as colliding
					collision_pairs[ship.id][enemy.id] = true
				else
					-- Clear collision tracking when not colliding
					if collision_pairs[ship.id] then
						collision_pairs[ship.id][enemy.id] = nil
					end
				end
			end
		end
	end

	-- Check if ship is out of bounds (only during gameplay)
	if game_state == "playing" and not is_dead then
		if Minimap.is_out_of_bounds(Config.ship.position) then
			if not is_out_of_bounds then
				-- Just went out of bounds
				is_out_of_bounds = true
				out_of_bounds_time = 0
				game_state = "out_of_bounds"
			end
		else
			-- Back in bounds
			is_out_of_bounds = false
			game_state = "playing"
		end
	end

	-- Update explosions and spawn their quads
	for i = #active_explosions, 1, -1 do
		local explosion = active_explosions[i]

		-- Update explosion (returns false if dead)
		if not explosion:update(0.016) then  -- 60fps = ~0.016s per frame
			table.remove(active_explosions, i)
		else
			-- Spawn quads for this explosion on first frame only
			if explosion.age <= 0.016 then
				for _, particle in ipairs(explosion.particles) do
					local quad = spawn_quad(
						particle.x,
						particle.y,
						particle.z,
						10, 10,  -- initial width, height
						explosion.sprite_id,  -- sprite_id
						64, 64,  -- sprite dimensions
						camera,  -- camera
						explosion.lifetime,  -- lifetime in seconds
						true  -- enable dither fading
					)
					-- Store reference to explosion for scale/opacity updates
					particle.quad_obj = quad
				end
			end

			-- Update quad scales and opacity based on explosion state
			local state = explosion:get_state()
			for _, particle in ipairs(explosion.particles) do
				if particle.quad_obj then
					particle.quad_obj.scale = state.scale
					-- Pass opacity directly (1.0 = opaque, 0.0 = transparent)
					particle.quad_obj.explosion_opacity = state.opacity
				end
			end
		end
	end

	-- Update spawned quads (age and remove expired ones)
	for i = #spawned_spheres, 1, -1 do
		local obj = spawned_spheres[i]
		if obj.lifetime then
			obj.age = obj.age + 0.016  -- Add one frame's worth of time (60fps)
			if obj.age >= obj.lifetime then
				table.remove(spawned_spheres, i)
			end
		end
	end

	-- Update death timer
	if is_dead then
		death_time = death_time + 0.016
	end

	-- Update weapon effects (beams, explosions, smoke)
	WeaponEffects.update(0.016)  -- 60fps delta time

	-- Check if any enemy ship has been destroyed (health reaches 0)
	for _, enemy in ipairs(enemy_ships) do
		if not destroyed_enemies[enemy.id] and enemy.current_health <= 0 then
			destroyed_enemies[enemy.id] = true
			enemy.is_destroyed = true
			printh("ENEMY DESTROYED: " .. enemy.id)

			-- Despawn the autonomous smoke emitter for this enemy
			WeaponEffects.unregister_smoke_spawner(enemy)

			-- Spawn explosion at enemy position (same sprite as player ship)
			local explosion = Explosion.new(
				enemy.position.x,
				enemy.position.y,
				enemy.position.z,
				Config.explosion
			)
			table.insert(active_explosions, explosion)

			-- Play big explosion sound effect (SFX 3)
			sfx(3)

			-- If the destroyed enemy is the currently selected target, clear targeting
			if current_selected_target and current_selected_target.id == enemy.id then
				-- Clear weapon targeting settings
				selected_weapon = nil
				current_selected_target = nil

				-- Clear camera targeting settings
				camera_locked_to_target = false
				if camera_pitch_before_targeting then
					camera.rx = camera_pitch_before_targeting
					camera_pitch_before_targeting = nil
				end
			end
		end
	end

	-- Update missions (only during gameplay)
	if game_state == "playing" then
		-- Update dialog system
		Missions.update_dialogs(1/60)  -- Assuming 60fps

		local current_mission = Missions.get_current_mission()

		if current_mission.id == 1 then
			-- Update mission 1 objectives
			Missions.update_camera_objective(camera.ry, camera.rx)
			local current_heading_angle = atan2(ship_heading_dir.x, ship_heading_dir.z)
			Missions.update_rotation_objective(current_heading_angle)
			Missions.update_movement_objective(ship_pos)
		elseif current_mission.id == 2 then
			-- Update mission 2 objectives
			Missions.update_subsystems_objective(Config.energy)
			Missions.update_targeting_objective(current_selected_target)
			-- Count destroyed enemies for combat objective
			local destroyed_count = 0
			for _ in pairs(destroyed_enemies) do
				destroyed_count = destroyed_count + 1
			end
			Missions.update_combat_objective(destroyed_count)
		elseif current_mission.id == 3 then
			-- Update mission 3 objectives
			Missions.update_search_objective(current_selected_target)
			-- Check if Grabon is destroyed (count destroyed enemies)
			local destroyed_count = 0
			for id in pairs(destroyed_enemies) do
				destroyed_count = destroyed_count + 1
			end
			local grabon_destroyed = destroyed_count >= 1
			Missions.update_destroy_objective(grabon_destroyed)
		elseif current_mission.id == 4 then
			-- Update mission 4 objectives
			Missions.update_search_objective_m4(current_selected_target)
			-- Count destroyed Grabons (mission 4 has 2 total)
			local destroyed_count = 0
			for id in pairs(destroyed_enemies) do
				destroyed_count = destroyed_count + 1
			end
			local grabons_alive = 2 - destroyed_count
			Missions.update_destroy_objective_m4(grabons_alive)
		end

		-- Check if current mission is complete
		if Missions.check_mission_complete() and not Missions.is_mission_complete() then
			Missions.set_mission_complete()

			-- Add delay before showing success screen for missions 2, 3, and 4
			local current_mission_obj = Missions.get_current_mission()
			if current_mission_obj and current_mission_obj.id == 2 then
				mission_success_time = -5.0  -- 5 second delay for mission 2
			elseif current_mission_obj and current_mission_obj.id == 3 then
				mission_success_time = -3.0  -- 3 second delay for mission 3
			elseif current_mission_obj and current_mission_obj.id == 4 then
				mission_success_time = -3.0  -- 3 second delay for mission 4
			else
				mission_success_time = 0
			end

			-- Transition to mission success scene
			game_state = "mission_success"
		end
	end

	-- Update mouse button state for next frame's click detection
	last_mouse_button_state = (mb & 1) == 1
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

-- Draw the "no energy" feedback message
function draw_no_energy_message()
	if not no_energy_message.visible then return end

	local msg_text = "NO ENERGY"
	local box_width = 60
	local box_height = 20
	local box_x = no_energy_message.x - box_width / 2
	local box_y = no_energy_message.y - box_height - 5

	-- Draw box background
	rectfill(box_x, box_y, box_x + box_width, box_y + box_height, 8)  -- Red background

	-- Draw box border
	rect(box_x, box_y, box_x + box_width, box_y + box_height, 7)  -- White border

	-- Draw text (centered)
	print(msg_text, box_x + 5, box_y + 6, 7)  -- White text
end

-- Draw shield charge status under health bar (slider-style bars)
function draw_shield_status()
	local allocated_shields = energy_system.shields

	-- Get configuration for shield sliders
	local shield_cfg = Config.shield_sliders
	local panel_x = shield_cfg.x
	local panel_y = shield_cfg.y
	local bar_width = shield_cfg.bar_width
	local bar_height = shield_cfg.bar_height
	local bar_spacing = shield_cfg.bar_spacing
	local fill_color = shield_cfg.fill_color
	local empty_color = shield_cfg.empty_color
	local border_color = shield_cfg.border_color

	-- Draw title
	-- print("shields", panel_x, panel_y + shield_cfg.label_y_offset, border_color)

	-- Draw 3 shield charge bars side by side
	for i = 1, 3 do
		local bar_x = panel_x + (i - 1) * (bar_width + bar_spacing)
		local bar_y = panel_y

		-- Draw background (dark - empty color)
		rectfill(bar_x, bar_y, bar_x + bar_width, bar_y + bar_height, empty_color)

		-- Draw charge progress (fill from left to right) - only if allocated
		if i <= allocated_shields and shield_charge.boxes[i] > 0 then
			local charge_fill_width = (bar_width - 2) * shield_charge.boxes[i]
			rectfill(bar_x + 1, bar_y + 1, bar_x + 1 + charge_fill_width, bar_y + bar_height - 1, fill_color)
		end

		-- Draw border (configured color)
		rect(bar_x, bar_y, bar_x + bar_width, bar_y + bar_height, border_color)
	end
end

function _draw()
	cls(0)  -- Clear to dark blue

	-- Get mouse position once for use throughout draw function
	local mx, my, mb = mouse()

	-- Handle +/- keys for camera zoom
	if keyp("=") or keyp("+") then
		-- Zoom in (decrease camera distance)
		camera.distance = camera.distance - 2
		camera.distance = max(Config.camera.min_distance, camera.distance)  -- Clamp minimum
	end
	if keyp("-") or keyp("_") then
		-- Zoom out (increase camera distance)
		camera.distance = camera.distance + 2
		camera.distance = min(Config.camera.max_distance, camera.distance)  -- Clamp maximum
	end

	-- ========================================
	-- BACKGROUND (Draw first)
	-- ========================================

	-- Draw stars first (before everything else)
	draw_stars()

	-- Draw sun after stars, but before all 3D objects
	draw_sun()

	if not model_shippy then
		print("no model loaded!", 10, 50, 8)
		return
	end

	-- ========================================
	-- GEOMETRY (3D models and faces)
	-- ========================================

	local all_faces = {}

	-- Calculate current light direction from yaw and pitch
	local light_dir = get_light_direction()

	-- Render planet with lit shader (same as ship)
	-- Check mission config for show_planet flag
	local current_mission = Missions.get_current_mission()
	local mission_config = current_mission.id == 1 and Config.missions.mission_1 or
	                        current_mission.id == 2 and Config.missions.mission_2 or
	                        current_mission.id == 3 and Config.missions.mission_3 or
	                        Config.missions.mission_4
	local show_planet = mission_config and mission_config.show_planet ~= false
	if model_planet and show_planet then
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
			Config.camera.render_distance
		)

		-- Add planet faces to all_faces
		for i = 1, #planet_faces do
			add(all_faces, planet_faces[i])
		end
	end

	-- Render ship (from config) - skip if ship has been dead for configured time
	if model_shippy and ship_pos and (not is_dead or death_time < Config.health.ship_disappear_time) then
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
			Config.camera.render_distance
		)

		-- Add all faces
		for i = 1, #shippy_faces do
			add(all_faces, shippy_faces[i])
		end
	end

	-- Render all satellites from enemy_ships array
	for _, enemy in ipairs(enemy_ships) do
		if enemy.type == "satellite" and model_satellite and enemy.position and not enemy.is_destroyed then
			local sat_pos = enemy.position
			local sat_rot = enemy.config.rotation
			local satellite_faces = RendererLit.render_mesh(
				model_satellite.verts, model_satellite.faces, camera,
				sat_pos.x, sat_pos.y, sat_pos.z,
				enemy.config.sprite_id,  -- sprite override
				light_dir,  -- light direction (directional light)
				nil,  -- light radius (unused for directional)
				light_brightness,  -- light brightness
				ambient,  -- ambient light
				false,  -- is_ground
				sat_rot.pitch, sat_rot.yaw, sat_rot.roll,
				Config.camera.render_distance
			)

			-- Add satellite faces to all_faces
			for i = 1, #satellite_faces do
				add(all_faces, satellite_faces[i])
			end
		end
	end

	-- Render all Grabons from enemy_ships array
	for _, enemy in ipairs(enemy_ships) do
		if enemy.type == "grabon" and enemy.model and enemy.position and not enemy.is_destroyed then
			local grabon_pos = enemy.position
			-- The renderer expects yaw in turns (0-1), with model alignment offset
			local grabon_yaw = enemy.heading + 0.25  -- 90° offset for model alignment

			local grabon_faces = RendererLit.render_mesh(
				enemy.model.verts, enemy.model.faces, camera,
				grabon_pos.x, grabon_pos.y, grabon_pos.z,
				enemy.config.sprite_id,  -- sprite override from config
				light_dir,  -- light direction (directional light)
				nil,  -- light radius (unused for directional)
				light_brightness,  -- light brightness
				ambient,  -- ambient light
				false,  -- is_ground
				0, grabon_yaw, 0,  -- pitch, yaw (heading + model offset), roll
				Config.camera.render_distance
			)

			-- Add Grabon faces to all_faces
			for i = 1, #grabon_faces do
				add(all_faces, grabon_faces[i])
			end
		end
	end

	-- Render all spawned objects (spheres or quads)
	for _, obj in ipairs(spawned_spheres) do
		-- Use custom mesh if provided (for quads), otherwise use model_sphere
		local mesh = obj.mesh or model_sphere

		if mesh then
			-- If this is a billboard mesh, regenerate vertices to face camera every frame
			local verts_to_render = mesh.verts
			if mesh.is_billboard then
				-- Apply explosion scale if this quad is part of an explosion
				local scale_factor = obj.scale or 1.0
				verts_to_render = create_billboard_quad(obj.mesh_half_size * scale_factor, camera)
			end

			-- Render the mesh using the lit renderer (skip lighting if mesh is unlit for performance)
			local obj_faces_rendered = RendererLit.render_mesh(
				verts_to_render, mesh.faces, camera,
				obj.x, obj.y, obj.z,
				nil,  -- sprite override (use sprite from model)
				light_dir,  -- light direction (directional light)
				nil,  -- light radius (unused for directional)
				light_brightness,  -- light brightness
				ambient,  -- ambient light
				false,  -- is_ground
				0, 0, 0,  -- no rotation
				Config.camera.render_distance,
				nil,  -- ground_always_behind
				nil,  -- fog_start_distance
				nil,  -- is_skybox
				nil,  -- fog_enabled
				mesh.unlit  -- is_unlit (skip lighting calculation for performance)
			)

			-- Add all rendered faces to the all_faces list
			for i = 1, #obj_faces_rendered do
				local face = obj_faces_rendered[i]
				-- Mark as unlit if mesh is marked as unlit
				if mesh.unlit then
					face.unlit = true
				end
				-- Apply explosion opacity if set
				if obj.explosion_opacity and obj.explosion_opacity < 1.0 then
					face.explosion_opacity = obj.explosion_opacity
				end
				-- Apply dither-based opacity if quad has dither fading enabled and lifetime
				if obj.dither_enabled and obj.lifetime then
					-- Calculate remaining life ratio (1.0 = full lifetime, 0.0 = expired)
					local remaining_ratio = 1.0 - (obj.age / obj.lifetime)
					-- Clamp to 0-1 range
					remaining_ratio = mid(0, remaining_ratio, 1)
					-- Store dither value for use in draw_faces
					face.dither_opacity = remaining_ratio
				end
				table.insert(all_faces, face)
			end
		end
	end

	-- Render explosions and add to face list with proper depth sorting
	ExplosionRenderer.render_explosions(active_explosions, camera, all_faces)

	-- Render weapon beams and add to face queue
	WeaponEffects.render_beams(camera, all_faces)

	-- Render weapon explosions and add to face queue
	WeaponEffects.render_explosions(camera, all_faces)

	-- Render weapon smoke and add to face queue
	WeaponEffects.render_smoke(camera, all_faces)

	-- Sort all faces by depth
	RendererLit.sort_faces(all_faces)

	-- Draw faces using lit rendering with color tables
	RendererLit.draw_faces(all_faces)

	-- ========================================
	-- WIREFRAME (3D overlays and effects)
	-- ========================================

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

	-- ========================================
	-- UI (Draw last)
	-- ========================================

	-- Draw weapons UI
	WeaponsUI.draw_weapons(energy_system, selected_weapon, weapon_states, Config, mx, my, ship_pos, ship_heading_dir, current_selected_target, WeaponEffects, ShipSystems, camera, draw_line_3d)

	-- Draw destination marker for current mission (mission UI now part of weapons panel)
	if game_state == "playing" then
		local mission_dest = Missions.get_current_mission()
		if mission_dest and mission_dest.destination then
			Missions.draw_destination_marker(mission_dest.destination, camera, draw_line_3d)
		end
	end

	-- Draw speed slider (check mission config for show_progress_slider flag)
	local show_progress_slider = mission_config and mission_config.show_progress_slider ~= false
	--if show_progress_slider then
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

	-- Slider handle (position based on desired slider speed, independent of impulse)
	local handle_y = slider_y + (1 - slider_speed_desired) * slider_height - slider_handle_height / 2
	handle_y = mid(slider_y, handle_y, slider_y + slider_height - slider_handle_height)
	rectfill(slider_x - 2, handle_y, slider_x + slider_width + 2, handle_y + slider_handle_height, 7)
	rect(slider_x - 2, handle_y, slider_x + slider_width + 2, handle_y + slider_handle_height, 6)

	-- Speed value text
	local speed_display = flr(ship_speed * Config.ship.max_speed * 10) / 10
	local text_x = slider_x + Config.slider.text_x_offset
	local text_y = slider_y + slider_height + Config.slider.text_y_offset
	print(Config.slider.text_prefix .. speed_display, text_x, text_y, Config.slider.text_color)
	--end

	-- Draw photon beam button and auto toggle
	if Config.photon_beam.enabled then
		local button_x = 390  -- slider_x - 60
		local button_y = slider_y + slider_height + 60
		local button_width = 50
		local button_height = 15
		local toggle_x = button_x
		local toggle_y = button_y + 20
		local toggle_size = 10

		-- Fire button background
		local button_color = current_selected_target and 11 or 5  -- Bright color if target selected, darker otherwise
		rectfill(button_x, button_y, button_x + button_width, button_y + button_height, button_color)
		rect(button_x, button_y, button_x + button_width, button_y + button_height, 7)
		print("fire", button_x + 10, button_y + 3, 0)

		-- Auto toggle checkbox
		local toggle_color = Config.photon_beam.auto_fire and 11 or 1
		rectfill(toggle_x, toggle_y, toggle_x + toggle_size, toggle_y + toggle_size, toggle_color)
		rect(toggle_x, toggle_y, toggle_x + toggle_size, toggle_y + toggle_size, 7)
		if Config.photon_beam.auto_fire then
			print("✓", toggle_x + 2, toggle_y, 0)
		end
		print("auto", toggle_x + 15, toggle_y + 1, 7)
	end

	-- CPU usage (drawn via UIRenderer)
	UIRenderer.draw_cpu_stats()

	-- ========================================
	-- DEBUG (Draw after UI)
	-- ========================================

	-- Debug weapons UI hitboxes
	if (Config.debug) then
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

	if (Config.debug) then
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

	-- Draw weapon effects (beams, explosions, smoke)
	local utilities = {
		draw_line_3d = draw_line_3d,
		project_to_screen = project_point,
		Renderer = Renderer,
	}
	WeaponEffects.draw(camera, utilities)

	-- Draw heading compass (arc, heading lines) when ship is moving or turning
	-- Calculate angle difference to see if we need to draw the compass
	local angle_diff = angle_difference(ship_heading_dir, target_heading_dir)

	-- Draw heading arc using ArcUI module
	local utilities = {
		draw_line_3d = draw_line_3d,
		dir_to_quat = dir_to_quat,
		quat_to_dir = quat_to_dir
	}
	ArcUI.draw_heading_arc(ship_heading_dir, target_heading_dir, angle_diff, camera, Config, utilities)

	-- Draw Grabon firing arc visualization when selected and firing arcs are enabled
	if current_selected_target and current_selected_target.type == "grabon" and current_selected_target.position and Config.show_firing_arcs then
		local grabon_pos = current_selected_target.position
		local grabon_ai = current_selected_target.config.ai
		if grabon_ai then
			-- Draw the firing arc for Grabon
			local grabon_dir = angle_to_dir(current_selected_target.heading)

			-- Check if player is in range and in firing arc (green if valid, red otherwise)
			local in_range = ShipSystems.is_in_range(grabon_pos, ship_pos, grabon_ai.attack_range)
			local in_arc = ShipSystems.is_in_firing_arc(grabon_pos, grabon_dir, ship_pos, grabon_ai.firing_arc_start, grabon_ai.firing_arc_end)
			local arc_color = (in_range and in_arc) and 11 or 8  -- Green (11) if valid firing position, red (8) otherwise

			WeaponEffects.draw_firing_arc(grabon_pos, grabon_dir, grabon_ai.attack_range, grabon_ai.firing_arc_start, grabon_ai.firing_arc_end, camera, draw_line_3d, arc_color)
		end
	end

	-- Draw physics debug wireframes if enabled
	if Config.debug_physics and ship_pos then
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

	-- Draw 2D selection boxes for satellites and Grabon
	ShipSelection.draw_selection_boxes(enemy_ships, current_selected_target, hovered_target, ship_pos, camera, project_point)

	-- Draw health bar at top left
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
	local health_color = health_percent > 0.5 and 3 or (health_percent > 0.25 and 8 or 8)  -- Green if >50%, yellow if >25%, red if <=25%
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

	-- Health text (inside the box with drop shadow)
	local health_display = flr(current_health)
	local health_text = "HP: " .. health_display
	local text_x = health_bar_x + 3
	local text_y = health_bar_y + 2
	-- Draw text shadow
	print(health_text, text_x + 1, text_y + 1, 1)
	-- Draw text
	print(health_text, text_x, text_y, 7)

	-- Draw energy bars
	draw_energy_bars()

	-- Draw no energy feedback message
	draw_no_energy_message()

	-- Draw shield charge status in lower right
	draw_shield_status()

	-- Draw target health bar and name above selected target
	ShipSelection.draw_target_health(current_selected_target, camera, project_point)

	-- Draw minimap during gameplay (via UIRenderer)
	if game_state == "playing" then
		-- Check if satellite is in sensor range
		local sat_in_range = false
		local first_sat_pos = nil
		if #enemy_ships > 0 and model_satellite then
			local first_sat = enemy_ships[1]
			first_sat_pos = first_sat.position
			local dx = first_sat_pos.x - Config.ship.position.x
			local dz = first_sat_pos.z - Config.ship.position.z
			local dist_to_sat = sqrt(dx * dx + dz * dz)
			sat_in_range = dist_to_sat <= first_sat.config.sensor_range
		end
		UIRenderer.draw_minimap(Config.ship.position, Config.planet.position, Config.planet.radius, first_sat_pos, sat_in_range)
	end

	-- Death screen (with 2 second delay before showing)
	if is_dead then
		death_time = death_time + (1 / 60)  -- Add one frame's worth of time

		if death_time >= Config.health.death_screen_delay then
			-- Check for mouse click
			local mouse_clicked = (mb & 1) == 1

			-- Update and draw death panel via UIRenderer
			local buttons = UIRenderer.get_buttons()
			buttons.restart_button:update(mx, my, mouse_clicked)
			UIRenderer.draw_death_screen()
		end
	end

	-- Out of bounds warning screen
	if is_out_of_bounds and game_state == "out_of_bounds" then
		out_of_bounds_time = out_of_bounds_time + (1 / 60)

		-- Check for mouse click
		local mouse_clicked = (mb & 1) == 1

		-- Calculate remaining time
		local remaining_time = Config.battlefield.out_of_bounds_warning_time - out_of_bounds_time
		remaining_time = mid(0, remaining_time, Config.battlefield.out_of_bounds_warning_time)

		-- Draw out of bounds panel via UIRenderer
		local buttons = UIRenderer.get_buttons()
		buttons.back_to_menu_button:update(mx, my, mouse_clicked)
		UIRenderer.draw_out_of_bounds(remaining_time)

		-- End game if time runs out
		if out_of_bounds_time >= Config.battlefield.out_of_bounds_warning_time then
			game_state = "menu"
			out_of_bounds_time = 0
			is_out_of_bounds = false
		end
	end

	-- Menu screen
	if game_state == "menu" then
		UIRenderer.draw_menu()
	end

	-- Mission success screen
	if game_state == "mission_success" then
		-- Update timer
		mission_success_time = mission_success_time + (1/60)  -- Assuming 60fps

		-- If we're still in the delay period for mission 2, just continue showing the game
		if mission_success_time < 0 then
			-- Don't show success screen yet, just return and keep rendering the game
			return
		end

		cls(0)  -- Clear screen

		-- Draw "Mission Success!!!" text in center
		local title = "Mission Success!!!"
		local title_x = 240 - (#title * 2)
		print(title, title_x - 1, 50, 0)   -- Shadow
		print(title, title_x, 49, 11)      -- Yellow text

		-- Draw narrative text about space academy (varies by mission)
		local current_mission = Missions.get_current_mission()
		local narrative_lines = {}

		if current_mission.id == 2 then
			narrative_lines = {
				"",
				"Excellent work, cadet!",
				"",
				"You've graduated top of your class",
				"with incredible fanfare from your",
				"peers and teachers alike.",
				"",
				"You have a bright future ahead of you.",
			}
		elseif current_mission.id == 3 then
			narrative_lines = {
				"",
				"Outstanding, Captain!",
				"",
				"Your maiden voyage was a complete",
				"success. You've proven yourself in",
				"real combat against a hostile Grabon.",
				"",
				"Your crew looks to you with confidence.",
				"This is only the beginning of your",
				"journey among the stars.",
			}
		elseif current_mission.id == 4 then
			narrative_lines = {
				"",
				"Incredible, Captain!",
				"",
				"You've successfully defeated",
				"overwhelming odds!",
				"",
				"Two enemy Grabons destroyed against",
				"a single ship. Your tactical prowess",
				"is unmatched.",
				"",
				"Command will remember this victory.",
			}
		else
			narrative_lines = {
				"",
				"Congratulations, cadet!",
				"",
				"Your instructors at the Academy were",
				"deeply impressed by your performance.",
				"You've successfully completed your",
				"first year of training.",
				"",
				"However, be warned: the next year",
				"will be far more challenging.",
			}
		end

		local text_y = 75
		local text_color = 7  -- White
		for _, line in ipairs(narrative_lines) do
			local text_x = 240 - (#line * 2)
			print(line, text_x, text_y, text_color)
			text_y = text_y + 8
		end

		-- OK button at bottom center
		local button_y = 180
		local button_width = 50
		local button_height = 15
		local button_x = 240 - (button_width / 2)

		-- Check if mouse is hovering over button
		local button_hovered = mx and my and
			mx >= button_x and mx <= button_x + button_width and
			my >= button_y and my <= button_y + button_height

		-- Draw button background
		local button_bg = button_hovered and 5 or 0
		rectfill(button_x, button_y, button_x + button_width, button_y + button_height, button_bg)

		-- Draw button border
		local button_border = button_hovered and 10 or 7
		rect(button_x, button_y, button_x + button_width, button_y + button_height, button_border)

		-- Draw button text
		local button_text = "OK"
		local button_text_x = button_x + (button_width - (#button_text * 4)) / 2
		local button_text_y = button_y + (button_height - 6) / 2
		print(button_text, button_text_x, button_text_y, 7)

		-- Check for button click or keyboard input
		local ok_clicked = ((mb & 1) == 1 and button_hovered) or keyp("return") or keyp("z")
		if ok_clicked then
			game_state = "menu"
			mission_success_time = 0
		end
	end

	-- Draw help panel overlay LAST (on top of absolutely everything)
	if game_state == "playing" then
		Missions.draw_help_panel(mx, my, Config)
	end
end

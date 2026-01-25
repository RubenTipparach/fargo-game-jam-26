--[[pod_format="raw",created="2024-11-07 20:00:00",modified="2024-11-07 20:00:00",revision=0]]
-- CameraSystem Module
-- Manages camera state, projection, and target tracking
-- Single Responsibility: Only handles camera-related functionality

local MathUtils = include("src/engine/math_utils.lua")

local CameraSystem = {}

-- Internal state (private)
local camera = nil
local target_rx = 0
local target_ry = 0
local target_camera_x = 0
local target_camera_z = 0

-- Camera heading for target tracking
local camera_heading_dir = {x = 0, z = 1}
local camera_target_heading_dir = {x = 0, z = 1}
local camera_locked_to_target = false
local camera_pitch_before_targeting = nil

-- Constants
local TAN_HALF_FOV = 0.7002075
local PROJ_SCALE = 270 / 0.7002075  -- 270 / tan_half_fov

-- Initialize camera from config
-- @param Config: Game configuration object
function CameraSystem.init(Config)
	camera = {
		x = 0,
		y = Config.camera.height or 0,
		z = 0,
		rx = Config.camera.rx,
		ry = Config.camera.ry,
		distance = Config.camera.distance,
	}
	target_rx = Config.camera.rx
	target_ry = Config.camera.ry
	target_camera_x = 0
	target_camera_z = 0
	camera_heading_dir = {x = 0, z = 1}
	camera_target_heading_dir = {x = 0, z = 1}
	camera_locked_to_target = false
	camera_pitch_before_targeting = nil
end

-- Get the camera object
-- @return: Camera table with x, y, z, rx, ry, distance
function CameraSystem.get_camera()
	return camera
end

-- Check if camera is locked to a target
function CameraSystem.is_locked()
	return camera_locked_to_target
end

-- Lock camera to a target
-- @param target: Target object with position field
function CameraSystem.lock_to_target(target)
	if target and target.position then
		camera_locked_to_target = true
		camera_pitch_before_targeting = camera.rx
	end
end

-- Unlock camera from target
function CameraSystem.unlock()
	if camera_locked_to_target then
		camera_locked_to_target = false
		-- Restore pitch but keep current camera state for smooth transition
		if camera_pitch_before_targeting then
			target_rx = camera_pitch_before_targeting
			camera_pitch_before_targeting = nil
		end
	end
end

-- Apply orbit rotation from mouse drag
-- @param dx: Delta X from mouse movement
-- @param dy: Delta Y from mouse movement
-- @param sensitivity: Orbit sensitivity multiplier
function CameraSystem.apply_orbit(dx, dy, sensitivity)
	if not camera_locked_to_target then
		target_ry = target_ry + dx * sensitivity
		target_rx = target_rx + dy * sensitivity
		-- Clamp pitch to avoid gimbal lock
		target_rx = mid(-1.5, target_rx, 1.5)
	end
end

-- Handle zoom input
-- @param delta: Positive to zoom in, negative to zoom out
-- @param Config: Config for min/max distance limits
function CameraSystem.handle_zoom(delta, Config)
	camera.distance = camera.distance - delta * 2
	camera.distance = mid(Config.camera.min_distance, camera.distance, Config.camera.max_distance)
end

-- Update camera position and rotation
-- @param ship_pos: Current ship position to follow
-- @param current_target: Currently selected target (or nil)
-- @param Config: Game configuration
function CameraSystem.update(ship_pos, current_target, Config)
	-- Sync camera heading from camera.ry
	camera_heading_dir = {x = sin(camera.ry), z = cos(camera.ry)}

	-- If locked to target, aim camera at it
	if camera_locked_to_target and current_target then
		local target_pos = nil

		-- Get position from target object
		if current_target.position then
			target_pos = current_target.position
		end

		if target_pos and ship_pos then
			-- Calculate target direction from ship to target
			local dx = target_pos.x - ship_pos.x
			local dz = target_pos.z - ship_pos.z
			local len = sqrt(dx * dx + dz * dz)
			if len > 0.001 then
				camera_target_heading_dir = {x = dx / len, z = dz / len}
			end

			-- Rotate camera toward target using dot product
			local dot = camera_heading_dir.x * camera_target_heading_dir.x +
			            camera_heading_dir.z * camera_target_heading_dir.z

			-- Rotate 90 degrees for left/right determination
			local camera_left_dir = {x = -camera_heading_dir.z, z = camera_heading_dir.x}
			local target_left_dir = {x = -camera_target_heading_dir.z, z = camera_target_heading_dir.x}

			local left_dot = camera_left_dir.x * camera_target_heading_dir.x +
			                 camera_left_dir.z * camera_target_heading_dir.z

			local alignment_check = camera_left_dir.x * target_left_dir.x +
			                        camera_left_dir.z * target_left_dir.z

			-- Rotate if not aligned
			if abs(alignment_check) > 0.001 then
				local turn_rate = 0.01
				local smoothed_rotation = left_dot * turn_rate
				camera.ry = camera.ry + smoothed_rotation
			end

			-- Update targets
			target_ry = camera.ry
			target_rx = camera_pitch_before_targeting or 0
		end
	end

	-- Apply camera smoothing
	local smoothing = 0.2
	camera.rx = camera.rx + (target_rx - camera.rx) * smoothing

	-- Only apply yaw smoothing if not locked to target
	if not camera_locked_to_target then
		camera.ry = camera.ry + (target_ry - camera.ry) * smoothing
	end

	-- Smooth camera following of ship position
	if ship_pos then
		target_camera_x = ship_pos.x
		target_camera_z = ship_pos.z

		local camera_smoothing = 0.15
		camera.x = camera.x + (target_camera_x - camera.x) * camera_smoothing
		camera.z = camera.z + (target_camera_z - camera.z) * camera_smoothing
	end

	-- Keep camera height from config
	camera.y = Config.camera.height or 0
end

-- Project a 3D point to screen space
-- @param x, y, z: World space coordinates
-- @param cam: Camera object (optional, uses internal camera if nil)
-- @return: screen_x, screen_y, view_z (or nil if behind camera)
function CameraSystem.project_point(x, y, z, cam)
	cam = cam or camera
	local cam_dist = cam.distance or 5

	-- Translate to camera space
	local cx = x - cam.x
	local cy = y - cam.y
	local cz = z - cam.z

	-- Apply camera rotation
	local sin_ry, cos_ry = sin(cam.ry), cos(cam.ry)
	local sin_rx, cos_rx = sin(cam.rx), cos(cam.rx)

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
		local px = x3 * inv_z * PROJ_SCALE + 240
		local py = y3 * inv_z * PROJ_SCALE + 135
		return px, py, z3
	end
	return nil, nil, nil
end

-- Unproject a screen point to world space at a given view depth
-- @param screen_x, screen_y: Screen coordinates
-- @param view_z: View space depth
-- @param cam: Camera object (optional)
-- @return: world_x, world_y, world_z
function CameraSystem.unproject_point(screen_x, screen_y, view_z, cam)
	cam = cam or camera
	local cam_dist = cam.distance or 5

	local sin_ry, cos_ry = sin(cam.ry), cos(cam.ry)
	local sin_rx, cos_rx = sin(cam.rx), cos(cam.rx)

	-- Unproject screen to view space
	local z3 = view_z
	local x3 = (screen_x - 240) / PROJ_SCALE * z3
	local y3 = (screen_y - 135) / PROJ_SCALE * z3

	-- Invert negation
	local x1 = -x3
	local y2 = -y3

	-- Invert camera distance
	local z2 = z3 - cam_dist

	-- Invert pitch rotation
	local cy = y2 * cos_rx + z2 * sin_rx
	local z1 = -y2 * sin_rx + z2 * cos_rx

	-- Invert yaw rotation
	local cx = x1 * cos_ry + z1 * sin_ry
	local cz = -x1 * sin_ry + z1 * cos_ry

	-- Convert to world space
	local world_x = cx + cam.x
	local world_y = cy + cam.y
	local world_z = cz + cam.z

	return world_x, world_y, world_z
end

-- Raycast from screen coordinates to ground plane (y=0)
-- @param screen_x, screen_y: Screen coordinates
-- @param cam: Camera object (optional)
-- @return: hit_x, hit_z (or nil, nil if no intersection)
function CameraSystem.raycast_to_ground(screen_x, screen_y, cam)
	cam = cam or camera

	-- Unproject at two depths to get ray
	local near_x, near_y, near_z = CameraSystem.unproject_point(screen_x, screen_y, 0.1, cam)
	local far_x, far_y, far_z = CameraSystem.unproject_point(screen_x, screen_y, 100, cam)

	-- Ray direction
	local ray_x = far_x - near_x
	local ray_y = far_y - near_y
	local ray_z = far_z - near_z

	-- Normalize
	local ray_len = sqrt(ray_x*ray_x + ray_y*ray_y + ray_z*ray_z)
	if ray_len < 0.0001 then
		return nil, nil
	end
	ray_x = ray_x / ray_len
	ray_y = ray_y / ray_len
	ray_z = ray_z / ray_len

	-- Intersect with y=0 plane
	if abs(ray_y) < 0.0001 then
		return nil, nil
	end

	local t = -near_y / ray_y
	if t < 0 then
		return nil, nil
	end

	return near_x + t * ray_x, near_z + t * ray_z
end

-- Build camera transformation matrix (3x4 for matmul3d)
-- @param cam: Camera object (optional)
-- @return: Userdata matrix
function CameraSystem.build_matrix(cam)
	cam = cam or camera
	local sin_ry, cos_ry = sin(cam.ry), cos(cam.ry)
	local sin_rx, cos_rx = sin(cam.rx), cos(cam.rx)

	local mat = userdata("f64", 4, 3)

	-- Row 0: x transformation
	mat:set(0, 0, cos_ry)
	mat:set(1, 0, 0)
	mat:set(2, 0, -sin_ry)
	mat:set(3, 0, 0)

	-- Row 1: y transformation
	mat:set(0, 1, sin_ry * sin_rx)
	mat:set(1, 1, cos_rx)
	mat:set(2, 1, cos_ry * sin_rx)
	mat:set(3, 1, 0)

	-- Row 2: z transformation
	mat:set(0, 2, sin_ry * cos_rx)
	mat:set(1, 2, -sin_rx)
	mat:set(2, 2, cos_ry * cos_rx)
	mat:set(3, 2, cam.distance or 30)

	return mat
end

return CameraSystem

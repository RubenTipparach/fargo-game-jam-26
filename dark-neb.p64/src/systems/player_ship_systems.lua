--[[pod_format="raw",created="2025-11-10 00:00:00",modified="2025-11-10 00:00:00",revision=1]]
-- Player Ship Systems Module
-- Encapsulates firing arc validation, rotation control, and speed management
-- Mirrors the exact implementations from main.lua and weapon_effects.lua

local PlayerShipSystems = {}

-- ============================================
-- FIRING ARC SYSTEM
-- ============================================

-- Check if a target is within weapon range
-- @param ship_pos: {x, y, z} ship position
-- @param target_pos: {x, y, z} target position
-- @param range: maximum firing distance
-- @return: true if target is in range
function PlayerShipSystems.is_in_range(ship_pos, target_pos, range)
	if not ship_pos or not target_pos or not range then
		return false
	end

	local dx = target_pos.x - ship_pos.x
	local dz = target_pos.z - ship_pos.z
	local distance_sq = dx * dx + dz * dz
	local range_sq = range * range

	return distance_sq <= range_sq
end

-- Check if a target is within weapon firing arc
-- Simplified 2D dot product test in X,Z space
-- @param ship_pos: {x, y, z} ship position
-- @param ship_heading: ship heading in turns (0-1 range, 0 = +Z axis) OR direction vector {x, z}
-- @param target_pos: {x, y, z} target position
-- @param arc_start: left edge of arc in degrees (negative = left)
-- @param arc_end: right edge of arc in degrees (positive = right)
-- @return: true if target is within firing arc
function PlayerShipSystems.is_in_firing_arc(ship_pos, ship_heading, target_pos, arc_start, arc_end)
	if not ship_pos or not target_pos or not ship_heading then
		return false
	end

	-- Get ship forward direction - handle both numeric heading and direction vector
	local ship_forward_x, ship_forward_z
	if ship_heading.x and ship_heading.z then
		-- Direction vector format {x, z}
		ship_forward_x = ship_heading.x
		ship_forward_z = ship_heading.z
	else
		-- Numeric heading in turns (0-1 range)
		-- 0 = +Z, 0.25 = +X, 0.5 = -Z, 0.75 = -X
		local ship_heading_rad = ship_heading * 2 * 3.14159265359
		ship_forward_x = math.sin(ship_heading_rad)
		ship_forward_z = math.cos(ship_heading_rad)
	end

	-- Vector from ship to target
	local to_target_x = target_pos.x - ship_pos.x
	local to_target_z = target_pos.z - ship_pos.z

	-- Normalize to_target
	local to_target_len = math.sqrt(to_target_x * to_target_x + to_target_z * to_target_z)
	if to_target_len < 0.001 then
		return false  -- Target is at ship position
	end

	to_target_x = to_target_x / to_target_len
	to_target_z = to_target_z / to_target_len

	-- Dot product with ship forward = cosine of angle between them
	local dot = ship_forward_x * to_target_x + ship_forward_z * to_target_z

	-- Calculate actual angle from dot product (in degrees, 0 = aligned with forward)
	local angle = math.acos(math.max(-1, math.min(1, dot))) * 180 / 3.14159265359

	-- Cross product to determine left vs right
	-- (ship_forward × to_target) in 2D: forward.x * target.z - forward.z * target.x
	local cross = ship_forward_x * to_target_z - ship_forward_z * to_target_x

	-- If cross < 0, target is to the right (negative angle)
	if cross < 0 then
		angle = -angle
	end

	-- Check if angle is within arc
	return angle >= arc_start and angle <= arc_end
end

-- ============================================
-- ROTATION SYSTEM
-- ============================================

-- Calculate rotation direction and magnitude to target heading
-- Rotates at constant turn_rate in shortest direction, returns new heading direction vector
-- Uses angle-based rotation with atan2 and direction vector conversion
-- @param current_heading_dir: {x, z} current direction vector
-- @param target_heading_dir: {x, z} target direction vector
-- @param turn_rate: turn rate (positive value in turns, e.g., 0.01 for 1% rotation per frame)
-- @return: {x, z} new heading direction after rotation step
function PlayerShipSystems.calculate_rotation(current_heading_dir, target_heading_dir, turn_rate)
	if not current_heading_dir or not target_heading_dir or not turn_rate then
		return {x = current_heading_dir.x, z = current_heading_dir.z}
	end

	local current_angle = atan2(current_heading_dir.x, current_heading_dir.z)
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
		local rotation_amount = angle_diff > 0 and turn_rate or -turn_rate

		-- Apply rotation to current angle
		local new_angle = current_angle + rotation_amount

		-- Convert back to direction vector
		local new_x = cos(new_angle)
		local new_z = sin(new_angle)

		-- Normalize to ensure unit vector (handle floating point drift)
		local len = sqrt(new_x * new_x + new_z * new_z)
		if len > 0.0001 then
			new_x = new_x / len
			new_z = new_z / len
		end

		return {x = new_x, z = new_z}
	end

	return {x = current_heading_dir.x, z = current_heading_dir.z}
end

-- ============================================
-- SPEED SYSTEM
-- ============================================

-- Calculate new ship speed using smooth interpolation
-- Smooth ship speed (lerp towards target)
-- @param current_speed: current ship speed
-- @param target_speed: target ship speed
-- @param speed_smoothing: smoothing factor (e.g., Config.ship.speed_smoothing = 0.08)
-- @return: float new ship speed after interpolation
function PlayerShipSystems.calculate_speed(current_speed, target_speed, speed_smoothing)
	if not current_speed or not target_speed or not speed_smoothing then
		return current_speed or 0
	end

	-- Smooth ship speed (lerp towards target)
	return current_speed + (target_speed - current_speed) * speed_smoothing
end

-- Calculate movement offset based on speed and direction
-- Move ship in direction of heading based on speed
-- @param ship_speed: current ship speed
-- @param ship_heading_dir: {x, z} ship heading direction (unit vector)
-- @param max_speed: maximum speed constant (e.g., Config.ship.max_speed)
-- @return: {x, z} movement offset for this frame
function PlayerShipSystems.calculate_movement(ship_speed, ship_heading_dir, max_speed)
	if not ship_speed or not ship_heading_dir or not max_speed then
		return {x = 0, z = 0}
	end

	local move_speed = ship_speed * max_speed * 0.1  -- Scale for reasonable movement

	return {
		x = ship_heading_dir.x * move_speed,
		z = ship_heading_dir.z * move_speed
	}
end

return PlayerShipSystems

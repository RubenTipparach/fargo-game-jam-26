-- Math Utilities Module
-- Provides common mathematical operations for 3D graphics

local MathUtils = {}

-- Fast inverse square root (Quake III algorithm)
-- Returns 1/sqrt(x) efficiently using Newton-Raphson refinement
-- @param number: value to compute inverse square root of
-- @return 1/sqrt(number)
function MathUtils.fast_inv_sqrt(number)
	if number <= 0 then return 0 end

	local x2 = number * 0.5
	local i = 1.0 / sqrt(number)  -- Initial guess

	-- Newton-Raphson iteration (Quake does 1-2 iterations)
	local y = i * (1.5 - (x2 * i * i))  -- 1st iteration
	-- y = y * (1.5 - (x2 * y * y))  -- 2nd iteration (optional, more accurate)

	return y
end

-- Normalize a vector to unit length
-- @param v: vector with x, y, z components
-- @return normalized vector
function MathUtils.normalize(v)
	local len_sq = v.x*v.x + v.y*v.y + v.z*v.z
	if len_sq > 0.0001 then
		local inv_len = MathUtils.fast_inv_sqrt(len_sq)
		return vec(v.x * inv_len, v.y * inv_len, v.z * inv_len)
	end
	return v
end

-- Calculate vector magnitude
-- @param v: vector with x, y, z components
-- @return magnitude (length)
function MathUtils.magnitude(v)
	return sqrt(v.x*v.x + v.y*v.y + v.z*v.z)
end

-- Cross product of two 3D vectors
-- @param a, b: vectors
-- @return cross product vector
function MathUtils.cross(a, b)
	return vec(
		a.y * b.z - a.z * b.y,
		a.z * b.x - a.x * b.z,
		a.x * b.y - a.y * b.x
	)
end

-- Dot product of two vectors
-- @param a, b: vectors
-- @return scalar dot product
function MathUtils.dot(a, b)
	return a.x * b.x + a.y * b.y + a.z * b.z
end

-- Rotate a point around Y axis (yaw)
-- @param x, z: coordinates
-- @param angle: rotation angle
-- @return rotated x, z
function MathUtils.rotate_y(x, z, angle)
	local cos_a, sin_a = cos(angle), sin(angle)
	return x * cos_a - z * sin_a, x * sin_a + z * cos_a
end

-- Rotate a point around X axis (pitch)
-- @param y, z: coordinates
-- @param angle: rotation angle
-- @return rotated y, z
function MathUtils.rotate_x(y, z, angle)
	local cos_a, sin_a = cos(angle), sin(angle)
	return y * cos_a - z * sin_a, y * sin_a + z * cos_a
end

-- Rotate a point around Z axis (roll)
-- @param x, y: coordinates
-- @param angle: rotation angle
-- @return rotated x, y
function MathUtils.rotate_z(x, y, angle)
	local cos_a, sin_a = cos(angle), sin(angle)
	return x * cos_a - y * sin_a, x * sin_a + y * cos_a
end

-- Apply full 3D rotation (yaw, pitch, roll) to a point
-- @param x, y, z: point coordinates
-- @param yaw, pitch, roll: rotation angles (can be nil)
-- @return rotated x, y, z
function MathUtils.rotate_3d(x, y, z, yaw, pitch, roll)
	-- Yaw (Y axis)
	if yaw then
		local cos_yaw, sin_yaw = cos(yaw), sin(yaw)
		local x_yaw = x * cos_yaw - z * sin_yaw
		local z_yaw = x * sin_yaw + z * cos_yaw
		x, z = x_yaw, z_yaw
	end

	-- Pitch (X axis)
	if pitch then
		local cos_pitch, sin_pitch = cos(pitch), sin(pitch)
		local y_pitch = y * cos_pitch - z * sin_pitch
		local z_pitch = y * sin_pitch + z * cos_pitch
		y, z = y_pitch, z_pitch
	end

	-- Roll (Z axis)
	if roll then
		local cos_roll, sin_roll = cos(roll), sin(roll)
		local x_roll = x * cos_roll - y * sin_roll
		local y_roll = x * sin_roll + y * cos_roll
		x, y = x_roll, y_roll
	end

	return x, y, z
end

-- Seeded random number generator for consistent placement
-- @param x, z, seed: input values
-- @return random float between 0 and 1
function MathUtils.seeded_random(x, z, seed)
	local hash = (x * 73856093) ~ (z * 19349663) ~ (seed * 83492791)
	hash = ((hash ~ (hash >> 13)) * 0x5bd1e995) & 0xffffffff
	hash = hash ~ (hash >> 15)
	return (hash & 0x7fffffff) / 0x7fffffff
end

-- Linear interpolation
-- @param a, b: values to interpolate between
-- @param t: interpolation factor (0-1)
-- @return interpolated value
function MathUtils.lerp(a, b, t)
	return a + (b - a) * t
end

-- Clamp value between min and max
-- @param value, min_val, max_val: numbers
-- @return clamped value
function MathUtils.clamp(value, min_val, max_val)
	if value < min_val then return min_val end
	if value > max_val then return max_val end
	return value
end

-- ============================================
-- DIRECTION/ANGLE CONVERSION (XZ Plane)
-- ============================================

-- Convert 2D direction vector to angle (in turns, 0-1 range)
-- @param dir: {x, z} direction vector on XZ plane
-- @return: Angle in turns (0-1 range, 0 = +Z direction)
function MathUtils.dir_to_angle(dir)
	return atan2(dir.x, dir.z)
end

-- Convert angle to 2D direction vector
-- @param angle: Angle in turns (0-1 range)
-- @return: {x, z} direction vector on XZ plane
function MathUtils.angle_to_dir(angle)
	return {x = cos(angle), z = sin(angle)}
end

-- Calculate shortest angular difference between two directions
-- @param dir1, dir2: {x, z} direction vectors
-- @return: Absolute angle difference in turns (0-0.5 range)
function MathUtils.angle_difference(dir1, dir2)
	local angle1 = MathUtils.dir_to_angle(dir1)
	local angle2 = MathUtils.dir_to_angle(dir2)

	local diff = angle2 - angle1
	if diff > 0.5 then
		diff = diff - 1
	elseif diff < -0.5 then
		diff = diff + 1
	end

	return abs(diff)
end

-- Update heading direction toward target at constant turn rate
-- @param current_dir: {x, z} current direction
-- @param target_dir: {x, z} target direction
-- @param turn_rate: Turn rate in turns per frame
-- @return: {x, z} new direction after applying rotation
function MathUtils.update_heading(current_dir, target_dir, turn_rate)
	local current_angle = MathUtils.dir_to_angle(current_dir)
	local target_angle = MathUtils.dir_to_angle(target_dir)

	-- Calculate shortest angular difference
	local angle_diff = target_angle - current_angle
	if angle_diff > 0.5 then
		angle_diff = angle_diff - 1
	elseif angle_diff < -0.5 then
		angle_diff = angle_diff + 1
	end

	-- Check if already at target
	if abs(angle_diff) < 0.001 then
		return {x = current_dir.x, z = current_dir.z}
	end

	-- Apply rotation at constant rate
	local rotation_amount = angle_diff > 0 and turn_rate or -turn_rate
	local new_angle = current_angle + rotation_amount

	-- Convert back to direction
	local new_dir = {
		x = cos(new_angle),
		z = sin(new_angle)
	}

	-- Normalize to handle floating point drift
	local len = sqrt(new_dir.x * new_dir.x + new_dir.z * new_dir.z)
	if len > 0.0001 then
		new_dir.x = new_dir.x / len
		new_dir.z = new_dir.z / len
	end

	return new_dir
end

-- ============================================
-- QUATERNION OPERATIONS (Y-Axis Rotation)
-- ============================================

-- Convert 2D direction vector to quaternion (rotation around Y axis)
-- @param dir: {x, z} direction vector
-- @return: {w, x, y, z} quaternion
function MathUtils.dir_to_quat(dir)
	local len = sqrt(dir.x * dir.x + dir.z * dir.z)
	if len < 0.0001 then
		return {w = 1, x = 0, y = 0, z = 0}
	end

	local norm_x = dir.x / len
	local norm_z = dir.z / len

	local cos_theta = norm_z
	local sin_theta = norm_x

	local half_cos = sqrt((1 + cos_theta) / 2)
	local half_sin = (sin_theta >= 0 and 1 or -1) * sqrt((1 - cos_theta) / 2)

	return {
		w = half_cos,
		x = 0,
		y = half_sin,
		z = 0
	}
end

-- Convert quaternion back to 2D direction vector
-- @param q: {w, x, y, z} quaternion
-- @return: {x, z} direction vector
function MathUtils.quat_to_dir(q)
	local x = 2 * (q.x * q.z + q.w * q.y)
	local z = 1 - 2 * (q.x * q.x + q.y * q.y)

	local len = sqrt(x * x + z * z)
	if len > 0.0001 then
		x = x / len
		z = z / len
	end

	return {x = x, z = z}
end

-- Quaternion SLERP with max turn rate
-- @param q1, q2: Quaternions to interpolate between
-- @param max_turn_rate: Maximum rotation in turns per step
-- @return: Interpolated quaternion
function MathUtils.quat_slerp(q1, q2, max_turn_rate)
	local dot = q1.w * q2.w + q1.x * q2.x + q1.y * q2.y + q1.z * q2.z

	-- Take shorter path
	if dot < 0 then
		q2 = {w = -q2.w, x = -q2.x, y = -q2.y, z = -q2.z}
		dot = -dot
	end

	if dot > 1 then dot = 1 end
	if dot < -1 then dot = -1 end

	local theta = atan2(sqrt(1 - dot * dot), dot)

	if theta > max_turn_rate then
		theta = max_turn_rate
	end

	local full_theta = atan2(sqrt(1 - dot * dot), dot)

	if full_theta < 0.00001 then
		return {w = q1.w, x = q1.x, y = q1.y, z = q1.z}
	end

	local t = theta / full_theta

	local sin_full = sin(full_theta)
	if abs(sin_full) < 0.0001 then
		-- Linear interpolation fallback
		local result_w = q1.w + t * (q2.w - q1.w)
		local result_x = q1.x + t * (q2.x - q1.x)
		local result_y = q1.y + t * (q2.y - q1.y)
		local result_z = q1.z + t * (q2.z - q1.z)
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

return MathUtils

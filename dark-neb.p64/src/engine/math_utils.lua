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

return MathUtils

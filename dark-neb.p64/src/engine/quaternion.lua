-- Quaternion Math Library for 3D Rotations
-- Quaternions are represented as {x, y, z, w} where w is the scalar component

local Quat = {}
local MathUtils = require("engine.math_utils")

-- Create a new quaternion
function Quat.new(x, y, z, w)
	return {x = x or 0, y = y or 0, z = z or 0, w = w or 1}
end

-- Identity quaternion (no rotation)
function Quat.identity()
	return {x = 0, y = 0, z = 0, w = 1}
end

-- Create quaternion from Euler angles (pitch, yaw, roll)
-- Angles are in Picotron format (0-1 = full rotation)
function Quat.from_euler(pitch, yaw, roll)
	pitch = pitch or 0
	yaw = yaw or 0
	roll = roll or 0

	-- Convert to half angles (Picotron already uses 0-1, so just divide by 2)
	local hp = pitch * 0.5
	local hy = yaw * 0.5
	local hr = roll * 0.5

	local cp, sp = cos(hp), sin(hp)
	local cy, sy = cos(hy), sin(hy)
	local cr, sr = cos(hr), sin(hr)

	return {
		x = sr * cp * cy - cr * sp * sy,
		y = cr * sp * cy + sr * cp * sy,
		z = cr * cp * sy - sr * sp * cy,
		w = cr * cp * cy + sr * sp * sy
	}
end

-- Convert quaternion to Euler angles (returns pitch, yaw, roll)
-- Returns angles in Picotron format (0-1)
function Quat.to_euler(q)
	-- Roll (x-axis rotation)
	local sinr_cosp = 2 * (q.w * q.x + q.y * q.z)
	local cosr_cosp = 1 - 2 * (q.x * q.x + q.y * q.y)
	local roll = atan2(sinr_cosp, cosr_cosp)

	-- Pitch (y-axis rotation)
	local sinp = 2 * (q.w * q.y - q.z * q.x)
	local pitch
	if abs(sinp) >= 1 then
		pitch = sinp > 0 and 0.25 or -0.25  -- 90 degrees = 0.25 in Picotron
	else
		pitch = asin(sinp)
	end

	-- Yaw (z-axis rotation)
	local siny_cosp = 2 * (q.w * q.z + q.x * q.y)
	local cosy_cosp = 1 - 2 * (q.y * q.y + q.z * q.z)
	local yaw = atan2(siny_cosp, cosy_cosp)

	return pitch, yaw, roll
end

-- Multiply two quaternions (combine rotations)
-- Order matters: q1 * q2 applies q2 first, then q1
function Quat.multiply(q1, q2)
	return {
		x = q1.w * q2.x + q1.x * q2.w + q1.y * q2.z - q1.z * q2.y,
		y = q1.w * q2.y - q1.x * q2.z + q1.y * q2.w + q1.z * q2.x,
		z = q1.w * q2.z + q1.x * q2.y - q1.y * q2.x + q1.z * q2.w,
		w = q1.w * q2.w - q1.x * q2.x - q1.y * q2.y - q1.z * q2.z
	}
end

-- Normalize a quaternion
function Quat.normalize(q)
	local len_sq = q.x * q.x + q.y * q.y + q.z * q.z + q.w * q.w
	if len_sq < 0.0001 then
		return Quat.identity()
	end
	local inv_len = MathUtils.fast_inv_sqrt(len_sq)
	return {
		x = q.x * inv_len,
		y = q.y * inv_len,
		z = q.z * inv_len,
		w = q.w * inv_len
	}
end

-- Conjugate of a quaternion (inverse rotation if normalized)
function Quat.conjugate(q)
	return {x = -q.x, y = -q.y, z = -q.z, w = q.w}
end

-- Rotate a 3D vector by a quaternion
function Quat.rotate_vector(q, vx, vy, vz)
	-- Convert vector to quaternion
	local vq = {x = vx, y = vy, z = vz, w = 0}

	-- result = q * v * q^-1
	local qconj = Quat.conjugate(q)
	local temp = Quat.multiply(q, vq)
	local result = Quat.multiply(temp, qconj)

	return result.x, result.y, result.z
end

-- Spherical linear interpolation between two quaternions
function Quat.slerp(q1, q2, t)
	-- Compute dot product
	local dot = q1.x * q2.x + q1.y * q2.y + q1.z * q2.z + q1.w * q2.w

	-- If negative dot, negate one quaternion to take shorter path
	if dot < 0 then
		q2 = {x = -q2.x, y = -q2.y, z = -q2.z, w = -q2.w}
		dot = -dot
	end

	-- If very close, use linear interpolation
	if dot > 0.9995 then
		return Quat.normalize({
			x = q1.x + t * (q2.x - q1.x),
			y = q1.y + t * (q2.y - q1.y),
			z = q1.z + t * (q2.z - q1.z),
			w = q1.w + t * (q2.w - q1.w)
		})
	end

	-- Spherical interpolation
	local theta = acos(dot)
	local sin_theta = sin(theta)
	local a = sin((1 - t) * theta) / sin_theta
	local b = sin(t * theta) / sin_theta

	return {
		x = a * q1.x + b * q2.x,
		y = a * q1.y + b * q2.y,
		z = a * q1.z + b * q2.z,
		w = a * q1.w + b * q2.w
	}
end

-- Create a "look at" quaternion that rotates to face a target
-- eye: position of the observer {x, y, z}
-- target: position to look at {x, y, z}
-- up: up vector (default {0, 1, 0})
function Quat.look_at(eye, target, up)
	up = up or {x = 0, y = 1, z = 0}

	-- Calculate forward vector
	local fx = target.x - eye.x
	local fy = target.y - eye.y
	local fz = target.z - eye.z
	local flen_sq = fx * fx + fy * fy + fz * fz
	if flen_sq < 0.0001 then
		return Quat.identity()
	end
	local inv_flen = MathUtils.fast_inv_sqrt(flen_sq)
	fx, fy, fz = fx * inv_flen, fy * inv_flen, fz * inv_flen

	-- Calculate right vector (cross product: forward x up)
	local rx = fy * up.z - fz * up.y
	local ry = fz * up.x - fx * up.z
	local rz = fx * up.y - fy * up.x
	local rlen_sq = rx * rx + ry * ry + rz * rz
	if rlen_sq < 0.0001 then
		-- Forward and up are parallel, choose arbitrary right
		rx, ry, rz = 1, 0, 0
	else
		local inv_rlen = MathUtils.fast_inv_sqrt(rlen_sq)
		rx, ry, rz = rx * inv_rlen, ry * inv_rlen, rz * inv_rlen
	end

	-- Recalculate up vector (cross product: right x forward)
	local ux = ry * fz - rz * fy
	local uy = rz * fx - rx * fz
	local uz = rx * fy - ry * fx

	-- Convert rotation matrix to quaternion
	local trace = rx + uy + fz
	local q

	if trace > 0 then
		local s = 0.5 / sqrt(trace + 1)
		q = {
			w = 0.25 / s,
			x = (uz - ry) * s,
			y = (fx - rz) * s,
			z = (ry - ux) * s
		}
	elseif rx > uy and rx > fz then
		local s = 2 * sqrt(1 + rx - uy - fz)
		q = {
			w = (uz - ry) / s,
			x = 0.25 * s,
			y = (ux + ry) / s,
			z = (fx + rz) / s
		}
	elseif uy > fz then
		local s = 2 * sqrt(1 + uy - rx - fz)
		q = {
			w = (fx - rz) / s,
			x = (ux + ry) / s,
			y = 0.25 * s,
			z = (ry + uz) / s
		}
	else
		local s = 2 * sqrt(1 + fz - rx - uy)
		q = {
			w = (ry - ux) / s,
			x = (fx + rz) / s,
			y = (ry + uz) / s,
			z = 0.25 * s
		}
	end

	return Quat.normalize(q)
end

-- Scale (multiply) a quaternion by a scalar
function Quat.scale(q, s)
	return {
		x = q.x * s,
		y = q.y * s,
		z = q.z * s,
		w = q.w * s
	}
end

return Quat

-- Frustum Culling Module
-- Implements AABB-based frustum culling for efficient rendering

local Frustum = {}
local MathUtils = require("engine.math_utils")

-- Plane structure: {normal_x, normal_y, normal_z, distance}
-- Represents a plane in 3D space using the equation: ax + by + cz + d = 0

-- Extract frustum planes from camera
-- Returns 6 planes: left, right, top, bottom, near, far
function Frustum.extract_planes(camera, fov, aspect, near, far)
	local planes = {}

	-- Camera forward, right, up vectors
	local yaw = camera.ry
	local pitch = camera.rx

	-- Forward vector
	local fx = sin(yaw) * cos(pitch)
	local fy = -sin(pitch)
	local fz = cos(yaw) * cos(pitch)

	-- Right vector (cross product of forward and world up)
	local rx = cos(yaw)
	local ry = 0
	local rz = -sin(yaw)

	-- Up vector (cross product of right and forward)
	local ux = ry * fz - rz * fy
	local uy = rz * fx - rx * fz
	local uz = rx * fy - ry * fx

	-- Normalize vectors using fast inverse square root
	local f_len_sq = fx*fx + fy*fy + fz*fz
	local inv_f_len = MathUtils.fast_inv_sqrt(f_len_sq)
	fx, fy, fz = fx*inv_f_len, fy*inv_f_len, fz*inv_f_len

	local r_len_sq = rx*rx + ry*ry + rz*rz
	local inv_r_len = MathUtils.fast_inv_sqrt(r_len_sq)
	rx, ry, rz = rx*inv_r_len, ry*inv_r_len, rz*inv_r_len

	local u_len_sq = ux*ux + uy*uy + uz*uz
	local inv_u_len = MathUtils.fast_inv_sqrt(u_len_sq)
	ux, uy, uz = ux*inv_u_len, uy*inv_u_len, uz*inv_u_len

	-- Calculate half-angles
	local fov_rad = fov * 0.5 * 0.0174533
	local tan_fov = sin(fov_rad) / cos(fov_rad)
	local half_v_side = far * tan_fov
	local half_h_side = half_v_side * aspect

	-- Near plane (points toward camera)
	local near_center_x = camera.x + fx * near
	local near_center_y = camera.y + fy * near
	local near_center_z = camera.z + fz * near

	planes.near = {
		nx = -fx,
		ny = -fy,
		nz = -fz,
		d = -(-fx * near_center_x + -fy * near_center_y + -fz * near_center_z)
	}

	-- Far plane (points away from camera)
	local far_center_x = camera.x + fx * far
	local far_center_y = camera.y + fy * far
	local far_center_z = camera.z + fz * far

	planes.far = {
		nx = fx,
		ny = fy,
		nz = fz,
		d = -(fx * far_center_x + fy * far_center_y + fz * far_center_z)
	}

	-- Left plane
	local left_normal_x = fy * uz - fz * uy
	local left_normal_y = fz * ux - fx * uz
	local left_normal_z = fx * uy - fy * ux

	-- Rotate by half horizontal FOV
	local cos_half_h = cos(atan2(half_h_side, far))
	local sin_half_h = sin(atan2(half_h_side, far))

	local lnx = fx * cos_half_h - rx * sin_half_h
	local lny = fy * cos_half_h - ry * sin_half_h
	local lnz = fz * cos_half_h - rz * sin_half_h

	local ln_len_sq = lnx*lnx + lny*lny + lnz*lnz
	local inv_ln_len = MathUtils.fast_inv_sqrt(ln_len_sq)
	lnx, lny, lnz = -lnx*inv_ln_len, -lny*inv_ln_len, -lnz*inv_ln_len

	planes.left = {
		nx = lnx,
		ny = lny,
		nz = lnz,
		d = -(lnx * camera.x + lny * camera.y + lnz * camera.z)
	}

	-- Right plane
	local rnx = -fx * cos_half_h + rx * sin_half_h
	local rny = -fy * cos_half_h + ry * sin_half_h
	local rnz = -fz * cos_half_h + rz * sin_half_h

	local rn_len_sq = rnx*rnx + rny*rny + rnz*rnz
	local inv_rn_len = MathUtils.fast_inv_sqrt(rn_len_sq)
	rnx, rny, rnz = -rnx*inv_rn_len, -rny*inv_rn_len, -rnz*inv_rn_len

	planes.right = {
		nx = rnx,
		ny = rny,
		nz = rnz,
		d = -(rnx * camera.x + rny * camera.y + rnz * camera.z)
	}

	-- Top plane
	local cos_half_v = cos(atan2(half_v_side, far))
	local sin_half_v = sin(atan2(half_v_side, far))

	local tnx = -fx * cos_half_v + ux * sin_half_v
	local tny = -fy * cos_half_v + uy * sin_half_v
	local tnz = -fz * cos_half_v + uz * sin_half_v

	local tn_len_sq = tnx*tnx + tny*tny + tnz*tnz
	local inv_tn_len = MathUtils.fast_inv_sqrt(tn_len_sq)
	tnx, tny, tnz = -tnx*inv_tn_len, -tny*inv_tn_len, -tnz*inv_tn_len

	planes.top = {
		nx = tnx,
		ny = tny,
		nz = tnz,
		d = -(tnx * camera.x + tny * camera.y + tnz * camera.z)
	}

	-- Bottom plane
	local bnx = fx * cos_half_v - ux * sin_half_v
	local bny = fy * cos_half_v - uy * sin_half_v
	local bnz = fz * cos_half_v - uz * sin_half_v

	local bn_len_sq = bnx*bnx + bny*bny + bnz*bnz
	local inv_bn_len = MathUtils.fast_inv_sqrt(bn_len_sq)
	bnx, bny, bnz = -bnx*inv_bn_len, -bny*inv_bn_len, -bnz*inv_bn_len

	planes.bottom = {
		nx = bnx,
		ny = bny,
		nz = bnz,
		d = -(bnx * camera.x + bny * camera.y + bnz * camera.z)
	}

	return planes
end

-- Get signed distance from point to plane
local function signed_distance_to_plane(plane, x, y, z)
	return plane.nx * x + plane.ny * y + plane.nz * z + plane.d
end

-- Test if AABB is on or forward of a plane
-- https://learnopengl.com/Guest-Articles/2021/Scene/Frustum-Culling
-- Based on: https://gdbooks.gitbooks.io/3dcollisions/content/Chapter2/static_aabb_plane.html
local function is_on_or_forward_plane(plane, center_x, center_y, center_z, extents_x, extents_y, extents_z)
	-- Compute the projection interval radius of AABB onto plane normal
	local r = extents_x * abs(plane.nx) +
	          extents_y * abs(plane.ny) +
	          extents_z * abs(plane.nz)

	-- Check if AABB is on or in front of plane
	return -r <= signed_distance_to_plane(plane, center_x, center_y, center_z)
end

-- Simple helper to check if value is within range
local function within(min_val, val, max_val)
	return val >= min_val and val <= max_val
end

-- Test if AABB is inside frustum using clip space test
-- Much simpler than plane-based approach - just transform 8 corners and check bounds
-- Returns true if AABB is visible (at least one corner inside clip space)
function Frustum.test_aabb_simple(camera, fov, aspect, near_plane, far_plane, min_x, min_y, min_z, max_x, max_y, max_z)
	-- Define 8 corners of AABB
	local corners = {
		{min_x, min_y, min_z},  -- xyz
		{max_x, min_y, min_z},  -- Xyz
		{min_x, max_y, min_z},  -- xYz
		{max_x, max_y, min_z},  -- XYz
		{min_x, min_y, max_z},  -- xyZ
		{max_x, min_y, max_z},  -- XyZ
		{min_x, max_y, max_z},  -- xYZ
		{max_x, max_y, max_z},  -- XYZ
	}

	-- Transform to view space and check clip space bounds
	local fov_rad = fov * 0.0174533  -- degrees to radians
	local tan_half_fov = sin(fov_rad * 0.5) / cos(fov_rad * 0.5)

	for _, corner in ipairs(corners) do
		local wx, wy, wz = corner[1], corner[2], corner[3]

		-- Transform to camera space
		local cx = wx - camera.x
		local cy = wy - camera.y
		local cz = wz - camera.z

		-- Rotate by camera yaw
		local cos_yaw = cos(camera.ry)
		local sin_yaw = sin(camera.ry)
		local vx = cx * cos_yaw - cz * sin_yaw
		local vz = cx * sin_yaw + cz * cos_yaw

		-- Rotate by camera pitch
		local cos_pitch = cos(camera.rx)
		local sin_pitch = sin(camera.rx)
		local vy = cy * cos_pitch - vz * sin_pitch
		local ez = cy * sin_pitch + vz * cos_pitch

		-- Check if corner is in clip space (w is the depth)
		local w = ez
		if w > 0 then  -- In front of camera
			-- Project to NDC
			local x = vx / (w * tan_half_fov * aspect)
			local y = vy / (w * tan_half_fov)

			-- Check if inside clip space bounds with margin to prevent popping (relaxed from [-1,1] to [-1.2,1.2])
			if within(-1.2, x, 1.2) and within(-1.2, y, 1.2) and within(near_plane, w, far_plane) then
				return true  -- At least one corner is visible
			end
		end
	end

	return false  -- All corners outside frustum
end

return Frustum

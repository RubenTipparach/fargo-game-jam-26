-- Frustum Culling Module
-- Implements AABB-based frustum culling for efficient rendering

local Frustum = {}

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

	-- Normalize vectors
	local f_len = sqrt(fx*fx + fy*fy + fz*fz)
	fx, fy, fz = fx/f_len, fy/f_len, fz/f_len

	local r_len = sqrt(rx*rx + ry*ry + rz*rz)
	rx, ry, rz = rx/r_len, ry/r_len, rz/r_len

	local u_len = sqrt(ux*ux + uy*uy + uz*uz)
	ux, uy, uz = ux/u_len, uy/u_len, uz/u_len

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

	local ln_len = sqrt(lnx*lnx + lny*lny + lnz*lnz)
	lnx, lny, lnz = -lnx/ln_len, -lny/ln_len, -lnz/ln_len

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

	local rn_len = sqrt(rnx*rnx + rny*rny + rnz*rnz)
	rnx, rny, rnz = -rnx/rn_len, -rny/rn_len, -rnz/rn_len

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

	local tn_len = sqrt(tnx*tnx + tny*tny + tnz*tnz)
	tnx, tny, tnz = -tnx/tn_len, -tny/tn_len, -tnz/tn_len

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

	local bn_len = sqrt(bnx*bnx + bny*bny + bnz*bnz)
	bnx, bny, bnz = -bnx/bn_len, -bny/bn_len, -bnz/bn_len

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

		-- Add camera distance offset (matches renderer transformation)
		ez = ez + camera.distance

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

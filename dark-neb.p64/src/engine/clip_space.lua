-- Clip Space Culling and Clipping Module
-- Implements proper frustum culling and near plane clipping in clip space
-- to prevent triangle distortion at extreme angles or when partially offscreen

local ClipSpace = {}

-- Tests if a point is behind the near plane
-- @param p: point in view space {x, y, z, w}
-- @return true if behind near plane (z < 0.01)
local function is_behind_near(p)
	return p.z < 0.01
end

-- Tests if all 3 vertices of a triangle are behind the near plane
-- Returns true if triangle should be culled entirely
-- @param p1, p2, p3: vertices in view space {x, y, z, w}
-- @return true if triangle is completely behind near plane
local function is_triangle_behind_near(p1, p2, p3)
	-- Near plane test only (z < 0.01 to match renderer's near value)
	if p1.z < 0.01 and p2.z < 0.01 and p3.z < 0.01 then
		return true
	end
	return false
end

-- Linearly interpolate between two vertices at the near plane (z = 0.01)
-- @param p1: vertex inside {x, y, z, w} in view space
-- @param p2: vertex outside {x, y, z, w} in view space
-- @param uv1, uv2: UV coordinates
-- @return clipped vertex and UV
local function clip_at_near_plane(p1, p2, uv1, uv2)
	local near = 0.01  -- Match renderer's near plane
	-- Find t where z = near: p1.z + t * (p2.z - p1.z) = near
	local t = (near - p1.z) / (p2.z - p1.z)

	-- Lerp all components
	local clipped = {
		x = p1.x + t * (p2.x - p1.x),
		y = p1.y + t * (p2.y - p1.y),
		z = near, -- Exactly on the near plane
		w = p1.w + t * (p2.w - p1.w)
	}

	local clipped_uv = nil
	if uv1 and uv2 then
		clipped_uv = {
			x = uv1.x + t * (uv2.x - uv1.x),
			y = uv1.y + t * (uv2.y - uv1.y)
		}
	end

	return clipped, clipped_uv
end

-- Clips a triangle against the near plane, generating 1 or 2 new triangles
-- Returns an array of clipped triangles (each with 3 vertices + UVs)
-- @param p1, p2, p3: vertices in clip space {x, y, z, w}
-- @param uv1, uv2, uv3: UV coordinates {x, y}
-- @return array of clipped triangles: {{p1, p2, p3, uv1, uv2, uv3}, ...}
function ClipSpace.clip_triangle_near_plane(p1, p2, p3, uv1, uv2, uv3)
	local n1, n2, n3 = is_behind_near(p1), is_behind_near(p2), is_behind_near(p3)

	-- All vertices in front - no clipping needed
	if not (n1 or n2 or n3) then
		return {{p1, p2, p3, uv1, uv2, uv3}}
	end

	-- All vertices behind - completely culled
	if n1 and n2 and n3 then
		return {}
	end

	-- Organize vertices into inside and outside groups
	local inside = {}
	local outside = {}

	-- Track original indices to maintain winding order
	if n1 then
		add(outside, {p1, uv1, 1})
	else
		add(inside, {p1, uv1, 1})
	end

	if n2 then
		add(outside, {p2, uv2, 2})
	else
		add(inside, {p2, uv2, 2})
	end

	if n3 then
		add(outside, {p3, uv3, 3})
	else
		add(inside, {p3, uv3, 3})
	end

	local clipped_tris = {}

	-- Case 1: One vertex outside, two inside -> generates one smaller triangle
	if #outside == 1 then
		local v_out = outside[1]
		local v_in1 = inside[1]
		local v_in2 = inside[2]

		-- Clip the two edges that cross the near plane
		local p_clip1, uv_clip1 = clip_at_near_plane(v_in1[1], v_out[1], v_in1[2], v_out[2])
		local p_clip2, uv_clip2 = clip_at_near_plane(v_in2[1], v_out[1], v_in2[2], v_out[2])

		-- Generate new triangle maintaining winding order
		add(clipped_tris, {v_in1[1], v_in2[1], p_clip1, v_in1[2], v_in2[2], uv_clip1})
		add(clipped_tris, {v_in2[1], p_clip2, p_clip1, v_in2[2], uv_clip2, uv_clip1})

	-- Case 2: Two vertices outside, one inside -> generates one smaller triangle
	elseif #outside == 2 then
		local v_in = inside[1]
		local v_out1 = outside[1]
		local v_out2 = outside[2]

		-- Fix winding order: if out1 comes after out2, swap them
		if v_out1[3] == 1 and v_out2[3] == 3 then
			v_out1, v_out2 = v_out2, v_out1
		end

		-- Clip the two edges that cross the near plane
		local p_clip1, uv_clip1 = clip_at_near_plane(v_in[1], v_out1[1], v_in[2], v_out1[2])
		local p_clip2, uv_clip2 = clip_at_near_plane(v_in[1], v_out2[1], v_in[2], v_out2[2])

		-- Generate new triangle
		add(clipped_tris, {v_in[1], p_clip1, p_clip2, v_in[2], uv_clip1, uv_clip2})
	end

	return clipped_tris
end

-- Culls and clips a triangle against the near plane only
-- Returns array of triangles that survive culling/clipping
-- @param p1, p2, p3: vertices in view space {x, y, z, w}
-- @param uv1, uv2, uv3: UV coordinates {x, y}
-- @param skip_near_cull: if true, skip near plane culling (for debug)
-- @return array of triangles: {{p1, p2, p3, uv1, uv2, uv3}, ...}
function ClipSpace.cull_and_clip_triangle(p1, p2, p3, uv1, uv2, uv3, skip_near_cull)
	-- Near plane culling: discard if all vertices behind
	if not skip_near_cull and is_triangle_behind_near(p1, p2, p3) then
		return {}
	end

	-- Near plane clipping
	return ClipSpace.clip_triangle_near_plane(p1, p2, p3, uv1, uv2, uv3)
end

-- Applies perspective division to a vertex
-- @param p: vertex in clip space {x, y, z, w}
-- @return vertex in NDC space {x, y, z, w} where w = 1/w
function ClipSpace.perspective_divide(p)
	if p.w == 0 then
		-- Avoid division by zero
		return {x = 0, y = 0, z = 0, w = 0}
	end

	local inv_w = 1 / p.w
	return {
		x = p.x * inv_w,
		y = p.y * inv_w,
		z = p.z * inv_w,
		w = inv_w  -- Store reciprocal for texture mapping
	}
end

-- Clips a line against the near plane
-- Returns the clipped line or nil if completely behind
-- @param p1, p2: line endpoints in view space {x, y, z, w}
-- @return clipped p1, p2 or nil if completely culled
function ClipSpace.clip_line_near_plane(p1, p2)
	local near = 0.01
	local n1, n2 = is_behind_near(p1), is_behind_near(p2)

	-- Both in front - no clipping
	if not (n1 or n2) then
		return p1, p2
	end

	-- Both behind - completely culled
	if n1 and n2 then
		return nil, nil
	end

	-- One behind, one in front - clip it
	if n1 then
		-- p1 is behind, p2 is in front
		local t = (near - p1.z) / (p2.z - p1.z)
		p1 = {
			x = p1.x + t * (p2.x - p1.x),
			y = p1.y + t * (p2.y - p1.y),
			z = near,
			w = p1.w + t * (p2.w - p1.w)
		}
	else
		-- p2 is behind, p1 is in front
		local t = (near - p2.z) / (p1.z - p2.z)
		p2 = {
			x = p2.x + t * (p1.x - p2.x),
			y = p2.y + t * (p1.y - p2.y),
			z = near,
			w = p2.w + t * (p1.w - p2.w)
		}
	end

	return p1, p2
end

-- Tests if a line is completely behind the near plane
-- @param p1, p2: line endpoints in view space {x, y, z, w}
-- @return true if line should be culled
function ClipSpace.is_line_behind_near(p1, p2)
	return p1.z < 0.01 and p2.z < 0.01
end

return ClipSpace

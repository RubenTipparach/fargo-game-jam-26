--[[pod_format="raw",created="2024-11-07 20:00:00",modified="2024-11-07 20:00:00",revision=0]]
-- Geometry Module
-- Creates procedural 3D meshes (spheres, quads, billboards)
-- Single Responsibility: Only handles geometry creation

local Geometry = {}

-- Create a UV-mapped sphere (from ld58.p64)
-- Uses proper UV wrapping for 64x32 texture sprites
-- @param radius: Sphere radius
-- @param segments: Number of horizontal segments (longitude)
-- @param stacks: Number of vertical segments (latitude)
-- @param sprite_id: Texture sprite ID
-- @param sprite_w, sprite_h: Sprite dimensions
-- @return: Mesh table {verts, faces, name}
function Geometry.create_sphere(radius, segments, stacks, sprite_id, sprite_w, sprite_h)
	local verts = {}
	local faces = {}

	-- Use ld58 parameters if not provided
	local rings = stacks or 6
	segments = segments or 8
	sprite_id = sprite_id or 1
	sprite_w = sprite_w or 64
	sprite_h = sprite_h or 32

	-- Generate vertices in rings from top to bottom
	-- Top vertex (north pole)
	add(verts, vec(0, radius, 0))

	-- Middle rings (latitude)
	for ring = 1, rings - 1 do
		local v = ring / rings
		local angle_v = v * 0.5
		local y = cos(angle_v) * radius
		local ring_radius = sin(angle_v) * radius

		-- Vertices around the ring (longitude)
		for seg = 0, segments - 1 do
			local angle_h = seg / segments
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
	local uv_offset = -uv_scale_v

	-- Generate faces - Top cap
	for seg = 0, segments - 1 do
		local next_seg = (seg + 1) % segments
		local v1 = 1
		local v2 = 2 + seg
		local v3 = 2 + next_seg

		local u1 = (seg + 0.5) / segments * uv_scale_u
		local u2 = seg / segments * uv_scale_u
		local u3 = (seg + 1) / segments * uv_scale_u
		local v_top = uv_scale_v - (0 + uv_offset)
		local v_ring1 = uv_scale_v - ((1 / rings) * uv_scale_v + uv_offset)

		add(faces, {v1, v3, v2, sprite_id,
			vec(u1, v_top), vec(u3, v_ring1), vec(u2, v_ring1)})
	end

	-- Middle rings
	for ring = 0, rings - 3 do
		local ring_start = 2 + ring * segments
		local next_ring_start = 2 + (ring + 1) * segments

		for seg = 0, segments - 1 do
			local next_seg = (seg + 1) % segments

			local v1 = ring_start + seg
			local v2 = ring_start + next_seg
			local v3 = next_ring_start + next_seg
			local v4 = next_ring_start + seg

			local u1 = seg / segments * uv_scale_u
			local u2 = (seg + 1) / segments * uv_scale_u
			local v1_uv = uv_scale_v - ((ring + 1) / rings * uv_scale_v + uv_offset)
			local v2_uv = uv_scale_v - ((ring + 2) / rings * uv_scale_v + uv_offset)

			add(faces, {v1, v2, v3, sprite_id,
				vec(u1, v1_uv), vec(u2, v1_uv), vec(u2, v2_uv)})
			add(faces, {v1, v3, v4, sprite_id,
				vec(u1, v1_uv), vec(u2, v2_uv), vec(u1, v2_uv)})
		end
	end

	-- Bottom cap
	local last_ring_start = 2 + (rings - 2) * segments
	local bottom_vertex = #verts
	for seg = 0, segments - 1 do
		local next_seg = (seg + 1) % segments
		local v1 = last_ring_start + seg
		local v2 = last_ring_start + next_seg
		local v3 = bottom_vertex

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
-- @param half_size: Half-width/height of the quad
-- @param camera: Camera object with rx, ry
-- @return: Table of 4 vertex vectors
function Geometry.create_billboard_quad(half_size, camera)
	local forward_x = sin(camera.ry) * cos(camera.rx)
	local forward_y = sin(camera.rx)
	local forward_z = cos(camera.ry) * cos(camera.rx)

	local right_x = cos(camera.ry)
	local right_y = 0
	local right_z = -sin(camera.ry)

	local up_x = -(forward_y * right_z - forward_z * right_y)
	local up_y = -(forward_z * right_x - forward_x * right_z)
	local up_z = -(forward_x * right_y - forward_y * right_x)

	local verts = {
		vec(-right_x * half_size + up_x * half_size, -right_y * half_size + up_y * half_size, -right_z * half_size + up_z * half_size),
		vec(right_x * half_size + up_x * half_size, right_y * half_size + up_y * half_size, right_z * half_size + up_z * half_size),
		vec(right_x * half_size - up_x * half_size, right_y * half_size - up_y * half_size, right_z * half_size - up_z * half_size),
		vec(-right_x * half_size - up_x * half_size, -right_y * half_size - up_y * half_size, -right_z * half_size - up_z * half_size),
	}

	return verts
end

-- Create a billboard quad mesh (64x64 unlit, camera-facing)
-- @param width, height: Quad dimensions
-- @param sprite_id: Texture sprite ID
-- @param sprite_w, sprite_h: Sprite dimensions
-- @return: Mesh table with billboard flag
function Geometry.create_quad(width, height, sprite_id, sprite_w, sprite_h)
	sprite_id = sprite_id or 1
	sprite_w = sprite_w or 64
	sprite_h = sprite_h or 64

	local hw = width / 2
	local hh = height / 2

	local verts = {
		vec(-hw, -hh, 0),
		vec(hw, -hh, 0),
		vec(hw, hh, 0),
		vec(-hw, hh, 0),
	}

	local faces = {
		{1, 2, 3, sprite_id,
			vec(0, sprite_h), vec(sprite_w, sprite_h), vec(sprite_w, 0)},
		{1, 3, 4, sprite_id,
			vec(0, sprite_h), vec(sprite_w, 0), vec(0, 0)},
	}

	return {verts = verts, faces = faces, name = "quad", unlit = true, is_billboard = true, half_size = hw}
end

return Geometry

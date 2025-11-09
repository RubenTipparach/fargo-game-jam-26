-- 3D Rendering Module
-- Handles projection, mesh rendering, and textured triangle drawing

local Renderer = {}

-- Profiler reference (set externally if profiling is enabled)
Renderer.profiler = nil

-- ============================================
-- RENDER CONFIGURATION
-- ============================================

-- Simple distance culling for terrain tiles
-- Accounts for tile height - taller tiles can be seen from farther away
-- @param center_x, center_z: tile center position in world space
-- @param tile_height: height of the tile (max_y - min_y)
-- @param camera: camera object with x,z position
-- @param render_distance: maximum render distance
-- @return true if tile should be culled (too far away)
function Renderer.tile_distance_cull(center_x, center_z, tile_height, camera, render_distance)
	local dx = center_x - camera.x
	local dz = center_z - camera.z
	local dist_sq = dx*dx + dz*dz

	-- Increase render distance for tall tiles (they're visible from farther away)
	-- Add 50% of tile height to render distance
	local adjusted_distance = render_distance + (tile_height * 0.5)

	-- Distance culling only
	return dist_sq > adjusted_distance * adjusted_distance
end


-- Scanline buffer for textured triangle rendering
local scanlines = userdata("f64",11,270)

-- Pre-allocate userdata pool to avoid allocations per triangle
local vert_data_pool = userdata("f64", 6, 3)


---Draws a 3D textured triangle to the screen. Note that the vertices need W components,
---and that they need to be the reciprocal of the W which is produced by the projection matrix.
---This step is typically done in the perspective division step.
---@param props table The properties passed to the shader. Expects a `tex` field with a texture index.
---@param vert_data userdata A 6x3 matrix where each row is the xyzwuv of a vertex.
---@param screen_height number The height of the screen, used for scanline truncation.
function Renderer.textri(props,vert_data,screen_height)
    local spr = props.tex

    -- To make it so that rasterizing top to bottom is always correct,
    -- and so that we know at which point to switch the minor side's slope,
    -- we need the vertices to be sorted by y.
    vert_data:sort(1)

    -- These values are used extensively in the setup, so we'll store them in
    -- local variables.
    local x1,y1,w1, y2,w2, x3,y3,w3 =
        vert_data[0],vert_data[1],vert_data[3],
        vert_data[7],vert_data[9],
        vert_data[12],vert_data[13],vert_data[15]

    -- To get perspective correct interpolation, we need to multiply
    -- the UVs by the w component of their vertices.
    local uv1,uv3 =
        vec(vert_data[4],vert_data[5])*w1,
        vec(vert_data[16],vert_data[17])*w3

    local t = (y2-y1)/(y3-y1)
    local uvd = (uv3-uv1)*t+uv1
    local v1,v2 =
        vec(spr,x1,y1,x1,y1,uv1.x,uv1.y,uv1.x,uv1.y,w1,w1),
        vec(
            spr,
            vert_data[6],y2,
            (x3-x1)*t+x1, y2,
            vert_data[10]*w2,vert_data[11]*w2, -- uv2
            uvd.x,uvd.y,
            w2,(w3-w1)*t+w1
        )

    local start_y = y1 < -1 and -1 or y1\1
    local mid_y = y2 < -1 and -1 or y2 > screen_height-1 and screen_height-1 or y2\1
    local stop_y = (y3 <= screen_height-1 and y3\1 or screen_height-1)

    -- Top half
    local dy = mid_y-start_y
    if dy > 0 then
        local slope = (v2-v1):div((y2-y1))

        scanlines:copy(slope*(start_y+1-y1)+v1,true,0,0,11)
            :copy(slope,true,0,11,11,0,11,dy-1)

        tline3d(scanlines:add(scanlines,true,0,11,11,11,11,dy-1),0,dy)
    end

    -- Bottom half
    dy = stop_y-mid_y
    if dy > 0 then
        -- This is, otherwise, the only place where v3 would be used,
        -- so we just inline it.
        local slope = (vec(spr,x3,y3,x3,y3,uv3.x,uv3.y,uv3.x,uv3.y,w3,w3)-v2)/(y3-y2)

        scanlines:copy(slope*(mid_y+1-y2)+v2,true,0,0,11)
            :copy(slope,true,0,11,11,0,11,dy-1)

        tline3d(scanlines:add(scanlines,true,0,11,11,11,11,dy-1),0,dy)
    end
end

-- Project and render a mesh with proper culling and sorting
-- @param verts: array of vertices
-- @param faces: array of faces
-- @param camera: camera object with x,y,z,rx,ry
-- @param offset_x, offset_y, offset_z: world position offset
-- @param sprite_override: override sprite ID for all faces (optional)
-- @param is_ground: mark as ground for special depth sorting (optional)
-- @param rot_pitch, rot_yaw, rot_roll: object rotation (optional)
-- @param render_distance: far clipping plane distance
-- @param ground_always_behind: apply depth bias to ground (optional, default true)
-- @param fog_start_distance: distance at which fog starts (optional)
-- @param is_skybox: skip pitch-based culling for skybox (optional)
-- @param fog_enabled: whether fog is enabled (optional, default true)
-- @return projected_faces: array of faces ready to draw (unsorted)
function Renderer.render_mesh(verts, faces, camera, offset_x, offset_y, offset_z, sprite_override, is_ground, rot_pitch, rot_yaw, rot_roll, render_distance, ground_always_behind, fog_start_distance, is_skybox, fog_enabled)
	local prof = Renderer.profiler

	if prof then prof("    setup") end
	-- Projection parameters (hardcoded constants for speed)
	local near = 0.01
	local far = render_distance or 20
	local tan_half_fov = 0.7002075  -- precalculated: tan(70/2 degrees)
	local cam_dist = camera.distance or 5

	-- Early culling: check if object is within render distance (horizontal only)
	local obj_x = offset_x or 0
	local obj_z = offset_z or 0
	local dx = obj_x - camera.x
	local dz = obj_z - camera.z
	local dist_sq = dx*dx + dz*dz
	local obj_dist = sqrt(dist_sq)  -- Store distance for fog calculation

	-- Cull objects beyond render range (unless it's ground)
	if not is_ground and dist_sq > far * far then
		if prof then prof("    setup") end
		return {}
	end

	-- Allocate arrays for vertex processing
	local projected = {}
	local depths = {}

	-- Precompute rotation values
	local cos_ry, sin_ry = cos(camera.ry), sin(camera.ry)
	local cos_rx, sin_rx = cos(camera.rx), sin(camera.rx)

	-- Precompute object rotation values (if provided)
	local cos_pitch, sin_pitch, cos_yaw, sin_yaw, cos_roll, sin_roll
	if rot_pitch or rot_yaw or rot_roll then
		cos_pitch, sin_pitch = cos(rot_pitch or 0), sin(rot_pitch or 0)
		cos_yaw, sin_yaw = cos(rot_yaw or 0), sin(rot_yaw or 0)
		cos_roll, sin_roll = cos(rot_roll or 0), sin(rot_roll or 0)
	end
	if prof then prof("    setup") end

	if prof then prof("    project") end

	-- Precompute projection scale
	local proj_scale = 270 / tan_half_fov
	local cam_x, cam_y, cam_z = camera.x, camera.y, camera.z
	local offset_x_val = offset_x or 0
	local offset_y_val = offset_y or 0
	local offset_z_val = offset_z or 0

	for i = 1, #verts do
		local v = verts[i]
		local x, y, z = v.x, v.y, v.z

		-- Apply object rotation (pitch, yaw, roll) if provided
		if rot_pitch or rot_yaw or rot_roll then
			-- Yaw (Y axis)
			local x_yaw = x * cos_yaw - z * sin_yaw
			local z_yaw = x * sin_yaw + z * cos_yaw

			-- Pitch (X axis)
			local y_pitch = y * cos_pitch - z_yaw * sin_pitch
			local z_pitch = y * sin_pitch + z_yaw * cos_pitch

			-- Roll (Z axis)
			local x_roll = x_yaw * cos_roll - y_pitch * sin_roll
			local y_roll = x_yaw * sin_roll + y_pitch * cos_roll

			x, y, z = x_roll, y_roll, z_pitch
		end

		-- Apply offset and camera transform in one step
		x = x + offset_x_val - cam_x
		y = y + offset_y_val - cam_y
		z = z + offset_z_val - cam_z

		-- Rotate around Y axis (using cached values)
		local x2 = x * cos_ry - z * sin_ry
		local z2 = x * sin_ry + z * cos_ry

		-- Rotate around X axis (using cached values)
		local y2 = y * cos_rx - z2 * sin_rx
		local z3 = y * sin_rx + z2 * cos_rx + cam_dist

		-- Perspective projection (allow vertices closer to camera)
		if z3 > near then
			local inv_z = 1 / z3
			local px = -x2 * inv_z * proj_scale + 240 
			local py = -y2 * inv_z * proj_scale + 135


			-- Store projected vertex and its depth
			projected[i] = {x=px, y=py, z=0, w=inv_z}
			depths[i] = z3
		else
			projected[i] = nil
			depths[i] = nil
		end
	end
	if prof then prof("    project") end

	-- Build list of projected faces with depth (not sorted yet)
	if prof then prof("    backface") end
	local projected_faces = {}
	local sprite_id = sprite_override  -- Cache sprite override
	local skip_culling = is_ground or is_skybox
	local depth_bias = is_ground and (ground_always_behind == nil or ground_always_behind) and 1000 or 0

	for i = 1, #faces do
		local face = faces[i]
		local v1_idx, v2_idx, v3_idx = face[1], face[2], face[3]
		local p1, p2, p3 = projected[v1_idx], projected[v2_idx], projected[v3_idx]

		if p1 and p2 and p3 then
			local d1, d2, d3 = depths[v1_idx], depths[v2_idx], depths[v3_idx]

			-- Fast screen-space backface culling (2D cross product)
			local cross = (p2.x - p1.x) * (p3.y - p1.y) - (p2.y - p1.y) * (p3.x - p1.x)

			-- Only include if facing towards camera (clockwise winding in screen space)
			if cross > 0 or skip_culling then
				-- Calculate average depth for sorting
				local avg_depth = (d1 + d2 + d3) * 0.333333 + depth_bias

				-- Calculate fog opacity (simplified - no fog for simple cubes)
				local fog_opacity = 0

				-- Create face entry (reuse sprite_override, no table copy needed)
				add(projected_faces, {
					face = {face[1], face[2], face[3], sprite_id or face[4], face[5], face[6], face[7]},
					depth = avg_depth,
					p1 = p1,
					p2 = p2,
					p3 = p3,
					fog = fog_opacity
				})
			end
		end
	end
	if prof then prof("    backface") end

	return projected_faces
end


-- Draw a list of sorted faces using the pooled vertex data
-- @param all_faces: sorted array of faces
-- @param ship_flash_red: whether to flash ship sprite red (optional)
function Renderer.draw_faces(all_faces, ship_flash_red)
	-- Draw all faces - optimized for batch rendering
	local vpool = vert_data_pool
	local n = #all_faces

	-- Pre-allocate sprite props table (reuse across all triangles)
	local props = {tex = 0}

	for i = 1, n do
		local f = all_faces[i]
		local face = f.face
		local sprite_id = face[4]
		local p1, p2, p3 = f.p1, f.p2, f.p3

		-- Get UVs - most faces have UVs, optimize for common case
		local uv1, uv2, uv3 = face[5], face[6], face[7]

		if uv1 then
			-- Fast path: UVs exist (common case)
			vpool[0], vpool[1], vpool[3], vpool[4], vpool[5] = p1.x, p1.y, p1.w, uv1.x, uv1.y
			vpool[6], vpool[7], vpool[9], vpool[10], vpool[11] = p2.x, p2.y, p2.w, uv2.x, uv2.y
			vpool[12], vpool[13], vpool[15], vpool[16], vpool[17] = p3.x, p3.y, p3.w, uv3.x, uv3.y
		else
			-- Slow path: default UVs (rare)
			vpool[0], vpool[1], vpool[3], vpool[4], vpool[5] = p1.x, p1.y, p1.w, 0, 0
			vpool[6], vpool[7], vpool[9], vpool[10], vpool[11] = p2.x, p2.y, p2.w, 16, 0
			vpool[12], vpool[13], vpool[15], vpool[16], vpool[17] = p3.x, p3.y, p3.w, 16, 16
		end

		-- Z is always 0 for screen-space vertices
		vpool[2], vpool[8], vpool[14] = 0, 0, 0

		-- Update sprite in reused props table
		props.tex = (sprite_id == 0 and ship_flash_red) and 8 or sprite_id

		-- Special sprite effects (flames/smoke only)
		if sprite_id == 3 then
			fillp(0b0101101001011010)
			Renderer.textri(props, vpool, 270)
			fillp()
		elseif sprite_id == 5 then
			local opacity = f.opacity or 1.0
			fillp(opacity > 0.75 and 0b0111111101111111 or
			      opacity > 0.5 and 0b0101101001011010 or
			      opacity > 0.25 and 0b1000010010000100 or 0b1000000010000000)
			Renderer.textri(props, vpool, 270)
			fillp()
		else
			-- Fast path: solid sprites (most common for cubes)
			Renderer.textri(props, vpool, 270)
		end
	end
end

-- Optimized insertion sort for small arrays (faster than quicksort for n < 20)
local function insertion_sort(faces, low, high)
	for i = low + 1, high do
		local key = faces[i]
		local key_depth = key.depth
		local j = i - 1

		-- Shift elements that are less than key (descending order)
		while j >= low and faces[j].depth < key_depth do
			faces[j + 1] = faces[j]
			j = j - 1
		end
		faces[j + 1] = key
	end
end

-- Hybrid quicksort with insertion sort for small partitions
local function quicksort(faces, low, high)
	while low < high do
		-- Use insertion sort for small partitions (faster)
		if high - low < 20 then
			insertion_sort(faces, low, high)
			return
		end

		-- Partition
		local pivot = faces[high].depth
		local i = low - 1

		for j = low, high - 1 do
			if faces[j].depth >= pivot then
				i = i + 1
				faces[i], faces[j] = faces[j], faces[i]
			end
		end

		i = i + 1
		faces[i], faces[high] = faces[high], faces[i]

		-- Recursively sort smaller partition, iterate on larger (tail recursion optimization)
		if i - low < high - i then
			quicksort(faces, low, i - 1)
			low = i + 1
		else
			quicksort(faces, i + 1, high)
			high = i - 1
		end
	end
end

-- Sort faces using hybrid quicksort/insertion sort
-- @param faces: array of faces to sort by depth
function Renderer.sort_faces(faces)
	local n = #faces
	if n > 1 then
		quicksort(faces, 1, n)
	end
end

return Renderer

-- 3D Lighting Renderer Module
-- Separate renderer for per-vertex lighting with scanline interpolation
-- Based on renderer.lua but adds lighting calculations

local RendererLit = {}

-- Profiler reference (set externally if profiling is enabled)
RendererLit.profiler = nil

-- Load lighting module
local Lighting = require("src.lighting")
local MathUtils = require("src.engine.math_utils")
local Frustum = require("src.engine.frustum")

-- ============================================
-- COLOR TABLE SPRITE CACHING
-- ============================================

-- Base color table loaded from sprite 16
local base_color_table = nil

-- Palette loaded from 0.pal
local palette_loaded = false

-- Cache of brightness-modified SPRITE INDICES
-- Structure: cached_sprites[sprite_id][brightness_level] = cached_sprite_index
local cached_sprites = {}

-- Number of brightness levels to cache (8 levels: 0-7)
-- Linear brightness using color table rows
local BRIGHTNESS_LEVELS = 8



-- Color table configuration for 8-level brightness
-- Uses color table (sprite 16) to remap colors based on brightness
-- Each brightness level uses a different row of the color table
-- Rows 56-63 contain the brightness gradients (dark to bright)
local colorMapper8 = {
	{index = 0, mask = 5},
	{index = 1, mask = 16},
	{index = 2, mask = 8},
	{index = 3, mask = 12},
	{index = 4, mask = 11},
	{index = 5, mask = 15},
	{index = 6, mask = 10},
	{index = 7, mask = 0}    -- Brightest (row 63)
}

-- Starting sprite slot for cached brightness sprites
-- We'll use sprites 128-255 for caching (128 slots to be safe)
local CACHE_SPRITE_START = 128

-- Next available cache slot
local next_cache_slot = CACHE_SPRITE_START

-- Initialize color table from sprite 16 and load palette
function RendererLit.init_color_table()
	-- Load color table sprite
	if not base_color_table then
		base_color_table = get_spr(16)
		printh("Color table loaded from sprite 16")

		-- Debug: Check color table dimensions and some sample values
		if base_color_table then
			-- Try to get dimensions (might not have width/height methods)
			local test_val = base_color_table:get(0, 0)
			printh("Color table test: get(0,0) = " .. (test_val or "nil"))

			-- Test lookups for colors 4 and 17 at row 32
			local c4_row32 = base_color_table:get(4, 32)
			local c17_row32 = base_color_table:get(17, 32)
			printh("Color table: 4@row32 = " .. (c4_row32 or "nil") .. ", 17@row32 = " .. (c17_row32 or "nil"))

			-- Test colors 196 and 209
			local c196_row32 = base_color_table:get(196, 32)
			local c209_row32 = base_color_table:get(209, 32)
			printh("Color table: 196@row32 = " .. (c196_row32 or "nil") .. ", 209@row32 = " .. (c209_row32 or "nil"))
		end
	end

	-- Load and apply palette from 0.pal
	if not palette_loaded then
		local palette_data = fetch("src/0.pal")
		if palette_data then
			printh("Palette loaded from src/0.pal")

			-- Count colors and apply palette
			local color_count = 0
			for i = 0, 63 do
				local color = palette_data[i]
				if color then
					color_count = color_count + 1
					-- Apply using pal() with p=2 to set RGB display palette
					pal(i, color, 2)
				end
			end

			-- Set color 0 as transparent
			palt(0, false)

			palette_loaded = true
			printh("SUCCESS: " .. color_count .. " colors loaded and applied!")
		else
			printh("WARNING: Could not load 0.pal")
		end
	end
end

-- Generate a brightness-modified sprite by applying color table
-- @param sprite_id: the original sprite index
-- @param brightness_level: 0-7 (0=darkest, 7=brightest)
-- @return sprite_index: index of the cached brightness sprite
function RendererLit.get_brightness_sprite(sprite_id, brightness_level)
	-- Ensure color table is loaded
	if not base_color_table then
		RendererLit.init_color_table()
	end

	-- Clamp brightness level to valid range FIRST (before cache check)
	if brightness_level < 0 then brightness_level = 0 end
	if brightness_level >= BRIGHTNESS_LEVELS then brightness_level = BRIGHTNESS_LEVELS - 1 end

	-- Check cache AFTER clamping
	if cached_sprites[sprite_id] and cached_sprites[sprite_id][brightness_level] then
		return cached_sprites[sprite_id][brightness_level]
	end

	-- Get original sprite
	local original_sprite = get_spr(sprite_id)
	if not original_sprite then
		printh("WARNING: Could not load sprite " .. sprite_id)
		return sprite_id  -- Return original sprite_id as fallback
	end

	-- Apply color table transformation using 8-level configuration
	local config = colorMapper8[brightness_level + 1]  -- Lua is 1-indexed
	if not config then
		printh("ERROR: Invalid brightness_level " .. brightness_level)
		return sprite_id  -- Fallback to original sprite
	end
	local color_table_row = config.mask

	-- If mask is 0, don't use color table - return original sprite
	if color_table_row == 0 then
		-- Cache the original sprite_id
		if not cached_sprites[sprite_id] then
			cached_sprites[sprite_id] = {}
		end
		cached_sprites[sprite_id][brightness_level] = sprite_id

		return sprite_id
	end

	-- Get sprite dimensions (supports 16x16, 64x32, etc.)
	local sprite_w = original_sprite:width()
	local sprite_h = original_sprite:height()

	-- Create new sprite userdata with correct dimensions
	local new_sprite = userdata("u8", sprite_w, sprite_h)
	-- Initialize to transparent
	for y = 0, sprite_h - 1 do
		for x = 0, sprite_w - 1 do
			new_sprite:set(x, y, 0)
		end
	end

	-- All 8 levels use a single row from the color table
	for y = 0, sprite_h - 1 do
		for x = 0, sprite_w - 1 do
			local c = original_sprite:get(x, y)
			-- Extract color index from low 6 bits (0x3f mask)
			-- High 2 bits are color table selection metadata
			local color_index = c & 0x3f

			if color_index == 0 then
				-- Keep transparent pixels as 0
				new_sprite:set(x, y, 0)
			else
				-- Look up remapped color from color table (sprite 16)
				-- Color table format: get(x, y) where:
				--   x (horizontal) = original color (0-63)
				--   y (vertical) = brightness level row (0-63)
				if base_color_table then
					local remapped_color = base_color_table:get(color_index, color_table_row)

					-- Use remapped color directly
					if remapped_color and remapped_color > 0 then
						new_sprite:set(x, y, remapped_color)
					else
						-- Fallback: keep original color index
						new_sprite:set(x, y, color_index)
					end
				else
					-- No color table - keep original color
					new_sprite:set(x, y, c)
				end
			end
		end
	end

	-- Allocate a sprite slot for this cached sprite
	local cache_slot = next_cache_slot
	next_cache_slot = next_cache_slot + 1

	-- Check if we're running out of sprite slots
	if cache_slot >= 256 then
		printh("ERROR: Out of sprite cache slots! cache_slot=" .. cache_slot)
		return sprite_id  -- Return original sprite as fallback
	end

	-- Store the sprite in the allocated slot
	set_spr(cache_slot, new_sprite)

	-- Cache the sprite index
	if not cached_sprites[sprite_id] then
		cached_sprites[sprite_id] = {}
	end
	cached_sprites[sprite_id][brightness_level] = cache_slot

	-- Debug: Print sprite 1 data for all brightness levels
	if sprite_id == 1 then
		printh("===== SPRITE 1 BRIGHTNESS " .. brightness_level .. " =====")
		printh("Cache slot: " .. cache_slot .. " | Row: " .. color_table_row)

		-- Print remapped sprite pixel data
		for y = 0, 15 do
			local row = ""
			for x = 0, 15 do
				local c = new_sprite:get(x, y)
				if c < 10 then
					row = row .. " " .. c .. " "
				elseif c < 100 then
					row = row .. c .. " "
				else
					row = row .. c
				end
			end
			printh(row)
		end

		-- After generating all brightness levels, print verification
		local sprite1_variants = 0
		if cached_sprites[1] then
			for _ in pairs(cached_sprites[1]) do
				sprite1_variants = sprite1_variants + 1
			end
		end

		printh("Sprite 1 variants: " .. sprite1_variants .. " / " .. BRIGHTNESS_LEVELS .. " expected")
		printh("=======================================")
	end

	return cache_slot
end

-- Get a cached sprite userdata for debugging (returns the userdata directly)
function RendererLit.get_cached_sprite_for_debug(sprite_id, brightness_level)
	local cache_index = RendererLit.get_brightness_sprite(sprite_id, brightness_level)
	return get_spr(cache_index)
end

-- Print the entire 16x16 sprite data as a visual block
function RendererLit.print_sprite_data(sprite_id, brightness_level)
	-- Get the cached sprite
	local cache_index = RendererLit.get_brightness_sprite(sprite_id, brightness_level)
	local sprite_data = get_spr(cache_index)

	if not sprite_data then
		printh("ERROR: Could not get sprite data for sprite " .. sprite_id .. " brightness " .. brightness_level)
		return
	end

	printh("===== SPRITE DATA =====")
	printh("Sprite ID: " .. sprite_id)
	printh("Brightness Level: " .. brightness_level)
	printh("Cache Index: " .. cache_index)
	printh("16x16 Pixel Data:")
	printh("----------------------")

	-- Print each row
	for y = 0, 15 do
		local row = ""
		for x = 0, 15 do
			local c = sprite_data:get(x, y)
			-- Format: 2-digit number with leading space if needed
			if c < 10 then
				row = row .. " " .. c .. " "
			else
				row = row .. c .. " "
			end
		end
		printh(row)
	end
	printh("======================")
end

-- Get sprite cache statistics (lightweight for HUD display)
function RendererLit.get_cache_stats()
	local total_cached = next_cache_slot - CACHE_SPRITE_START
	local unique_sprites = 0
	local total_variants = 0

	for sprite_id, brightness_table in pairs(cached_sprites) do
		unique_sprites = unique_sprites + 1
		for brightness_level, _ in pairs(brightness_table) do
			total_variants = total_variants + 1
		end
	end

	return {
		unique_sprites = unique_sprites,
		total_variants = total_variants,
		slots_used = total_cached,
		slots_available = 256 - CACHE_SPRITE_START,
		next_slot = next_cache_slot,
		memory_kb = (total_cached * 256) / 1024
	}
end

-- Print sprite cache statistics to console
function RendererLit.print_cache_stats()
	local stats = RendererLit.get_cache_stats()

	printh("=== SPRITE CACHE STATS ===")
	printh("Unique sprites cached: " .. stats.unique_sprites)
	printh("Total brightness variants: " .. stats.total_variants)
	printh("Cache slots used: " .. stats.slots_used .. " / " .. stats.slots_available)
	printh("Next available slot: " .. stats.next_slot)
	printh("Memory per sprite: ~256 bytes (16x16)")
	printh("Total cache memory: ~" .. (stats.slots_used * 256) .. " bytes")
	printh("=========================")

	return stats
end

-- Clear sprite cache (useful when light changes significantly)
function RendererLit.clear_cache()
	cached_sprites = {}
	next_cache_slot = CACHE_SPRITE_START
	printh("Sprite cache cleared")
end

-- Debug function: Force print sprite data for any sprite/brightness combo
function RendererLit.debug_print_sprite(sprite_id, brightness_level)
	-- Force regenerate by temporarily clearing cache
	local old_cache = cached_sprites[sprite_id]
	if old_cache then
		cached_sprites[sprite_id] = nil
	end

	-- This will regenerate and print
	local cache_idx = RendererLit.get_brightness_sprite(sprite_id, brightness_level)

	-- Restore cache
	if old_cache then
		cached_sprites[sprite_id] = old_cache
	end

	printh("Debug: Sprite " .. sprite_id .. " brightness " .. brightness_level .. " cached at index " .. cache_idx)
end

-- Generate 8-level brightness sprite for comparison (old math)
-- @param sprite_id: the original sprite index
-- @param brightness_level: 0-7 (0=darkest, 7=brightest)
-- @return sprite userdata directly (not cached)
function RendererLit.get_brightness_sprite_8level(sprite_id, brightness_level)
	-- Ensure color table is loaded
	if not base_color_table then
		RendererLit.init_color_table()
	end

	-- Get original sprite
	local original_sprite = get_spr(sprite_id)
	if not original_sprite then
		return get_spr(sprite_id)
	end

	-- Create new sprite userdata (16x16)
	local new_sprite = userdata("u8", 16, 16)
	for y = 0, 15 do
		for x = 0, 15 do
			new_sprite:set(x, y, 0)
		end
	end

	-- Apply color table transformation using 8-level configuration
	local config = colorMapper8[brightness_level + 1]  -- Lua is 1-indexed

	-- All 8 levels use a single row from the color table
	for y = 0, 15 do
		for x = 0, 15 do
			local c = original_sprite:get(x, y)
			if c == 0 or (c >= 56 and c <= 63) then
				new_sprite:set(x, y, c)
			else
				new_sprite:set(x, y, base_color_table:get(c, config.mask))
			end
		end
	end

	return new_sprite
end

-- ============================================
-- TEXTURE RENDERING
-- ============================================

-- Scanline buffer for textured triangle rendering
local scanlines = userdata("f64",11,270)

---Draws a 3D textured triangle to the screen. Note that the vertices need W components,
---and that they need to be the reciprocal of the W which is produced by the projection matrix.
---This step is typically done in the perspective division step.
---@param props table The properties passed to the shader. Expects a `tex` field with a texture index.
---@param vert_data userdata A 6x3 matrix where each row is the xyzwuv of a vertex.
---@param screen_height number|function The height of the screen (270) or a scanline callback function.
function RendererLit.textri(props,vert_data,screen_height)
	-- If screen_height is a function, it's a scanline callback
	local scanline_callback = type(screen_height) == "function" and screen_height or nil
	local actual_height = scanline_callback and 270 or screen_height

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
	local mid_y = y2 < -1 and -1 or y2 > actual_height-1 and actual_height-1 or y2\1
	local stop_y = (y3 <= actual_height-1 and y3\1 or actual_height-1)

	-- Top half
	local dy = mid_y-start_y
	if dy > 0 then
		local slope = (v2-v1):div((y2-y1))

		scanlines:copy(slope*(start_y+1-y1)+v1,true,0,0,11)
			:copy(slope,true,0,11,11,0,11,dy-1)

		-- Apply scanline callback if provided
		if scanline_callback then
			for y = start_y, mid_y - 1 do
				scanline_callback(y)
			end
		end

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

		-- Apply scanline callback if provided
		if scanline_callback then
			for y = mid_y, stop_y - 1 do
				scanline_callback(y)
			end
		end

		tline3d(scanlines:add(scanlines,true,0,11,11,11,11,dy-1),0,dy)
	end
end

-- ============================================
-- PER-VERTEX LIT MESH RENDERING
-- ============================================

-- Render mesh with per-vertex lighting
-- Calculates brightness per vertex based on light type
-- @param light_dir_or_pos: {x, y, z} either light direction (directional) or position (point light)
-- @param light_radius: maximum distance light reaches (nil for directional light)
-- @param light_brightness: brightness of light source 0-1 (required)
-- @param ambient: ambient light level 0-1 (optional, default 0.2)
function RendererLit.render_mesh(verts, faces, camera, offset_x, offset_y, offset_z, sprite_override, light_dir_or_pos, light_radius, light_brightness, ambient, is_ground, rot_pitch, rot_yaw, rot_roll, render_distance, ground_always_behind, fog_start_distance, is_skybox, fog_enabled, is_unlit)
	local prof = RendererLit.profiler

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

	-- Frustum culling: calculate AABB for the mesh in world space
	if not is_ground and not is_skybox and #verts > 0 then
		-- Calculate mesh bounding box in local space
		local min_x, min_y, min_z = verts[1].x, verts[1].y, verts[1].z
		local max_x, max_y, max_z = min_x, min_y, min_z

		for i = 2, #verts do
			local v = verts[i]
			if v.x < min_x then min_x = v.x end
			if v.x > max_x then max_x = v.x end
			if v.y < min_y then min_y = v.y end
			if v.y > max_y then max_y = v.y end
			if v.z < min_z then min_z = v.z end
			if v.z > max_z then max_z = v.z end
		end

		-- Transform AABB to world space (apply offset and object rotation)
		-- For simplicity, we'll use a conservative AABB that contains the rotated box
		local aabb_center_x = (min_x + max_x) / 2 + obj_x
		local aabb_center_y = (min_y + max_y) / 2 + (offset_y or 0)
		local aabb_center_z = (min_z + max_z) / 2 + obj_z
		local aabb_extents_x = (max_x - min_x) / 2
		local aabb_extents_y = (max_y - min_y) / 2
		local aabb_extents_z = (max_z - min_z) / 2

		-- Add extra margin for object rotation (conservative)
		if rot_pitch or rot_yaw or rot_roll then
			local max_extent = max(aabb_extents_x, max(aabb_extents_y, aabb_extents_z))
			aabb_extents_x = max_extent
			aabb_extents_y = max_extent
			aabb_extents_z = max_extent
		end

		-- Test if AABB is in frustum
		local fov = 70  -- degrees (matches tan_half_fov)
		local aspect = 480 / 270  -- screen width / height
		if not Frustum.test_aabb_simple(camera, fov, aspect, near, far,
			aabb_center_x - aabb_extents_x, aabb_center_y - aabb_extents_y, aabb_center_z - aabb_extents_z,
			aabb_center_x + aabb_extents_x, aabb_center_y + aabb_extents_y, aabb_center_z + aabb_extents_z) then
			-- Object is completely outside frustum
			if prof then prof("    setup") end
			return {}
		end
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

	-- Calculate face normals and per-face brightness for flat shading
	local face_brightness = {}

	-- Calculate brightness per-face using face normals
	for i = 1, #faces do
		local face = faces[i]

		-- Skip lighting calculation for unlit meshes - use full brightness (no shading), no performance cost for lighting
		if is_unlit then
			face_brightness[i] = 1.0  -- Full brightness, no lighting
		else
			local v1, v2, v3 = verts[face[1]], verts[face[2]], verts[face[3]]

			-- Calculate two edge vectors
			local e1x, e1y, e1z = v2.x - v1.x, v2.y - v1.y, v2.z - v1.z
			local e2x, e2y, e2z = v3.x - v1.x, v3.y - v1.y, v3.z - v1.z

			-- Cross product to get face normal (e2 x e1 for outward-facing normal)
			local nx = e2y * e1z - e2z * e1y
			local ny = e2z * e1x - e2x * e1z
			local nz = e2x * e1y - e2y * e1x

			-- Apply object rotation to normal if rotation is provided
			if rot_pitch or rot_yaw or rot_roll then
				-- Rotate by yaw (Y-axis)
				if rot_yaw then
					local temp_x = nx * cos_yaw - nz * sin_yaw
					local temp_z = nx * sin_yaw + nz * cos_yaw
					nx, nz = temp_x, temp_z
				end
				-- Rotate by pitch (X-axis)
				if rot_pitch then
					local temp_y = ny * cos_pitch - nz * sin_pitch
					local temp_z = ny * sin_pitch + nz * cos_pitch
					ny, nz = temp_y, temp_z
				end
				-- Rotate by roll (Z-axis)
				if rot_roll then
					local temp_x = nx * cos_roll - ny * sin_roll
					local temp_y = nx * sin_roll + ny * cos_roll
					nx, ny = temp_x, temp_y
				end
			end

			-- Normalize using fast inverse square root
			local len_sq = nx * nx + ny * ny + nz * nz
			if len_sq > 0.0001 then
				local inv_len = MathUtils.fast_inv_sqrt(len_sq)
				nx, ny, nz = nx * inv_len, ny * inv_len, nz * inv_len

				-- Calculate brightness for this face using face normal
				if light_radius == nil then
					-- Directional light
					face_brightness[i] = Lighting.calculate_directional_brightness(light_dir_or_pos, light_brightness, ambient, {x = nx, y = ny, z = nz})
				else
					-- Point light - use center of triangle for distance calculation
					local cx = (v1.x + v2.x + v3.x) / 3 + offset_x_val
					local cy = (v1.y + v2.y + v3.y) / 3 + offset_y_val
					local cz = (v1.z + v2.z + v3.z) / 3 + offset_z_val
					face_brightness[i] = Lighting.calculate_vertex_brightness(cx, cy, cz, light_dir_or_pos, light_radius, light_brightness, ambient, {x = nx, y = ny, z = nz})
				end
			else
				-- Degenerate face - use ambient only
				face_brightness[i] = ambient
			end
		end
	end

	-- Batch vertex transformation using matmul3d (much faster than loop)
	local num_verts = #verts
	if num_verts > 0 then
		-- Create userdata for batch transformation (reuse if possible)
		-- Format: 3 columns (x,y,z) × num_verts rows
		local vert_data = userdata("f64", 3, num_verts)

		-- Copy vertex positions to userdata
		for i = 1, num_verts do
			local v = verts[i]
			vert_data:set(0, i-1, v.x)  -- 0-indexed
			vert_data:set(1, i-1, v.y)
			vert_data:set(2, i-1, v.z)
		end

		-- Apply object rotation if needed (using matrix multiplication)
		if rot_pitch or rot_yaw or rot_roll then
			-- Apply rotations sequentially (could optimize to combined matrix)

			if rot_yaw then
				-- Yaw rotation matrix (Y-axis)
				local mat_yaw = userdata("f64", 3, 4)
				mat_yaw:set(0, 0, cos_yaw)   mat_yaw:set(0, 1, 0)         mat_yaw:set(0, 2, -sin_yaw)  mat_yaw:set(0, 3, 0)
				mat_yaw:set(1, 0, 0)         mat_yaw:set(1, 1, 1)         mat_yaw:set(1, 2, 0)         mat_yaw:set(1, 3, 0)
				mat_yaw:set(2, 0, sin_yaw)   mat_yaw:set(2, 1, 0)         mat_yaw:set(2, 2, cos_yaw)   mat_yaw:set(2, 3, 0)
				vert_data:matmul3d(mat_yaw, vert_data, 1)
			end

			if rot_pitch then
				-- Pitch rotation matrix (X-axis)
				local mat_pitch = userdata("f64", 3, 4)
				mat_pitch:set(0, 0, 1)         mat_pitch:set(0, 1, 0)           mat_pitch:set(0, 2, 0)           mat_pitch:set(0, 3, 0)
				mat_pitch:set(1, 0, 0)         mat_pitch:set(1, 1, cos_pitch)   mat_pitch:set(1, 2, -sin_pitch)  mat_pitch:set(1, 3, 0)
				mat_pitch:set(2, 0, 0)         mat_pitch:set(2, 1, sin_pitch)   mat_pitch:set(2, 2, cos_pitch)   mat_pitch:set(2, 3, 0)
				vert_data:matmul3d(mat_pitch, vert_data, 1)
			end

			if rot_roll then
				-- Roll rotation matrix (Z-axis)
				local mat_roll = userdata("f64", 3, 4)
				mat_roll:set(0, 0, cos_roll)   mat_roll:set(0, 1, -sin_roll)  mat_roll:set(0, 2, 0)  mat_roll:set(0, 3, 0)
				mat_roll:set(1, 0, sin_roll)   mat_roll:set(1, 1, cos_roll)   mat_roll:set(1, 2, 0)  mat_roll:set(1, 3, 0)
				mat_roll:set(2, 0, 0)          mat_roll:set(2, 1, 0)          mat_roll:set(2, 2, 1)  mat_roll:set(2, 3, 0)
				vert_data:matmul3d(mat_roll, vert_data, 1)
			end
		end

		-- First, apply offset (translate vertices relative to camera position)
		for i = 1, num_verts do
			vert_data:set(0, i-1, vert_data:get(0, i-1) + offset_x_val - cam_x)
			vert_data:set(1, i-1, vert_data:get(1, i-1) + offset_y_val - cam_y)
			vert_data:set(2, i-1, vert_data:get(2, i-1) + offset_z_val - cam_z)
		end

		-- Build camera rotation matrix matching original transformation:
		-- x1 = x * cos_ry - z * sin_ry
		-- z1 = x * sin_ry + z * cos_ry
		-- y2 = y * cos_rx - z1 * sin_rx
		-- z3 = y * sin_rx + z1 * cos_rx + cam_dist
		local cam_mat = userdata("f64", 3, 4)

		-- Column 0: x2 = x1 = x * cos_ry - z * sin_ry
		cam_mat:set(0, 0, cos_ry)
		cam_mat:set(0, 1, 0)
		cam_mat:set(0, 2, -sin_ry)
		cam_mat:set(0, 3, 0)

		-- Column 1: y2 = y * cos_rx - z1 * sin_rx
		--          = y * cos_rx - (x * sin_ry + z * cos_ry) * sin_rx
		cam_mat:set(1, 0, -sin_ry * sin_rx)
		cam_mat:set(1, 1, cos_rx)
		cam_mat:set(1, 2, -cos_ry * sin_rx)
		cam_mat:set(1, 3, 0)

		-- Column 2: z3 = y * sin_rx + z1 * cos_rx + cam_dist
		--          = y * sin_rx + (x * sin_ry + z * cos_ry) * cos_rx + cam_dist
		cam_mat:set(2, 0, sin_ry * cos_rx)
		cam_mat:set(2, 1, sin_rx)
		cam_mat:set(2, 2, cos_ry * cos_rx)
		cam_mat:set(2, 3, cam_dist)

		-- Apply camera transformation
		vert_data:matmul3d(cam_mat, vert_data, 1)

		-- Project vertices and populate projected/depths arrays
		for i = 1, num_verts do
			local x2 = vert_data:get(0, i-1)
			local y2 = vert_data:get(1, i-1)
			local z3 = vert_data:get(2, i-1)

			-- Only project if in front of near plane
			if z3 > near then
				local inv_z = 1 / z3
				local px = -x2 * inv_z * proj_scale + 240
				local py = -y2 * inv_z * proj_scale + 135

				-- Store projected vertex
				projected[i] = {x=px, y=py, z=0, w=inv_z}
				depths[i] = z3
			else
				projected[i] = nil
				depths[i] = nil
			end
		end
	end
	if prof then prof("    project") end

	-- Build list of projected faces with depth and per-face brightness
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

				-- Create face entry with per-face brightness (flat shading)
				-- Format: {v1, v2, v3, sprite, uv1, uv2, uv3}
				local sprite_a = sprite_id or face[4]
				local uv1, uv2, uv3 = face[5], face[6], face[7]

				-- Get face brightness (same for all 3 vertices = flat shading)
				local brightness = face_brightness[i]

				local face_data = {
					face = {face[1], face[2], face[3], sprite_a, uv1, uv2, uv3},
					depth = avg_depth,
					p1 = p1,
					p2 = p2,
					p3 = p3,
					fog = fog_opacity,
				}

				-- Only add brightness for lit faces; unlit faces skip this so draw_faces knows to render without lighting
				if not face.unlit then
					face_data.b1 = brightness
					face_data.b2 = brightness
					face_data.b3 = brightness
				end

				add(projected_faces, face_data)
			end
		end
	end
	if prof then prof("    backface") end

	return projected_faces
end

-- ============================================
-- LIT FACE DRAWING
-- ============================================

-- Pre-allocate userdata pool to avoid allocations per triangle
local vert_data_pool = userdata("f64", 6, 3)

-- Draw a list of sorted faces with per-vertex lighting using color tables
-- Uses cached brightness-modified sprites instead of dithering
-- Handles both lit faces (with b1,b2,b3) and unlit faces (without)
-- @param all_faces: sorted array of faces with optional brightness data
function RendererLit.draw_faces(all_faces)
	local vpool = vert_data_pool
	local n = #all_faces

	-- Pre-allocate sprite props table (reuse across all triangles)
	local props = {tex = 0}

	for i = 1, n do
		local f = all_faces[i]
		local face = f.face
		local sprite_a = face[4]
		local p1, p2, p3 = f.p1, f.p2, f.p3

		-- Get UVs - face format: {v1, v2, v3, sprite, uv1, uv2, uv3}
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

		-- Determine the effective opacity to use for dithering
		-- Explosion opacity takes precedence if set
		local effective_opacity = 1.0
		if f.explosion_opacity then
			effective_opacity = f.explosion_opacity
		elseif f.dither_opacity then
			effective_opacity = f.dither_opacity
		end

		-- Check if this face has dither opacity (fade out effect)
		if effective_opacity < 0.9 then
			-- Apply dither fading using fillp patterns for smooth transparency
			local fillp_pattern = 0

			-- Select dither pattern based on opacity level
			if effective_opacity > 0.875 then
				fillp_pattern = 0b1000000010000000
			elseif effective_opacity > 0.75 then
				fillp_pattern = 0b1000010000100001
			elseif effective_opacity > 0.625 then
				fillp_pattern = 0b1000010010000100
			elseif effective_opacity > 0.5 then
				fillp_pattern = 0b1010010010100100
			elseif effective_opacity > 0.375 then
				fillp_pattern = 0b0101101001011010
			elseif effective_opacity > 0.25 then
				fillp_pattern = 0b0101101101011011
			elseif effective_opacity > 0.125 then
				fillp_pattern = 0b0111101101111011
			else
				fillp_pattern = 0b0111111101111111
			end

			-- Apply dither pattern
			fillp(fillp_pattern)

			-- Render the face with dither pattern
			if f.b1 then
				-- Lit face with dither
				local b1, b2, b3 = f.b1, f.b2, f.b3
				local avg_b = (b1 + b2 + b3) / 3
				local brightness_level = flr(avg_b * (BRIGHTNESS_LEVELS - 1) + 0.5)
				if brightness_level < 0 then brightness_level = 0 end
				if brightness_level >= BRIGHTNESS_LEVELS then brightness_level = BRIGHTNESS_LEVELS - 1 end
				local brightness_sprite = RendererLit.get_brightness_sprite(sprite_a, brightness_level)
				props.tex = brightness_sprite
				props.tex2 = nil
				RendererLit.textri(props, vpool, 270)
			else
				-- Unlit face with dither
				props.tex = sprite_a
				props.tex2 = nil
				RendererLit.textri(props, vpool, 270)
			end

			-- Reset fill pattern
			fillp()
		else
			-- No dither opacity: render normally
			-- Check if this face has lighting data
			if f.b1 then
				-- Lit face: use cached brightness sprite
				local b1, b2, b3 = f.b1, f.b2, f.b3

				-- Calculate average brightness for this triangle (0-1)
				local avg_b = (b1 + b2 + b3) / 3

				-- Convert brightness to level (0-3)
				local brightness_level = flr(avg_b * (BRIGHTNESS_LEVELS - 1) + 0.5)
				if brightness_level < 0 then brightness_level = 0 end
				if brightness_level >= BRIGHTNESS_LEVELS then brightness_level = BRIGHTNESS_LEVELS - 1 end

				-- Get cached brightness sprite
				local brightness_sprite = RendererLit.get_brightness_sprite(sprite_a, brightness_level)

				-- Draw using brightness sprite
				props.tex = brightness_sprite
				props.tex2 = nil
				RendererLit.textri(props, vpool, 270)
			else
				-- Unlit face: render normally without lighting
				props.tex = sprite_a
				props.tex2 = nil
				RendererLit.textri(props, vpool, 270)
			end
		end
	end
end

-- ============================================
-- FACE SORTING
-- ============================================

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
function RendererLit.sort_faces(faces)
	local n = #faces
	if n > 1 then
		quicksort(faces, 1, n)
	end
end

-- Export BRIGHTNESS_LEVELS for external use
RendererLit.BRIGHTNESS_LEVELS = BRIGHTNESS_LEVELS

return RendererLit

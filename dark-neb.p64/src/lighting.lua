-- Flat Shading Lighting Module
-- Calculates lighting for flat shaded polygons based on normal angle to light

local Lighting = {}

-- Dither patterns for different light levels (from darkest to brightest)
-- Pattern 0 = all dark (0% light), Pattern 8 = all bright (100% light)
Lighting.DITHER_PATTERNS = {
	0b0000000000000000,  -- 0/16 = 0% (all dark)
	0b1000000000000000,  -- 1/16 = 6.25%
	0b1000000010000000,  -- 2/16 = 12.5%
	0b1010000010100000,  -- 4/16 = 25%
	0b1010000010101000,  -- 5/16 = 31.25%
	0b1010100010101000,  -- 6/16 = 37.5%
	0b1010101010101000,  -- 7/16 = 43.75%
	0b1010101010101010,  -- 8/16 = 50%
	0b1110101010101010,  -- 9/16 = 56.25%
	0b1110101011101010,  -- 10/16 = 62.5%
	0b1111101011101010,  -- 11/16 = 68.75%
	0b1111101011111010,  -- 12/16 = 75%
	0b1111101111111010,  -- 13/16 = 81.25%
	0b1111111111111010,  -- 14/16 = 87.5%
	0b1111111111111110,  -- 15/16 = 93.75%
	0b1111111111111111,  -- 16/16 = 100% (all light)
}

-- Calculate flat shading brightness for a triangle face
-- @param normal: normalized face normal {x, y, z}
-- @param light_dir: normalized light direction {x, y, z} (points FROM surface TO light)
-- @return brightness: 0-1 value (0 = dark, 1 = bright)
function Lighting.calculate_flat_brightness(normal, light_dir)
	-- Dot product between normal and light direction
	local dot = normal.x * light_dir.x + normal.y * light_dir.y + normal.z * light_dir.z

	-- Clamp to 0-1 range (negative = facing away from light)
	if dot < 0 then
		return 0
	end

	return dot
end

-- Convert brightness (0-1) to dither pattern index (1-16)
-- @param brightness: 0-1 value
-- @return pattern_idx: index into DITHER_PATTERNS (1-16)
function Lighting.brightness_to_pattern(brightness)
	local idx = flr(brightness * 15) + 1
	if idx < 1 then idx = 1 end
	if idx > 16 then idx = 16 end
	return idx
end

-- Apply dither pattern based on brightness
-- @param pattern_idx: index into DITHER_PATTERNS (1-16)
function Lighting.apply_pattern(pattern_idx)
	fillp(Lighting.DITHER_PATTERNS[pattern_idx])
end

-- Apply inverted dither pattern (for second layer)
-- @param pattern_idx: index into DITHER_PATTERNS (1-16)
function Lighting.apply_inverted_pattern(pattern_idx)
	-- Invert the pattern by XORing with all 1s
	local pattern = Lighting.DITHER_PATTERNS[pattern_idx]
	local inverted = pattern ~ 0b1111111111111111
	fillp(inverted)
end

-- Calculate face normal from three vertices
-- @param v1, v2, v3: vertices with x,y,z fields
-- @return normal: normalized normal vector {x, y, z}
function Lighting.calculate_face_normal(v1, v2, v3)
	-- Calculate two edge vectors
	local e1x = v2.x - v1.x
	local e1y = v2.y - v1.y
	local e1z = v2.z - v1.z

	local e2x = v3.x - v1.x
	local e2y = v3.y - v1.y
	local e2z = v3.z - v1.z

	-- Cross product (e1 x e2) for outward-facing normal
	local nx = e1y * e2z - e1z * e2y
	local ny = e1z * e2x - e1x * e2z
	local nz = e1x * e2y - e1y * e2x

	-- Normalize
	local len = sqrt(nx * nx + ny * ny + nz * nz)
	if len > 0.0001 then
		nx = nx / len
		ny = ny / len
		nz = nz / len
	end

	return {x = nx, y = ny, z = nz}
end

-- Calculate light direction from surface point to light position
-- @param surface_pos: surface position {x, y, z}
-- @param light_pos: light position {x, y, z}
-- @return light_dir: normalized direction vector FROM surface TO light {x, y, z}
function Lighting.calculate_light_direction(surface_pos, light_pos)
	local dx = light_pos.x - surface_pos.x
	local dy = light_pos.y - surface_pos.y
	local dz = light_pos.z - surface_pos.z

	-- Normalize
	local len = sqrt(dx * dx + dy * dy + dz * dz)
	if len > 0.0001 then
		dx = dx / len
		dy = dy / len
		dz = dz / len
	end

	return {x = dx, y = dy, z = dz}
end

-- Calculate per-vertex brightness for point light
-- @param vx, vy, vz: vertex world position
-- @param light_pos: light position {x, y, z}
-- @param light_radius: maximum distance light reaches
-- @param light_brightness: brightness of light source (0-1)
-- @param ambient: ambient light level (0-1)
-- @param normal: vertex normal (optional, for directional lighting)
-- @return brightness: 0-1 value
function Lighting.calculate_vertex_brightness(vx, vy, vz, light_pos, light_radius, light_brightness, ambient, normal)
	-- Calculate distance from vertex to light
	local dx = light_pos.x - vx
	local dy = light_pos.y - vy
	local dz = light_pos.z - vz
	local dist = sqrt(dx * dx + dy * dy + dz * dz)

	-- Distance attenuation (inverse square with linear falloff)
	local attenuation = 1.0
	if dist > 0.0001 then
		-- Linear falloff to avoid harsh cutoff
		attenuation = max(0, 1.0 - (dist / light_radius))
	end

	-- If normal is provided, use directional lighting (dot product)
	local directional = 1.0
	if normal and dist > 0.0001 then
		-- Normalize light direction
		local light_dir_x = dx / dist
		local light_dir_y = dy / dist
		local light_dir_z = dz / dist

		-- Dot product with normal
		local dot = normal.x * light_dir_x + normal.y * light_dir_y + normal.z * light_dir_z
		directional = max(0, dot)
	end

	-- Combine ambient, attenuation, and directional lighting
	local brightness = ambient + (light_brightness * attenuation * directional * (1.0 - ambient))

	-- Clamp to 0-1
	if brightness < 0 then brightness = 0 end
	if brightness > 1 then brightness = 1 end

	return brightness
end

-- Calculate per-vertex brightness for directional light
-- @param light_dir: normalized light direction {x, y, z} (direction light is shining)
-- @param light_brightness: brightness of light source (0-1)
-- @param ambient: ambient light level (0-1)
-- @param normal: vertex normal (required for directional lighting)
-- @return brightness: 0-1 value
function Lighting.calculate_directional_brightness(light_dir, light_brightness, ambient, normal)
	-- Normalize light direction if needed
	local len = sqrt(light_dir.x * light_dir.x + light_dir.y * light_dir.y + light_dir.z * light_dir.z)
	local lx, ly, lz = light_dir.x, light_dir.y, light_dir.z
	if len > 0.0001 then
		lx, ly, lz = lx / len, ly / len, lz / len
	end

	-- Dot product with normal (negative because light_dir is the direction light is shining)
	local dot = -(normal.x * lx + normal.y * ly + normal.z * lz)

	-- Clamp to 0-1 (negative = facing away from light)
	local directional = max(0, dot)

	-- Combine ambient and directional lighting
	local brightness = ambient + (light_brightness * directional * (1.0 - ambient))

	-- Clamp to 0-1
	if brightness < 0 then brightness = 0 end
	if brightness > 1 then brightness = 1 end

	return brightness
end

return Lighting

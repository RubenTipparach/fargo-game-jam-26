--[[pod_format="raw",created="2024-11-07 20:00:00",modified="2024-11-07 20:00:00",revision=0]]
-- StarField Module
-- Manages background star generation and rendering
-- Single Responsibility: Only handles star field visuals

local StarField = {}

-- Internal state (private)
local star_positions = nil  -- Userdata storing star positions and colors
local star_transformed = nil  -- Reused each frame for batch transforms
local star_count = 0

-- Constants
local TAN_HALF_FOV = 0.7002075
local PROJ_SCALE = 270 / 0.7002075

-- Initialize star field from config
-- @param Config: Game configuration with stars settings
function StarField.init(Config)
	star_count = Config.stars.count

	-- Helper function to pick color based on probabilities
	local function pick_star_color()
		local rand = rnd()
		local cumulative = 0
		for color_cfg in all(Config.stars.colors) do
			cumulative = cumulative + color_cfg.probability
			if rand <= cumulative then
				return color_cfg.color
			end
		end
		return Config.stars.colors[1].color
	end

	-- Create userdata for star positions and colors
	-- 4 columns x star_count rows (x, y, z, color per star)
	star_positions = userdata("f64", 4, star_count)

	for i = 1, star_count do
		local range = Config.stars.range
		local x = rnd(range.x.max - range.x.min) + range.x.min
		local y = rnd(range.y.max - range.y.min) + range.y.min
		local z = rnd(range.z.max - range.z.min) + range.z.min
		local color = pick_star_color()

		-- Store in userdata (0-indexed)
		star_positions:set(0, i-1, x)
		star_positions:set(1, i-1, y)
		star_positions:set(2, i-1, z)
		star_positions:set(3, i-1, color)
	end

	-- Pre-allocate transformed positions buffer
	star_transformed = userdata("f64", 4, star_count)
end

-- Draw stars using batch matrix multiplication
-- Stars rotate opposite to camera to appear fixed in background
-- @param camera: Camera object with rx, ry, distance
function StarField.draw(camera)
	if not star_positions then return end

	-- Create transformed positions if needed
	if not star_transformed then
		star_transformed = userdata("f64", 4, star_count)
	end

	-- Build transformation matrix with negated camera rotation
	-- This makes stars appear fixed as camera rotates
	local sin_ry, cos_ry = sin(-camera.ry), cos(-camera.ry)
	local sin_rx, cos_rx = sin(-camera.rx), cos(-camera.rx)
	local cam_dist = camera.distance or 30

	-- Create 3x4 transformation matrix for matmul3d
	local mat = userdata("f64", 3, 4)

	-- Column 0 (x output)
	mat:set(0, 0, -cos_ry)
	mat:set(0, 1, 0)
	mat:set(0, 2, sin_ry)
	mat:set(0, 3, 0)

	-- Column 1 (y output)
	mat:set(1, 0, sin_ry * sin_rx)
	mat:set(1, 1, -cos_rx)
	mat:set(1, 2, cos_ry * sin_rx)
	mat:set(1, 3, 0)

	-- Column 2 (z output)
	mat:set(2, 0, sin_ry * cos_rx)
	mat:set(2, 1, sin_rx)
	mat:set(2, 2, cos_ry * cos_rx)
	mat:set(2, 3, cam_dist)

	-- Batch transform all stars
	star_transformed:copy(star_positions, true)
	star_transformed:matmul3d(mat, star_transformed, 1)

	-- Project and draw stars
	for i = 0, star_count - 1 do
		local x = star_transformed:get(0, i)
		local y = star_transformed:get(1, i)
		local z = star_transformed:get(2, i)
		local color = star_positions:get(3, i)

		-- Perspective projection
		if z > 0.01 then
			local inv_z = 1 / z
			local px = -x * inv_z * PROJ_SCALE + 240
			local py = -y * inv_z * PROJ_SCALE + 135
			pset(px, py, color)
		end
	end
end

-- Get star count (for debugging)
function StarField.get_count()
	return star_count
end

return StarField

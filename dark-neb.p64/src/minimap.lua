--[[pod_format="raw",created="2024-11-08 00:00:00",modified="2024-11-08 00:00:00",revision=0]]
-- Minimap Module
-- Displays player position, planets, and battlefield boundaries

local Minimap = {}

-- Configuration
Minimap.X = 480 - 64 - 5  -- Top-right corner with 5px margin
Minimap.Y = 10  -- Top Y position
Minimap.SIZE = 64  -- 64x64 pixels for the minimap
Minimap.MAP_SIZE = 512  -- World space is 512x512 units
Minimap.SCALE = Minimap.SIZE / Minimap.MAP_SIZE  -- Pixels per world unit

-- Draw the minimap
-- @param ship_pos: {x, z} player ship position
-- @param planet_pos: {x, z} planet position
-- @param planet_radius: radius of the planet in world units
function Minimap.draw(ship_pos, planet_pos, planet_radius)
	-- Draw minimap background with border
	rectfill(Minimap.X - 2, Minimap.Y - 2, Minimap.X + Minimap.SIZE + 1, Minimap.Y + Minimap.SIZE + 1, 0)  -- Black border
	rectfill(Minimap.X, Minimap.Y, Minimap.X + Minimap.SIZE, Minimap.Y + Minimap.SIZE, 1)  -- Dark blue background

	-- Draw map boundary (256x256 world space)
	local boundary_size = Minimap.MAP_SIZE * Minimap.SCALE
	rect(Minimap.X, Minimap.Y, Minimap.X + boundary_size, Minimap.Y + boundary_size, 11)  -- Yellow border

	-- Convert world coordinates to minimap coordinates
	-- Map center is at (128, 128) in the minimap view
	local function world_to_minimap(world_x, world_z)
		local minimap_x = Minimap.X + (world_x + Minimap.MAP_SIZE / 2) * Minimap.SCALE
		local minimap_y = Minimap.Y + (world_z + Minimap.MAP_SIZE / 2) * Minimap.SCALE
		return minimap_x, minimap_y
	end

	-- Draw planet as a circle
	if planet_pos then
		local planet_x, planet_y = world_to_minimap(planet_pos.x, planet_pos.z)
		local planet_radius_pixels = planet_radius * Minimap.SCALE
		circfill(planet_x, planet_y, planet_radius_pixels, 8)  -- Red planet
		circ(planet_x, planet_y, planet_radius_pixels, 15)  -- Bright border
	end

	-- Draw ship as a yellow diamond (blinking to avoid overlap with enemy indicators)
	if ship_pos then
		-- Blink at 2Hz (visible/invisible every 0.5 seconds)
		if (time() * 2) % 1 < 0.5 then
			local ship_x, ship_y = world_to_minimap(ship_pos.x, ship_pos.z)
			-- Draw a small diamond
			local size = 3
			line(ship_x - size, ship_y, ship_x, ship_y - size, 10)  -- Top-left to top
			line(ship_x, ship_y - size, ship_x + size, ship_y, 10)  -- Top to top-right
			line(ship_x + size, ship_y, ship_x, ship_y + size, 10)  -- Top-right to bottom
			line(ship_x, ship_y + size, ship_x - size, ship_y, 10)  -- Bottom to top-left
			circfill(ship_x, ship_y, 1, 10)  -- Center dot
		end
	end
end

-- Check if position is out of bounds
-- @param pos: {x, z} position to check
-- @return true if out of bounds
function Minimap.is_out_of_bounds(pos)
	local half_size = Minimap.MAP_SIZE / 2
	return pos.x < -half_size or pos.x > half_size or
	       pos.z < -half_size or pos.z > half_size
end

-- Get distance to nearest boundary
-- @param pos: {x, z} position to check
-- @return distance to nearest boundary
function Minimap.distance_to_boundary(pos)
	local half_size = Minimap.MAP_SIZE / 2
	local dist_x = half_size - abs(pos.x)
	local dist_z = half_size - abs(pos.z)
	return min(dist_x, dist_z)
end

return Minimap

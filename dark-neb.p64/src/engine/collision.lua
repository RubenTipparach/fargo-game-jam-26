-- Collision and Physics Helpers Module
-- Provides AABB collision detection and physics utilities

local Collision = {}

-- Collision Object (AABB - Axis-Aligned Bounding Box)
-- @param x, y, z: center position
-- @param width, height, depth: full dimensions
-- @param y_offset: optional Y offset to adjust collision box position (default 0)
-- @return collision object with bounds
function Collision.create_box(x, y, z, width, height, depth, y_offset)
	y_offset = y_offset or 0

	return {
		x = x,
		y = y,
		z = z,
		width = width,
		height = height,
		depth = depth,
		y_offset = y_offset,

		-- Calculate actual bounds with offset
		get_bounds = function(self)
			local adjusted_y = self.y + self.y_offset
			return {
				top = adjusted_y + self.height,
				bottom = adjusted_y,
				half_width = self.width / 2,
				half_depth = self.depth / 2
			}
		end
	}
end

-- Check if a point is inside an axis-aligned bounding box
-- @param point_x, point_z: point coordinates (2D horizontal plane)
-- @param box_x, box_z: box center position
-- @param half_width, half_depth: box half-extents
-- @return true if point is inside box
function Collision.point_in_box(point_x, point_z, box_x, box_z, half_width, half_depth)
	local dx = point_x - box_x
	local dz = point_z - box_z
	return abs(dx) < half_width and abs(dz) < half_depth
end

-- Check if two axis-aligned bounding boxes overlap (AABB collision)
-- @param box1_x, box1_z: first box center position
-- @param box1_half_width, box1_half_depth: first box half-extents
-- @param box2_x, box2_z: second box center position
-- @param box2_half_width, box2_half_depth: second box half-extents
-- @return true if boxes overlap
function Collision.box_overlap(box1_x, box1_z, box1_half_width, box1_half_depth, box2_x, box2_z, box2_half_width, box2_half_depth)
	local dx = abs(box1_x - box2_x)
	local dz = abs(box1_z - box2_z)
	return dx < (box1_half_width + box2_half_width) and dz < (box1_half_depth + box2_half_depth)
end

-- Find the nearest edge of a box and calculate push-out vector
-- @param point_x, point_z: point coordinates
-- @param box_x, box_z: box center position
-- @param half_width, half_depth: box half-extents
-- @return pushed_x, pushed_z: new position pushed outside the box
function Collision.push_out_of_box(point_x, point_z, box_x, box_z, half_width, half_depth)
	local dx = point_x - box_x
	local dz = point_z - box_z

	-- Calculate distances to each edge
	local dist_left = abs(dx + half_width)
	local dist_right = abs(dx - half_width)
	local dist_front = abs(dz + half_depth)
	local dist_back = abs(dz - half_depth)

	-- Find closest edge
	local min_dist = min(dist_left, dist_right, dist_front, dist_back)

	-- Push out through closest edge
	if min_dist == dist_left then
		return box_x - half_width - 0.1, point_z
	elseif min_dist == dist_right then
		return box_x + half_width + 0.1, point_z
	elseif min_dist == dist_front then
		return point_x, box_z - half_depth - 0.1
	else
		return point_x, box_z + half_depth + 0.1
	end
end

-- Calculate bounding box from vertex array
-- @param verts: array of vertices with x, y, z components
-- @return min_x, max_x, min_y, max_y, min_z, max_z
function Collision.calculate_bounds(verts)
	local min_x, max_x = 999, -999
	local min_y, max_y = 999, -999
	local min_z, max_z = 999, -999

	for _, v in ipairs(verts) do
		min_x = min(min_x, v.x)
		max_x = max(max_x, v.x)
		min_y = min(min_y, v.y)
		max_y = max(max_y, v.y)
		min_z = min(min_z, v.z)
		max_z = max(max_z, v.z)
	end

	return min_x, max_x, min_y, max_y, min_z, max_z
end

-- Draw wireframe for a collision object
-- @param collision_obj: collision object created with create_box()
-- @param camera: camera object
-- @param color: line color
function Collision.draw_collision_wireframe(collision_obj, camera, color)
	local bounds = collision_obj:get_bounds()
	local adjusted_y = collision_obj.y + collision_obj.y_offset
	local center_y = adjusted_y + collision_obj.height / 2

	Collision.draw_wireframe(
		camera,
		collision_obj.x,
		center_y,
		collision_obj.z,
		collision_obj.width,
		collision_obj.height,
		collision_obj.depth,
		color
	)
end

-- Helper function to draw wireframe collision box in 3D
-- @param camera: camera object with x, y, rx, ry
-- @param x, y, z: box center position
-- @param width, height, depth: box dimensions (full size, not half)
-- @param color: line color
function Collision.draw_wireframe(camera, x, y, z, width, height, depth, color)
	-- Calculate 8 corners of the box (centered on x, y, z)
	local hw, hh, hd = width/2, height/2, depth/2
	local corners = {
		vec(x - hw, y - hh, z - hd),  -- bottom front left
		vec(x + hw, y - hh, z - hd),  -- bottom front right
		vec(x + hw, y - hh, z + hd),  -- bottom back right
		vec(x - hw, y - hh, z + hd),  -- bottom back left
		vec(x - hw, y + hh, z - hd),  -- top front left
		vec(x + hw, y + hh, z - hd),  -- top front right
		vec(x + hw, y + hh, z + hd),  -- top back right
		vec(x - hw, y + hh, z + hd),  -- top back left
	}

	-- Project corners to screen space
	local projected = {}
	local fov = 70
	local fov_rad = fov * 0.5 * 0.0174533
	local tan_half_fov = sin(fov_rad) / cos(fov_rad)
	local cam_dist = 3

	for i, corner in ipairs(corners) do
		local cx, cy, cz = corner.x - camera.x, corner.y - camera.y, corner.z - camera.z

		-- Apply camera rotation
		local cos_ry, sin_ry = cos(camera.ry), sin(camera.ry)
		local cos_rx, sin_rx = cos(camera.rx), sin(camera.rx)

		local x2 = cx * cos_ry - cz * sin_ry
		local z2 = cx * sin_ry + cz * cos_ry

		local y2 = cy * cos_rx - z2 * sin_rx
		local z3 = cy * sin_rx + z2 * cos_rx

		z3 += cam_dist

		if z3 > 0.01 then
			local px = x2 / z3 * (270 / tan_half_fov) + 240
			local py = y2 / z3 * (270 / tan_half_fov) + 135
			projected[i] = {x = px, y = py}
		end
	end

	-- Draw lines between corners if both endpoints are visible
	local edges = {
		{1, 2}, {2, 3}, {3, 4}, {4, 1},  -- bottom
		{5, 6}, {6, 7}, {7, 8}, {8, 5},  -- top
		{1, 5}, {2, 6}, {3, 7}, {4, 8}   -- vertical
	}

	for _, edge in ipairs(edges) do
		local p1, p2 = projected[edge[1]], projected[edge[2]]
		if p1 and p2 then
			line(p1.x, p1.y, p2.x, p2.y, color)
		end
	end
end

return Collision

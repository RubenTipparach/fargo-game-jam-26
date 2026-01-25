--[[pod_format="raw",created="2024-11-07 20:00:00",modified="2024-11-07 20:00:00",revision=0]]
-- CollisionSystem Module
-- Handles collision detection and tracking
-- Single Responsibility: Only handles collision detection and events

local CollisionSystem = {}

-- Internal state for tracking active collisions
local collision_pairs = {}

-- Initialize collision system
function CollisionSystem.init()
	collision_pairs = {}
end

-- Clear all collision tracking
function CollisionSystem.reset()
	collision_pairs = {}
end

-- Check AABB-Sphere collision
-- @param box_min: {x, y, z} minimum bounds
-- @param box_max: {x, y, z} maximum bounds
-- @param sphere_center: {x, y, z} sphere center
-- @param sphere_radius: Sphere radius
-- @return: true if colliding
function CollisionSystem.check_box_sphere(box_min, box_max, sphere_center, sphere_radius)
	-- Find closest point on box to sphere center
	local closest_x = max(box_min.x, min(sphere_center.x, box_max.x))
	local closest_y = max(box_min.y, min(sphere_center.y, box_max.y))
	local closest_z = max(box_min.z, min(sphere_center.z, box_max.z))

	-- Calculate distance
	local dx = sphere_center.x - closest_x
	local dy = sphere_center.y - closest_y
	local dz = sphere_center.z - closest_z
	local distance = sqrt(dx * dx + dy * dy + dz * dz)

	return distance < sphere_radius
end

-- Check AABB-AABB collision
-- @param box1_min, box1_max: First box bounds
-- @param box2_min, box2_max: Second box bounds
-- @return: true if colliding
function CollisionSystem.check_box_box(box1_min, box1_max, box2_min, box2_max)
	return (box1_min.x < box2_max.x and box1_max.x > box2_min.x) and
	       (box1_min.y < box2_max.y and box1_max.y > box2_min.y) and
	       (box1_min.z < box2_max.z and box1_max.z > box2_min.z)
end

-- Check if this is a new collision (wasn't colliding last frame)
-- @param id1, id2: Collision pair identifiers
-- @return: true if this is a new collision
function CollisionSystem.is_new_collision(id1, id2)
	if not collision_pairs[id1] then
		return true
	end
	return not collision_pairs[id1][id2]
end

-- Mark a collision pair as active
function CollisionSystem.mark_colliding(id1, id2)
	if not collision_pairs[id1] then
		collision_pairs[id1] = {}
	end
	collision_pairs[id1][id2] = true
end

-- Clear a collision pair (no longer colliding)
function CollisionSystem.clear_collision(id1, id2)
	if collision_pairs[id1] then
		collision_pairs[id1][id2] = nil
	end
end

-- Build box bounds from position and half-size
-- @param pos: {x, y, z} center position
-- @param half_size: {x, y, z} half dimensions
-- @return: box_min, box_max
function CollisionSystem.build_box(pos, half_size)
	local box_min = {
		x = pos.x - half_size.x,
		y = pos.y - half_size.y,
		z = pos.z - half_size.z,
	}
	local box_max = {
		x = pos.x + half_size.x,
		y = pos.y + half_size.y,
		z = pos.z + half_size.z,
	}
	return box_min, box_max
end

-- Check player collision with planet
-- @param ship_pos: Player ship position
-- @param ship_collider: Ship collider config with half_size
-- @param planet_pos: Planet position
-- @param planet_radius: Planet collision radius
-- @return: true if colliding
function CollisionSystem.check_planet_collision(ship_pos, ship_collider, planet_pos, planet_radius)
	local ship_box_min, ship_box_max = CollisionSystem.build_box(ship_pos, ship_collider.half_size)
	local planet_center = {
		x = planet_pos.x,
		y = planet_pos.y,
		z = planet_pos.z,
	}
	return CollisionSystem.check_box_sphere(ship_box_min, ship_box_max, planet_center, planet_radius)
end

-- Process player collisions with all enemies
-- @param ship_id: Player ship ID
-- @param ship_pos: Player ship position
-- @param ship_collider: Ship collider config
-- @param enemies: Array of enemy objects with position and config.collider
-- @return: Array of collision events {enemy = enemy_obj, is_new = bool}
function CollisionSystem.process_enemy_collisions(ship_id, ship_pos, ship_collider, enemies)
	local collisions = {}
	local ship_box_min, ship_box_max = CollisionSystem.build_box(ship_pos, ship_collider.half_size)

	for _, enemy in ipairs(enemies) do
		if not enemy.is_destroyed and enemy.config and enemy.config.collider then
			local enemy_half_size = enemy.config.collider.half_size
			local enemy_box_min, enemy_box_max = CollisionSystem.build_box(enemy.position, enemy_half_size)

			local is_colliding = CollisionSystem.check_box_box(ship_box_min, ship_box_max, enemy_box_min, enemy_box_max)

			if is_colliding then
				local is_new = CollisionSystem.is_new_collision(ship_id, enemy.id)
				CollisionSystem.mark_colliding(ship_id, enemy.id)

				table.insert(collisions, {
					enemy = enemy,
					is_new = is_new,
				})
			else
				CollisionSystem.clear_collision(ship_id, enemy.id)
			end
		end
	end

	return collisions
end

-- Draw wireframe box for debug visualization
-- @param min_x, min_y, min_z, max_x, max_y, max_z: Box bounds
-- @param camera: Camera object
-- @param color: Draw color
-- @param draw_line_3d_fn: Function to draw 3D lines
function CollisionSystem.draw_box_wireframe(min_x, min_y, min_z, max_x, max_y, max_z, camera, color, draw_line_3d_fn)
	local corners = {
		{min_x, min_y, min_z}, {max_x, min_y, min_z},
		{max_x, max_y, min_z}, {min_x, max_y, min_z},
		{min_x, min_y, max_z}, {max_x, min_y, max_z},
		{max_x, max_y, max_z}, {min_x, max_y, max_z},
	}

	local edges = {
		{1,2}, {2,3}, {3,4}, {4,1},  -- Front face
		{5,6}, {6,7}, {7,8}, {8,5},  -- Back face
		{1,5}, {2,6}, {3,7}, {4,8},  -- Connecting edges
	}

	for _, edge in ipairs(edges) do
		local c1 = corners[edge[1]]
		local c2 = corners[edge[2]]
		draw_line_3d_fn(c1[1], c1[2], c1[3], c2[1], c2[2], c2[3], camera, color)
	end
end

return CollisionSystem

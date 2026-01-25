--[[pod_format="raw",created="2024-11-07 20:00:00",modified="2024-11-07 20:00:00",revision=0]]
-- SubsystemManager Module
-- Manages ship subsystem hitboxes and damage routing
-- Single Responsibility: Track subsystem health and apply effects when destroyed

local SubsystemManager = {}

-- Config reference
local Config = nil

-- Track subsystem state per entity
-- {entity_id = {weapons = {health, max_health, destroyed}, engines = {...}, ...}}
local entity_subsystems = {}

-- Subsystem names for iteration
local SUBSYSTEM_NAMES = {"weapons", "engines", "shields", "sensors", "life_support"}

-- Initialize with config reference
function SubsystemManager.init(config)
	Config = config
end

-- Initialize subsystems for an entity
-- @param entity_id: Unique identifier for the entity
-- @param subsystem_type: "player" or "grabon" (matches Config.subsystems keys)
function SubsystemManager.init_entity(entity_id, subsystem_type)
	if not Config or not Config.subsystems then
		printh("SubsystemManager: Config.subsystems not found")
		return
	end

	local subsystem_config = Config.subsystems[subsystem_type]
	if not subsystem_config then
		printh("SubsystemManager: Unknown subsystem type: " .. tostring(subsystem_type))
		return
	end

	entity_subsystems[entity_id] = {}

	for _, name in ipairs(SUBSYSTEM_NAMES) do
		local cfg = subsystem_config[name]
		if cfg then
			entity_subsystems[entity_id][name] = {
				health = cfg.max_health,
				max_health = cfg.max_health,
				destroyed = false,
				offset = cfg.offset,
				half_size = cfg.half_size,
			}
		end
	end

	printh("SubsystemManager: Initialized " .. entity_id .. " with type " .. subsystem_type)
end

-- Reset entity subsystems (for respawn/new game)
function SubsystemManager.reset_entity(entity_id)
	if entity_subsystems[entity_id] then
		for _, name in ipairs(SUBSYSTEM_NAMES) do
			local sub = entity_subsystems[entity_id][name]
			if sub then
				sub.health = sub.max_health
				sub.destroyed = false
			end
		end
		printh("SubsystemManager: Reset " .. entity_id)
	end
end

-- Remove entity from tracking
function SubsystemManager.remove_entity(entity_id)
	entity_subsystems[entity_id] = nil
end

-- Transform world position to entity's local space
-- @param world_pos: {x, y, z} position in world space
-- @param entity_pos: {x, y, z} entity center position
-- @param entity_heading: heading in turns (0-1)
-- @return: {x, y, z} position in local space
local function transform_to_local(world_pos, entity_pos, entity_heading)
	local dx = world_pos.x - entity_pos.x
	local dy = world_pos.y - entity_pos.y
	local dz = world_pos.z - entity_pos.z

	-- Rotate by negative heading to get local space
	local cos_h = cos(-entity_heading)
	local sin_h = sin(-entity_heading)

	return {
		x = dx * cos_h - dz * sin_h,
		y = dy,
		z = dx * sin_h + dz * cos_h
	}
end

-- Check if a point is inside a box
-- @param point: {x, y, z} local space point
-- @param offset: {x, y, z} box center offset
-- @param half_size: {x, y, z} box half extents
local function point_in_box(point, offset, half_size)
	return abs(point.x - offset.x) <= half_size.x and
	       abs(point.y - offset.y) <= half_size.y and
	       abs(point.z - offset.z) <= half_size.z
end

-- Ray-box intersection test
-- @param ray_origin: {x, y, z} ray start in local space
-- @param ray_dir: {x, y, z} normalized ray direction
-- @param offset: {x, y, z} box center offset
-- @param half_size: {x, y, z} box half extents
-- @return: distance to intersection or nil if no hit
local function ray_box_intersection(ray_origin, ray_dir, offset, half_size)
	local min_bound = {
		x = offset.x - half_size.x,
		y = offset.y - half_size.y,
		z = offset.z - half_size.z,
	}
	local max_bound = {
		x = offset.x + half_size.x,
		y = offset.y + half_size.y,
		z = offset.z + half_size.z,
	}

	local t_min = -9999999
	local t_max = 9999999

	-- X axis
	if abs(ray_dir.x) > 0.0001 then
		local t1 = (min_bound.x - ray_origin.x) / ray_dir.x
		local t2 = (max_bound.x - ray_origin.x) / ray_dir.x
		if t1 > t2 then t1, t2 = t2, t1 end
		t_min = max(t_min, t1)
		t_max = min(t_max, t2)
	elseif ray_origin.x < min_bound.x or ray_origin.x > max_bound.x then
		return nil
	end

	-- Y axis
	if abs(ray_dir.y) > 0.0001 then
		local t1 = (min_bound.y - ray_origin.y) / ray_dir.y
		local t2 = (max_bound.y - ray_origin.y) / ray_dir.y
		if t1 > t2 then t1, t2 = t2, t1 end
		t_min = max(t_min, t1)
		t_max = min(t_max, t2)
	elseif ray_origin.y < min_bound.y or ray_origin.y > max_bound.y then
		return nil
	end

	-- Z axis
	if abs(ray_dir.z) > 0.0001 then
		local t1 = (min_bound.z - ray_origin.z) / ray_dir.z
		local t2 = (max_bound.z - ray_origin.z) / ray_dir.z
		if t1 > t2 then t1, t2 = t2, t1 end
		t_min = max(t_min, t1)
		t_max = min(t_max, t2)
	elseif ray_origin.z < min_bound.z or ray_origin.z > max_bound.z then
		return nil
	end

	if t_min > t_max or t_max < 0 then
		return nil
	end

	return t_min > 0 and t_min or t_max
end

-- Apply directional damage to an entity's subsystems
-- @param entity_id: Entity identifier
-- @param entity_pos: {x, y, z} entity position
-- @param entity_heading: heading in turns (0-1)
-- @param impact_origin: {x, y, z} where the attack came from (attacker position)
-- @param damage: amount of damage to apply
-- @return: {subsystem = name_of_hit_subsystem, destroyed = bool} or nil if hull hit
function SubsystemManager.apply_directional_damage(entity_id, entity_pos, entity_heading, impact_origin, damage)
	local subs = entity_subsystems[entity_id]
	if not subs then
		printh("SubsystemManager: No subsystems for " .. tostring(entity_id))
		return nil
	end

	-- Calculate ray from impact origin toward entity center in local space
	local local_impact = transform_to_local(impact_origin, entity_pos, entity_heading)

	-- Ray direction: from impact toward center (0,0,0 in local space)
	local ray_len = sqrt(local_impact.x^2 + local_impact.y^2 + local_impact.z^2)
	if ray_len < 0.001 then
		-- Impact at center, default to life support
		local sub = subs.life_support
		if sub and not sub.destroyed then
			sub.health = sub.health - damage
			if sub.health <= 0 then
				sub.health = 0
				sub.destroyed = true
				printh("SubsystemManager: " .. entity_id .. " life_support DESTROYED")
				return {subsystem = "life_support", destroyed = true}
			end
			return {subsystem = "life_support", destroyed = false}
		end
		return nil
	end

	local ray_dir = {
		x = -local_impact.x / ray_len,
		y = -local_impact.y / ray_len,
		z = -local_impact.z / ray_len,
	}

	-- Find closest subsystem hit
	local closest_hit = nil
	local closest_dist = 9999999
	local closest_name = nil

	for _, name in ipairs(SUBSYSTEM_NAMES) do
		local sub = subs[name]
		if sub and not sub.destroyed then
			local dist = ray_box_intersection(local_impact, ray_dir, sub.offset, sub.half_size)
			if dist and dist < closest_dist then
				closest_dist = dist
				closest_hit = sub
				closest_name = name
			end
		end
	end

	-- Apply damage to hit subsystem
	if closest_hit then
		closest_hit.health = closest_hit.health - damage
		if closest_hit.health <= 0 then
			closest_hit.health = 0
			closest_hit.destroyed = true
			printh("SubsystemManager: " .. entity_id .. " " .. closest_name .. " DESTROYED")
			return {subsystem = closest_name, destroyed = true}
		end
		printh("SubsystemManager: " .. entity_id .. " " .. closest_name .. " hit for " .. damage .. " (" .. closest_hit.health .. "/" .. closest_hit.max_health .. ")")
		return {subsystem = closest_name, destroyed = false}
	end

	-- No subsystem hit - hull damage (handled by caller)
	return nil
end

-- Check if a subsystem is destroyed
function SubsystemManager.is_destroyed(entity_id, subsystem_name)
	local subs = entity_subsystems[entity_id]
	if subs and subs[subsystem_name] then
		return subs[subsystem_name].destroyed
	end
	return false
end

-- Get subsystem health
function SubsystemManager.get_health(entity_id, subsystem_name)
	local subs = entity_subsystems[entity_id]
	if subs and subs[subsystem_name] then
		return subs[subsystem_name].health, subs[subsystem_name].max_health
	end
	return 0, 0
end

-- Get all subsystem states for an entity
function SubsystemManager.get_all_states(entity_id)
	return entity_subsystems[entity_id]
end

-- Repair a subsystem
-- @param entity_id: Entity identifier
-- @param subsystem_name: Name of subsystem to repair
-- @param amount: Amount of health to restore
-- @return: true if fully repaired, false if still damaged
function SubsystemManager.repair(entity_id, subsystem_name, amount)
	local subs = entity_subsystems[entity_id]
	if not subs or not subs[subsystem_name] then
		return true  -- Nothing to repair
	end

	local sub = subs[subsystem_name]
	sub.health = min(sub.max_health, sub.health + amount)

	-- Clear destroyed flag if health is above 0
	if sub.health > 0 and sub.destroyed then
		sub.destroyed = false
		printh("SubsystemManager: " .. entity_id .. " " .. subsystem_name .. " REPAIRED")
	end

	return sub.health >= sub.max_health
end

-- Apply subsystem destruction effects to an entity
-- @param entity: Entity object with id, current_health, and flags
-- @param energy_system: EnergySystem module (for player)
-- @param targeting_system: TargetingSystem module (for player)
-- @param dt: Delta time
function SubsystemManager.apply_effects(entity, energy_system, targeting_system, dt)
	if not entity or not entity.id then return end

	local subs = entity_subsystems[entity.id]
	if not subs then return end

	-- Weapons destroyed: set flag (checked by weapon firing code)
	if subs.weapons and subs.weapons.destroyed then
		entity.weapons_disabled = true
	else
		entity.weapons_disabled = false
	end

	-- Engines destroyed: zero speed, can't turn
	if subs.engines and subs.engines.destroyed then
		entity.engines_disabled = true
		if entity.speed then
			entity.speed = 0
		end
		if entity.current_speed then
			entity.current_speed = 0
		end
	else
		entity.engines_disabled = false
	end

	-- Shields destroyed: disable charging
	if subs.shields and subs.shields.destroyed then
		entity.shields_disabled = true
	else
		entity.shields_disabled = false
	end

	-- Sensors destroyed: lose targeting ability
	if subs.sensors and subs.sensors.destroyed then
		entity.sensors_disabled = true
		-- Clear targeting for player
		if targeting_system and entity.id == "player_ship" then
			targeting_system.clear()
		end
	else
		entity.sensors_disabled = false
	end

	-- Life support destroyed: continuous health drain
	if subs.life_support and subs.life_support.destroyed then
		entity.life_support_disabled = true
		local drain_rate = Config.subsystems.damage_effects.life_support_drain or 2
		if entity.current_health then
			entity.current_health = entity.current_health - (drain_rate * dt)
		end
	else
		entity.life_support_disabled = false
	end
end

-- Draw debug visualization of subsystem hitboxes
-- @param entity_id: Entity identifier
-- @param entity_pos: {x, y, z} entity position
-- @param entity_heading: heading in turns (0-1)
-- @param camera: Camera object
-- @param draw_line_3d_fn: Function to draw 3D lines
function SubsystemManager.draw_debug(entity_id, entity_pos, entity_heading, camera, draw_line_3d_fn)
	local subs = entity_subsystems[entity_id]
	if not subs then return end

	local cos_h = cos(entity_heading)
	local sin_h = sin(entity_heading)

	-- Colors for each subsystem
	local colors = {
		weapons = 8,      -- Red
		engines = 11,     -- Green
		shields = 12,     -- Blue
		sensors = 10,     -- Yellow
		life_support = 9, -- Orange
	}

	for _, name in ipairs(SUBSYSTEM_NAMES) do
		local sub = subs[name]
		if sub then
			local color = sub.destroyed and 5 or colors[name]  -- Gray if destroyed

			-- Transform offset to world space
			local world_x = entity_pos.x + sub.offset.x * cos_h - sub.offset.z * sin_h
			local world_y = entity_pos.y + sub.offset.y
			local world_z = entity_pos.z + sub.offset.x * sin_h + sub.offset.z * cos_h

			-- Draw wireframe box
			local hs = sub.half_size
			local corners = {
				{x = -hs.x, y = -hs.y, z = -hs.z},
				{x = hs.x, y = -hs.y, z = -hs.z},
				{x = hs.x, y = hs.y, z = -hs.z},
				{x = -hs.x, y = hs.y, z = -hs.z},
				{x = -hs.x, y = -hs.y, z = hs.z},
				{x = hs.x, y = -hs.y, z = hs.z},
				{x = hs.x, y = hs.y, z = hs.z},
				{x = -hs.x, y = hs.y, z = hs.z},
			}

			-- Rotate corners by heading and translate
			for i, c in ipairs(corners) do
				local rx = c.x * cos_h - c.z * sin_h
				local rz = c.x * sin_h + c.z * cos_h
				corners[i] = {
					x = world_x + rx,
					y = world_y + c.y,
					z = world_z + rz,
				}
			end

			-- Draw edges
			local edges = {
				{1,2}, {2,3}, {3,4}, {4,1},  -- Front face
				{5,6}, {6,7}, {7,8}, {8,5},  -- Back face
				{1,5}, {2,6}, {3,7}, {4,8},  -- Connecting edges
			}

			for _, edge in ipairs(edges) do
				local c1, c2 = corners[edge[1]], corners[edge[2]]
				draw_line_3d_fn(c1.x, c1.y, c1.z, c2.x, c2.y, c2.z, camera, color)
			end
		end
	end
end

-- Notify that an enemy was damaged (for AI reaction)
-- @param enemy: Enemy object
-- @param attacker_pos: {x, z} position of attacker
function SubsystemManager.on_entity_damaged(enemy, attacker_pos)
	if not enemy then return end

	enemy.last_hit_from = {x = attacker_pos.x, z = attacker_pos.z}
	enemy.last_hit_time = t()
	enemy.under_fire = true

	-- Force immediate AI replanning
	enemy.ai_last_planning_time = 0
	enemy.ai_planning_interval = 0.3  -- Fast reaction
end

return SubsystemManager

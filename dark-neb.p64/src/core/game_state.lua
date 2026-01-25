--[[pod_format="raw",created="2024-11-07 20:00:00",modified="2024-11-07 20:00:00",revision=0]]
-- GameState Module
-- Centralized runtime state management following SOLID principles
-- Single Responsibility: Only manages mutable game state
-- Dependency Inversion: Config injected via init()

local GameState = {}

-- Internal state (private)
local state = nil

-- Initialize all game state from config
-- @param Config: The game configuration object
function GameState.init(Config)
	state = {
		-- ============================================
		-- GAME FLOW STATE
		-- ============================================
		game_state = "menu",  -- "menu", "playing", "out_of_bounds", "game_over", "mission_success"
		is_dead = false,
		death_time = 0,
		mission_success_time = 0,
		out_of_bounds_time = 0,
		is_out_of_bounds = false,
		skip_next_menu_click = false,

		-- ============================================
		-- PLAYER STATE
		-- ============================================
		current_health = Config.health.max_health,
		player_health_obj = {
			id = "player_ship",
			current_health = Config.health.max_health,
			max_health = Config.health.max_health,
			armor = Config.ship.armor,
		},

		-- ============================================
		-- SHIP MOVEMENT STATE
		-- ============================================
		ship_pos = nil,  -- Cached position reference (updated each frame from Config.ship.position)
		ship_speed = Config.ship.speed,
		target_ship_speed = Config.ship.speed,
		slider_speed_desired = Config.ship.speed,
		ship_heading_dir = {x = 0, z = 1},  -- Start facing +Z
		target_heading_dir = {x = 0, z = 1},
		rotation_start_dir = {x = 0, z = 1},
		rotation_progress = 0,

		-- Ship object for collision tracking
		ship = {
			id = "player_ship",
			type = "ship",
			armor = Config.ship.armor,
			collision_cooldown = 0,
		},

		-- ============================================
		-- TARGETING STATE
		-- ============================================
		hovered_target = nil,
		current_selected_target = nil,
		photon_beams = {},

		-- ============================================
		-- WEAPON STATE
		-- ============================================
		selected_weapon = nil,
		weapon_states = {},

		-- ============================================
		-- ENERGY STATE
		-- ============================================
		energy_system = {
			weapons = Config.energy.systems.weapons.allocated,
			impulse = Config.energy.systems.impulse.allocated,
			shields = Config.energy.systems.shields.allocated,
			tractor_beam = Config.energy.systems.tractor_beam.allocated,
			sensors = Config.energy.systems.sensors.allocated,
		},
		no_energy_message = {
			visible = false,
			x = 0,
			y = 0,
			duration = 0,
			max_duration = 1.0,
		},
		energy_block_hitboxes = {},

		-- ============================================
		-- SHIELD STATE
		-- ============================================
		shield_charge = {
			boxes = {0, 0, 0},
			charge_time = Config.energy.systems.shields.charge_time,
		},

		-- ============================================
		-- COLLISION STATE
		-- ============================================
		collision_pairs = {},

		-- ============================================
		-- GAME OBJECTS
		-- ============================================
		enemy_ships = {},
		destroyed_enemies = {},
		active_explosions = {},
		spawned_spheres = {},
		particle_trails = {},

		-- ============================================
		-- MODELS (loaded at runtime)
		-- ============================================
		models = {
			shippy = nil,
			sphere = nil,
			planet = nil,
			satellite = nil,
		},
		planet_rotation = 0,

		-- ============================================
		-- LIGHTING STATE
		-- ============================================
		light_yaw = Config.lighting.yaw,
		light_pitch = Config.lighting.pitch,
		light_brightness = Config.lighting.brightness,
		ambient = Config.lighting.ambient,

		-- ============================================
		-- FRAME COUNTERS
		-- ============================================
		update_frame_counter = 0,
		spawn_timer = 0,
	}

	-- Initialize weapon states
	GameState.init_weapon_states(Config)
end

-- Initialize weapon states from config
function GameState.init_weapon_states(Config)
	state.weapon_states = {}
	for i = 1, #Config.weapons do
		state.weapon_states[i] = {
			charge = 0,
			auto_fire = false,
			hovering = false,
		}
	end
end

-- Get the current state (read-only access pattern)
-- @return: The current game state table
function GameState.get()
	return state
end

-- Reset state for a new game (called when starting from menu)
-- @param Config: The game configuration object
function GameState.reset(Config)
	state.game_state = "playing"
	state.is_dead = false
	state.death_time = 0
	state.mission_success_time = 0
	state.out_of_bounds_time = 0
	state.is_out_of_bounds = false

	-- Reset player health
	state.current_health = Config.health.max_health
	state.player_health_obj.current_health = Config.health.max_health

	-- Reset ship state
	state.ship_speed = Config.ship.speed
	state.target_ship_speed = Config.ship.speed
	state.slider_speed_desired = Config.ship.speed
	state.ship_heading_dir = {x = 0, z = 1}
	state.target_heading_dir = {x = 0, z = 1}

	-- Reset targeting
	state.hovered_target = nil
	state.current_selected_target = nil
	state.photon_beams = {}

	-- Reset enemies
	state.enemy_ships = {}
	state.destroyed_enemies = {}

	-- Reset effects
	state.active_explosions = {}
	state.spawned_spheres = {}
	state.particle_trails = {}

	-- Reset collision tracking
	state.collision_pairs = {}

	-- Reset shields
	state.shield_charge.boxes = {0, 0, 0}

	-- Reinitialize weapon states
	GameState.init_weapon_states(Config)
end

-- Check if a weapon is ready to fire
-- @param weapon_id: weapon index (1-based)
-- @return: true if weapon is fully charged and target is selected
function GameState.is_weapon_ready(weapon_id)
	local weapon_state = state.weapon_states[weapon_id]

	if not state.current_selected_target then
		return false
	end

	if weapon_state.charge < 0.999 then
		return false
	end

	return true
end

-- Sync player health between current_health and player_health_obj
function GameState.sync_player_health()
	state.player_health_obj.current_health = state.current_health
end

-- Set game state with validation
-- @param new_state: One of "menu", "playing", "out_of_bounds", "game_over", "mission_success"
function GameState.set_game_state(new_state)
	local valid_states = {
		menu = true,
		playing = true,
		out_of_bounds = true,
		game_over = true,
		mission_success = true,
	}

	if valid_states[new_state] then
		state.game_state = new_state
	else
		printh("WARNING: Invalid game state: " .. tostring(new_state))
	end
end

-- Get current game state
function GameState.get_game_state()
	return state.game_state
end

-- Handle player death
function GameState.kill_player()
	state.current_health = 0
	state.player_health_obj.current_health = 0
	state.is_dead = true
	state.death_time = 0
	state.game_state = "game_over"
end

-- Check if player is dead
function GameState.is_player_dead()
	return state.is_dead
end

-- Add an explosion to the active explosions list
function GameState.add_explosion(explosion)
	table.insert(state.active_explosions, explosion)
end

-- Add a spawned object (quad/sphere) to the list
function GameState.add_spawned_object(obj)
	table.insert(state.spawned_spheres, obj)
end

-- Add an enemy ship to the list
function GameState.add_enemy(enemy)
	table.insert(state.enemy_ships, enemy)
end

-- Mark an enemy as destroyed
function GameState.mark_enemy_destroyed(enemy_id)
	state.destroyed_enemies[enemy_id] = true
end

-- Check if an enemy is destroyed
function GameState.is_enemy_destroyed(enemy_id)
	return state.destroyed_enemies[enemy_id] == true
end

-- Update energy allocation for a system
-- @param system_name: "weapons", "impulse", "shields", "tractor_beam", or "sensors"
-- @param amount: New allocation amount
function GameState.set_energy(system_name, amount)
	if state.energy_system[system_name] ~= nil then
		state.energy_system[system_name] = amount
	end
end

-- Get energy allocation for a system
function GameState.get_energy(system_name)
	return state.energy_system[system_name] or 0
end

-- Get total allocated energy
function GameState.get_total_energy()
	return state.energy_system.weapons +
	       state.energy_system.impulse +
	       state.energy_system.shields +
	       state.energy_system.tractor_beam +
	       state.energy_system.sensors
end

return GameState

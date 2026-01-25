--[[pod_format="raw",created="2024-11-07 20:00:00",modified="2024-11-07 20:00:00",revision=0]]
-- 3D Model Viewer with Flat Shading
-- Features:
-- - Loads shippy.obj
-- - Flat shading with lighting based on angle from light
-- - Base color (dark) with dithered lighting layer
-- - Mouse orbit camera controls (Y axis up)

-- Require polyfill for Picotron
local _modules = {}

function require(name)
	if _modules[name] == nil then
		_modules[name] = include(name:gsub('%.', '/') .. '.lua')
	end
	return _modules[name]
end

-- Load modules (use include like ld58 does)
Lighting = include("src/lighting.lua")
Renderer = include("src/engine/renderer.lua")
RendererLit = include("src/engine/renderer_lit.lua")
Quat = include("src/engine/quaternion.lua")
MathUtils = include("src/engine/math_utils.lua")
DebugRenderer = include("src/debug_renderer.lua")
ExplosionRenderer = include("src/engine/explosion_renderer.lua")
Explosion = include("src/particles/explosion.lua")
UIRenderer = include("src/ui/ui_renderer.lua")
Panel = include("src/ui/panel.lua")
Button = include("src/ui/button.lua")
ArcUI = include("src/ui/arc_ui.lua")
WeaponsUI = include("src/ui/weapons_ui.lua")
ShipSelection = include("src/ui/ship_selection.lua")
ArcVisualization = include("src/ui/arc_visualization.lua")
DebugVisualization = include("src/ui/debug_visualization.lua")
WeaponEffects = include("src/systems/weapon_effects.lua")
Missions = include("src/systems/missions.lua")
ShipSystems = include("src/systems/ship_systems.lua")
AISystem = include("src/systems/ai_system.lua")
CollisionSystem = include("src/systems/collision_system.lua")
InputSystem = include("src/systems/input_system.lua")
SubsystemManager = include("src/systems/subsystem_manager.lua")
GameState = include("src/core/game_state.lua")
CameraSystem = include("src/systems/camera_system.lua")
StarField = include("src/systems/star_field.lua")
MovementSystem = include("src/systems/movement_system.lua")
SceneRenderer = include("src/rendering/scene_renderer.lua")
Minimap = include("src/minimap.lua")
SubsystemUI = include("src/ui/subsystem_ui.lua")
Menu = include("src/menu.lua")
Config = include("config.lua")

-- ============================================
-- SCENE CONFIGURATION
-- ============================================

-- Camera settings - managed by CameraSystem module
-- Local reference will be set in _init() from CameraSystem.get_camera()
local camera = nil

-- Mouse/input state managed by InputSystem module
local mx, my, mb = 0, 0, 0  -- Updated each frame by InputSystem
local mission_success_time = 0  -- Timer for mission success scene

-- Ship speed and movement state managed by MovementSystem module
-- slider_dragging state managed by InputSystem
local slider_x = Config.slider.x
local slider_y = Config.slider.y
local slider_height = Config.slider.height
local slider_width = Config.slider.width
local slider_handle_height = Config.slider.handle_height

-- Light settings (from config)
local light_yaw = Config.lighting.yaw
local light_pitch = Config.lighting.pitch
local light_brightness = Config.lighting.brightness
local ambient = Config.lighting.ambient

-- Ship heading control - managed by MovementSystem
-- Local reference synced each frame for convenience
local ship_heading_dir = nil  -- Synced from MovementSystem.get_heading_dir()

-- Camera heading is managed by CameraSystem module

-- Raycast intersection for visualization
local raycast_x = nil
local raycast_z = nil

-- Game state
local current_health = Config.health.max_health
local is_dead = false
local destroyed_enemies = {}  -- Track which enemy ships have been destroyed (by ID)
local death_time = 0
local game_state = "menu"  -- "menu", "playing", "out_of_bounds", "game_over"
local out_of_bounds_time = 0  -- Time spent out of bounds
local is_out_of_bounds = false

-- Player health wrapper for smoke spawner registration
-- This allows the smoke spawner to track player health dynamically
local player_health_obj = {
	id = "player_ship",
	current_health = Config.health.max_health,
	max_health = Config.health.max_health,
	armor = Config.ship.armor,
}

-- Explosions
local active_explosions = {}

-- Spawned spheres (persistent objects)
local spawned_spheres = {}

-- Energy system state
local energy_system = {
	weapons = Config.energy.systems.weapons.allocated,
	impulse = Config.energy.systems.impulse.allocated,
	shields = Config.energy.systems.shields.allocated,
	tractor_beam = Config.energy.systems.tractor_beam.allocated,
	sensors = Config.energy.systems.sensors.allocated,
}

-- No energy message feedback
local no_energy_message = {
	visible = false,
	x = 0,
	y = 0,
	duration = 0,
	max_duration = 1.0  -- Show for 1 second
}

-- Shield charging state
local shield_charge = {
	boxes = {},  -- {1: charge_amount, 2: charge_amount, 3: charge_amount}
	charge_time = Config.energy.systems.shields.charge_time,  -- From config
}

-- Initialize shield charges
for i = 1, 3 do
	shield_charge.boxes[i] = 0
end

-- Cached position variables for efficiency
local ship_pos = nil  -- Current ship position (updated each frame)

-- Ship object for collision tracking
local ship = {
	id = "player_ship",
	type = "ship",
	armor = Config.ship.armor,
	collision_cooldown = 0,  -- Cooldown since last collision
}

-- Collision pair tracking is managed by CollisionSystem module

-- Weapon selection and charging state
local selected_weapon = nil  -- Currently selected weapon (1 or 2)
local weapon_states = {}  -- Charging and auto-fire state for each weapon

-- Initialize weapon states
function init_weapon_states()
	weapon_states = {}
	for i = 1, #Config.weapons do
		weapon_states[i] = {
			charge = 0,  -- Charging progress (0 to 1)
			auto_fire = false,  -- Auto-fire toggle
			hovering = false,  -- Hovering over weapon button
		}
	end
end

init_weapon_states()

-- Check if a weapon is ready to fire (charged and has a target)
-- @param weapon_id: weapon index (1-based)
-- @param target: target object to check (passed explicitly to avoid global issues)
-- @return: true if weapon is fully charged and target is selected, false otherwise
function is_weapon_ready(weapon_id, target)
	local state = weapon_states[weapon_id]

	if not target then
		return false  -- No target selected
	end

	if state.charge < 0.999 then
		return false  -- Weapon not fully charged
	end

	-- Add more conditions here as needed (e.g., cooldown, overheat, etc.)
	return true
end

-- Star generation moved to StarField module

-- Calculate light direction from yaw and pitch
function get_light_direction()
	local cy, sy = cos(light_yaw), sin(light_yaw)
	local cp, sp = cos(light_pitch), sin(light_pitch)
	return {
		x = cy * cp,
		y = sp,
		z = sy * cp
	}
end

-- Projection functions moved to CameraSystem module
-- Keep aliases for backward compatibility
project_point = CameraSystem.project_point
local unproject_point = CameraSystem.unproject_point
raycast_to_ground_plane = CameraSystem.raycast_to_ground
build_camera_matrix = CameraSystem.build_matrix

-- Star drawing moved to StarField module

-- Draw a 3D line in world space
function draw_line_3d(x1, y1, z1, x2, y2, z2, camera, color)
	local px1, py1, pz1 = project_point(x1, y1, z1, camera)
	local px2, py2, pz2 = project_point(x2, y2, z2, camera)

	if px1 and px2 and pz1 > 0 and pz2 > 0 then
		line(px1, py1, px2, py2, color)
	end
end

-- Rotation functions now use MathUtils module
local dir_to_quat = MathUtils.dir_to_quat
local quat_to_dir = MathUtils.quat_to_dir
local dir_to_angle = MathUtils.dir_to_angle
local angle_to_dir = MathUtils.angle_to_dir
local angle_difference = MathUtils.angle_difference
local quat_slerp = MathUtils.quat_slerp

-- ============================================
-- PHYSICS AND COLLISION
-- ============================================

-- Draw wireframe box for debug
local function draw_box_wireframe(min_x, min_y, min_z, max_x, max_y, max_z, camera, color)
	-- 8 corners of the box
	local corners = {
		{min_x, min_y, min_z}, {max_x, min_y, min_z},
		{max_x, max_y, min_z}, {min_x, max_y, min_z},
		{min_x, min_y, max_z}, {max_x, min_y, max_z},
		{max_x, max_y, max_z}, {min_x, max_y, max_z},
	}

	-- 12 edges of the box
	local edges = {
		{1,2}, {2,3}, {3,4}, {4,1},  -- Front face
		{5,6}, {6,7}, {7,8}, {8,5},  -- Back face
		{1,5}, {2,6}, {3,7}, {4,8},  -- Connecting edges
	}

	for _, edge in ipairs(edges) do
		local c1 = corners[edge[1]]
		local c2 = corners[edge[2]]
		draw_line_3d(c1[1], c1[2], c1[3], c2[1], c2[2], c2[3], camera, color)
	end
end

-- Draw 2D screen-space bounding box around a 3D object
-- Projects the object center and draws a rectangle on screen
local function draw_2d_selection_box(world_x, world_y, world_z, camera, color, size)
	size = size or 20  -- Default size in pixels
	local screen_x, screen_y = project_point(world_x, world_y, world_z, camera)
	if screen_x and screen_y then
		-- Draw rectangle around the projected point
		rect(screen_x - size, screen_y - size, size * 2, size * 2, color)
	end
end

-- Box vs Sphere collision now handled by CollisionSystem module

-- Model data
local model_shippy = nil
local model_sphere = nil
local model_planet = nil
local model_satellite = nil
local planet_rotation = 0

-- Particle trails managed by MovementSystem

-- Targeting and weapons
local hovered_target = nil  -- Currently hovered target object (satellite, planet, enemy ship, etc)
local current_selected_target = nil  -- Currently selected target object for firing/tracking
-- Camera lock state is managed by CameraSystem module

-- Enemy ships array - holds all targetable enemy objects
-- Structure per object: {
--   id = "satellite_1", "satellite_2", etc,
--   type = "satellite" | "planet" | "enemy_ship",
--   position = {x, y, z},  -- Current position (can be updated dynamically)
--   config = reference to Config object (satellite, planet, etc),
--   model = model data (model_satellite, model_planet, etc),
--   is_destroyed = boolean,
--   health = current_health (mirrors config.current_health)
-- }
local enemy_ships = {}  -- Array of all enemy ships/satellites in the level



-- Geometry functions moved to Geometry module
local Geometry = include("src/engine/geometry.lua")

-- Helper: Create enemy ship object from config
local function create_enemy_from_config(enemy_config, enemy_type, model)
	return {
		id = enemy_config.id,
		type = enemy_type,
		position = {x = enemy_config.position.x, y = enemy_config.position.y, z = enemy_config.position.z},
		config = enemy_config,
		model = model,
		is_destroyed = false,
		health = enemy_config.current_health,
		current_health = enemy_config.current_health,
		max_health = enemy_config.max_health,
		armor = enemy_config.armor,
		collision_cooldown = 0,
		-- Grabon-specific fields (ignored for satellites)
		heading = enemy_config.heading or 0,
		speed = enemy_config.ai and enemy_config.ai.speed or 0,
		ai_target = nil,
		ai_target_detected = false,
		ai_last_weapon_fire_time = {0, 0},
	}
end

-- Helper: Get target position and reference from current_selected_target
local function get_target_pos_ref(target)
	if not target or not target.position then return nil, nil end
	if target.type == "satellite" or target.type == "grabon" then
		return target.position, target
	elseif target.type == "planet" then
		return Config.planet.position, Config.planet
	end
	return nil, nil
end

-- Helper: Fire weapon at target (handles beam, explosion, damage, smoke)
local function fire_weapon_at_target(weapon_id, target_pos, target_ref, weapon_state)
	WeaponEffects.fire_beam(ship_pos, target_pos)
	WeaponEffects.spawn_explosion(target_pos, nil)

	if target_ref.type == "grabon" or target_ref.type == "satellite" then
		WeaponEffects.apply_weapon_damage(ship_pos, target_ref)
	else
		WeaponEffects.spawn_explosion(target_pos, target_ref)
	end

	-- Spawn smoke if heavily damaged
	if target_ref.current_health and target_ref.max_health then
		local health_percent = target_ref.current_health / target_ref.max_health
		if health_percent < 0.3 then
			local smoke_pos = {
				x = target_pos.x + (math.random() - 0.5) * 4,
				y = target_pos.y + 2,
				z = target_pos.z + (math.random() - 0.5) * 4
			}
			WeaponEffects.spawn_smoke(smoke_pos, {x = 0, y = 0.3, z = 0})
		end
	end

	weapon_state.charge = 0
end

function create_sphere(radius, segments, stacks, sprite_id, sprite_w, sprite_h)
	return Geometry.create_sphere(radius, segments, stacks, sprite_id, sprite_w, sprite_h)
end

function create_billboard_quad(half_size, cam)
	return Geometry.create_billboard_quad(half_size, cam)
end

function create_quad(width, height, sprite_id, sprite_w, sprite_h, cam)
	return Geometry.create_quad(width, height, sprite_id, sprite_w, sprite_h)
end

function spawn_quad(x, y, z, width, height, sprite_id, sprite_w, sprite_h, camera_obj, lifetime, dither_enabled)
	local quad_mesh = create_quad(width or 10, height or 10, sprite_id or 19, sprite_w, sprite_h)
	local hw = (width or 10) / 2
	local obj = {
		x = x, y = y, z = z,
		mesh = quad_mesh,
		mesh_half_size = hw,
		lifetime = lifetime,
		age = 0,
		dither_enabled = dither_enabled or false,
		scale = 1.0,
		explosion_opacity = 1.0
	}
	add(spawned_spheres, obj)
	return obj
end

function _init()
	RendererLit.init_color_table()
	CameraSystem.init(Config)
	camera = CameraSystem.get_camera()
	StarField.init(Config)
	EnergySystem = include("src/systems/energy_system.lua")
	EnergySystem.init(Config)
	ShieldSystem = include("src/systems/shield_system.lua")
	ShieldSystem.init(Config)
	SubsystemManager.init(Config)
	SubsystemManager.init_entity("player_ship", "player")
	SubsystemUI.init(Config, SubsystemManager)
	SubsystemUI.init_entity_repair("player_ship", Config.subsystems.repair.starting_kits)
	CollisionSystem.init()
	MovementSystem.init(Config)
	SceneRenderer.init(RendererLit, StarField, CameraSystem)
	WeaponEffects.setup(Config, SubsystemManager, AISystem, SubsystemUI)
	Missions.init(Config)
	Menu.init(Config)
	build_energy_hitboxes()

	UIRenderer.init({panel = Panel, button = Button, minimap = Minimap, menu = Menu}, Config, {
		on_restart = function()
			game_state, is_dead, death_time, out_of_bounds_time, is_out_of_bounds = "menu", false, 0, 0, false
			Missions.init(Config)
			skip_next_menu_click = true
		end,
		on_menu = function()
			game_state, out_of_bounds_time, is_out_of_bounds = "menu", 0, false
		end
	})

	model_sphere = create_sphere(Config.sphere.radius, Config.sphere.segments, Config.sphere.stacks)
	model_planet = create_sphere(Config.planet.radius, Config.planet.segments, Config.planet.stacks, Config.planet.sprite_id, 64, 32)

	local load_obj = require("src.engine.obj_loader")
	model_shippy = load_obj(Config.ship.model_file, Config.ship.sprite_w, Config.ship.sprite_h)

	enemy_ships = {}
	local mission = Config.missions.mission_1
	if mission.satellites and #mission.satellites > 0 then
		model_satellite = load_obj(mission.satellites[1].model_file)
		for _, sat_config in ipairs(mission.satellites) do
			table.insert(enemy_ships, create_enemy_from_config(sat_config, "satellite", model_satellite))
		end
	end
end

-- Load satellites for current mission
function reload_mission_satellites()
	local current_mission_num = Missions.get_current_mission().id
	local mission = current_mission_num == 1 and Config.missions.mission_1 or
	                current_mission_num == 2 and Config.missions.mission_2 or
	                current_mission_num == 3 and Config.missions.mission_3 or Config.missions.mission_4

	enemy_ships = {}
	destroyed_enemies = {}

	local load_obj_func = require("src.engine.obj_loader")

	-- Load satellites for Mission 1 & 2
	if mission.satellites and #mission.satellites > 0 then
		model_satellite = load_obj_func(mission.satellites[1].model_file)
		for _, sat_config in ipairs(mission.satellites) do
			table.insert(enemy_ships, create_enemy_from_config(sat_config, "satellite", model_satellite))
		end
	end

	-- Load Grabon enemies for Mission 3 & 4
	if mission.enemies and #mission.enemies > 0 then
		for _, enemy_config in ipairs(mission.enemies) do
			local model_grabon = load_obj_func(enemy_config.model_file) or model_satellite
			local enemy = create_enemy_from_config(enemy_config, "grabon", model_grabon)
			table.insert(enemy_ships, enemy)
			SubsystemManager.init_entity(enemy.id, "grabon")
			SubsystemUI.init_entity_repair(enemy.id, Config.subsystems.repair.starting_kits)
		end
	end

	-- Load planet position from mission config
	if mission.planet_start then
		Config.planet.position = {x = mission.planet_start.x, y = mission.planet_start.y, z = mission.planet_start.z}
	end
end

-- Update Grabon AI for Mission 3
-- Handles movement, rotation, target detection, and weapon firing
function update_grabon_ai()
	current_health, is_dead = AISystem.update_grabon_ai(enemy_ships, ship_pos, is_dead, player_health_obj, current_health, active_explosions, spawned_spheres, Config, ShipSystems, WeaponEffects, Explosion, shield_charge, angle_to_dir, apply_shield_absorption)
end

-- Shield absorption moved to ShieldSystem module
function apply_shield_absorption()
	return ShieldSystem.try_absorb()
end
-- Energy system functions moved to EnergySystem module
-- Wrapper functions for backward compatibility
function build_energy_hitboxes()
	EnergySystem.build_hitboxes()
end

function draw_energy_bars(mouse_x, mouse_y)
	EnergySystem.draw(mouse_x, mouse_y)
end

function handle_energy_clicks(mx, my)
	local handled = EnergySystem.handle_click(mx, my)
	if handled then
		-- Sync local energy_system with module state
		local es = EnergySystem.get_state()
		energy_system.weapons = es.weapons
		energy_system.impulse = es.impulse
		energy_system.shields = es.shields
		energy_system.tractor_beam = es.tractor_beam
		energy_system.sensors = es.sensors
	end
	return handled
end

local _update_frame_counter = 0

-- Helper: Handle player death
local function handle_player_death()
	current_health = 0
	player_health_obj.current_health = 0
	is_dead = true
	death_time = 0
	game_state = "game_over"
	music(-1)
	if Config.explosion.enabled then
		table.insert(active_explosions, Explosion.new(Config.ship.position.x, Config.ship.position.y, Config.ship.position.z, Config.explosion))
		sfx(3)
	end
end

-- Helper: Process all collisions for this frame
local function process_collisions()
	if is_dead then return end

	-- Planet collision
	if CollisionSystem.check_planet_collision(ship_pos, Config.ship.collider, Config.planet.position, Config.planet.collider.radius) then
		handle_player_death()
		return
	end

	-- Enemy ship collisions
	local collisions = CollisionSystem.process_enemy_collisions(ship.id, ship_pos, Config.ship.collider, enemy_ships)
	for _, event in ipairs(collisions) do
		if event.is_new then printh("COLLISION: Player <> " .. event.enemy.id) end

		local shield_absorbed = apply_shield_absorption()
		if not shield_absorbed then
			WeaponEffects.apply_collision_damage(player_health_obj)
		end
		WeaponEffects.apply_collision_damage(event.enemy)

		current_health = player_health_obj.current_health
		if current_health <= 0 then
			handle_player_death()
			return
		end
	end
end

-- Helper: Update mission objectives and check completion
local function update_mission_objectives()
	Missions.update_dialogs(1/60)
	local m = Missions.get_current_mission()
	local destroyed_count = 0
	for _ in pairs(destroyed_enemies) do destroyed_count = destroyed_count + 1 end

	if m.id == 1 then
		Missions.update_camera_objective(camera.ry, camera.rx)
		Missions.update_rotation_objective(atan2(ship_heading_dir.x, ship_heading_dir.z))
		Missions.update_movement_objective(ship_pos)
	elseif m.id == 2 then
		Missions.update_subsystems_objective(Config.energy)
		Missions.update_targeting_objective(current_selected_target)
		Missions.update_combat_objective(destroyed_count)
	elseif m.id == 3 then
		Missions.update_search_objective(current_selected_target)
		Missions.update_destroy_objective(destroyed_count >= 1)
	elseif m.id == 4 then
		Missions.update_search_objective_m4(current_selected_target)
		Missions.update_destroy_objective_m4(2 - destroyed_count)
	end

	if Missions.check_mission_complete() and not Missions.is_mission_complete() then
		Missions.set_mission_complete()
		mission_success_time = m.id == 2 and -5.0 or (m.id >= 3 and -3.0 or 0)
		game_state = "mission_success"
	end
end

function _update()
	_update_frame_counter = _update_frame_counter + 1

	-- Update energy system (handles no-energy message timer)
	EnergySystem.update(1/60)

	-- Update input system and get mouse state
	local input = InputSystem.update()
	mx, my, mb = input.mouse_x, input.mouse_y, input.mouse_buttons
	local last_mouse_button_state = not input.button_pressed and input.button_held  -- Derive from InputSystem

	-- Sync ship heading from MovementSystem for use in calculations
	ship_heading_dir = MovementSystem.get_heading_dir()



	-- Handle menu input
	if game_state == "menu" then
		local menu_input = {
			select = keyp("return") or keyp("z"),
		}
		-- Block menu clicks until mouse button is released after returning from mission
		if skip_next_menu_click then
			-- Keep blocking until mouse is released
			if (mb & 1) == 0 then
				skip_next_menu_click = false  -- Mouse released, allow clicks again
			end
		end
		local mouse_click = ((mb & 1) == 1) and not skip_next_menu_click

		if Menu.update(menu_input, mx, my, mouse_click) then
			-- Campaign selected, start game
			game_state = "playing"
			is_dead = false
			current_health = Config.health.max_health
			death_time = 0
			out_of_bounds_time = 0
			is_out_of_bounds = false

			-- Reset player health wrapper
			player_health_obj.current_health = current_health

			-- Initialize player subsystems and repair kits
			SubsystemManager.init_entity("player_ship", "player")
			SubsystemUI.init_entity_repair("player_ship", Config.subsystems.repair.starting_kits)

			-- Reset player ship state
			Config.ship.position = {x = 0, y = 0, z = 0}
			Config.ship.heading = 0
			MovementSystem.reset()

			-- Reset mission camera tracking first
			Missions.init(Config)  -- Initialize missions with all state reset

			-- Set up selected mission
			local selected = Menu.get_selected_mission()
			if selected then
				local presets = {
					mission_2 = {advances = 1, w = 0, i = 0, s = 0, sn = 0, t = 0},
					mission_3 = {advances = 2, w = 4, i = 2, s = 0, sn = 0, t = 0},
					mission_4 = {advances = 3, w = 4, i = 2, s = 2, sn = 0, t = 0},
				}
				local p = presets[selected.id]
				if p then
					for _ = 1, p.advances do Missions.advance_mission() end
					Config.energy.systems.weapons.allocated, Config.energy.systems.impulse.allocated = p.w, p.i
					Config.energy.systems.shields.allocated, Config.energy.systems.sensors.allocated = p.s, p.sn
					Config.energy.systems.tractor_beam.allocated = p.t
					energy_system.weapons, energy_system.impulse, energy_system.shields = p.w, p.i, p.s
					energy_system.sensors, energy_system.tractor_beam = p.sn, p.t
				end
			end

			reload_mission_satellites()

			-- Play mission music
			local m = Missions.get_current_mission()
			local mc = (m.id <= 2) and Config.music.missions_1_2 or Config.music.missions_3_4
			if mc then
				fetch(mc.sfx_file):poke(mc.memory_address)
				music(mc.pattern, nil, nil, mc.memory_address)
				poke(0x5539, 0x20)
			end

			-- Register smoke spawners
			WeaponEffects.register_smoke_spawner(player_health_obj, 0.5, function() return {x = 0, y = 0, z = 0} end)
			for _, enemy in ipairs(enemy_ships) do
				WeaponEffects.register_smoke_spawner(enemy, 0.5, function() return enemy.position end)
			end
			return
		end

	-- Skip all gameplay updates while in menu
	return
	end  -- Close if game_state == "menu"

	-- Cache ship position at start of update
	ship_pos = Config.ship.position

	-- Check for objective panel toggle click (top-right corner of dialog panel)
	local panel_toggle_x = Config.mission_ui.dialog_panel_x + Config.mission_ui.dialog_toggle_x_offset
	local panel_toggle_y = Config.mission_ui.dialog_panel_y + Config.mission_ui.dialog_toggle_y_offset
	local panel_toggle_size = Config.mission_ui.dialog_toggle_size
	if (mb & 1 == 1) and not last_mouse_button_state then  -- Click detected
		if mx >= panel_toggle_x and mx <= panel_toggle_x + panel_toggle_size and my >= panel_toggle_y and my <= panel_toggle_y + panel_toggle_size then
			Missions.toggle_objective_panel()
		end
	end

	-- Check mouse over UI elements
	local over_slider = mx >= slider_x - 5 and mx <= slider_x + slider_width + 5 and my >= slider_y and my <= slider_y + slider_height
	local ec = Config.energy
	local num_vis = 0
	for _, s in ipairs({"weapons", "impulse", "shields", "tractor_beam", "sensors"}) do
		if not ec.systems[s].hidden then num_vis = num_vis + 1 end
	end
	local over_energy_ui = mx >= ec.ui_x and mx < ec.ui_x + ec.system_bar_x_offset + 4 * (ec.bar_width + ec.bar_spacing) and
	                       my >= ec.ui_y and my < ec.ui_y + (num_vis - 1) * ec.system_spacing + ec.bar_height + 5
	local button_pressed = (mb & 1 == 1) and not last_mouse_button_state
	local button_held = (mb & 1 == 1)

	if button_held then
		if game_state == "playing" and over_slider then
			InputSystem.start_slider_drag()
			MovementSystem.set_slider_speed(1 - mid(0, (my - slider_y) / slider_height, 1))
		elseif game_state == "playing" and over_energy_ui and button_pressed then
			build_energy_hitboxes()
			handle_energy_clicks(mx, my)
		elseif button_pressed then
			if Missions.check_ok_button_click(mx, my, button_pressed, Config) then
				game_state, skip_next_menu_click = "menu", true
				Missions.init(Config)
			elseif WeaponsUI.is_show_arcs_toggle_clicked(mx, my) then
				Config.show_firing_arcs = not Config.show_firing_arcs
			elseif game_state == "playing" then
				local weapon_id = WeaponsUI.get_weapon_at_point(mx, my, Config)
				if weapon_id then
					local w, s = Config.weapons[weapon_id], weapon_states[weapon_id]
					if energy_system.weapons >= w.energy_cost and s.charge >= 1.0 and current_selected_target then
						local tp, tr = get_target_pos_ref(current_selected_target)
						if tp and tr and ShipSystems.is_in_range(ship_pos, tp, w.range) and
						   ShipSystems.is_in_firing_arc(ship_pos, ship_heading_dir, tp, w.arc_start, w.arc_end) then
							fire_weapon_at_target(weapon_id, tp, tr, s)
						end
					else selected_weapon = weapon_id end
				else
					local toggle_id = WeaponsUI.get_toggle_at_point(mx, my, Config)
					if toggle_id then weapon_states[toggle_id].auto_fire = not weapon_states[toggle_id].auto_fire end
				end
			end
		elseif not InputSystem.is_slider_dragging() then
			-- If camera is locked to target, left-click unsnaps it
			if CameraSystem.is_locked() then
				CameraSystem.unlock()
				printh("Camera unsnapped from target!")
			end
			-- Camera orbit (free rotate when not locked)
			if not CameraSystem.is_locked() and input.drag_active then
				CameraSystem.apply_orbit(input.drag_dx, input.drag_dy, Config.camera.orbit_sensitivity)
			end
		end
	else
		-- Button released - InputSystem.update() already resets drag state
		InputSystem.stop_slider_drag()
	end

	-- Always update raycast position for crosshair visualization
	raycast_x, raycast_z = raycast_to_ground_plane(mx, my, camera)

	-- Check if mouse is hovering over any enemy
	hovered_target = nil
	for _, enemy in ipairs(enemy_ships) do
		if enemy.position and not enemy.is_destroyed then
			local px, py = project_point(enemy.position.x, enemy.position.y, enemy.position.z, camera)
			if px and py and sqrt((mx - px)^2 + (my - py)^2) < 20 then
				hovered_target = enemy
				break
			end
		end
	end

	-- Right-click to set ship heading or select target
	if game_state == "playing" and mb & 2 == 2 and not (mb & 1 == 1) then
		if hovered_target then
			current_selected_target = hovered_target
			CameraSystem.lock_to_target(hovered_target)
		elseif raycast_x and raycast_z then
			local dir_x = raycast_x - Config.ship.position.x
			local dir_z = raycast_z - Config.ship.position.z
			if sqrt(dir_x * dir_x + dir_z * dir_z) > 0.0001 then
				MovementSystem.set_target_heading(dir_x, dir_z)
			end
		end
	end

	-- Z button to cycle through enemies
	if game_state == "playing" and btnp(4) then
		local valid_targets = {}
		for _, enemy in ipairs(enemy_ships) do
			if not enemy.is_destroyed then add(valid_targets, enemy) end
		end
		if #valid_targets > 0 then
			local current_index = 0
			for i, enemy in ipairs(valid_targets) do
				if current_selected_target and enemy.id == current_selected_target.id then current_index = i break end
			end
			current_selected_target = valid_targets[(current_index % #valid_targets) + 1]
			CameraSystem.lock_to_target(current_selected_target)
		end
	end

	-- Arrow keys to rotate ship
	if game_state == "playing" then
		if btn(1) then MovementSystem.rotate_target_heading(-Config.ship.arrow_key_rotation_speed) end
		if btn(0) then MovementSystem.rotate_target_heading(Config.ship.arrow_key_rotation_speed) end
	end

	-- Debug controls
	if Config.debug_lighting then
		local spd = Config.lighting.rotation_speed
		if keyp("left") or keyp("a") then light_yaw = light_yaw - spd end
		if keyp("right") or keyp("d") then light_yaw = light_yaw + spd end
		if keyp("up") or keyp("w") then light_pitch = light_pitch - spd end
		if keyp("down") or keyp("s") then light_pitch = light_pitch + spd end
		light_pitch = mid(-1.5, light_pitch, 1.5)
	end
	if Config.debug then
		if keyp("o") then DebugVisualization.adjust_mask_offset(-1) end
		if keyp("p") then DebugVisualization.adjust_mask_offset(1) end
	end
	if Config.enable_x_button and keyp("x") then
		local target_pos = (#enemy_ships > 0 and model_satellite) and enemy_ships[1].position or (model_planet and Config.planet.position)
		if target_pos then WeaponEffects.fire_beam(ship_pos, target_pos) end
	end

	-- Update weapon charging
	for i = 1, #Config.weapons do
		local w, s = Config.weapons[i], weapon_states[i]
		if energy_system.weapons >= w.energy_cost then
			s.charge = min(1.0, s.charge + 1/60 / w.charge_time)
		else s.charge = 0 end
	end

	ShieldSystem.update(1/60, energy_system.shields)

	-- Handle auto-fire
	if game_state == "playing" then
		for i = 1, #Config.weapons do
			local s = weapon_states[i]
			if s.auto_fire and is_weapon_ready(i, current_selected_target) then
				local target_pos, target_ref = get_target_pos_ref(current_selected_target)
				if target_pos and target_ref and ship_pos then
					local w = Config.weapons[i]
					if ShipSystems.is_in_range(ship_pos, target_pos, w.range) and
					   ShipSystems.is_in_firing_arc(ship_pos, ship_heading_dir, target_pos, w.arc_start, w.arc_end) then
						fire_weapon_at_target(i, target_pos, target_ref, s)
					end
				end
			end
		end
	end

	CameraSystem.update(ship_pos, current_selected_target, Config)
	local movement_delta = MovementSystem.update(energy_system.impulse, Config.energy.systems.impulse.capacity, is_dead)
	Config.ship.position.x = Config.ship.position.x + movement_delta.dx
	Config.ship.position.z = Config.ship.position.z + movement_delta.dz
	MovementSystem.update_particles(ship_pos, is_dead)
	planet_rotation = planet_rotation + Config.planet.spin_speed
	process_collisions()

	-- Update AI and subsystems
	local mission_id = Missions.get_current_mission().id
	if game_state == "playing" and (mission_id == 3 or mission_id == 4) then update_grabon_ai() end
	if game_state == "playing" then
		SubsystemManager.apply_effects(player_health_obj, nil, nil, 0.016)
		for _, enemy in ipairs(enemy_ships) do
			if not enemy.is_destroyed then
				SubsystemManager.apply_effects(enemy, nil, nil, 0.016)
				-- Auto-queue repairs for damaged enemy subsystems
				SubsystemUI.auto_queue_repairs(enemy.id)
			end
		end
		current_health = player_health_obj.current_health
		SubsystemUI.update(0.016)
	end

	-- Check if ship is out of bounds (only during gameplay)
	if game_state == "playing" and not is_dead then
		if Minimap.is_out_of_bounds(Config.ship.position) then
			if not is_out_of_bounds then
				-- Just went out of bounds
				is_out_of_bounds = true
				out_of_bounds_time = 0
				game_state = "out_of_bounds"
			end
		else
			-- Back in bounds
			is_out_of_bounds = false
			game_state = "playing"
		end
	end

	-- Update explosions and spawn their quads
	for i = #active_explosions, 1, -1 do
		local explosion = active_explosions[i]

		-- Update explosion (returns false if dead)
		if not explosion:update(0.016) then  -- 60fps = ~0.016s per frame
			table.remove(active_explosions, i)
		else
			-- Spawn quads for this explosion on first frame only
			if explosion.age <= 0.016 then
				for _, p in ipairs(explosion.particles) do
					p.quad_obj = spawn_quad(p.x, p.y, p.z, 10, 10, explosion.sprite_id, 64, 64, camera, explosion.lifetime, true)
				end
			end
			local state = explosion:get_state()
			for _, p in ipairs(explosion.particles) do
				if p.quad_obj then p.quad_obj.scale, p.quad_obj.explosion_opacity = state.scale, state.opacity end
			end
		end
	end

	-- Update spawned quads
	for i = #spawned_spheres, 1, -1 do
		local obj = spawned_spheres[i]
		if obj.lifetime then
			obj.age = obj.age + 0.016
			if obj.age >= obj.lifetime then table.remove(spawned_spheres, i) end
		end
	end

	if is_dead then death_time = death_time + 0.016 end
	WeaponEffects.update(0.016)

	-- Check for destroyed enemies
	for _, enemy in ipairs(enemy_ships) do
		if not destroyed_enemies[enemy.id] and enemy.current_health <= 0 then
			destroyed_enemies[enemy.id] = true
			enemy.is_destroyed = true
			WeaponEffects.unregister_smoke_spawner(enemy)
			table.insert(active_explosions, Explosion.new(enemy.position.x, enemy.position.y, enemy.position.z, Config.explosion))
			sfx(3)
			if current_selected_target and current_selected_target.id == enemy.id then
				selected_weapon, current_selected_target = nil, nil
				CameraSystem.unlock()
			end
		end
	end

	-- Update missions (only during gameplay)
	if game_state == "playing" then
		update_mission_objectives()
	end

	-- Update mouse button state for next frame's click detection
	last_mouse_button_state = (mb & 1) == 1
end

-- Draw sun as a billboard sprite positioned opposite to light direction
-- Draw sun via SceneRenderer
local function draw_sun()
	local light_dir = get_light_direction()
	SceneRenderer.draw_sun(camera, light_dir, Config, project_point)
end

-- UI functions moved to modules
function draw_no_energy_message()
	EnergySystem.draw_no_energy_message()
end

function draw_shield_status()
	ShieldSystem.draw(energy_system.shields)
end

function _draw()
	cls(0)  -- Clear to dark blue

	-- Get mouse position once for use throughout draw function
	local mx, my, mb = mouse()

	-- Handle +/- keys for camera zoom
	if keyp("=") or keyp("+") then
		-- Zoom in (decrease camera distance)
		camera.distance = camera.distance - 2
		camera.distance = max(Config.camera.min_distance, camera.distance)  -- Clamp minimum
	end
	if keyp("-") or keyp("_") then
		-- Zoom out (increase camera distance)
		camera.distance = camera.distance + 2
		camera.distance = min(Config.camera.max_distance, camera.distance)  -- Clamp maximum
	end

	-- ========================================
	-- BACKGROUND (Draw first)
	-- ========================================

	-- Draw stars first (before everything else)
	StarField.draw(camera)

	-- Draw sun after stars, but before all 3D objects
	draw_sun()

	if not model_shippy then
		print("no model loaded!", 10, 50, 8)
		return
	end

	-- ========================================
	-- GEOMETRY (3D models and faces)
	-- ========================================

	local all_faces = {}

	-- Calculate current light direction from yaw and pitch
	local light_dir = get_light_direction()

	-- Render planet with lit shader (same as ship)
	-- Check mission config for show_planet flag
	local current_mission = Missions.get_current_mission()
	local mission_config = current_mission.id == 1 and Config.missions.mission_1 or
	                        current_mission.id == 2 and Config.missions.mission_2 or
	                        current_mission.id == 3 and Config.missions.mission_3 or
	                        Config.missions.mission_4
	local show_planet = mission_config and mission_config.show_planet ~= false
	if model_planet and show_planet then
		local planet_pos = Config.planet.position
		local planet_rot = Config.planet.rotation

		local planet_faces = RendererLit.render_mesh(
			model_planet.verts, model_planet.faces, camera,
			planet_pos.x, planet_pos.y, planet_pos.z,
			nil,  -- sprite override (use sprite from model = sprite 24)
			light_dir,  -- light direction (directional light)
			nil,  -- light radius (unused for directional)
			light_brightness,  -- light brightness
			ambient,  -- ambient light
			false,  -- is_ground
			planet_rot.pitch, planet_rotation, planet_rot.roll,  -- Use planet_rotation for yaw
			Config.camera.render_distance
		)

		-- Add planet faces to all_faces
		for i = 1, #planet_faces do
			add(all_faces, planet_faces[i])
		end
	end

	-- Render ship (from config) - skip if ship has been dead for configured time
	if model_shippy and ship_pos and (not is_dead or death_time < Config.health.ship_disappear_time) then
		local ship_rot = Config.ship.rotation
		local ship_yaw = dir_to_angle(ship_heading_dir) + 0.25  -- Convert direction to angle, add 90° offset for model alignment
		local shippy_faces = RendererLit.render_mesh(
			model_shippy.verts, model_shippy.faces, camera,
			ship_pos.x, ship_pos.y, ship_pos.z,
			Config.ship.sprite_id,  -- sprite override (use sprite from config)
			light_dir,  -- light direction (directional light)
			nil,  -- light radius (unused for directional)
			light_brightness,  -- light brightness
			ambient,  -- ambient light
			false,  -- is_ground
			ship_rot.pitch, ship_yaw, ship_rot.roll,  -- Use direction-derived yaw
			Config.camera.render_distance
		)

		-- Add all faces
		for i = 1, #shippy_faces do
			add(all_faces, shippy_faces[i])
		end
	end

	-- Render all enemy ships (satellites and grabons)
	for _, enemy in ipairs(enemy_ships) do
		if enemy.position and not enemy.is_destroyed then
			local model = enemy.type == "satellite" and model_satellite or enemy.model
			if model then
				local rot = enemy.config.rotation or {pitch=0, yaw=0, roll=0}
				local yaw = enemy.type == "grabon" and (enemy.heading + 0.25) or rot.yaw
				local faces = RendererLit.render_mesh(model.verts, model.faces, camera,
					enemy.position.x, enemy.position.y, enemy.position.z,
					enemy.config.sprite_id, light_dir, nil, light_brightness, ambient, false,
					rot.pitch or 0, yaw, rot.roll or 0, Config.camera.render_distance)
				for i = 1, #faces do add(all_faces, faces[i]) end
			end
		end
	end

	-- Render effects
	SceneRenderer.render_spawned_objects(spawned_spheres, camera, all_faces, Config, model_sphere, create_billboard_quad, RendererLit, light_dir, light_brightness, ambient)
	ExplosionRenderer.render_explosions(active_explosions, camera, all_faces)
	WeaponEffects.render_beams(camera, all_faces)
	WeaponEffects.render_explosions(camera, all_faces)
	WeaponEffects.render_smoke(camera, all_faces)
	RendererLit.sort_faces(all_faces)
	RendererLit.draw_faces(all_faces)

	-- 3D overlays
	SceneRenderer.render_particle_trails(MovementSystem.get_particles(), ship_pos, camera, Config, project_point)
	SceneRenderer.render_crosshair(raycast_x, raycast_z, ship_pos, camera, Config, project_point)

	-- UI
	local weapons_disabled = player_health_obj.weapons_disabled or false
	WeaponsUI.draw_weapons(energy_system, selected_weapon, weapon_states, Config, mx, my, ship_pos, ship_heading_dir, current_selected_target, WeaponEffects, ShipSystems, camera, draw_line_3d, weapons_disabled)

	if game_state == "playing" then
		local m = Missions.get_current_mission()
		if m and m.destination then Missions.draw_destination_marker(m.destination, camera, draw_line_3d) end
	end

	-- Speed slider
	rectfill(slider_x, slider_y, slider_x + slider_width, slider_y + slider_height, 1)
	local current_speed = MovementSystem.get_speed()
	local fill_h = current_speed * slider_height
	if fill_h > 0 then rectfill(slider_x, slider_y + slider_height - fill_h, slider_x + slider_width, slider_y + slider_height, 11) end
	rect(slider_x, slider_y, slider_x + slider_width, slider_y + slider_height, 7)
	local handle_y = mid(slider_y, slider_y + (1 - MovementSystem.get_slider_speed()) * slider_height - slider_handle_height / 2, slider_y + slider_height - slider_handle_height)
	rectfill(slider_x - 2, handle_y, slider_x + slider_width + 2, handle_y + slider_handle_height, 7)
	rect(slider_x - 2, handle_y, slider_x + slider_width + 2, handle_y + slider_handle_height, 6)
	print(Config.slider.text_prefix .. flr(current_speed * Config.ship.max_speed * 10) / 10, slider_x + Config.slider.text_x_offset, slider_y + slider_height + Config.slider.text_y_offset, Config.slider.text_color)

	-- Arc visualizations
	local utilities = {draw_line_3d = draw_line_3d, dir_to_quat = dir_to_quat, quat_to_dir = quat_to_dir, project_to_screen = project_point, Renderer = Renderer}
	ArcVisualization.draw_all_arcs(ship_heading_dir, MovementSystem.get_target_heading_dir(), current_selected_target, ship_pos, camera, Config, WeaponEffects, ArcUI, utilities, angle_to_dir, angle_difference, ShipSystems)

	if Config.debug_physics and ship_pos then
		DebugVisualization.draw_physics_debug(ship_pos, show_planet, spawned_spheres, enemy_ships, Config, camera, draw_box_wireframe, draw_line_3d, DebugRenderer, angle_to_dir)
	end

	ShipSelection.draw_selection_boxes(enemy_ships, current_selected_target, hovered_target, ship_pos, camera, project_point, Config)
	UIRenderer.draw_health_bar(Config, current_health)
	draw_energy_bars(mx, my)
	draw_no_energy_message()
	draw_shield_status()
	ShipSelection.draw_target_health(current_selected_target, camera, project_point)

	-- Minimap
	if game_state == "playing" then
		local sat_pos, sat_in_range = nil, false
		if #enemy_ships > 0 and model_satellite then
			sat_pos = enemy_ships[1].position
			local dx, dz = sat_pos.x - Config.ship.position.x, sat_pos.z - Config.ship.position.z
			sat_in_range = sqrt(dx*dx + dz*dz) <= enemy_ships[1].config.sensor_range
		end
		UIRenderer.draw_minimap(Config.ship.position, Config.planet.position, Config.planet.radius, sat_pos, sat_in_range)

		-- Draw subsystem UI displays
		local sub_ui = Config.subsystems.ui
		-- Find nearest enemy for player incoming attack indicator
		local nearest_enemy_pos = nil
		local nearest_dist = 9999
		local player_pos = Config.ship.position
		for _, enemy in ipairs(enemy_ships) do
			if not enemy.is_destroyed and enemy.position then
				local dx = enemy.position.x - player_pos.x
				local dz = enemy.position.z - player_pos.z
				local dist = sqrt(dx*dx + dz*dz)
				if dist < nearest_dist then
					nearest_dist = dist
					nearest_enemy_pos = enemy.position
				end
			end
		end

		-- Clear hover state before drawing
		SubsystemUI.clear_hover()

		-- Draw target subsystem display (if target selected)
		if current_selected_target and not current_selected_target.is_destroyed then
			SubsystemUI.draw_target(current_selected_target, player_pos, sub_ui.target_x, sub_ui.target_y, mx, my)
		end

		-- Draw player subsystem display
		local player_heading = atan2(ship_heading_dir.x, ship_heading_dir.z)
		local input_state = InputSystem.get_input()
		SubsystemUI.draw_player("player_ship", nearest_enemy_pos, player_pos, player_heading, sub_ui.player_x, sub_ui.player_y, mx, my, input_state.button_pressed)

		-- Draw hover tooltip (after both displays)
		SubsystemUI.draw_hover_tooltip()
	end

	-- Death screen
	if is_dead and game_state == "game_over" then
		death_time = death_time + 1/60
		if death_time >= Config.health.death_screen_delay then
			UIRenderer.get_buttons().restart_button:update(mx, my, (mb & 1) == 1)
			UIRenderer.draw_death_screen()
		end
	end

	-- Out of bounds warning
	if is_out_of_bounds and game_state == "out_of_bounds" then
		out_of_bounds_time = out_of_bounds_time + 1/60
		local remaining = mid(0, Config.battlefield.out_of_bounds_warning_time - out_of_bounds_time, Config.battlefield.out_of_bounds_warning_time)
		UIRenderer.get_buttons().back_to_menu_button:update(mx, my, (mb & 1) == 1)
		UIRenderer.draw_out_of_bounds(remaining)
		if out_of_bounds_time >= Config.battlefield.out_of_bounds_warning_time then
			game_state, out_of_bounds_time, is_out_of_bounds = "menu", 0, false
		end
	end

	if game_state == "menu" then UIRenderer.draw_menu() end

	-- Mission success screen
	if game_state == "mission_success" then
		mission_success_time = mission_success_time + 1/60
		if mission_success_time >= 0 and UIRenderer.draw_mission_success(Missions.get_current_mission().id, mx, my, mb) then
			game_state, mission_success_time, skip_next_menu_click = "menu", 0, true
			Missions.init(Config)
		end
	end

	-- Debug
	UIRenderer.draw_cpu_stats(Config)
	if Config.debug then
		DebugVisualization.draw_weapon_hitboxes(WeaponsUI, Config, mx, my)
		DebugVisualization.draw_camera_info(camera, ship_heading_dir, MovementSystem.get_target_heading_dir(), raycast_x, raycast_z)
		DebugVisualization.draw_full_debug_ui(all_faces, RendererLit)
	end

	-- Draw help panel overlay LAST (on top of absolutely everything)
	if game_state == "playing" then
		Missions.draw_help_panel(mx, my, Config)
	end
end

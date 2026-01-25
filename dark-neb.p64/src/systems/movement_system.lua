--[[pod_format="raw",created="2024-11-07 20:00:00",modified="2024-11-07 20:00:00",revision=0]]
-- MovementSystem Module
-- Handles ship movement, rotation, and particle trails
-- Single Responsibility: Only manages movement mechanics

local MovementSystem = {}

-- Internal state
local state = {
	ship_speed = 0,
	target_ship_speed = 0,
	slider_speed_desired = 0,
	ship_heading_dir = {x = 0, z = 1},
	target_heading_dir = {x = 0, z = 1},
	particle_trails = {},
	spawn_timer = 0,
}

-- Config reference
local Config = nil

-- Initialize movement system
function MovementSystem.init(config)
	Config = config
	state.ship_speed = config.ship.speed
	state.target_ship_speed = config.ship.speed
	state.slider_speed_desired = config.ship.speed
	state.ship_heading_dir = {x = 0, z = 1}
	state.target_heading_dir = {x = 0, z = 1}
	state.particle_trails = {}
	state.spawn_timer = 0
end

-- Reset movement state for new game
function MovementSystem.reset()
	state.ship_speed = Config.ship.speed
	state.target_ship_speed = Config.ship.speed
	state.slider_speed_desired = Config.ship.speed
	state.ship_heading_dir = {x = 0, z = 1}
	state.target_heading_dir = {x = 0, z = 1}
	state.particle_trails = {}
	state.spawn_timer = 0
end

-- Set desired speed from slider
function MovementSystem.set_slider_speed(value)
	state.slider_speed_desired = value
end

-- Get current slider speed
function MovementSystem.get_slider_speed()
	return state.slider_speed_desired
end

-- Get current ship speed
function MovementSystem.get_speed()
	return state.ship_speed
end

-- Get ship heading direction
function MovementSystem.get_heading_dir()
	return state.ship_heading_dir
end

-- Get target heading direction
function MovementSystem.get_target_heading_dir()
	return state.target_heading_dir
end

-- Set target heading direction (from mouse raycast)
function MovementSystem.set_target_heading(dir_x, dir_z)
	local len = sqrt(dir_x * dir_x + dir_z * dir_z)
	if len > 0.0001 then
		state.target_heading_dir = {x = dir_x / len, z = dir_z / len}
	end
end

-- Rotate target heading by angle (for arrow key controls)
function MovementSystem.rotate_target_heading(delta_angle)
	local current_angle = atan2(state.target_heading_dir.x, state.target_heading_dir.z)
	local new_angle = current_angle + delta_angle
	state.target_heading_dir = {
		x = cos(new_angle),
		z = sin(new_angle)
	}
end

-- Update ship movement and rotation
-- @param impulse_energy: Current impulse energy allocation
-- @param max_impulse: Maximum impulse capacity
-- @param is_dead: Whether player is dead
-- @return: Movement delta {dx, dz}
function MovementSystem.update(impulse_energy, max_impulse, is_dead)
	-- Calculate impulse energy multiplier
	local impulse_multiplier = impulse_energy / max_impulse

	-- Apply impulse multiplier to get actual target speed
	state.target_ship_speed = state.slider_speed_desired * impulse_multiplier

	-- Smooth ship speed (lerp towards target)
	state.ship_speed = state.ship_speed + (state.target_ship_speed - state.ship_speed) * Config.ship.speed_smoothing

	-- Update rotation
	local current_angle = atan2(state.ship_heading_dir.x, state.ship_heading_dir.z)
	local target_angle = atan2(state.target_heading_dir.x, state.target_heading_dir.z)

	-- Calculate shortest angular difference (wraps around 0/1 boundary)
	local angle_diff = target_angle - current_angle
	if angle_diff > 0.5 then
		angle_diff = angle_diff - 1
	elseif angle_diff < -0.5 then
		angle_diff = angle_diff + 1
	end

	-- Only rotate if not already at target
	if abs(angle_diff) > 0.001 then
		-- Determine direction and apply rotation
		local rotation_amount = angle_diff > 0 and Config.ship.turn_rate or -Config.ship.turn_rate
		local new_angle = current_angle + rotation_amount

		-- Convert back to direction vector
		state.ship_heading_dir.x = cos(new_angle)
		state.ship_heading_dir.z = sin(new_angle)

		-- Normalize to handle floating point drift
		local len = sqrt(state.ship_heading_dir.x * state.ship_heading_dir.x + state.ship_heading_dir.z * state.ship_heading_dir.z)
		if len > 1 then
			state.ship_heading_dir.x = state.ship_heading_dir.x / len
			state.ship_heading_dir.z = state.ship_heading_dir.z / len
		end

		-- Sync heading to Config for weapon calculations
		Config.ship.heading = new_angle
	end

	-- Calculate movement delta
	local dx, dz = 0, 0
	if not is_dead and state.ship_speed > 0.01 then
		local move_speed = state.ship_speed * Config.ship.max_speed * 0.1
		dx = state.ship_heading_dir.x * move_speed
		dz = state.ship_heading_dir.z * move_speed
	end

	return {dx = dx, dz = dz}
end

-- Update particle trails
-- @param ship_pos: Current ship position {x, y, z}
-- @param is_dead: Whether player is dead
function MovementSystem.update_particles(ship_pos, is_dead)
	local dt = 1/60

	-- Update existing particles
	local i = 1
	while i <= #state.particle_trails do
		local cube = state.particle_trails[i]
		cube.age = cube.age + dt
		if cube.age >= cube.lifetime then
			table.remove(state.particle_trails, i)
		else
			i = i + 1
		end
	end

	-- Spawn new particles if alive and moving
	if not is_dead and state.ship_speed > 0.01 then
		state.spawn_timer = state.spawn_timer + dt

		if state.spawn_timer >= Config.particles.spawn_rate then
			state.spawn_timer = 0

			-- Random point in sphere
			local scatter_radius = 30
			local scatter_x = (rnd(2) - 1) * scatter_radius
			local scatter_y = (rnd(2) - 1) * scatter_radius
			local scatter_z = (rnd(2) - 1) * scatter_radius

			-- Normalize to sphere surface and scale
			local dist_sq = scatter_x * scatter_x + scatter_y * scatter_y + scatter_z * scatter_z
			local dist = sqrt(dist_sq)
			if dist > 0.01 then
				local scale = (rnd(1) ^ (1/3)) * scatter_radius / dist
				scatter_x = scatter_x * scale
				scatter_y = scatter_y * scale
				scatter_z = scatter_z * scale
			end

			-- Spawn position
			local spawn_x = ship_pos.x + scatter_x
			local spawn_y = ship_pos.y + scatter_y
			local spawn_z = ship_pos.z + scatter_z

			-- Velocity based on heading
			local vel_magnitude = state.ship_speed * Config.particles.line_length
			local vel_x = -state.ship_heading_dir.x * vel_magnitude
			local vel_z = -state.ship_heading_dir.z * vel_magnitude

			-- End position
			local end_x = spawn_x + vel_x
			local end_y = spawn_y
			local end_z = spawn_z + vel_z

			-- Add particle
			add(state.particle_trails, {
				x1 = spawn_x, y1 = spawn_y, z1 = spawn_z,
				x2 = end_x, y2 = end_y, z2 = end_z,
				age = 0,
				lifetime = Config.particles.lifetime,
				color = Config.particles.color
			})
		end
	end
end

-- Get particle trails for rendering
function MovementSystem.get_particles()
	return state.particle_trails
end

-- Get full state (for debugging)
function MovementSystem.get_state()
	return state
end

return MovementSystem

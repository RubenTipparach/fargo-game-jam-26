--[[pod_format="raw",created="2024-11-07 20:00:00",modified="2024-11-07 20:00:00",revision=0]]
-- AI System Module
-- Handles enemy AI behavior including movement, rotation, target detection, and weapon firing

local AISystem = {}

-- AI States
local AI_STATE = {
	IDLE = "idle",
	ATTACK = "attack",
	RETREAT = "retreat",
	EVADE = "evade",
	CLOSE_DISTANCE = "close_distance",
	MAINTAIN_DISTANCE = "maintain_distance"
}

-- AI planning update interval (in seconds)
local AI_PLANNING_INTERVAL_MIN = 3.0
local AI_PLANNING_INTERVAL_MAX = 5.0

-- AI distance constants
local AI_MIN_DISTANCE = 20  -- Minimum safe distance from player (triggers EVADE)

-- Determine AI state based on conditions
-- @param enemy: enemy ship data
-- @param target_distance: distance to player
-- @param collision_detected: whether collision is imminent
-- @param ai: AI configuration
-- @return: AI state
local function determine_ai_state(enemy, target_distance, collision_detected, ai)
	local health_percent = enemy.current_health / enemy.max_health

	-- Priority 1: Evade collision
	if collision_detected then
		return AI_STATE.EVADE
	end

	-- Priority 2: Evade if too close to player (minimum safe distance)
	if target_distance < AI_MIN_DISTANCE then
		return AI_STATE.EVADE
	end

	-- Priority 3: Retreat if low health
	if health_percent < 0.2 then
		return AI_STATE.RETREAT
	end

	-- Priority 4: Close distance if too far
	if target_distance > ai.attack_range then
		return AI_STATE.CLOSE_DISTANCE
	end

	-- Priority 5: Maintain attack distance
	if target_distance < ai.attack_range * 0.5 then
		return AI_STATE.MAINTAIN_DISTANCE
	end

	-- Default: Attack
	return AI_STATE.ATTACK
end

-- Calculate desired heading direction based on AI state
-- Ships move in the direction they face, so this determines both heading and movement
-- @param state: current AI state
-- @param enemy_pos: enemy position
-- @param player_pos: player position
-- @param collision_obstacle: nearest obstacle position (if any)
-- @return: desired heading direction vector {x, z}
local function calculate_desired_heading(state, enemy_pos, player_pos, collision_obstacle)
	local dx = player_pos.x - enemy_pos.x
	local dz = player_pos.z - enemy_pos.z
	local dist = math.sqrt(dx*dx + dz*dz)

	if state == AI_STATE.RETREAT then
		-- Face and move away from player
		return {x = -dx / dist, z = -dz / dist}

	elseif state == AI_STATE.EVADE then
		-- If there's a collision obstacle, face perpendicular to it
		if collision_obstacle then
			local odx = collision_obstacle.x - enemy_pos.x
			local odz = collision_obstacle.z - enemy_pos.z
			local odist = math.sqrt(odx*odx + odz*odz)
			-- Perpendicular vector (rotate 90 degrees)
			return {x = -odz / odist, z = odx / odist}
		else
			-- No collision obstacle, evading because too close to player - face away
			return {x = -dx / dist, z = -dz / dist}
		end

	elseif state == AI_STATE.CLOSE_DISTANCE then
		-- Face and move towards player
		return {x = dx / dist, z = dz / dist}

	elseif state == AI_STATE.MAINTAIN_DISTANCE then
		-- Face and move away from player to maintain optimal range
		return {x = -dx / dist, z = -dz / dist}

	elseif state == AI_STATE.ATTACK then
		-- Face player to keep weapons on target
		return {x = dx / dist, z = dz / dist}
	end

	-- Default: towards player
	return {x = dx / dist, z = dz / dist}
end

-- Calculate desired speed based on AI state
-- @param state: current AI state
-- @param ai: AI configuration
-- @return: desired speed (0-1 normalized)
local function calculate_desired_speed(state, ai)
	local max_speed = ai.speed  -- Use configured speed directly

	if state == AI_STATE.RETREAT then
		return max_speed * 1.0  -- Full speed retreat

	elseif state == AI_STATE.EVADE then
		return max_speed * 0.8  -- Fast evasion

	elseif state == AI_STATE.CLOSE_DISTANCE then
		return max_speed * 0.7  -- Moderate approach speed

	elseif state == AI_STATE.MAINTAIN_DISTANCE then
		return max_speed * 0.3  -- Slow back away

	elseif state == AI_STATE.ATTACK then
		return max_speed * 0.7  -- Moderate strafe speed
	end

	return 0  -- Idle
end

-- Update Grabon AI for Mission 3
-- Handles movement, rotation, target detection, and weapon firing
function AISystem.update_grabon_ai(enemy_ships, ship_pos, is_dead, player_health_obj, current_health, active_explosions, spawned_spheres, Config, ShipSystems, WeaponEffects, Explosion, shield_charge, angle_to_dir, apply_shield_absorption)
	for _, enemy in ipairs(enemy_ships) do
		if enemy.type == "grabon" and not enemy.is_destroyed then
			local ai = enemy.config.ai

			-- Detect player target
			if not enemy.ai_target_detected then
				-- Detect if player within sensor range
				if ShipSystems.is_in_range(enemy.position, ship_pos, ai.target_detection_range) then
					enemy.ai_target_detected = true
					enemy.ai_target = ship_pos
				end
			end

			if enemy.ai_target_detected then
				-- Update target position (follow player)
				enemy.ai_target = ship_pos

				-- Calculate distance to target
				local dx = enemy.ai_target.x - enemy.position.x
				local dz = enemy.ai_target.z - enemy.position.z
				local target_distance = math.sqrt(dx*dx + dz*dz)

				-- Check for obstacles
				local collision_threshold = 10.0
				local collision_detected = false
				local nearest_obstacle = nil
				local nearest_distance = collision_threshold

				-- Check collision with player
				if target_distance < collision_threshold then
					collision_detected = true
					nearest_obstacle = ship_pos
					nearest_distance = target_distance
				end

				-- Check collision with other enemies/satellites
				for _, other_enemy in ipairs(enemy_ships) do
					if other_enemy.id ~= enemy.id and other_enemy.position then
						local odx = other_enemy.position.x - enemy.position.x
						local odz = other_enemy.position.z - enemy.position.z
						local other_distance = math.sqrt(odx*odx + odz*odz)
						if other_distance < collision_threshold and other_distance < nearest_distance then
							collision_detected = true
							nearest_obstacle = other_enemy.position
							nearest_distance = other_distance
						end
					end
				end

				-- Check collision with spawned objects (asteroids, planets)
				for _, obj in ipairs(spawned_spheres) do
					if obj.x and obj.z then
						local odx = obj.x - enemy.position.x
						local odz = obj.z - enemy.position.z
						local obj_distance = math.sqrt(odx*odx + odz*odz)
						if obj_distance < collision_threshold and obj_distance < nearest_distance then
							collision_detected = true
							nearest_obstacle = {x = obj.x, y = obj.y or 0, z = obj.z}
							nearest_distance = obj_distance
						end
					end
				end

				-- Initialize AI planning state
				if not enemy.ai_last_planning_time then
					enemy.ai_last_planning_time = 0
					enemy.ai_planning_interval = AI_PLANNING_INTERVAL_MIN + rnd(AI_PLANNING_INTERVAL_MAX - AI_PLANNING_INTERVAL_MIN)
					enemy.ai_current_state = AI_STATE.IDLE
					enemy.ai_desired_heading = {x = 0, z = 1}
					enemy.ai_desired_speed = 0
				end

				-- Check if it's time to update planning
				local current_time = t()
				local time_since_last_plan = current_time - enemy.ai_last_planning_time

				if time_since_last_plan >= enemy.ai_planning_interval or collision_detected then
					-- Update AI state based on conditions (collision overrides interval)
					local ai_state = determine_ai_state(enemy, target_distance, collision_detected, ai)

					-- Calculate desired heading direction based on state (ships move where they face)
					local desired_heading = calculate_desired_heading(ai_state, enemy.position, ship_pos, nearest_obstacle)

					-- Calculate desired speed based on state
					local desired_speed = calculate_desired_speed(ai_state, ai)

					-- Store planning results
					enemy.ai_current_state = ai_state
					enemy.ai_desired_heading = desired_heading
					enemy.ai_desired_speed = desired_speed

					-- Reset planning timer with new random interval
					enemy.ai_last_planning_time = current_time
					enemy.ai_planning_interval = AI_PLANNING_INTERVAL_MIN + rnd(AI_PLANNING_INTERVAL_MAX - AI_PLANNING_INTERVAL_MIN)
				end

				-- Use cached planning results
				local desired_heading = enemy.ai_desired_heading
				local desired_speed = enemy.ai_desired_speed

				-- Convert current heading to direction vector
				local current_dir = angle_to_dir(enemy.heading)

				-- Smoothly rotate towards desired heading using ShipSystems
				local new_dir = ShipSystems.calculate_rotation(current_dir, desired_heading, ai.turn_rate)

				-- Convert back to heading (0-1 turns)
				enemy.heading = atan2(new_dir.x, new_dir.z)

				-- Initialize speed if needed
				if not enemy.current_speed then enemy.current_speed = 0 end

				-- Smoothly interpolate towards desired speed using ShipSystems
				enemy.current_speed = ShipSystems.calculate_speed(enemy.current_speed, desired_speed, 1.0)

				-- Apply movement in HEADING direction (ships move where they face)
				if abs(enemy.current_speed) > 0.01 then
					local movement = ShipSystems.calculate_movement(enemy.current_speed, new_dir, ai.speed)
					enemy.position.x = enemy.position.x + movement.x
					enemy.position.z = enemy.position.z + movement.z
				end

				-- Use facing direction for weapon firing
				local forward_dir = new_dir

				-- Fire weapons if in range - check per-weapon firing arc
				if not is_dead then
					-- Check each weapon individually
					for w = 1, #ai.weapons do
						local weapon = ai.weapons[w]

						-- Check if target is in range and in THIS weapon's firing arc
						local in_range = ShipSystems.is_in_range(enemy.position, ship_pos, weapon.range)
						local in_arc = ShipSystems.is_in_firing_arc(enemy.position, forward_dir, ship_pos, weapon.firing_arc_start, weapon.firing_arc_end)

						if in_range and in_arc then
							local current_time = t()  -- Get current elapsed time (Picotron API)

							if not enemy.ai_last_weapon_fire_time then
								enemy.ai_last_weapon_fire_time = {}
							end

							if not enemy.ai_last_weapon_fire_time[w] then
								enemy.ai_last_weapon_fire_time[w] = 0
							end

							-- Fire if enough time has passed
							if current_time - enemy.ai_last_weapon_fire_time[w] > weapon.fire_rate then
								-- Fire beam from Grabon towards player
								-- Calculate muzzle position using weapon offset
								local muzzle_offset = weapon.muzzle_offset or {x = 0, y = 0, z = 0}
								local muzzle_pos = {
									x = enemy.position.x + muzzle_offset.x,
									y = enemy.position.y + muzzle_offset.y,
									z = enemy.position.z + muzzle_offset.z,
								}
								WeaponEffects.fire_beam(muzzle_pos, ship_pos, 12)  -- Sprite 12 for Grabon disruptor beams
								-- Apply shield absorption first
								local health_before = player_health_obj.current_health
								local shield_absorbed = apply_shield_absorption()
								if not shield_absorbed then
									-- Shields didn't absorb, apply damage to health
									WeaponEffects.spawn_explosion(ship_pos, player_health_obj)
									-- Sync current_health with player_health_obj
									current_health = player_health_obj.current_health
									-- Check if player died
									if current_health <= 0 then
										is_dead = true
										death_time = 0
										-- Spawn explosion at ship position when player dies
										if Config.explosion.enabled then
											table.insert(active_explosions, Explosion.new(Config.ship.position.x, Config.ship.position.y, Config.ship.position.z, Config.explosion))
											sfx(3)
										end
									end
									-- Reset shield charge progress when hit without shields
									for i = 1, 3 do
										shield_charge.boxes[i] = 0
									end
									-- Spawn additional damage effects when player takes health damage
									if player_health_obj.current_health < health_before then
										WeaponEffects.spawn_smoke(ship_pos)
									end
								else
									printh("Shield absorbed Grabon attack!")
								end
								-- Track firing time
								enemy.ai_last_weapon_fire_time[w] = current_time
							end
						end
					end
				end
			end
		end
	end

	return current_health, is_dead
end

return AISystem

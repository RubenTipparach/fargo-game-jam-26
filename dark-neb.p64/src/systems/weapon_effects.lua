--[[pod_format="raw",created="2024-11-09 00:00:00",modified="2025-11-09 13:18:36",revision=2]]
-- Weapon Effects System
-- Handles beams, explosions, and smoke effects

local WeaponEffects = {}

-- Configuration reference (set via setup function)
local Config = nil

-- Load particle systems
local Explosion = require("src.particles.explosion")
local Smoke = require("src.particles.smoke")

-- Active beams
local beams = {}
-- Active explosions (particle-based)
local explosions = {}
-- Active smoke particles (particle-based)
local smoke_particles = {}

-- Beam configuration
local BEAM_CONFIG = {
	sprite_id = 13,
	width = 2,  -- Width of beam quad in world units
	lifetime = 0.15,  -- How long beam stays visible
}

-- Explosion configuration
local EXPLOSION_CONFIG = {
	sprite_id = 17,  -- Small explosion sprite
	scale = 1.0,
	lifetime = 0.3,  -- How long explosion stays visible
	damage = 10,  -- Damage per explosion
}

-- Smoke configuration
local SMOKE_CONFIG = {
	sprite_id = 18,  -- Smoke sprite
	max_particles = 4,
	lifetime = 4.0,  -- Longer smoke duration for more persistent effect
	growth_time = 0.2,  -- Time to reach max size (slower growth)
	initial_scale = 0.5,
	max_scale = 2.0,
	spawn_interval = 1,  -- Time between smoke spawns when object is damaged (seconds)
	-- Velocity configuration for spawned smoke
	velocity_x_spread = 0.4,      -- Horizontal X velocity spread (±0.2)
	velocity_y_base = 1.4,        -- Base upward velocity
	velocity_y_spread = 0.3,      -- Variation in upward velocity (0.8 to 1.1)
	velocity_z_spread = 0.4,      -- Horizontal Z velocity spread (±0.2)
}
-- Helper function to calculate collision damage
-- Config is passed in at runtime from main.lua
local function calculate_collision_damage(base_dmg, armor, config)
	armor = armor or (config and config.collision.default_armor) or 0.5
	local armor_factor = config and config.collision.armor_factor or 2.0
	return base_dmg * (1 + armor_factor * (1 - armor))
end

-- Autonomous smoke spawners (objects that spawn smoke when damaged)
-- Each entry: {object=ref, health_threshold=0.3, last_spawn_time=0, spawn_pos_fn=function}
local smoke_spawners = {}

-- Beam object - simple billboard at target position
local Beam = {}
Beam.__index = Beam

function Beam.new(start_pos, end_pos, config)
	local self = setmetatable({}, Beam)
	self.start_pos = {x = start_pos.x, y = start_pos.y, z = start_pos.z}
	self.end_pos = {x = end_pos.x, y = end_pos.y, z = end_pos.z}
	self.lifetime = config.lifetime or 0.15
	self.age = 0
	self.active = true
	self.sprite_id = config.sprite_id or 13
	self.width = config.width or 2
	self.is_incoming = config.is_incoming or false  -- True for incoming beams (towards camera), false for outgoing
	return self
end

function Beam:update(dt)
	self.age = self.age + dt
	if self.age >= self.lifetime then
		self.active = false
		return false
	end
	return true
end

-- Get mesh face for rendering - creates two segments based on camera distance
-- @param camera: camera object with distance property
function Beam:get_mesh_face(camera)
	-- Calculate beam direction and length
	local dx = self.end_pos.x - self.start_pos.x
	local dy = self.end_pos.y - self.start_pos.y
	local dz = self.end_pos.z - self.start_pos.z
	local beam_length = sqrt(dx*dx + dy*dy + dz*dz)

	if beam_length < 0.01 then
		return nil  -- Beam is too short
	end

	-- Normalize beam direction
	dx = dx / beam_length
	dy = dy / beam_length
	dz = dz / beam_length

	-- Get camera distance (default 30 if not provided)
	local cam_dist = (camera and camera.distance) or 30

	-- Determine the split point based on beam direction and camera distance
	-- For outgoing beams: split at camera_distance from start
	-- For incoming beams: split at camera_distance from end (backwards)
	local split_distance
	if self.is_incoming then
		-- Incoming: start from far end, move backwards toward camera by camera_distance
		split_distance = max(0, beam_length - cam_dist)
	else
		-- Outgoing: start from near end, move forward by camera_distance
		split_distance = min(beam_length, cam_dist)
	end

	-- Create two segments from the beam
	-- Segment 1: start to split point
	-- Segment 2: split point to end
	return self:_create_dual_segment_mesh(dx, dy, dz, beam_length, split_distance)
end

-- Helper function to create dual segment mesh
-- @param dx, dy, dz: normalized beam direction
-- @param beam_length: total beam length
-- @param split_distance: distance along beam to split at
function Beam:_create_dual_segment_mesh(dx, dy, dz, beam_length, split_distance)
	-- Create first perpendicular vector to beam direction, in XZ plane
	-- This keeps the beam flat on the XZ plane (horizontal width)
	local perp1_x = -dz
	local perp1_z = dx

	-- Normalize perpendicular vector 1
	local perp_len = sqrt(perp1_x*perp1_x + perp1_z*perp1_z)
	if perp_len > 0 then
		perp1_x = perp1_x / perp_len
		perp1_z = perp1_z / perp_len
	end

	-- Create second perpendicular vector (cross product: beam_dir × perp1)
	local perp2_x = dy * perp1_z
	local perp2_y = dz * perp1_x - dx * perp1_z
	local perp2_z = -dy * perp1_x

	-- Normalize perpendicular vector 2
	local perp2_len = sqrt(perp2_x*perp2_x + perp2_y*perp2_y + perp2_z*perp2_z)
	if perp2_len > 0 then
		perp2_x = perp2_x / perp2_len
		perp2_y = perp2_y / perp2_len
		perp2_z = perp2_z / perp2_len
	end

	local half_width = self.width / 2

	-- Segment 1: from start (0) to split_distance
	local half_len1 = split_distance / 2
	local mid1_x = self.start_pos.x + dx * half_len1
	local mid1_y = self.start_pos.y + dy * half_len1
	local mid1_z = self.start_pos.z + dz * half_len1

	local verts1 = {
		-- Quad 1 for segment 1
		{x = -dx * half_len1 - perp1_x * half_width, y = -dy * half_len1, z = -dz * half_len1 - perp1_z * half_width},
		{x = -dx * half_len1 + perp1_x * half_width, y = -dy * half_len1, z = -dz * half_len1 + perp1_z * half_width},
		{x = dx * half_len1 + perp1_x * half_width, y = dy * half_len1, z = dz * half_len1 + perp1_z * half_width},
		{x = dx * half_len1 - perp1_x * half_width, y = dy * half_len1, z = dz * half_len1 - perp1_z * half_width},
		-- Quad 2 for segment 1
		{x = -dx * half_len1 - perp2_x * half_width, y = -dy * half_len1 - perp2_y * half_width, z = -dz * half_len1 - perp2_z * half_width},
		{x = -dx * half_len1 + perp2_x * half_width, y = -dy * half_len1 + perp2_y * half_width, z = -dz * half_len1 + perp2_z * half_width},
		{x = dx * half_len1 + perp2_x * half_width, y = dy * half_len1 + perp2_y * half_width, z = dz * half_len1 + perp2_z * half_width},
		{x = dx * half_len1 - perp2_x * half_width, y = dy * half_len1 - perp2_y * half_width, z = dz * half_len1 - perp2_z * half_width},
	}

	-- Segment 2: from split_distance to end
	local remaining_len = beam_length - split_distance
	local half_len2 = remaining_len / 2
	local mid2_x = self.start_pos.x + dx * (split_distance + half_len2)
	local mid2_y = self.start_pos.y + dy * (split_distance + half_len2)
	local mid2_z = self.start_pos.z + dz * (split_distance + half_len2)

	local verts2 = {
		-- Quad 1 for segment 2
		{x = -dx * half_len2 - perp1_x * half_width, y = -dy * half_len2, z = -dz * half_len2 - perp1_z * half_width},
		{x = -dx * half_len2 + perp1_x * half_width, y = -dy * half_len2, z = -dz * half_len2 + perp1_z * half_width},
		{x = dx * half_len2 + perp1_x * half_width, y = dy * half_len2, z = dz * half_len2 + perp1_z * half_width},
		{x = dx * half_len2 - perp1_x * half_width, y = dy * half_len2, z = dz * half_len2 - perp1_z * half_width},
		-- Quad 2 for segment 2
		{x = -dx * half_len2 - perp2_x * half_width, y = -dy * half_len2 - perp2_y * half_width, z = -dz * half_len2 - perp2_z * half_width},
		{x = -dx * half_len2 + perp2_x * half_width, y = -dy * half_len2 + perp2_y * half_width, z = -dz * half_len2 + perp2_z * half_width},
		{x = dx * half_len2 + perp2_x * half_width, y = dy * half_len2 + perp2_y * half_width, z = dz * half_len2 + perp2_z * half_width},
		{x = dx * half_len2 - perp2_x * half_width, y = dy * half_len2 - perp2_y * half_width, z = dz * half_len2 - perp2_z * half_width},
	}

	-- Fade progress for beam fade-out effect
	local fade_progress = self.age / self.lifetime
	local opacity = max(0, 1.0 - fade_progress)

	-- Face data is the same for both segments - all 8 faces visible from any angle
	local face_template = {
		{1, 2, 3, self.sprite_id, vec(16,0), vec(16,16), vec(0,16)},
		{1, 3, 4, self.sprite_id, vec(16,0), vec(0,16), vec(0,0)},
		{3, 2, 1, self.sprite_id, vec(0,16), vec(16,16), vec(16,0)},
		{4, 3, 1, self.sprite_id, vec(0,0), vec(0,16), vec(16,0)},
		{5, 6, 7, self.sprite_id, vec(16,0), vec(16,16), vec(0,16)},
		{5, 7, 8, self.sprite_id, vec(16,0), vec(0,16), vec(0,0)},
		{7, 6, 5, self.sprite_id, vec(0,16), vec(16,16), vec(16,0)},
		{8, 7, 5, self.sprite_id, vec(0,0), vec(0,16), vec(16,0)}
	}

	-- Return both segments
	return {
		{
			verts = verts1,
			faces = face_template,
			x = mid1_x,
			y = mid1_y,
			z = mid1_z,
			opacity = opacity
		},
		{
			verts = verts2,
			faces = face_template,
			x = mid2_x,
			y = mid2_y,
			z = mid2_z,
			opacity = opacity
		}
	}
end

-- Initialize WeaponEffects with config reference
function WeaponEffects.setup(config)
	Config = config
end

-- Fire a beam from origin towards target
-- @param origin: {x, y, z} starting position
-- @param target: {x, y, z} target position
-- @return beam object
function WeaponEffects.fire_beam(origin, target, sprite_id)
	printh("FIRE_BEAM called: origin=(" .. origin.x .. "," .. origin.y .. "," .. origin.z .. ") target=(" .. target.x .. "," .. target.y .. "," .. target.z .. ")")
	local beam_config = {
		sprite_id = sprite_id or BEAM_CONFIG.sprite_id,
		width = BEAM_CONFIG.width,
		lifetime = BEAM_CONFIG.lifetime,
	}
	local beam = Beam.new(origin, target, beam_config)
	table.insert(beams, beam)
	printh("Beam created, total beams: " .. #beams)

	-- Play beam sound effect (SFX 1)
	sfx(1)

	return beam
end

-- Spawn explosion at position (also applies damage)
-- @param pos: {x, y, z} position
-- @param target: reference to target object (satellite/planet config table)
function WeaponEffects.spawn_explosion(pos, target)
	-- Create particle-based explosion using the Explosion class
	local explosion = Explosion.new(pos.x, pos.y, pos.z, {
		quad_count = 1,
		sprite_id = EXPLOSION_CONFIG.sprite_id,
		lifetime = EXPLOSION_CONFIG.lifetime,
		initial_scale = 0.5,
		max_scale = 3.0,
		speed_up_time = 0.1,
		slowdown_time = 0.2,
		slow_growth_factor = 0.1,
	})

	table.insert(explosions, explosion)

	-- Play explosion sound effect (SFX 2)
	sfx(2)

	-- Apply damage to target if it exists
	if target and target.current_health and target.max_health then
		target.current_health = target.current_health - EXPLOSION_CONFIG.damage
		if target.current_health < 0 then
			target.current_health = 0
		end

		-- Log target health after damage
		local target_name = target.id or "target"
		local health_percent = (target.current_health / target.max_health) * 100
		printh(target_name .. " took damage: " .. target.current_health .. "/" .. target.max_health .. " (" .. flr(health_percent) .. "%)")

		-- Spawn smoke if target is below 70% health (30% remaining)
		local health_ratio = target.current_health / target.max_health
		if health_ratio < 0.3 then
			WeaponEffects.spawn_smoke(pos)
		end
	end

	return explosion
end

-- Apply collision damage to a target based on armor rating
-- @param target: target object with current_health, max_health, armor
function WeaponEffects.apply_collision_damage(target)
	if not target or not target.current_health or not target.max_health then
		return
	end

	local base_damage = Config and Config.collision.base_damage or 5
	local damage = calculate_collision_damage(base_damage, target.armor, Config)

	target.current_health = target.current_health - damage
	if target.current_health < 0 then
		target.current_health = 0
	end

	local target_name = target.id or "target"
	local health_percent = (target.current_health / target.max_health) * 100
	printh(target_name .. " collision damage: " .. target.current_health .. "/" .. target.max_health .. " (" .. flr(health_percent) .. "%)")
end

-- Spawn smoke particle at position
-- @param pos: {x, y, z} position
-- @param velocity: {x, y, z} optional velocity
function WeaponEffects.spawn_smoke(pos, velocity)
	-- Only spawn if under max limit
	if #smoke_particles >= SMOKE_CONFIG.max_particles then
		printh("SMOKE SPAWN BLOCKED: max particles reached (" .. #smoke_particles .. "/" .. SMOKE_CONFIG.max_particles .. ")")
		return nil
	end

	-- Add random offset to spawn position to avoid perfect stacking
	local spawn_offset = 0.5
	local pos_x = pos.x + (rnd(spawn_offset * 2) - spawn_offset)
	local pos_y = pos.y + (rnd(spawn_offset * 2) - spawn_offset)
	local pos_z = pos.z + (rnd(spawn_offset * 2) - spawn_offset)

	-- Default velocity with random horizontal spread - uses config values
	local vel = velocity or {
		x = (rnd(SMOKE_CONFIG.velocity_x_spread) - SMOKE_CONFIG.velocity_x_spread / 2),
		y = SMOKE_CONFIG.velocity_y_base + rnd(SMOKE_CONFIG.velocity_y_spread),
		z = (rnd(SMOKE_CONFIG.velocity_z_spread) - SMOKE_CONFIG.velocity_z_spread / 2),
	}

	-- Randomize smoke size by about 20% (0.8 to 1.2 scale multiplier)
	local size_variance = 0.8 + rnd(0.4)

	local smoke = Smoke.new(pos_x, pos_y, pos_z, {
		sprite_id = SMOKE_CONFIG.sprite_id,
		lifetime = SMOKE_CONFIG.lifetime,
		initial_scale = SMOKE_CONFIG.initial_scale * size_variance * 0.8,  -- Shrink 20% overall and add variance
		max_scale = SMOKE_CONFIG.max_scale * size_variance * 0.8,           -- Shrink 20% overall and add variance
		growth_time = SMOKE_CONFIG.growth_time,
		velocity = vel,
	})

	printh("SMOKE SPAWNED: pos=(" .. pos_x .. "," .. pos_y .. "," .. pos_z .. ") total=" .. (#smoke_particles + 1))
	table.insert(smoke_particles, smoke)
	return smoke
end

-- Update all effects
function WeaponEffects.update(delta)
	-- Update beams
	for i = #beams, 1, -1 do
		local beam = beams[i]
		beam.age = beam.age + delta
		if beam.age >= beam.lifetime then
			table.remove(beams, i)
		end
	end

	-- Update explosions (particle-based)
	for i = #explosions, 1, -1 do
		local exp = explosions[i]
		if not exp:update(delta) then
			table.remove(explosions, i)
		end
	end

	-- Update smoke particles (particle-based)
	for i = #smoke_particles, 1, -1 do
		local smoke = smoke_particles[i]
		if not smoke:update(delta) then
			table.remove(smoke_particles, i)
		end
	end

	-- Update autonomous smoke spawners (spawns smoke on damaged objects)
	WeaponEffects.update_smoke_spawners(delta)
end

-- Build simple billboard quad for a beam at target position
local function build_beam_quad(start_pos, end_pos, camera, sprite_id, width)
	local half_size = width

	-- Camera right vector
	local right_x = cos(camera.ry)
	local right_y = 0
	local right_z = -sin(camera.ry)

	-- Camera up vector (cross product)
	local forward_x = sin(camera.ry) * cos(camera.rx)
	local forward_y = sin(camera.rx)
	local forward_z = cos(camera.ry) * cos(camera.rx)

	local up_x = -(forward_y * right_z - forward_z * right_y)
	local up_y = -(forward_z * right_x - forward_x * right_z)
	local up_z = -(forward_x * right_y - forward_y * right_x)

	-- Simple billboard quad at end_pos (target position)
	local verts = {
		{x = -right_x * half_size + up_x * half_size, y = -right_y * half_size + up_y * half_size, z = -right_z * half_size + up_z * half_size},
		{x = right_x * half_size + up_x * half_size, y = right_y * half_size + up_y * half_size, z = right_z * half_size + up_z * half_size},
		{x = right_x * half_size - up_x * half_size, y = right_y * half_size - up_y * half_size, z = right_z * half_size - up_z * half_size},
		{x = -right_x * half_size - up_x * half_size, y = -right_y * half_size - up_y * half_size, z = -right_z * half_size - up_z * half_size},
	}

	local faces = {
		{1, 2, 3, sprite_id, vec(0,0), vec(16,0), vec(16,16)},
		{1, 3, 4, sprite_id, vec(0,0), vec(16,16), vec(0,16)}
	}

	return {
		verts = verts,
		faces = faces,
		x = end_pos.x,
		y = end_pos.y,
		z = end_pos.z
	}
end

-- Project a world-space vertex to screen space (used by explosions and smoke)
local function project_vertex(world_pos, camera)
	local PROJ_SCALE = 270 / 0.7002075
	local NEAR_PLANE = 0.01
	local cam_dist = camera.distance or 30

	-- Precompute camera rotation
	local cos_ry, sin_ry = cos(camera.ry), sin(camera.ry)
	local cos_rx, sin_rx = cos(camera.rx), sin(camera.rx)

	-- Translate to camera-relative coordinates
	local x = world_pos.x - camera.x
	local y = world_pos.y - camera.y
	local z = world_pos.z - camera.z

	-- Rotate around Y axis (yaw)
	local x2 = x * cos_ry - z * sin_ry
	local z2 = x * sin_ry + z * cos_ry

	-- Rotate around X axis (pitch)
	local y2 = y * cos_rx - z2 * sin_rx
	local z3 = y * sin_rx + z2 * cos_rx + cam_dist

	-- Check near plane
	if z3 <= NEAR_PLANE then
		return nil
	end

	-- Perspective projection
	local inv_z = 1 / z3
	local px = -x2 * inv_z * PROJ_SCALE + 240
	local py = -y2 * inv_z * PROJ_SCALE + 135

	return {
		x = px,
		y = py,
		z = 0,
		w = inv_z,
		depth = z3,
		cam_x = x2,
		cam_y = y2,
		cam_z = z3
	}
end

-- Render beams and add to face list
-- Beams are split into two segments based on camera distance to handle culling
function WeaponEffects.render_beams(camera, all_faces)
	for _, beam in ipairs(beams) do
		if beam.active then
			local segments = beam:get_mesh_face(camera)
			if segments then
				-- get_mesh_face returns an array of 2 segments
				for _, mesh in ipairs(segments) do
					-- Process each face in the segment mesh individually
					for i = 1, #mesh.faces do
						local face = mesh.faces[i]
						local v1_idx, v2_idx, v3_idx = face[1], face[2], face[3]
						local v1 = mesh.verts[v1_idx]
						local v2 = mesh.verts[v2_idx]
						local v3 = mesh.verts[v3_idx]

						-- Convert to world coordinates
						local w1 = {x = v1.x + mesh.x, y = v1.y + mesh.y, z = v1.z + mesh.z}
						local w2 = {x = v2.x + mesh.x, y = v2.y + mesh.y, z = v2.z + mesh.z}
						local w3 = {x = v3.x + mesh.x, y = v3.y + mesh.y, z = v3.z + mesh.z}

						-- Project all vertices
						local p1 = project_vertex(w1, camera)
						local p2 = project_vertex(w2, camera)
						local p3 = project_vertex(w3, camera)

						-- Only add face if all vertices project to screen
						if p1 and p2 and p3 then
							-- Calculate average depth
							local avg_depth = (p1.depth + p2.depth + p3.depth) * 0.333333

							table.insert(all_faces, {
								face = {v1_idx, v2_idx, v3_idx, face[4], face[5], face[6], face[7]},
								depth = avg_depth,
								p1 = p1,
								p2 = p2,
								p3 = p3,
								unlit = true,
								dither_opacity = mesh.opacity
							})
						end
					end
				end
			end
		end
	end
end

-- Render explosions and add to face list (particle-based)
function WeaponEffects.render_explosions(camera, all_faces)
	for _, explosion in ipairs(explosions) do
		local mesh = explosion:get_mesh_face(camera)
		if mesh then
			for i = 1, #mesh.faces do
				local face = mesh.faces[i]
				local v1_idx, v2_idx, v3_idx = face[1], face[2], face[3]
				local v1 = mesh.verts[v1_idx]
				local v2 = mesh.verts[v2_idx]
				local v3 = mesh.verts[v3_idx]

				-- Convert to world coordinates
				local w1 = {x = v1.x + mesh.x, y = v1.y + mesh.y, z = v1.z + mesh.z}
				local w2 = {x = v2.x + mesh.x, y = v2.y + mesh.y, z = v2.z + mesh.z}
				local w3 = {x = v3.x + mesh.x, y = v3.y + mesh.y, z = v3.z + mesh.z}

				-- Project all vertices
				local p1 = project_vertex(w1, camera)
				local p2 = project_vertex(w2, camera)
				local p3 = project_vertex(w3, camera)

				-- Only add face if all vertices are in front of camera
				if p1 and p2 and p3 then
					-- Calculate average depth with slight bias
					local avg_depth = (p1.depth + p2.depth + p3.depth) * 0.333333 - 10

					table.insert(all_faces, {
						face = {v1_idx, v2_idx, v3_idx, face[4], face[5], face[6], face[7]},
						depth = avg_depth,
						p1 = p1,
						p2 = p2,
						p3 = p3,
						unlit = true,
						explosion_opacity = mesh.opacity
					})
				end
			end
		end
	end
end

-- Render smoke particles and add to face list (particle-based)
function WeaponEffects.render_smoke(camera, all_faces)
	for _, smoke in ipairs(smoke_particles) do
		local mesh = smoke:get_mesh_face(camera)
		if mesh then
			for i = 1, #mesh.faces do
				local face = mesh.faces[i]
				local v1_idx, v2_idx, v3_idx = face[1], face[2], face[3]
				local v1 = mesh.verts[v1_idx]
				local v2 = mesh.verts[v2_idx]
				local v3 = mesh.verts[v3_idx]

				-- Convert to world coordinates
				local w1 = {x = v1.x + mesh.x, y = v1.y + mesh.y, z = v1.z + mesh.z}
				local w2 = {x = v2.x + mesh.x, y = v2.y + mesh.y, z = v2.z + mesh.z}
				local w3 = {x = v3.x + mesh.x, y = v3.y + mesh.y, z = v3.z + mesh.z}

				-- Project all vertices
				local p1 = project_vertex(w1, camera)
				local p2 = project_vertex(w2, camera)
				local p3 = project_vertex(w3, camera)

				-- Only add face if all vertices are in front of camera
				if p1 and p2 and p3 then
					-- Calculate average depth with slight bias
					local avg_depth = (p1.depth + p2.depth + p3.depth) * 0.333333 - 5

					table.insert(all_faces, {
						face = {v1_idx, v2_idx, v3_idx, face[4], face[5], face[6], face[7]},
						depth = avg_depth,
						p1 = p1,
						p2 = p2,
						p3 = p3,
						dither_opacity = 1.0 - face.fog,  -- Convert fog to opacity for renderer's dither system
						unlit = true,
						smoke_opacity = mesh.opacity
					})
				end
			end
		end
	end
end

-- Draw all effects
-- @param camera: camera object with view matrix
-- @param utilities: object containing draw_line_3d, project_to_screen, and Renderer for drawing 3D quads
function WeaponEffects.draw(camera, utilities)
	-- Beams, explosions, and smoke are now added to the face queue in main.lua before sorting
end

-- Get all beams
function WeaponEffects.get_beams()
	return beams
end

-- Get all smoke particles
function WeaponEffects.get_smoke_particles()
	return smoke_particles
end

-- Get all explosions
function WeaponEffects.get_explosions()
	return explosions
end

-- Clear all effects
function WeaponEffects.clear()
	beams = {}
	explosions = {}
	smoke_particles = {}
	smoke_spawners = {}
end

-- Register an object for autonomous smoke spawning when damaged
-- @param object: object with current_health and max_health properties
-- @param health_threshold: spawn smoke when health ratio is below this (default 0.3 = 30%)
-- @param spawn_pos_fn: function(object) that returns {x, y, z} spawn position
function WeaponEffects.register_smoke_spawner(object, health_threshold, spawn_pos_fn)
	if not object or not object.current_health or not object.max_health then
		return nil
	end

	local spawner = {
		object = object,
		health_threshold = health_threshold or 0.3,
		last_spawn_time = 0,
		spawn_pos_fn = spawn_pos_fn or function(obj)
			-- Default: spawn at object position if it has x, y, z
			return {x = obj.x or 0, y = obj.y or 0, z = obj.z or 0}
		end
	}

	table.insert(smoke_spawners, spawner)
	return spawner
end

-- Unregister an object from autonomous smoke spawning
-- @param object: object reference to remove
function WeaponEffects.unregister_smoke_spawner(object)
	for i = #smoke_spawners, 1, -1 do
		if smoke_spawners[i].object == object then
			table.remove(smoke_spawners, i)
			return true
		end
	end
	return false
end

-- Update autonomous smoke spawners (called from main update loop)
function WeaponEffects.update_smoke_spawners(dt)
	-- if #smoke_spawners > 0 then
	-- 	printh("UPDATE_SMOKE_SPAWNERS: " .. #smoke_spawners .. " spawners active")
	-- end

	for i = #smoke_spawners, 1, -1 do
		local spawner = smoke_spawners[i]

		-- Remove if object is no longer valid or has been destroyed
		if not spawner.object or not spawner.object.current_health or spawner.object.is_destroyed then
			table.remove(smoke_spawners, i)
		else
			local health_ratio = spawner.object.current_health / spawner.object.max_health

			-- if #smoke_spawners > 0 then
			-- 	printh("  Spawner health: " .. health_ratio .. " threshold: " .. spawner.health_threshold)
			-- end

			-- If below threshold and max particles not reached, spawn smoke
			if health_ratio < spawner.health_threshold then
				spawner.last_spawn_time = spawner.last_spawn_time + dt

				-- Only spawn if spawn interval has passed
				if spawner.last_spawn_time >= SMOKE_CONFIG.spawn_interval then
					local spawn_pos = spawner.spawn_pos_fn(spawner.object)
					WeaponEffects.spawn_smoke(spawn_pos)
					spawner.last_spawn_time = 0
				end
			else
				-- Reset timer if above threshold
				spawner.last_spawn_time = 0
			end
		end
	end
end

-- Check if a target is within weapon range
-- @param ship_pos: {x, y, z} ship position
-- @param target_pos: {x, y, z} target position
-- @param range: maximum firing distance
-- @return: true if target is in range


-- Draw firing arc visualization in 3D space
-- Draws radial lines from ship in 25-unit segments to show firing arc
-- @param ship_pos: {x, y, z} ship position
-- @param ship_heading: ship heading in turns (0-1 range) OR direction vector {x, z}
-- @param range: firing range (distance)
-- @param arc_start: left edge of arc in degrees
-- @param arc_end: right edge of arc in degrees
-- @param camera: camera object with view matrix
-- @param draw_line_3d: function to draw 3D lines
-- @param color: line color
function WeaponEffects.draw_firing_arc(ship_pos, ship_heading, range, arc_start, arc_end, camera, draw_line_3d, color)
	if not ship_pos or not camera or not draw_line_3d then
		return
	end

	-- Get ship forward direction - handle both numeric heading and direction vector
	local ship_forward_x, ship_forward_z
	if ship_heading.x and ship_heading.z then
		-- Direction vector format {x, z}
		ship_forward_x = ship_heading.x
		ship_forward_z = ship_heading.z
	else
		-- Numeric heading in turns (0-1 range)
		local ship_heading_rad = ship_heading * 2 * 3.14159265359
		ship_forward_x = math.sin(ship_heading_rad)
		ship_forward_z = math.cos(ship_heading_rad)
	end

	-- Draw radial line segments of 25 units each
	local segment_length = 25
	local num_segments = math.ceil(range / segment_length)

	-- Draw arc edges (the two boundary lines of the arc)
	for side = 1, 2 do
		local arc_angle = side == 1 and arc_start or arc_end
		local arc_angle_rad = arc_angle * 3.14159265359 / 180

		-- Rotate the ship forward direction by the arc angle (rotate in the ship's local coordinate system)
		local rotated_x = ship_forward_x * math.cos(arc_angle_rad) - ship_forward_z * math.sin(arc_angle_rad)
		local rotated_z = ship_forward_x * math.sin(arc_angle_rad) + ship_forward_z * math.cos(arc_angle_rad)

		-- Draw segments along this edge
		for seg = 0, num_segments - 1 do
			local start_dist = seg * segment_length
			local end_dist = math.min((seg + 1) * segment_length, range)

			local seg_start_x = ship_pos.x + rotated_x * start_dist
			local seg_start_z = ship_pos.z + rotated_z * start_dist

			local seg_end_x = ship_pos.x + rotated_x * end_dist
			local seg_end_z = ship_pos.z + rotated_z * end_dist

			draw_line_3d(seg_start_x, ship_pos.y, seg_start_z, seg_end_x, ship_pos.y, seg_end_z, camera, color)
		end
	end

	-- Draw arc curve segments (connecting the two edges at various distances)
	for arc_dist = segment_length, range, segment_length do
		local arc_segments = 8
		local total_arc = arc_end - arc_start

		for seg = 0, arc_segments - 1 do
			local angle1 = arc_start + (total_arc * (seg / arc_segments))
			local angle2 = arc_start + (total_arc * ((seg + 1) / arc_segments))

			local angle1_rad = angle1 * 3.14159265359 / 180
			local angle2_rad = angle2 * 3.14159265359 / 180

			-- Rotate ship forward by both angles (rotate in the ship's local coordinate system)
			local rotated1_x = ship_forward_x * math.cos(angle1_rad) - ship_forward_z * math.sin(angle1_rad)
			local rotated1_z = ship_forward_x * math.sin(angle1_rad) + ship_forward_z * math.cos(angle1_rad)

			local rotated2_x = ship_forward_x * math.cos(angle2_rad) - ship_forward_z * math.sin(angle2_rad)
			local rotated2_z = ship_forward_x * math.sin(angle2_rad) + ship_forward_z * math.cos(angle2_rad)

			-- Points on arc curve
			local p1_x = ship_pos.x + rotated1_x * arc_dist
			local p1_z = ship_pos.z + rotated1_z * arc_dist

			local p2_x = ship_pos.x + rotated2_x * arc_dist
			local p2_z = ship_pos.z + rotated2_z * arc_dist

			-- Draw arc segment
			draw_line_3d(p1_x, ship_pos.y, p1_z, p2_x, ship_pos.y, p2_z, camera, color)
		end
	end
end

return WeaponEffects

--[[pod_format="raw",created="2024-11-09 00:00:00",modified="2024-11-09 00:00:00",revision=0]]
-- Weapon Effects System
-- Handles beams, explosions, and smoke effects

local WeaponEffects = {}

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

-- Get mesh face for rendering
function Beam:get_mesh_face()
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
	-- This gives us a perpendicular that's perpendicular to both beam and perp1
	local perp2_x = dy * perp1_z - dz * perp1_x
	local perp2_y = dz * perp1_x - dx * perp1_z
	local perp2_z = dx * 0 - dy * perp1_x  -- Note: simplified cross product

	-- Actually, let's compute it correctly: cross(beam_dir, perp1)
	-- beam = (dx, dy, dz), perp1 = (perp1_x, 0, perp1_z)
	-- cross = (dy * perp1_z - dz * 0, dz * perp1_x - dx * perp1_z, dx * 0 - dy * perp1_x)
	perp2_x = dy * perp1_z
	perp2_y = dz * perp1_x - dx * perp1_z
	perp2_z = -dy * perp1_x

	-- Normalize perpendicular vector 2
	local perp2_len = sqrt(perp2_x*perp2_x + perp2_y*perp2_y + perp2_z*perp2_z)
	if perp2_len > 0 then
		perp2_x = perp2_x / perp2_len
		perp2_y = perp2_y / perp2_len
		perp2_z = perp2_z / perp2_len
	end

	local half_width = self.width / 2
	local half_length = beam_length / 2

	-- Calculate midpoint
	local mid_x = (self.start_pos.x + self.end_pos.x) / 2
	local mid_y = (self.start_pos.y + self.end_pos.y) / 2
	local mid_z = (self.start_pos.z + self.end_pos.z) / 2

	-- Create beam quad vertices centered at midpoint
	-- Two perpendicular quads for visibility from all angles
	-- Quad 1: Uses perp1 (XZ plane perpendicular)
	-- Quad 2: Uses perp2 (truly perpendicular to both beam and perp1)
	-- Vertices relative to midpoint:
	local verts = {
		-- Quad 1: First perpendicular direction
		-- Start point, left (relative to midpoint, so negate to go backward)
		{x = -dx * half_length - perp1_x * half_width, y = -dy * half_length, z = -dz * half_length - perp1_z * half_width},
		-- Start point, right
		{x = -dx * half_length + perp1_x * half_width, y = -dy * half_length, z = -dz * half_length + perp1_z * half_width},
		-- End point, right (positive direction from midpoint)
		{x = dx * half_length + perp1_x * half_width, y = dy * half_length, z = dz * half_length + perp1_z * half_width},
		-- End point, left
		{x = dx * half_length - perp1_x * half_width, y = dy * half_length, z = dz * half_length - perp1_z * half_width},

		-- Quad 2: Second perpendicular direction (cross product of beam and perp1)
		-- Start point, bottom (relative to midpoint, so negate to go backward)
		{x = -dx * half_length - perp2_x * half_width, y = -dy * half_length - perp2_y * half_width, z = -dz * half_length - perp2_z * half_width},
		-- Start point, top
		{x = -dx * half_length + perp2_x * half_width, y = -dy * half_length + perp2_y * half_width, z = -dz * half_length + perp2_z * half_width},
		-- End point, top (positive direction from midpoint)
		{x = dx * half_length + perp2_x * half_width, y = dy * half_length + perp2_y * half_width, z = dz * half_length + perp2_z * half_width},
		-- End point, bottom
		{x = dx * half_length - perp2_x * half_width, y = dy * half_length - perp2_y * half_width, z = dz * half_length - perp2_z * half_width},
	}

	-- Fade progress for beam fade-out effect
	local fade_progress = self.age / self.lifetime
	local opacity = max(0, 1.0 - fade_progress)

	local faces = {
		-- Quad 1: XZ plane - both facing directions for visibility from any angle
		{1, 2, 3, self.sprite_id, vec(16,0), vec(16,16), vec(0,16)},
		{1, 3, 4, self.sprite_id, vec(16,0), vec(0,16), vec(0,0)},
		-- Reverse winding for back faces
		{3, 2, 1, self.sprite_id, vec(0,16), vec(16,16), vec(16,0)},
		{4, 3, 1, self.sprite_id, vec(0,0), vec(0,16), vec(16,0)},

		-- Quad 2: Y axis - both facing directions for visibility from any angle
		{5, 6, 7, self.sprite_id, vec(16,0), vec(16,16), vec(0,16)},
		{5, 7, 8, self.sprite_id, vec(16,0), vec(0,16), vec(0,0)},
		-- Reverse winding for back faces
		{7, 6, 5, self.sprite_id, vec(0,16), vec(16,16), vec(16,0)},
		{8, 7, 5, self.sprite_id, vec(0,0), vec(0,16), vec(16,0)}
	}

	-- Debug: Print beam info
	printh("=== BEAM ===")
	printh("Start: " .. self.start_pos.x .. ", " .. self.start_pos.y .. ", " .. self.start_pos.z)
	printh("End: " .. self.end_pos.x .. ", " .. self.end_pos.y .. ", " .. self.end_pos.z)
	printh("Dir: " .. dx .. ", " .. dy .. ", " .. dz .. " (len=" .. beam_length .. ")")
	printh("Perp1: " .. perp1_x .. ", 0, " .. perp1_z)
	printh("Perp2: " .. perp2_x .. ", " .. perp2_y .. ", " .. perp2_z)
	printh("Midpoint: " .. mid_x .. ", " .. mid_y .. ", " .. mid_z)
	for i, v in ipairs(verts) do
		printh("V" .. i .. ": " .. v.x .. ", " .. v.y .. ", " .. v.z)
	end

	return {
		verts = verts,
		faces = faces,
		x = mid_x,
		y = mid_y,
		z = mid_z,
		opacity = opacity
	}
end

-- Fire a beam from origin towards target
-- @param origin: {x, y, z} starting position
-- @param target: {x, y, z} target position
-- @return beam object
function WeaponEffects.fire_beam(origin, target)
	printh("FIRE_BEAM called: origin=(" .. origin.x .. "," .. origin.y .. "," .. origin.z .. ") target=(" .. target.x .. "," .. target.y .. "," .. target.z .. ")")
	local beam = Beam.new(origin, target, BEAM_CONFIG)
	table.insert(beams, beam)
	printh("Beam created, total beams: " .. #beams)
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

	-- Apply damage to target if it exists
	if target and target.current_health and target.max_health then
		target.current_health = target.current_health - EXPLOSION_CONFIG.damage
		if target.current_health < 0 then
			target.current_health = 0
		end

		-- Spawn smoke if target is below 70% health (30% remaining)
		local health_ratio = target.current_health / target.max_health
		if health_ratio < 0.3 then
			WeaponEffects.spawn_smoke(pos)
		end
	end

	return explosion
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
-- ClipSpace culling in renderer_lit will handle near plane clipping
function WeaponEffects.render_beams(camera, all_faces)
	for _, beam in ipairs(beams) do
		if beam.active then
			local mesh = beam:get_mesh_face()
			if mesh then
				-- Process each face in the beam mesh individually
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
	if #smoke_particles > 0 then
		printh("RENDER_SMOKE: " .. #smoke_particles .. " smoke particles active")
	end
	for _, smoke in ipairs(smoke_particles) do
		local mesh = smoke:get_mesh_face(camera)
		if mesh then
			printh("  Smoke mesh generated, opacity=" .. smoke:get_opacity(smoke.age / smoke.lifetime))
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

		-- Remove if object is no longer valid
		if not spawner.object or not spawner.object.current_health then
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

return WeaponEffects

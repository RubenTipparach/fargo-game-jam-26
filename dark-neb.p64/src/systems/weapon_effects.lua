--[[pod_format="raw",created="2024-11-09 00:00:00",modified="2024-11-09 00:00:00",revision=0]]
-- Weapon Effects System
-- Handles beams, explosions, and smoke effects

local WeaponEffects = {}

-- Active beams
local beams = {}
-- Active explosions
local explosions = {}
-- Active smoke particles
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
	growth_time = 0.3,  -- Time to reach max size
	fade_time = 0.7,  -- Time to fade out
	initial_scale = 0.5,
	max_scale = 2.0,
}

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
function Beam:get_mesh_face(camera)
	local half_size = self.width

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
		{1, 2, 3, self.sprite_id, vec(0,0), vec(16,0), vec(16,16)},
		{1, 3, 4, self.sprite_id, vec(0,0), vec(16,16), vec(0,16)}
	}

	return {
		verts = verts,
		faces = faces,
		x = self.end_pos.x,
		y = self.end_pos.y,
		z = self.end_pos.z,
		opacity = 1.0
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
	local explosion = {
		pos = {x = pos.x, y = pos.y, z = pos.z},
		lifetime = EXPLOSION_CONFIG.lifetime,
		age = 0,
		target = target,  -- Reference to damaged target
	}
	table.insert(explosions, explosion)

	-- Apply damage to target if it exists
	if target and target.current_health then
		target.current_health = target.current_health - EXPLOSION_CONFIG.damage
		if target.current_health < 0 then
			target.current_health = 0
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
		return nil
	end

	local smoke = {
		pos = {x = pos.x, y = pos.y, z = pos.z},
		velocity = velocity or {x = 0, y = 0.5, z = 0},
		lifetime = SMOKE_CONFIG.growth_time + SMOKE_CONFIG.fade_time,
		age = 0,
		scale = SMOKE_CONFIG.initial_scale,
	}
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

	-- Update explosions
	for i = #explosions, 1, -1 do
		local exp = explosions[i]
		exp.age = exp.age + delta
		if exp.age >= exp.lifetime then
			table.remove(explosions, i)
		end
	end

	-- Update smoke particles
	for i = #smoke_particles, 1, -1 do
		local smoke = smoke_particles[i]
		smoke.age = smoke.age + delta

		-- Update position
		smoke.pos.x = smoke.pos.x + smoke.velocity.x * delta
		smoke.pos.y = smoke.pos.y + smoke.velocity.y * delta
		smoke.pos.z = smoke.pos.z + smoke.velocity.z * delta

		-- Update scale
		if smoke.age < SMOKE_CONFIG.growth_time then
			-- Growth phase
			local t = smoke.age / SMOKE_CONFIG.growth_time
			smoke.scale = SMOKE_CONFIG.initial_scale + (SMOKE_CONFIG.max_scale - SMOKE_CONFIG.initial_scale) * t
		else
			-- Fade phase
			local t = (smoke.age - SMOKE_CONFIG.growth_time) / SMOKE_CONFIG.fade_time
			smoke.scale = SMOKE_CONFIG.max_scale * (1 - t)
		end

		if smoke.age >= smoke.lifetime then
			table.remove(smoke_particles, i)
		end
	end
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

-- Project a world-space vertex to screen space (same as main Renderer)
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
		depth = z3
	}
end

-- Render beams and add to face list (same pattern as ExplosionRenderer)
function WeaponEffects.render_beams(camera, all_faces)
	printh("RENDER_BEAMS: " .. #beams .. " beams active")
	for _, beam in ipairs(beams) do
		printh("  Beam: active=" .. tostring(beam.active))
		if beam.active then
			local mesh = beam:get_mesh_face(camera)
			if mesh then
				printh("    Got mesh with " .. #mesh.faces .. " faces")
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
						-- Calculate average depth
						local avg_depth = (p1.depth + p2.depth + p3.depth) * 0.333333

						table.insert(all_faces, {
							face = {v1_idx, v2_idx, v3_idx, face[4], face[5], face[6], face[7]},
							depth = avg_depth,
							p1 = p1,
							p2 = p2,
							p3 = p3,
							fog = 0,
							unlit = true
						})
						printh("    Added face " .. i)
					else
						printh("    Face " .. i .. " culled (p1=" .. tostring(p1 ~= nil) .. " p2=" .. tostring(p2 ~= nil) .. " p3=" .. tostring(p3 ~= nil) .. ")")
					end
				end
			else
				printh("    No mesh returned")
			end
		end
	end
end

-- Draw all effects
-- @param camera: camera object with view matrix
-- @param utilities: object containing draw_line_3d, project_to_screen, and Renderer for drawing 3D quads
function WeaponEffects.draw(camera, utilities)
	-- Beams are now added to the face queue in main.lua before sorting

	-- Draw explosions
	for _, exp in ipairs(explosions) do
		-- Project to screen and draw sprite
		local screen_x, screen_y = utilities.project_to_screen(exp.pos.x, exp.pos.y, exp.pos.z, camera)
		if screen_x and screen_y then
			-- Draw explosion sprite with fade
			local fade = 1 - (exp.age / exp.lifetime)
			spr(EXPLOSION_CONFIG.sprite_id, flr(screen_x) - 4, flr(screen_y) - 4, 1, 1, 0, 0)
		end
	end

	-- Draw smoke particles
	for _, smoke in ipairs(smoke_particles) do
		-- Project to screen
		local screen_x, screen_y = utilities.project_to_screen(smoke.pos.x, smoke.pos.y, smoke.pos.z, camera)
		if screen_x and screen_y then
			-- Calculate fade
			local fade = 1
			if smoke.age > SMOKE_CONFIG.growth_time then
				fade = 1 - ((smoke.age - SMOKE_CONFIG.growth_time) / SMOKE_CONFIG.fade_time)
			end

			-- Draw smoke sprite scaled
			local scale = smoke.scale
			spr(SMOKE_CONFIG.sprite_id, flr(screen_x) - scale * 4, flr(screen_y) - scale * 4, scale, scale, 0, 0)
		end
	end
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
end

return WeaponEffects

--[[pod_format="raw",created="2024-11-08 00:00:00",modified="2024-11-08 00:00:00",revision=0]]
-- Explosion Particle Object
-- Spawns multiple quads that scale up fast then slow down, fade out with dithering

local Explosion = {}
Explosion.__index = Explosion

-- Create a new explosion at the given position
-- config: table with the following optional fields:
--   - quad_count: number of quads to spawn (default: 1)
--   - sprite_id: sprite ID for quads (default: 19)
--   - lifetime: total lifetime in seconds (default: 2.0)
--   - initial_scale: starting scale (default: 1.0)
--   - max_scale: maximum scale reached at peak (default: 15.0)
--   - speed_up_time: time to reach max scale (default: 0.3s) - fast scaling
--   - slowdown_time: time from max scale to end (default: 1.7s) - slow fade
--   - slow_growth_factor: additional growth during fade phase (default: 0.2)
--   - fade_start_ratio: when fade starts as ratio of lifetime (default: 0.5)
--   - spread_distance: distance to spread quads from center (default: 5)
function Explosion.new(x, y, z, config)
	local self = setmetatable({}, Explosion)

	config = config or {}

	self.x = x
	self.y = y
	self.z = z
	self.lifetime = config.lifetime or 2.0
	self.age = 0
	self.active = true

	-- Scaling configuration
	self.initial_scale = config.initial_scale or 1.0
	self.max_scale = config.max_scale or 15.0
	self.speed_up_time = config.speed_up_time or 0.3
	self.slowdown_time = config.slowdown_time or 1.7
	self.slow_growth_factor = config.slow_growth_factor or 0.2
	self.fade_start_ratio = config.fade_start_ratio or 0.5

	-- Quad configuration
	self.quad_count = config.quad_count or 1
	self.sprite_id = config.sprite_id or 19
	self.spread_distance = config.spread_distance or 5

	-- Particles list to track individual quad particles
	self.particles = {}

	-- Spawn the quad particles
	self:spawn_particles()

	return self
end

-- Spawn all the quad particles in a burst
function Explosion:spawn_particles()
	-- Spawn only one quad at the center
	local particle = {
		x = self.x,
		y = self.y,
		z = self.z,
		age = 0,
		-- quad_obj will be set by the caller when integrating with main.lua
	}

	add(self.particles, particle)
end

-- Get the current scale at a given time progress (0 to 1)
-- Scales up fast initially, then continues to grow slowly while fading
function Explosion:get_scale(time_progress)
	if time_progress < 0 then
		return self.initial_scale
	end

	local speed_up_ratio = self.speed_up_time / self.lifetime

	-- Fast scale-up phase
	if time_progress <= speed_up_ratio then
		-- Linear scaling up to max quickly
		local phase_progress = time_progress / speed_up_ratio
		return self.initial_scale + (self.max_scale - self.initial_scale) * phase_progress
	end

	-- Slow scale-up/fade phase (continue growing slowly)
	-- After fast phase, continue scaling upward but at a much slower rate
	local remaining_ratio = (time_progress - speed_up_ratio) / (1 - speed_up_ratio)
	-- Add configurable growth during the slow phase
	local scale_growth_multiplier = 1.0 + (remaining_ratio * self.slow_growth_factor)
	return self.max_scale * scale_growth_multiplier
end

-- Get the current opacity at a given time progress (0 to 1)
-- Fades linearly from opaque to transparent over the lifetime
function Explosion:get_opacity(time_progress)
	if time_progress < 0 then
		return 1.0
	elseif time_progress >= 1 then
		return 0.0
	end

	-- Linear fade from opaque to transparent
	return 1.0 - time_progress
end

-- Update the explosion (returns false if explosion is dead)
function Explosion:update(dt)
	self.age += dt

	local time_progress = self.age / self.lifetime

	if time_progress >= 1 then
		self.active = false
		return false
	end

	-- Update individual particles (though they're mostly visual)
	for particle in all(self.particles) do
		particle.age += dt
	end

	return true
end

-- Get explosion state for rendering
-- Returns table with scale and opacity based on current age
function Explosion:get_state()
	local time_progress = self.age / self.lifetime
	return {
		scale = self:get_scale(time_progress),
		opacity = self:get_opacity(time_progress),
		age = self.age,
		lifetime = self.lifetime,
		time_progress = time_progress,
		active = self.active
	}
end

-- Get mesh face for rendering (used by ExplosionRenderer)
-- Creates quads that scale and fade using dither patterns
function Explosion:get_mesh_face(camera)
	local time_progress = self.age / self.lifetime
	local scale = self:get_scale(time_progress)
	local opacity = self:get_opacity(time_progress)

	-- If fully faded, don't render
	if opacity <= 0 then
		return nil
	end

	-- Build quad meshes for all particles
	local all_verts = {}
	local all_faces = {}
	local vert_offset = 0

	for _, particle in ipairs(self.particles) do
		local half_size = scale

		-- Camera forward vector (direction camera is looking)
		local forward_x = sin(camera.ry) * cos(camera.rx)
		local forward_y = sin(camera.rx)
		local forward_z = cos(camera.ry) * cos(camera.rx)

		-- Camera right vector (perpendicular to forward, in XZ plane)
		local right_x = cos(camera.ry)
		local right_y = 0
		local right_z = -sin(camera.ry)

		-- Camera up vector (cross product of forward and right, inverted)
		local up_x = -(forward_y * right_z - forward_z * right_y)
		local up_y = -(forward_z * right_x - forward_x * right_z)
		local up_z = -(forward_x * right_y - forward_y * right_x)

		-- Build quad vertices using right and up vectors
		local billboard_verts = {
			{x = -right_x * half_size + up_x * half_size, y = -right_y * half_size + up_y * half_size, z = -right_z * half_size + up_z * half_size},  -- Top-left
			{x = right_x * half_size + up_x * half_size, y = right_y * half_size + up_y * half_size, z = right_z * half_size + up_z * half_size},    -- Top-right
			{x = right_x * half_size - up_x * half_size, y = right_y * half_size - up_y * half_size, z = right_z * half_size - up_z * half_size},    -- Bottom-right
			{x = -right_x * half_size - up_x * half_size, y = -right_y * half_size - up_y * half_size, z = -right_z * half_size - up_z * half_size},  -- Bottom-left
		}

		-- Add verts to list
		for _, v in ipairs(billboard_verts) do
			add(all_verts, v)
		end

		-- Add faces (two triangles per quad) with opacity encoded as fog level for dithering
		local base = vert_offset + 1
		add(all_faces, {base, base+1, base+2, self.sprite_id, vec(0,0), vec(16,0), vec(16,16), fog = 1 - opacity})
		add(all_faces, {base, base+2, base+3, self.sprite_id, vec(0,0), vec(16,16), vec(0,16), fog = 1 - opacity})

		vert_offset = vert_offset + 4
	end

	return {
		verts = all_verts,
		faces = all_faces,
		x = self.x,
		y = self.y,
		z = self.z,
		opacity = opacity,
		use_dither = true
	}
end

return Explosion

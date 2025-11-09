--[[pod_format="raw",created="2024-11-09 00:00:00",modified="2024-11-09 00:00:00",revision=0]]
-- Smoke Particle Object
-- Spawns billboard quads that grow, float upward, and fade out

local Smoke = {}
Smoke.__index = Smoke

-- Create a new smoke particle at the given position
-- config: table with the following optional fields:
--   - sprite_id: sprite ID for quad (default: 18)
--   - lifetime: total lifetime in seconds (default: 1.0)
--   - initial_scale: starting scale (default: 0.5)
--   - max_scale: maximum scale (default: 2.0)
--   - growth_time: time to reach max scale (default: 0.3s)
--   - fade_time: time to fade out (default: 0.7s)
--   - velocity: {x, y, z} optional velocity (default upward movement)
function Smoke.new(x, y, z, config)
	local self = setmetatable({}, Smoke)

	config = config or {}

	self.x = x
	self.y = y
	self.z = z
	self.lifetime = config.lifetime or 2.0
	self.age = 0
	self.active = true

	-- Scaling configuration
	self.initial_scale = config.initial_scale or 0.5
	self.max_scale = config.max_scale or 2.0
	self.growth_time = config.growth_time or 0.2

	-- Sprite configuration
	self.sprite_id = config.sprite_id or 18

	-- Movement
	self.velocity = config.velocity or {x = 0, y = 0.5, z = 0}

	return self
end

-- Get the current scale at a given time progress (0 to 1)
-- Grows during growth_time, then stays at max_scale (no shrinking)
function Smoke:get_scale(time_progress)
	if time_progress < 0 then
		return self.initial_scale
	end

	local growth_ratio = self.growth_time / self.lifetime

	-- Growth phase - slow linear growth
	if time_progress <= growth_ratio then
		local phase_progress = time_progress / growth_ratio
		return self.initial_scale + (self.max_scale - self.initial_scale) * phase_progress
	end

	-- After growth phase, stay at max scale (no shrinking, only opacity fades)
	return self.max_scale
end

-- Get the current opacity at a given time progress (0 to 1)
-- Stays opaque for ~25% of lifetime, then fades linearly to transparent
function Smoke:get_opacity(time_progress)
	if time_progress < 0 then
		return 1.0
	elseif time_progress >= 1 then
		return 0.0
	end

	-- Stay opaque for the first 25% of lifetime, then fade
	local opaque_ratio = 0.25

	if time_progress <= opaque_ratio then
		return 1.0
	end

	-- Fade from opaque to transparent after opaque phase
	local fade_progress = (time_progress - opaque_ratio) / (1 - opaque_ratio)
	return 1.0 - fade_progress
end

-- Update the smoke particle (returns false if smoke is dead)
function Smoke:update(dt)
	self.age = self.age + dt

	-- Update position based on velocity
	self.x = self.x + self.velocity.x * dt
	self.y = self.y + self.velocity.y * dt
	self.z = self.z + self.velocity.z * dt

	local time_progress = self.age / self.lifetime

	if time_progress >= 1 then
		self.active = false
		return false
	end

	return true
end

-- Get smoke state for rendering
-- Returns table with scale and opacity based on current age
function Smoke:get_state()
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

-- Get mesh face for rendering (used for 3D billboard quad rendering)
-- Creates a quad that faces the camera and scales/fades
function Smoke:get_mesh_face(camera)
	local time_progress = self.age / self.lifetime
	local scale = self:get_scale(time_progress)
	local opacity = self:get_opacity(time_progress)

	-- If fully faded, don't render
	if opacity <= 0 then
		return nil
	end

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

	local all_verts = {}
	for _, v in ipairs(billboard_verts) do
		add(all_verts, v)
	end

	-- Add faces (two triangles per quad) with opacity encoded as fog level for dithering
	local all_faces = {}
	add(all_faces, {1, 2, 3, self.sprite_id, vec(0,0), vec(16,0), vec(16,16), fog = 1 - opacity})
	add(all_faces, {1, 3, 4, self.sprite_id, vec(0,0), vec(16,16), vec(0,16), fog = 1 - opacity})

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

return Smoke

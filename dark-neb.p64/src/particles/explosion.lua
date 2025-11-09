--[[pod_format="raw",created="2024-11-08 00:00:00",modified="2024-11-08 00:00:00",revision=0]]
-- Explosion Particle System
-- Creates growing and fading explosion effects using sprite 19

local Explosion = {}
Explosion.__index = Explosion

-- Create a new explosion at a position
-- x, y, z: world position of explosion
-- config: explosion configuration (from Config.explosion)
function Explosion.new(x, y, z, config)
	local self = setmetatable({}, Explosion)

	self.x = x
	self.y = y
	self.z = z
	self.lifetime = config.lifetime or 5.0
	self.age = 0
	self.sprite_id = config.sprite_id or 19
	self.quad_size = config.quad_size or 5
	self.max_scale = config.max_scale or 3.0
	self.dither_enabled = config.dither_enabled ~= false

	return self
end

-- Update explosion age
function Explosion:update(dt)
	self.age = self.age + dt
	return self.age < self.lifetime
end

-- Get current scale based on age (grows then shrinks while fading)
function Explosion:get_scale()
	local progress = self.age / self.lifetime
	-- Grow fast initially, then fade
	if progress < 0.3 then
		-- Growing phase: 0-30% time, scale from 1 to max
		return 1 + (progress / 0.3) * (self.max_scale - 1)
	else
		-- Fading phase: 30-100% time, scale stays at max but fades
		return self.max_scale
	end
end

-- Get current opacity (fade over time)
function Explosion:get_opacity()
	local progress = self.age / self.lifetime
	-- Fade out over time
	if progress < 0.2 then
		return 1.0  -- Full opacity for first 20%
	else
		-- Linear fade from 100% to 0%
		return max(0, 1.0 - (progress - 0.2) / 0.8)
	end
end

-- Get mesh for rendering (returns local vertices and faces for processing)
function Explosion:get_mesh_face(camera)
	local scale = self:get_scale()
	local opacity = self:get_opacity()

	-- Create a quad (2 triangles) at the explosion position
	-- Size: quad_size * scale on each side
	local half_size = (self.quad_size * scale) / 2

	-- Billboard quad vertices (in local space, centered at origin)
	-- Offset slightly in Z to avoid near-plane clipping
	local verts = {
		{x = -half_size, y = -half_size, z = 0.5},
		{x = half_size, y = -half_size, z = 0.5},
		{x = half_size, y = half_size, z = 0.5},
		{x = -half_size, y = half_size, z = 0.5},
	}

	-- Two triangles forming a quad
	-- Face format: {v1, v2, v3, sprite_id, uv1, uv2, uv3}
	-- Winding order: counter-clockwise from camera view (right-hand rule)
	local faces = {
		{1, 3, 2, self.sprite_id, {0, 0}, {16, 16}, {16, 0}},
		{1, 4, 3, self.sprite_id, {0, 0}, {0, 16}, {16, 16}},
	}

	return {
		verts = verts,
		faces = faces,
		opacity = opacity,
		x = self.x,
		y = self.y,
		z = self.z,
	}
end

-- Check if explosion is still active
function Explosion:is_active()
	return self.age < self.lifetime
end

return Explosion

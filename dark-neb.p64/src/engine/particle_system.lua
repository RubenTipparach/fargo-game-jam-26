-- Particle System Module
-- Handles creation, updating, and rendering of 3D particles

local ParticleSystem = {}
ParticleSystem.__index = ParticleSystem

-- Create a new particle system
function ParticleSystem.new(config)
	local self = setmetatable({}, ParticleSystem)

	-- Configuration
	self.particle_size = config.size or 0.16
	self.max_particles = config.max_particles or 4
	self.particle_lifetime = config.lifetime or 2.0
	self.spawn_rate = config.spawn_rate or 0.3
	self.sprite_id = config.sprite_id or 5
	self.scale_growth = config.scale_growth or 1.5  -- How much to grow over lifetime

	-- State
	self.particles = {}
	self.spawn_timer = 0

	-- Billboard mode: use camera-facing quads instead of 3D meshes for performance
	self.use_billboards = config.use_billboards or true

	-- Initialize particle pool
	for i = 1, self.max_particles do
		add(self.particles, {
			active = false,
			life = 0,
			x = 0, y = 0, z = 0,
			vx = 0, vy = 0, vz = 0,
			rot_x = 0, rot_y = 0, rot_z = 0,
			vrot_x = 0, vrot_y = 0, vrot_z = 0
		})
	end

	return self
end

-- Spawn a new particle at a given position with initial velocity
function ParticleSystem:spawn(x, y, z, vx, vy, vz, config)
	config = config or {}

	-- Find inactive particle slot
	for particle in all(self.particles) do
		if not particle.active then
			particle.active = true
			particle.life = 0
			particle.x = x
			particle.y = y
			particle.z = z

			-- Set velocity (inherit + random offset)
			local random_vx = config.random_vx or ((rnd(2) - 1) * 0.02)
			local random_vy = config.random_vy or (rnd(0.03) + 0.01)
			local random_vz = config.random_vz or ((rnd(2) - 1) * 0.02)

			particle.vx = (vx or 0) + random_vx
			particle.vy = (vy or 0) + random_vy
			particle.vz = (vz or 0) + random_vz

			-- No rotation for smoke
			particle.rot_x = 0
			particle.rot_y = 0
			particle.rot_z = 0
			particle.vrot_x = 0
			particle.vrot_y = 0
			particle.vrot_z = 0

			return true
		end
	end

	return false  -- No available slots
end

-- Update all active particles
function ParticleSystem:update(dt)
	for particle in all(self.particles) do
		if particle.active then
			particle.life += dt

			-- Update position
			particle.x += particle.vx
			particle.y += particle.vy
			particle.z += particle.vz

			-- No rotation update for smoke

			-- Apply drag
			particle.vx *= 0.98
			particle.vy *= 0.98
			particle.vz *= 0.98

			-- Deactivate particle when it expires
			if particle.life >= self.particle_lifetime then
				particle.active = false
			end
		end
	end
end

-- Render all active particles (returns faces to add to render queue)
-- @param render_mesh_func: function to render 3D meshes (or nil for billboards)
-- @param camera: camera object for billboard orientation (required if using billboards)
function ParticleSystem:render(render_mesh_func, camera)
	local all_particle_faces = {}

	for particle in all(self.particles) do
		if particle.active then
			local life_progress = particle.life / self.particle_lifetime

			-- Scale grows over lifetime
			local scale = (1.0 + life_progress * self.scale_growth) * self.particle_size

			-- Opacity grows from 25% to 100% over lifetime
			local opacity = 0.25 + (life_progress * 0.75)

			if opacity > 0 then
				if self.use_billboards and camera then
					-- BILLBOARD MODE: Create camera-facing quad
					-- Calculate camera's right and up vectors in world space
					local half_size = scale

					-- Camera forward vector (direction camera is looking)
					local forward_x = sin(camera.ry) * cos(camera.rx)
					local forward_y = sin(camera.rx)  -- Inverted pitch
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
						vec(-right_x * half_size + up_x * half_size, -right_y * half_size + up_y * half_size, -right_z * half_size + up_z * half_size),  -- Top-left
						vec(right_x * half_size + up_x * half_size, right_y * half_size + up_y * half_size, right_z * half_size + up_z * half_size),    -- Top-right
						vec(right_x * half_size - up_x * half_size, right_y * half_size - up_y * half_size, right_z * half_size - up_z * half_size),    -- Bottom-right
						vec(-right_x * half_size - up_x * half_size, -right_y * half_size - up_y * half_size, -right_z * half_size - up_z * half_size),  -- Bottom-left
					}

					-- Billboard faces: two triangles forming a quad
					local billboard_faces = {
						{1, 2, 3, self.sprite_id, vec(0,0), vec(16,0), vec(16,16)},    -- First triangle
						{1, 3, 4, self.sprite_id, vec(0,0), vec(16,16), vec(0,16)},    -- Second triangle
					}

					-- Render billboard at particle position
					local particle_sorted = render_mesh_func(
						billboard_verts,
						billboard_faces,
						particle.x,
						particle.y,
						particle.z
					)

					-- Add opacity information to each face
					for _, f in ipairs(particle_sorted) do
						f.opacity = opacity
						add(all_particle_faces, f)
					end
				end
			end
		end
	end

	return all_particle_faces
end

-- Get count of active particles
function ParticleSystem:get_active_count()
	local count = 0
	for particle in all(self.particles) do
		if particle.active then
			count += 1
		end
	end
	return count
end

return ParticleSystem

--[[pod_format="raw",created="2024-11-08 00:00:00",modified="2024-11-08 00:00:00",revision=0]]
-- Game Configuration

local Config = {}

-- Debug flags
Config.debug = false  -- General debug info (lights, sprites, etc)
Config.debug_lighting = true  -- Show only lighting arrow and rotation values
Config.show_cpu = true  -- Always show CPU stats

-- Star configuration
Config.stars = {
	count = 100,
	-- Color probabilities (must sum to 1.0)
	colors = {
		{color = 37, probability = 0.40},  -- 40% chance
		{color = 38, probability = 0.40},  -- 40% chance
		{color = 28, probability = 0.05},  -- 5% chance
		{color = 8,  probability = 0.05},  -- 5% chance
		{color = 9,  probability = 0.05},  -- 5% chance
		{color = 10, probability = 0.05},  -- 5% chance
	},
	-- Position range (world space)
	range = {
		x = {min = -200, max = 200},
		y = {min = -200, max = 200},
		z = {min = -200, max = 200},
	}
}

-- Camera configuration
Config.camera = {
	distance = 30,
	height = 3,  -- Camera elevation above ground (y position of focus point)
	rx = 0.05,  -- Initial rotation X (0.25 = looking straight down)
	ry = -0.36,  -- Initial rotation Y
	orbit_sensitivity = 0.01,  -- Mouse orbit speed
}

-- Ship/Model configuration
Config.ship = {
	position = {x = 0, y = 0, z = 0},
	rotation = {pitch = 0, yaw = 0, roll = 0},
	model_file = "shippy1.obj",
	sprite_id = 5,  -- Ship texture sprite
	speed = 0,  -- Current ship speed (0-1)
	max_speed = 1,  -- Maximum speed value
	speed_smoothing = 0.005,  -- Speed interpolation smoothing
	heading = 0,  -- Current heading in turns (0-1 range, 0 = +Z axis)
	target_heading = 0,  -- Target heading to turn towards (0-1 range)
	turn_rate = 0.0008,  -- Turns per frame (higher = faster turns)
	heading_arc_radius = 5,  -- Radius of the heading arc indicator
	heading_arc_segments = 16,  -- Number of segments for the arc
}

-- Sphere configuration
Config.sphere = {
	position = {x = -8, y = 0, z = 0},  -- To the left
	rotation = {pitch = 0, yaw = 0, roll = 0},
	radius = 3,
	segments = 8,
	stacks = 4,
}

-- Planet configuration
Config.planet = {
	position = {x = 50, y = 0, z = 0},  -- To the right (closer for visibility)
	rotation = {pitch = 0, yaw = 0, roll = 0},
	radius = 20,  -- Smaller radius to fit in view
	segments = 8,  -- More segments for smoother sphere
	stacks = 6,
	sprite_id = 24,  -- Sprite to use for texture
	spin_speed = 0.0001,  -- Rotation speed (faster for visibility)
}

-- Sun configuration (billboard sprite in skybox)
Config.sun = {
	sprite_id = 25,  -- Sun sprite
	size = 16,  -- Screen-space size of sun sprite
	distance = 100,  -- Distance from camera (for positioning opposite to light)
}

-- Lighting configuration
Config.lighting = {
	yaw = 0.19,  -- Initial light yaw
	pitch = -0.96,  -- Initial light pitch
	brightness = 2.0,
	ambient = 0.2,
	rotation_speed = 0.005,  -- Light rotation speed with WASD
}

-- Rendering configuration
Config.rendering = {
	render_distance = 200,  -- Increased for distant objects like planet
	clear_color = 0,  -- Dark blue/black background
}

-- Particle system configuration for ship movement
Config.particles = {
	enabled = true,  -- Enable particle effects for ship movement
	max_particles = 40,  -- Maximum number of active particles (increased for farther spread)
	lifetime = 2.0,  -- Particle lifetime in seconds (longer so trails last visible)
	spawn_rate = 0.05,  -- Rate at which particles spawn (lower = faster spawning)
	line_length = 2,  -- Length of particle lines in 3D units
	base_color = 11,  -- Base particle color (bright cyan)
	-- Color palette based on distance from ship (closest to farthest)
	color_palette = {28, 12, 7, 6, 13, 1},  -- 6 colors from closest to farthest
	max_dist = 30,  -- Maximum distance for color distribution
}

return Config

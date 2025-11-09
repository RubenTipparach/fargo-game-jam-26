--[[pod_format="raw",created="2024-11-08 00:00:00",modified="2024-11-08 00:00:00",revision=0]]
-- Game Configuration

local Config = {}

-- Debug flags
Config.debug = false  -- General debug info (lights, sprites, etc)
Config.debug_lighting = false  -- Show only lighting arrow and rotation values
Config.show_cpu = true  -- Always show CPU stats
Config.debug_physics = false  -- Show physics bounding boxes and collision wireframes
Config.enable_x_button = false  -- Enable X button input (disabled for now)

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
	render_distance = 200,  -- Maximum distance for rendering objects
	turn_rate = 0.0015,  -- Camera turn rate during target lock (turns per frame, higher = faster)
}

-- Ship/Model configuration
Config.ship = {
	position = {x = 0, y = 0, z = 0},
	rotation = {pitch = 0, yaw = 0, roll = 0},
	model_file = "models/shippy1.obj",
	sprite_id = 5,  -- Ship texture sprite
	speed = 0,  -- Current ship speed (0-1)
	max_speed = 1,  -- Maximum speed value
	speed_smoothing = 0.005,  -- Speed interpolation smoothing
	heading = 0,  -- Current heading in turns (0-1 range, 0 = +Z axis)
	target_heading = 0,  -- Target heading to turn towards (0-1 range)
	turn_rate = 0.0008,  -- Turns per frame (higher = faster turns)
	heading_arc_radius = 5,  -- Radius of the heading arc indicator
	heading_arc_segments = 16,  -- Number of segments for the arc
	-- Box collider for collision detection
	collider = {
		type = "box",
		half_size = {x = 2, y = 1.5, z = 3},  -- Half-extents of the box
	},
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
	-- Sphere collider for collision detection
	collider = {
		type = "sphere",
		radius = 20,  -- Match the planet radius
	},
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

-- Crosshair configuration
Config.crosshair = {
	max_distance = 8,  -- Only show crosshair if within this distance from ship on XZ plane
}

-- Speed slider configuration
Config.slider = {
	x = 450,  -- Right side of screen
	y = 100,   -- Top position
	height = 150,  -- Length of the slider track
	width = 10,  -- Width of the slider track
	handle_height = 20,  -- Height of the draggable handle
	text_x_offset = -30,  -- X offset for speed text from slider
	text_y_offset = 7,  -- Y offset for speed text from slider bottom
	text_color = 7,  -- Text color (white)
	text_prefix = "speed: ",  -- Text label prefix
}

-- Satellite configuration
Config.satellite = {
	position = {x = -30, y = 0, z = -40},
	rotation = {pitch = 0, yaw = 0, roll = 0},
	model_file = "models/satelite.obj",
	sprite_id = 2,  -- Texture sprite
	max_health = 100,  -- Health of satellite
	current_health = 100,  -- Current health
	sensor_range = 200,  -- Range for sensor detection (no fog of war for tutorial)
	-- Box collider for targeting
	collider = {
		type = "box",
		half_size = {x = 2, y = 2, z = 2},
	},
	bounding_box_color_default = 13,  -- Blue (cyan)
	bounding_box_color_hover = 10,  -- Yellow
}

-- Photon beam configuration
Config.photon_beam = {
	enabled = true,
	auto_fire = false,  -- Toggle for automatic firing
	fire_rate = 0.1,  -- Seconds between shots when auto firing
	beam_speed = 50,  -- World units per second
	beam_lifetime = 5.0,  -- Seconds before beam disappears
	beam_color = 11,  -- Bright cyan
}

-- Health and gameplay configuration
Config.health = {
	max_health = 100,
	death_screen_delay = 5.0,  -- Seconds before death screen appears
	ship_disappear_time = 0.5,  -- Seconds before ship disappears after collision
	health_bar_width = 150,
	health_bar_height = 10,
	health_bar_x = 10,  -- Top left X position
	health_bar_y = 10,  -- Top left Y position
}

-- Battlefield configuration
Config.battlefield = {
	map_size = 512,  -- Map is 512x512 units
	out_of_bounds_warning_time = 30.0,  -- Seconds before game ends after leaving (30 seconds)
}

-- Explosion particle configuration
Config.explosion = {
	enabled = true,  -- Enable explosions on death
	sprite_id = 19,  -- Sprite ID for explosion (big explosion sprite)

	-- Scale behavior
	quad_count = 1,  -- Number of quads to spawn (1 = single center quad)
	initial_scale = 1.0,  -- Starting scale of the quad
	max_scale = 5.0,  -- Maximum scale reached at peak
	speed_up_time = 0.2,  -- Time to reach max scale (seconds)
	slowdown_time = 1.7,  -- Time from max scale to end (seconds)
	slow_growth_factor = 0.2,  -- Additional growth during fade phase (20%)

	-- Fade behavior
	lifetime = 2.0,  -- Total explosion lifetime in seconds
	fade_start_ratio = 0.5,  -- When fade starts (0.5 = halfway through lifetime)

	-- Spread
	spread_distance = 5,  -- Distance to spread quads from center (for future multi-quad use)

	dither_enabled = true,  -- Apply dithering for growing/fading effect
}

return Config

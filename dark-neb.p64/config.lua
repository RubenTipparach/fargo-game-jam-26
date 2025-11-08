--[[pod_format="raw",created="2024-11-08 00:00:00",modified="2024-11-08 00:00:00",revision=0]]
-- Game Configuration

local Config = {}

-- Debug flags
Config.debug = false  -- General debug info (lights, sprites, etc)
Config.debug_lighting = false  -- Show only lighting arrow and rotation values
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
	height = 0,  -- Camera elevation above ground (y position of focus point)
	rx = 0.25,  -- Initial rotation X (0.25 = looking straight down)
	ry = 0,  -- Initial rotation Y
	orbit_sensitivity = 0.01,  -- Mouse orbit speed
}

-- Ship/Model configuration
Config.ship = {
	position = {x = 0, y = 0, z = 0},
	rotation = {pitch = 0, yaw = 0, roll = 0},
	model_file = "shippy1.obj",
	speed = 0,  -- Current ship speed (0-1)
	max_speed = 10,  -- Maximum speed value
	speed_smoothing = 0.01,  -- Speed interpolation smoothing
	heading = 0,  -- Current heading in radians (0 = +Z axis)
	target_heading = 0,  -- Target heading to turn towards
	turn_rate = 0.002,  -- Radians per frame (higher = faster turns)
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
	stacks = 8,
	sprite_id = 24,  -- Sprite to use for texture
	spin_speed = 0.0001,  -- Rotation speed (faster for visibility)
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

return Config

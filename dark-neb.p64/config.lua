--[[pod_format="raw",created="2024-11-08 00:00:00",modified="2024-11-08 00:00:00",revision=0]]
-- Game Configuration

local Config = {}

-- Debug flags
Config.debug = false  -- General debug info (lights, sprites, etc)
Config.debug_lighting = false  -- Show only lighting arrow and rotation values
Config.show_cpu = false  -- Always show CPU stats
Config.debug_physics = true  -- Show physics bounding boxes and collision wireframes
Config.enable_x_button = false  -- Enable X button input (disabled for now)
Config.show_firing_arcs = false  -- Always show firing arc visualization

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
	min_distance = 25,  -- Minimum zoom distance
	max_distance = 100,  -- Maximum zoom distance
	height = 6,  -- Camera elevation above ground (y position of focus point)
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
	arrow_key_rotation_speed = 0.01,  -- Arrow key rotation sensitivity (turns per frame)
	heading_arc_radius = 5,  -- Radius of the heading arc indicator
	heading_arc_segments = 8,  -- Number of segments for the arc
	armor = 0.8,  -- Armor rating (0-1): lower = takes more collision damage
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

-- Shield charge sliders configuration
Config.shield_sliders = {
	x = 10,  -- X position (matches health bar)
	y = 22,  -- Y position (health_bar_y + health_bar_height + 2)
	bar_width = 18,  -- Width of each shield bar
	bar_height = 10,  -- Height of each shield bar
	bar_spacing = 2,  -- Space between bars
	label_y_offset = -8,  -- Offset for "shields" label above bars

	-- Shield fill colors
	fill_color = 12,  -- Color when shield is charging/charged (blue)
	empty_color = 0,  -- Color when shield is empty/not charged (black)
	border_color = 7,  -- Border color (white)
}

-- Collision damage configuration
Config.collision = {
	base_damage = 5,  -- Base damage per frame during collision
	armor_factor = 2.0,  -- How much armor affects damage (lower armor = more damage)
	default_armor = 0.5,  -- Default armor if not specified
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
	lifetime = 3.5,  -- Total explosion lifetime in seconds
	fade_start_ratio = 0.5,  -- When fade starts (0.5 = halfway through lifetime)

	-- Spread
	spread_distance = 5,  -- Distance to spread quads from center (for future multi-quad use)

	dither_enabled = true,  -- Apply dithering for growing/fading effect
}

-- Music configuration
Config.music = {
	-- Mission 1 & 2 music
	missions_1_2 = {
		sfx_file = "sfx/novSong.sfx",
		pattern = 3,  -- Start playing from pattern 3
		memory_address = 0x80000,  -- Memory address to load music into
	},
	-- Mission 3 & 4 music
	missions_3_4 = {
		sfx_file = "sfx/darkneb.sfx",
		pattern = 8,  -- Start playing from pattern 8
		memory_address = 0x80000,  -- Memory address to load music into
		
	},
}

-- Weapons configuration
Config.weapons = {
	{
		name = "Photon Beam A",
		energy_cost = 2,  -- Minimum energy required to fire
		charge_time = 3,  -- Time in seconds to charge
		range = 80,  -- Maximum firing distance
		arc_start = -60,  -- Left edge of firing arc (degrees)
		arc_end = 30,  -- Right edge of firing arc (degrees)
		-- Muzzle offset from ship center (world units)
		muzzle_offset = {x = -2.0, y = 0.5, z = 3.0},  -- Left side, slightly forward
	},
	{
		name = "Photon Beam B",
		energy_cost = 4,  -- Minimum energy required to fire
		charge_time = 3.5,  -- Time in seconds to charge
		range = 80,  -- Maximum firing distance
		arc_start = -30,  -- Left edge of firing arc (degrees)
		arc_end = 60,  -- Right edge of firing arc (degrees)
		-- Muzzle offset from ship center (world units)
		muzzle_offset = {x = 2.0, y = 0.5, z = 3.0},  -- Right side, slightly forward
	},
}

-- Energy system configuration
Config.energy = {
	max_total = 8,  -- Total energy available
	bar_width = 8,  -- Width of each discrete energy rectangle
	bar_height = 8,  -- Height of each energy rectangle
	bar_spacing = 2,  -- Space between rectangles

	-- System energy capacities and defaults
	systems = {
		weapons = {
			capacity = 4,
			allocated = 4,  -- Auto-allocate all 4 bars to weapons for simplicity
			color_full = 24,  -- maroon
			color_empty = 0,  -- Black/dark
			label_offset = 5,  -- X offset from last box to label text
		},
		impulse = {
			capacity = 4,
			allocated = 2,
			color_full = 11,  -- green
			color_empty = 0,
			label_offset = 5,  -- X offset from last box to label text
		},
		shields = {
			capacity = 3,
			allocated = 0,
			color_full = 12,  -- blue
			color_empty = 0,
			label_offset = 5,  -- X offset from last box to label text
			charge_time = 15.0,  -- Seconds per shield box to fully charge
		},
		tractor_beam = {
			capacity = 2,
			allocated = 0,
			color_full = 18,  -- purple
			color_empty = 0,
			label_offset = 5,  -- X offset from last box to label text
			hidden = true,  -- Hide tractor_beam UI for now
		},
		sensors = {
			capacity = 2,
			allocated = 0,
			color_full = 17,  -- cyan
			color_empty = 0,
			label_offset = 5,  -- X offset from last box to label text
			-- Sensor-specific UI config
			damage_boost = {
				enabled = true,  -- Show damage boost text
				text_y_offset = 2,  -- Offset below sensor boxes
				text_x_offset = 0,  -- X offset from bar_x
				one_box_bonus = 0.5,  -- 50% bonus with 1 box
				two_plus_bonus = 0.7,  -- 70% bonus with 2+ boxes
			},
		},
	},

	-- UI POSITIONING (hitboxes will automatically use these values for ALL systems including sensors)
	ui_x = 10,  -- X position: left side position (vertical total energy bar) - HITBOXES MOVE WITH THIS
	ui_y = 40,  -- Y position: top of energy display (below health bar) - HITBOXES MOVE WITH THIS
	system_spacing = 15,  -- Vertical space between each system's energy bar - HITBOXES MOVE WITH THIS
	system_bar_x_offset = 20,  -- Horizontal offset for system energy bars from total energy bar - HITBOXES MOVE WITH THIS

	-- System label styling
	label = {
		color = 7,  -- White text
		text_color = 7,  -- Text color for system names
	},

	-- Total energy bar styling (vertical bar on the left)
	total_bar = {
		color_full = 0,  -- Black for filled (allocated) energy
		color_empty = 7,  -- White for empty (unallocated) energy
		border_color = 7,  -- White border
	},

	-- System box styling
	box = {
		border_color = 7,  -- White border around all boxes
	},

	-- Hitbox configuration for energy allocation clicks
	-- These define the clickable areas for adjusting energy allocation
	-- NOTE: Hitboxes automatically adjust with ui_x, ui_y, and system_spacing changes
	hitbox = {
		enabled = true,  -- Enable/disable hitbox detection
		padding = 1,  -- Extra padding around bars for easier clicking
	},
}

-- Mission and Goal UI configuration
Config.mission_ui = {
	panel_x = 10,  -- Left side of panel
	panel_y = 10,  -- Top of panel (below any top UI)
	panel_width = 110,  -- Width of unified panel
	panel_height = 225,  -- Total height of unified panel

	-- Dialog panel (objectives and mission info)
	dialog_panel_x = 30,  -- Top-left corner
	dialog_panel_y = 115,
	dialog_panel_width = 200,  -- Width of dialog panel
	dialog_panel_height = 80,  -- Height of dialog panel

	-- Dialog toggle button ("H" for hide/show)
	dialog_toggle_x_offset = -20,  -- Offset from dialog_panel_x (right edge of panel)
	dialog_toggle_y_offset = 10,  -- Offset from dialog_panel_y
	dialog_toggle_size = 12,  -- Size of the toggle button

	-- Mission objective section
	objective = {
		title_color = 11,  -- Yellow for title
		text_color = 7,  -- White for text
		text_color_complete = 11,  -- Green when complete
		title_spacing = 10,  -- Space after mission title
		objective_spacing = 10,  -- Space for objective name
		bar_height = 3,  -- Height of progress bar
		bar_color = 10,  -- Yellow for progress
		bar_color_complete = 11,  -- Green when complete
		bar_empty_color = 1,  -- Dark for empty
	},

	-- Overall progress slider
	progress_slider = {
		label_y_offset = -18,  -- Distance above slider for "Progress" text
		slider_y_offset = -10,  -- Distance from bottom of panel
		slider_height = 3,  -- Height of slider bar
		slider_color = 10,  -- Yellow for progress
		slider_empty_color = 1,  -- Dark for empty
	},

	-- Separator between mission and weapons
	separator = {
		margin_top = 5,  -- Space above separator
		margin_bottom = 3,  -- Space below separator
		color = 7,  -- White line
	},

	-- Max name length before abbreviation
	max_objective_name_length = 12,
}

-- Mission configurations
Config.missions = {
	-- Mission 1: Tutorial/Starting mission - no enemies, focus on controls
	mission_1 = {
		name = "Mission 1: Tutorial",
		description = "Learn basic controls",
		ship_start = {x = 0, y = 0, z = 0},
		planet_start = {x = 50, y = 0, z = 0},
		show_planet = true,
		show_progress_slider = true,
		-- No satellites for tutorial mission
		satellites = {},
		objectives = {
			{
				type = "tutorial",
				description = "Master ship controls",
			},
		},
	},
	-- Mission 2: Weapon systems with enemy satellites
	mission_2 = {
		name = "Mission 2: Weapons & Targeting",
		description = "Destroy the satellites",
		ship_start = {x = 0, y = 0, z = 0},
		planet_start = {x = 50, y = 0, z = 0},
		show_planet = true,
		show_progress_slider = true,
		-- Satellite definitions for this mission
		-- Both satellites positioned ~100m away from ship start (0, 0, 0)
		satellites = {
			{
				id = "satellite_1",
				position = {x = -70.7, y = 0, z = -70.7},  -- ~100m away (diagonal)
				rotation = {pitch = 0, yaw = 0, roll = 0},
				model_file = "models/satelite.obj",
				sprite_id = 2,
				max_health = 100,
				current_health = 100,
				armor = 1.5,  -- Less armored than ship
				sensor_range = 200,
				collider = {
					type = "box",
					half_size = {x = 2, y = 2, z = 2},
				},
				bounding_box_color_default = 13,  -- Blue (cyan)
				bounding_box_color_hover = 10,  -- Yellow
			},
			{
				id = "satellite_2",
				position = {x = 70.7, y = 0, z = 70.7},  -- ~100m away (diagonal opposite)
				rotation = {pitch = 0, yaw = 0, roll = 0},
				model_file = "models/satelite.obj",
				sprite_id = 2,
				max_health = 100,
				current_health = 100,
				armor = 1.5,  -- Less armored than ship
				sensor_range = 200,
				collider = {
					type = "box",
					half_size = {x = 2, y = 2, z = 2},
				},
				bounding_box_color_default = 13,  -- Blue (cyan)
				bounding_box_color_hover = 10,  -- Yellow
			},
		},
		objectives = {
			{
				type = "destroy",
				target = "satellite",
				min_health_percent = 50,  -- Keep satellite above 50% health
			},
		},
	},
	-- Mission 3: Patrol - First day on the job, find and destroy the enemy
	mission_3 = {
		name = "Mission 3: Patrol",
		description = "Find and destroy the enemy Grabon",
		ship_start = {x = 0, y = 0, z = 0},
		show_planet = false,
		show_progress_slider = false,
		-- Enemy Grabon AI opponent
		enemies = {
			{
				id = "grabon_1",
				position = {x = 100, y = 0, z = 100},  -- Far away, player must search
				rotation = {pitch = 0, yaw = 0, roll = 0},
				heading = 0.5,  -- Initial heading (0-1 turns)
				model_file = "models/grabons.obj",
				sprite_id = 1,
				max_health = 150,
				current_health = 150,
				armor = 2.0,  -- Tougher than satellites
				sensor_range = 250,  -- Can detect player from far away
				-- AI behavior
				ai = {
					-- Movement
					speed = 0.5,  -- Allocated speed (0-1)
					max_speed = 1.0,
					turn_rate = 0.001,  -- Slow rotation towards target
					-- Combat
					target_detection_range = 250,
					attack_range = 70,
					firing_arc_start = -90,  -- Weapon arc
					firing_arc_end = 90,
					-- Dual weapons (like player ship)
					weapons = {
						{
							name = "Primary Cannon",
							charge_time = 2.0,
							fire_rate = 3.0,  -- Seconds between shots
							range = 80,
							damage = 5,
							last_fire_time = 0,
							-- Muzzle offset from Grabon center (world units)
							muzzle_offset = {x = -1.5, y = 0.3, z = 4.0},  -- Left side, forward
						},
						{
							name = "Secondary Cannon",
							charge_time = 2.5,
							fire_rate = 3.0,
							range = 80,
							damage = 5,
							last_fire_time = 0,
							-- Muzzle offset from Grabon center (world units)
							muzzle_offset = {x = 1.5, y = 0.3, z = 4.0},  -- Right side, forward
						},
					},
				},
				collider = {
					type = "box",
					half_size = {x = 2.5, y = 1.5, z = 3.5},  -- Slightly larger than satellite
				},
				bounding_box_color_default = 8,  -- Red (enemy)
				bounding_box_color_hover = 10,  -- Yellow when targeted
			},
		},
		objectives = {
			{
				type = "find_and_destroy",
				target = "grabon",
				min_health_percent = 0,  -- Fully destroy
			},
		},
	},
	-- Mission 4: Dual Combat - Two enemy Grabons
	mission_4 = {
		name = "Mission 4: Dual Combat",
		description = "Destroy both enemy Emularns",
		ship_start = {x = 0, y = 0, z = 0},
		show_planet = false,
		show_progress_slider = false,
		-- Two Enemy Grabon AI opponents
		enemies = {
			{
				id = "emularn_1",
				position = {x = 80, y = 0, z = 80},  -- First Grabon (northeast)
				rotation = {pitch = 0, yaw = 0, roll = 0},
				heading = 0.75,  -- Initial heading (0-1 turns)
				model_file = "models/Emularns.obj",
				sprite_id = 4,
				max_health = 150,
				current_health = 150,
				armor = 2.0,  -- Tougher than satellites
				sensor_range = 250,  -- Can detect player from far away
				-- AI behavior
				ai = {
					-- Movement
					speed = 0.5,  -- Allocated speed (0-1)
					max_speed = 1.0,
					turn_rate = 0.001,  -- Slow rotation towards target
					-- Combat
					target_detection_range = 250,
					attack_range = 80,
					firing_arc_start = -90,  -- Weapon arc
					firing_arc_end = 90,
					-- Dual weapons (like player ship)
					weapons = {
						{
							name = "Primary Cannon",
							charge_time = 2.0,
							fire_rate = 3.0,  -- Seconds between shots
							range = 70,
							damage = 5,
							last_fire_time = 0,
							-- Muzzle offset from Grabon center (world units)
							muzzle_offset = {x = -1.5, y = 0.3, z = 4.0},  -- Left side, forward
						},
						{
							name = "Secondary Cannon",
							charge_time = 2.5,
							fire_rate = 3.0,
							range = 80,
							damage = 5,
							last_fire_time = 0,
							-- Muzzle offset from Grabon center (world units)
							muzzle_offset = {x = 1.5, y = 0.3, z = 4.0},  -- Right side, forward
						},
					},
				},
				collider = {
					type = "box",
					half_size = {x = 2.5, y = 1.5, z = 3.5},  -- Slightly larger than satellite
				},
				bounding_box_color_default = 8,  -- Red (enemy)
				bounding_box_color_hover = 10,  -- Yellow when targeted
			},
			{
				id = "emularn_2",
				position = {x = -80, y = 0, z = -80},  -- Second Grabon (southwest)
				rotation = {pitch = 0, yaw = 0, roll = 0},
				heading = 0.25,  -- Initial heading (0-1 turns)
				model_file = "models/Emularns.obj",
				sprite_id = 4,
				max_health = 150,
				current_health = 150,
				armor = 2.0,  -- Tougher than satellites
				sensor_range = 250,  -- Can detect player from far away
				-- AI behavior
				ai = {
					-- Movement
					speed = 0.5,  -- Allocated speed (0-1)
					max_speed = 1.0,
					turn_rate = 0.001,  -- Slow rotation towards target
					-- Combat
					target_detection_range = 250,
					attack_range = 70,
					firing_arc_start = -90,  -- Weapon arc
					firing_arc_end = 90,
					-- Dual weapons (like player ship)
					weapons = {
						{
							name = "Primary Cannon",
							charge_time = 2.0,
							fire_rate = 3.0,  -- Seconds between shots
							range = 70,
							damage = 5,
							last_fire_time = 0,
							-- Muzzle offset from Grabon center (world units)
							muzzle_offset = {x = -1.5, y = 0.3, z = 4.0},  -- Left side, forward
						},
						{
							name = "Secondary Cannon",
							charge_time = 2.5,
							fire_rate = 3.0,
							range = 70,
							damage = 5,
							last_fire_time = 0,
							-- Muzzle offset from Grabon center (world units)
							muzzle_offset = {x = 1.5, y = 0.3, z = 4.0},  -- Right side, forward
						},
					},
				},
				collider = {
					type = "box",
					half_size = {x = 2.5, y = 1.5, z = 3.5},  -- Slightly larger than satellite
				},
				bounding_box_color_default = 8,  -- Red (enemy)
				bounding_box_color_hover = 10,  -- Yellow when targeted
			},
		},
		objectives = {
			{
				type = "find_and_destroy",
				target = "grabon",
				min_health_percent = 0,  -- Fully destroy both
			},
		},
	},
}

-- Set current mission (default to mission 1)
Config.current_mission = Config.missions.mission_1

return Config

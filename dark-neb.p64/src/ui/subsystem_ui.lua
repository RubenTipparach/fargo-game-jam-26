--[[pod_format="raw",created="2024-11-08 00:00:00",modified="2024-11-08 00:00:00",revision=0]]
-- SubsystemUI Module
-- Displays subsystem status for player and target ships
-- Shows attack angles, damage states, and repair queue

local SubsystemUI = {}

-- Configuration
local Config = nil
local SubsystemManager = nil

-- UI state
local player_hit_flash = {}  -- {subsystem_name = flash_time_remaining}

-- Repair state per entity
-- {entity_id = {queue = {}, progress = 0, kits = 10}}
local entity_repair_state = {}

-- Subsystem display layout (angle in turns, 0 = right, 0.25 = up)
-- Arranged evenly in a circle (5 items = 0.2 turns apart)
-- Ship orientation: front = up (0.25), rear = down (0.75)
local SUBSYSTEM_LAYOUT = {
	sensors = {angle = 0.25, radius = 1.0},       -- Front (top)
	shields = {angle = 0.45, radius = 1.0},       -- Front-left
	life_support = {angle = 0.65, radius = 1.0},  -- Rear-left
	engines = {angle = 0.85, radius = 1.0},       -- Rear-right
	weapons = {angle = 0.05, radius = 1.0},       -- Front-right
}

-- Subsystem full names for hover display
local SUBSYSTEM_NAMES = {
	weapons = "Weapons",
	engines = "Engines",
	shields = "Shields",
	sensors = "Sensors",
	life_support = "Life Support",
}

-- Hover state
local hovered_subsystem = nil
local hover_mx, hover_my = 0, 0

-- Colors for each subsystem
local SUBSYSTEM_COLORS = {
	weapons = 8,       -- Red
	engines = 11,      -- Green
	shields = 12,      -- Blue
	sensors = 10,      -- Yellow
	life_support = 9,  -- Orange
}

-- Subsystem short names for display
local SUBSYSTEM_SHORT = {
	weapons = "WPN",
	engines = "ENG",
	shields = "SHD",
	sensors = "SNS",
	life_support = "LIF",
}

-- Initialize with dependencies
function SubsystemUI.init(config, subsystem_manager)
	Config = config
	SubsystemManager = subsystem_manager
	player_hit_flash = {}
	entity_repair_state = {}
end

-- Initialize repair state for an entity
function SubsystemUI.init_entity_repair(entity_id, starting_kits)
	local kits = starting_kits or (Config.subsystems and Config.subsystems.repair and Config.subsystems.repair.starting_kits) or 10
	entity_repair_state[entity_id] = {
		queue = {},
		progress = 0,
		kits = kits,
	}
end

-- Get repair kits for an entity
function SubsystemUI.get_repair_kits(entity_id)
	local state = entity_repair_state[entity_id]
	return state and state.kits or 0
end

-- Flash a player subsystem when hit
function SubsystemUI.flash_subsystem(subsystem_name)
	player_hit_flash[subsystem_name] = 0.5  -- Flash for 0.5 seconds
end

-- Add subsystem to repair queue for an entity
function SubsystemUI.queue_repair(entity_id, subsystem_name)
	local state = entity_repair_state[entity_id]
	if not state then return false end

	-- Don't add if no repair kits available
	if state.kits <= 0 then return false end

	-- Don't add if already in queue
	for _, name in ipairs(state.queue) do
		if name == subsystem_name then return false end
	end
	table.insert(state.queue, subsystem_name)
	return true
end

-- Remove subsystem from repair queue
function SubsystemUI.cancel_repair(entity_id, subsystem_name)
	local state = entity_repair_state[entity_id]
	if not state then return end

	for i = #state.queue, 1, -1 do
		if state.queue[i] == subsystem_name then
			table.remove(state.queue, i)
			if i == 1 then state.progress = 0 end
			return
		end
	end
end

-- Get repair queue for an entity
function SubsystemUI.get_repair_queue(entity_id)
	local state = entity_repair_state[entity_id]
	return state and state.queue or {}
end

-- Get repair progress for an entity (0-1)
function SubsystemUI.get_repair_progress(entity_id)
	local state = entity_repair_state[entity_id]
	return state and state.progress or 0
end

-- Update repair progress and flash timers
-- @param dt: Delta time
function SubsystemUI.update(dt)
	-- Update flash timers
	for name, time_left in pairs(player_hit_flash) do
		player_hit_flash[name] = time_left - dt
		if player_hit_flash[name] <= 0 then
			player_hit_flash[name] = nil
		end
	end

	-- Get repair time from config
	local repair_time = (Config.subsystems and Config.subsystems.repair and Config.subsystems.repair.repair_time) or 5.0

	-- Process repair queue for all entities
	for entity_id, state in pairs(entity_repair_state) do
		if #state.queue > 0 and state.kits > 0 and SubsystemManager then
			local current_repair = state.queue[1]
			local health, max_health = SubsystemManager.get_health(entity_id, current_repair)

			if health < max_health then
				-- Progress repair (fixed time, not health-based)
				state.progress = state.progress + (dt / repair_time)

				if state.progress >= 1 then
					-- Repair complete - fully restore subsystem and consume kit
					SubsystemManager.repair(entity_id, current_repair, max_health)
					state.kits = state.kits - 1
					table.remove(state.queue, 1)
					state.progress = 0
					printh("Repair complete: " .. entity_id .. " " .. current_repair .. " (kits remaining: " .. state.kits .. ")")
				end
			else
				-- Already full health, skip without consuming kit
				table.remove(state.queue, 1)
				state.progress = 0
			end
		end
	end
end

-- Auto-queue repairs for damaged subsystems (for AI enemies)
function SubsystemUI.auto_queue_repairs(entity_id)
	if not SubsystemManager then return end

	local states = SubsystemManager.get_all_states(entity_id)
	if not states then return end

	local repair_state = entity_repair_state[entity_id]
	if not repair_state or repair_state.kits <= 0 then return end

	-- Priority order for auto-repair
	local priority = {"weapons", "engines", "shields", "sensors", "life_support"}

	for _, name in ipairs(priority) do
		local sub = states[name]
		if sub and sub.health < sub.max_health then
			-- Check if already in queue
			local in_queue = false
			for _, queued in ipairs(repair_state.queue) do
				if queued == name then in_queue = true break end
			end
			if not in_queue and #repair_state.queue < repair_state.kits then
				SubsystemUI.queue_repair(entity_id, name)
			end
		end
	end
end

-- Calculate which subsystem is likely to be hit based on attack angle
-- @param attack_angle: Angle of attack in turns (0-1), where 0.25 = from front
-- @return: Name of most likely subsystem to be hit
local function get_likely_hit_subsystem(attack_angle)
	-- Normalize angle to 0-1
	attack_angle = attack_angle % 1

	-- Find the subsystem whose layout angle is closest to the attack angle
	local closest_subsystem = "weapons"
	local closest_diff = 1

	for name, layout in pairs(SUBSYSTEM_LAYOUT) do
		-- Calculate angular distance (accounting for wrap-around at 0/1)
		local diff = abs(attack_angle - layout.angle)
		if diff > 0.5 then diff = 1 - diff end  -- Handle wrap-around

		if diff < closest_diff then
			closest_diff = diff
			closest_subsystem = name
		end
	end

	return closest_subsystem
end

-- Get box position for a subsystem
-- @param cx, cy: Center of the circular display
-- @param radius: Radius of the display circle
-- @param subsystem_name: Name of the subsystem
-- @return: box_x, box_y center position
local function get_subsystem_box_pos(cx, cy, radius, subsystem_name)
	local layout = SUBSYSTEM_LAYOUT[subsystem_name]
	if not layout then return cx, cy end
	local box_x = cx + cos(layout.angle) * radius * layout.radius
	local box_y = cy - sin(layout.angle) * radius * layout.radius
	return box_x, box_y
end

-- Draw a single subsystem box
-- @param cx, cy: Center of the circular display
-- @param radius: Radius of the display circle
-- @param subsystem_name: Name of the subsystem
-- @param health: Current health
-- @param max_health: Maximum health
-- @param destroyed: Whether subsystem is destroyed
-- @param highlighted: Whether this subsystem is likely to be hit (danger indicator)
-- @param flashing: Whether to flash (player hit effect)
-- @param in_repair_queue: Position in repair queue (0 = not queued)
-- @param mx, my: Mouse position for hover detection (optional)
-- @return: box_x, box_y, half (for external hover detection)
local function draw_subsystem_box(cx, cy, radius, subsystem_name, health, max_health, destroyed, highlighted, flashing, in_repair_queue, mx, my)
	local layout = SUBSYSTEM_LAYOUT[subsystem_name]
	if not layout then return nil, nil, nil end

	-- Calculate box position
	local box_x, box_y = get_subsystem_box_pos(cx, cy, radius, subsystem_name)

	local box_size = 8
	local half = box_size / 2

	-- Check hover
	if mx and my then
		if mx >= box_x - half and mx <= box_x + half and my >= box_y - half and my <= box_y + half + 3 then
			hovered_subsystem = subsystem_name
			hover_mx, hover_my = mx, my
		end
	end

	-- Determine color
	local fill_color = SUBSYSTEM_COLORS[subsystem_name] or 7
	local border_color = 6  -- Light gray

	if destroyed then
		fill_color = 1  -- Dark blue (disabled)
		border_color = SUBSYSTEM_COLORS[subsystem_name] or 6  -- Keep original subsystem color for border
	elseif flashing and (t() * 8) % 1 < 0.5 then
		fill_color = 7  -- White flash
		border_color = 7
	elseif highlighted then
		-- Gold blinking border for danger (slow blink ~1Hz)
		if (t() * 2) % 1 < 0.5 then
			border_color = 10  -- Gold/Yellow
		else
			border_color = 9   -- Orange (alternate)
		end
	end

	-- Draw box
	rectfill(box_x - half, box_y - half, box_x + half, box_y + half, fill_color)
	rect(box_x - half, box_y - half, box_x + half, box_y + half, border_color)

	-- Draw extra thick border if highlighted (danger)
	if highlighted and not destroyed then
		rect(box_x - half - 1, box_y - half - 1, box_x + half + 1, box_y + half + 1, border_color)
	end

	-- Draw health bar (1 pixel height)
	if max_health > 0 then
		local bar_width = box_size
		local bar_x = box_x - half
		local bar_y = box_y + half + 2

		-- Background
		rectfill(bar_x, bar_y, bar_x + bar_width, bar_y, 1)

		-- Health fill
		local health_ratio = health / max_health
		local fill_width = flr(bar_width * health_ratio)
		if fill_width > 0 then
			local health_color = 11  -- Green
			if health_ratio < 0.5 then health_color = 10 end  -- Yellow
			if health_ratio < 0.25 then health_color = 8 end  -- Red
			rectfill(bar_x, bar_y, bar_x + fill_width, bar_y, health_color)
		end
	end

	-- Draw repair queue indicator
	if in_repair_queue > 0 then
		local queue_text = tostring(in_repair_queue)
		print(queue_text, box_x - 1, box_y - half - 6, 11)
	end

	return box_x, box_y, half
end

-- Draw attack angle indicator
-- @param cx, cy: Center of the circular display
-- @param radius: Radius of the display circle
-- @param attack_angle: Angle of attack in turns (0-1), where 0.25 = top/front
local function draw_attack_angle(cx, cy, radius, attack_angle)
	if not attack_angle then return end

	-- Draw arrow pointing inward from attack direction
	local arrow_start_x = cx + cos(attack_angle) * (radius + 5)  -- Outer end
	local arrow_start_y = cy - sin(attack_angle) * (radius + 5)
	local arrow_end_x = cx + cos(attack_angle) * (radius - 2)    -- Inner end (tip)
	local arrow_end_y = cy - sin(attack_angle) * (radius - 2)

	line(arrow_start_x, arrow_start_y, arrow_end_x, arrow_end_y, 8)  -- Red arrow

	-- Arrow head at inner end (tip), lines go toward center to form "V" pointing inward
	local head_angle1 = attack_angle + 0.1  -- Same direction + spread
	local head_angle2 = attack_angle - 0.1  -- Same direction - spread
	local head_len = 4
	line(arrow_end_x, arrow_end_y, arrow_end_x + cos(head_angle1) * head_len, arrow_end_y - sin(head_angle1) * head_len, 8)
	line(arrow_end_x, arrow_end_y, arrow_end_x + cos(head_angle2) * head_len, arrow_end_y - sin(head_angle2) * head_len, 8)
end

-- Draw target subsystem display
-- @param target: Target entity with position and heading
-- @param player_pos: Player position {x, z}
-- @param ui_x, ui_y: Top-left corner of the display
-- @param mx, my: Mouse position for hover detection (optional)
function SubsystemUI.draw_target(target, player_pos, ui_x, ui_y, mx, my)
	if not target or not target.id or not SubsystemManager then return end

	local states = SubsystemManager.get_all_states(target.id)
	if not states then return end

	local display_size = 50
	local radius = display_size / 2 - 5
	local cx = ui_x + display_size / 2
	local cy = ui_y + display_size / 2

	-- Draw background circle
	circfill(cx, cy, radius + 3, 0)
	circ(cx, cy, radius + 3, 6)

	-- Calculate attack angle (player to target direction, relative to target heading)
	-- Only show if we have a selected target with valid position
	local attack_angle = nil
	local likely_hit = nil
	if player_pos and target.position then
		-- Negate dx to fix left/right mirroring (screen X is opposite of world X for atan2)
		local dx = target.position.x - player_pos.x
		local dz = player_pos.z - target.position.z
		local world_angle = atan2(dx, dz)  -- Angle from target to player (corrected)
		local target_heading = target.heading or 0
		attack_angle = (world_angle - target_heading + 0.25) % 1  -- Relative to target's front
		likely_hit = get_likely_hit_subsystem(attack_angle)
	end

	-- Draw each subsystem FIRST (so arrow draws on top)
	for name, state in pairs(states) do
		local highlighted = (name == likely_hit)
		draw_subsystem_box(cx, cy, radius, name, state.health, state.max_health, state.destroyed, highlighted, false, 0, mx, my)
	end

	-- Draw attack angle indicator ON TOP of subsystems
	if attack_angle then
		draw_attack_angle(cx, cy, radius, attack_angle)
	end

	-- Label in red (target/enemy color)
	print("TARGET", ui_x + 8, ui_y + display_size + 2, 8)
end

-- Draw player subsystem display
-- @param player_id: Player entity ID
-- @param enemy_pos: Nearest enemy position {x, z} or nil
-- @param player_pos: Player position {x, z}
-- @param player_heading: Player heading in turns
-- @param ui_x, ui_y: Top-left corner of the display
-- @param mx, my: Mouse position for repair queue interaction
-- @param clicked: Whether mouse was clicked this frame
function SubsystemUI.draw_player(player_id, enemy_pos, player_pos, player_heading, ui_x, ui_y, mx, my, clicked)
	if not player_id or not SubsystemManager then
		-- Debug: draw placeholder if no manager
		rectfill(ui_x, ui_y, ui_x + 50, ui_y + 50, 2)
		print("NO MGR", ui_x + 5, ui_y + 20, 8)
		return
	end

	local states = SubsystemManager.get_all_states(player_id)
	if not states then
		-- Debug: draw placeholder if no states
		rectfill(ui_x, ui_y, ui_x + 50, ui_y + 50, 5)
		print("NO STATE", ui_x + 2, ui_y + 20, 8)
		return
	end

	local display_size = 50
	local radius = display_size / 2 - 5
	local cx = ui_x + display_size / 2
	local cy = ui_y + display_size / 2

	-- Draw background circle
	circfill(cx, cy, radius + 3, 0)
	circ(cx, cy, radius + 3, 6)

	-- Calculate incoming attack angle (enemy to player, relative to player heading)
	-- Only show arrow if enemy_pos is provided (indicates active threat)
	local attack_angle = nil
	local likely_hit = nil
	if enemy_pos and player_pos then
		-- Negate dx to fix left/right mirroring (screen X is opposite of world X for atan2)
		local dx = player_pos.x - enemy_pos.x
		local dz = enemy_pos.z - player_pos.z
		local world_angle = atan2(dx, dz)  -- Angle from enemy to player (corrected)
		attack_angle = (world_angle - player_heading + 0.25) % 1  -- Relative to player's front
		likely_hit = get_likely_hit_subsystem(attack_angle)
	end

	-- Get repair state for this entity
	local repair_state = entity_repair_state[player_id]
	local repair_queue = repair_state and repair_state.queue or {}
	local repair_kits = repair_state and repair_state.kits or 0

	-- Draw each subsystem FIRST and check for clicks
	for name, state in pairs(states) do
		local layout = SUBSYSTEM_LAYOUT[name]
		if layout then
			local box_x, box_y = get_subsystem_box_pos(cx, cy, radius, name)
			local box_size = 8
			local half = box_size / 2

			-- Check for repair queue click (allow destroyed subsystems to be queued for repair)
			if clicked and state.health < state.max_health and repair_kits > 0 then
				if mx >= box_x - half and mx <= box_x + half and my >= box_y - half and my <= box_y + half + 3 then
					-- Toggle repair queue
					local in_queue = false
					for i, queued in ipairs(repair_queue) do
						if queued == name then
							SubsystemUI.cancel_repair(player_id, name)
							in_queue = true
							break
						end
					end
					if not in_queue then
						SubsystemUI.queue_repair(player_id, name)
					end
				end
			end

			-- Find position in repair queue
			local queue_pos = 0
			for i, queued in ipairs(repair_queue) do
				if queued == name then
					queue_pos = i
					break
				end
			end

			local highlighted = (name == likely_hit)
			local flashing = player_hit_flash[name] ~= nil
			draw_subsystem_box(cx, cy, radius, name, state.health, state.max_health, state.destroyed, highlighted, flashing, queue_pos, mx, my)
		end
	end

	-- Draw attack angle indicator ON TOP of subsystems (if enemy nearby)
	if attack_angle then
		draw_attack_angle(cx, cy, radius, attack_angle)
	end

	-- Draw repair queue list and progress
	local queue_y = ui_y + display_size + 12

	-- Show repair kits count
	print("KITS:" .. repair_kits, ui_x, queue_y, repair_kits > 0 and 11 or 8)
	queue_y = queue_y + 8

	-- Show repair queue with progress
	if #repair_queue > 0 then
		local repair_progress = repair_state and repair_state.progress or 0

		for i, subsystem_name in ipairs(repair_queue) do
			local short_name = SUBSYSTEM_SHORT[subsystem_name] or subsystem_name
			local color = SUBSYSTEM_COLORS[subsystem_name] or 7

			if i == 1 then
				-- Currently repairing - show progress bar
				local bar_width = 30
				local bar_x = ui_x
				local bar_y = queue_y

				-- Background
				rectfill(bar_x, bar_y, bar_x + bar_width, bar_y + 6, 1)
				-- Progress fill
				rectfill(bar_x, bar_y, bar_x + flr(bar_width * repair_progress), bar_y + 6, color)
				-- Border
				rect(bar_x, bar_y, bar_x + bar_width, bar_y + 6, 6)
				-- Label
				print(short_name, bar_x + bar_width + 3, bar_y, color)
			else
				-- Queued - just show name with queue position
				print(i .. ":" .. short_name, ui_x, queue_y, 5)
			end
			queue_y = queue_y + 8

			-- Only show first 4 in queue
			if i >= 4 then
				if #repair_queue > 4 then
					print("+" .. (#repair_queue - 4) .. " more", ui_x, queue_y, 5)
				end
				break
			end
		end
	end

	-- Label in green (player/friendly color)
	print("PLAYER", ui_x + 6, ui_y + display_size + 2, 11)
end

-- Clear hover state (call before drawing subsystem UIs)
function SubsystemUI.clear_hover()
	hovered_subsystem = nil
end

-- Draw hover tooltip near mouse if hovering over a subsystem
function SubsystemUI.draw_hover_tooltip()
	if hovered_subsystem and SUBSYSTEM_NAMES[hovered_subsystem] then
		local text = SUBSYSTEM_NAMES[hovered_subsystem]

		-- Measure text width using Picotron's print return value (print offscreen)
		local text_width = print(text, 0, -20) - 1  -- -1 to remove trailing space
		local text_height = 7  -- Picotron default font height

		-- Padding around text
		local pad_x = 3
		local pad_y = 3

		-- Calculate box dimensions
		local box_width = text_width + pad_x * 2
		local box_height = text_height + pad_y * 2

		-- Position tooltip to the right of mouse
		local box_x = hover_mx + 10
		local box_y = hover_my - box_height / 2

		-- Keep tooltip on screen
		if box_x + box_width > 475 then
			box_x = hover_mx - box_width - 5
		end
		if box_y < 2 then box_y = 2 end
		if box_y + box_height > 268 then box_y = 268 - box_height end

		-- Draw background box
		rectfill(box_x, box_y, box_x + box_width - 1, box_y + box_height - 1, 0)
		rect(box_x, box_y, box_x + box_width - 1, box_y + box_height - 1, 6)

		-- Draw text centered in box
		local text_x = box_x + pad_x
		local text_y = box_y + pad_y
		print(text, text_x, text_y, 7)
	end
end

-- Get UI configuration
function SubsystemUI.get_layout()
	return {
		target_x = 480 - 64 - 5 - 55,  -- Left of minimap
		target_y = 10,
		player_x = 165,                 -- Right of health bar
		player_y = 5,                   -- Near top, aligned with health bar area
		display_size = 50,
	}
end

return SubsystemUI

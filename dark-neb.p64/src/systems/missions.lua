--[[pod_format="raw",created="2024-11-09 00:00:00",modified="2024-11-09 00:00:00",revision=0]]
-- Missions System
-- Manages tutorial missions and objectives

local Missions = {}

-- Mission state
local current_mission = 1
local mission_data = {}
local mission_complete = false  -- Flag to signal mission completion to main game loop

-- Cumulative tracking for delta-based objectives
local cumulative_camera_movement = 0
local cumulative_ship_rotation = 0
local last_camera_ry = 0
local last_camera_rx = 0
local last_ship_heading_angle = 0

-- Track initial distance for movement objective progress calculation
local initial_movement_distance = nil

-- Dialog system for mission objectives
local dialog_text = ""
local dialog_visible = false
local dialog_duration = 0
local dialog_max_duration = 5.0  -- Show dialog for 5 seconds
local shown_dialogs = {}  -- Track which dialogs have been shown

-- Next objective tracking
local next_objective_index = 1  -- Track which objective to show next

-- Help panel position
local help_panel_x = 180  -- Top-left corner
local help_panel_y = 10

-- Panel visibility toggle
local show_objective_panel = true  -- Whether to show the objective panel

-- Track if OK button was already clicked to prevent continuous activation
local ok_button_clicked = false

-- Mission 2 specific tracking
local mission_2_targeting_checked = false  -- Whether targeting has been initiated
local mission_2_satellites_destroyed = 0  -- Count of destroyed satellites

-- Mission 3 specific tracking
local mission_3_grabon_detected = false  -- Whether player has detected the Grabon
local mission_3_grabon_engaged = false  -- Whether player has engaged with Grabon
local mission_3_grabon_destroyed = false  -- Whether Grabon is destroyed

-- Mission 1: Movement and Camera Control
-- Goals: Move camera, rotate ship, move to designated position
local MISSION_1 = {
	id = 1,
	name = "Movement & Camera",
	description = "Learn to move and control the camera",
	objectives = {
		{
			id = "camera",
			name = "Move camera around ship",
			progress = 0,
			target = 1.0,  -- 100% completion
			completed = false,
		},
		{
			id = "rotation",
			name = "Rotate ship",
			progress = 0,
			target = 1.0,  -- Full 360 degree rotation
			completed = false,
		},
		{
			id = "movement",
			name = "Move to destination",
			progress = 0,
			target = 1.0,  -- Reached destination
			completed = false,
		},
	},
	destination = {x = 50, y = 0, z = 50},  -- Green cube position
	destination_radius = 5,  -- How close to destination counts as completion
}

-- Mission 2: Subsystems & Combat
-- Goals: Enable subsystems, learn targeting, destroy enemy ships
local MISSION_2 = {
	id = 2,
	name = "Subsystems & Combat",
	description = "Master your ship's subsystems and destroy enemy satellites",
	objectives = {
		{
			id = "subsystems",
			name = "Enable all subsystems",
			progress = 0,
			target = 1.0,
			completed = false,
		},
		{
			id = "targeting",
			name = "Target an enemy satellite",
			progress = 0,
			target = 1.0,
			completed = false,
		},
		{
			id = "combat",
			name = "Destroy both satellites",
			progress = 0,
			target = 1.0,
			completed = false,
		},
	},
}

-- Mission 3: Patrol - First day on the job
-- Goals: Find and destroy the enemy Grabon
local MISSION_3 = {
	id = 3,
	name = "Patrol",
	description = "Find and destroy the enemy Grabon",
	objectives = {
		{
			id = "search",
			name = "Search for the enemy",
			progress = 0,
			target = 1.0,
			completed = false,
		},
		{
			id = "engage",
			name = "Engage the Grabon",
			progress = 0,
			target = 1.0,
			completed = false,
		},
		{
			id = "destroy",
			name = "Destroy the Grabon",
			progress = 0,
			target = 1.0,
			completed = false,
		},
	},
}

local MISSIONS = {
	MISSION_1,
	MISSION_2,
	MISSION_3,
}

-- Initialize missions
function Missions.init(config)
	current_mission = 1
	mission_complete = false  -- Reset mission complete flag
	shown_dialogs = {}  -- Reset shown dialogs
	cumulative_camera_movement = 0
	cumulative_ship_rotation = 0
	last_camera_ry = 0
	last_camera_rx = 0
	last_ship_heading_angle = 0
	initial_movement_distance = nil  -- Reset movement distance tracker
	ok_button_clicked = false  -- Reset OK button state
	next_objective_index = 1
	dialog_text = ""  -- Reset dialog text
	dialog_visible = false  -- Hide dialog
	dialog_duration = 0  -- Reset dialog duration

	-- Set dialog panel position from config
	if config and config.mission_ui then
		help_panel_x = config.mission_ui.dialog_panel_x
		help_panel_y = config.mission_ui.dialog_panel_y
	end

	for _, mission in ipairs(MISSIONS) do
		mission_data[mission.id] = {
			started = false,
			completed = false,
			objectives = {}
		}
		for _, obj in ipairs(mission.objectives) do
			mission_data[mission.id].objectives[obj.id] = {
				progress = 0,
				completed = false,
			}
			-- Also reset the mission objective progress
			obj.progress = 0
			obj.completed = false
		end
	end

	-- Reset Mission 2 specific tracking variables
	mission_2_targeting_checked = false
	mission_2_satellites_destroyed = 0

	-- Reset Mission 3 specific tracking variables
	mission_3_grabon_detected = false
	mission_3_grabon_engaged = false
	mission_3_grabon_destroyed = false

	-- Show first objective for mission 1
	Missions.show_next_objective()
end

-- Get current mission
function Missions.get_current_mission()
	return MISSIONS[current_mission]
end

-- Get mission by ID
function Missions.get_mission(mission_id)
	return MISSIONS[mission_id]
end

-- Update camera movement tracking (for Mission 1)
-- Tracks cumulative camera movement using delta changes
function Missions.update_camera_objective(current_ry, current_rx)
	if current_mission ~= 1 then return end

	local mission = MISSIONS[1]
	local obj = mission.objectives[1]  -- Camera objective

	-- Initialize on first call to avoid counting initial position as movement
	if last_camera_ry == 0 and last_camera_rx == 0 and cumulative_camera_movement == 0 then
		last_camera_ry = current_ry
		last_camera_rx = current_rx
		obj.progress = 0
		return
	end

	-- Calculate delta movement and accumulate
	local ry_delta = math.abs(current_ry - last_camera_ry)
	local rx_delta = math.abs(current_rx - last_camera_rx)

	-- Handle wrapping for ry (can go around the circle)
	if ry_delta > 3.0 then
		ry_delta = 6.28 - ry_delta  -- Wrap around 2π
	end

	cumulative_camera_movement = cumulative_camera_movement + ry_delta + rx_delta

	-- Update last values
	last_camera_ry = current_ry
	last_camera_rx = current_rx

	-- Normalize to 0-1 range (target is 1.0 radians of cumulative movement)
	obj.progress = math.min(1.0, cumulative_camera_movement / 1.0)

	if obj.progress >= 0.99 and not obj.completed then
		obj.completed = true
		mission_data[1].objectives["camera"].completed = true
		if not shown_dialogs["camera_done"] then
			shown_dialogs["camera_done"] = true
			Missions.show_next_objective()
		end
	end
end

-- Update ship rotation tracking (for Mission 1)
-- Tracks cumulative ship rotation using delta changes
function Missions.update_rotation_objective(current_heading_angle)
	if current_mission ~= 1 then return end

	local mission = MISSIONS[1]
	local obj = mission.objectives[2]  -- Rotation objective

	-- Initialize on first call to avoid counting initial position as movement
	if last_ship_heading_angle == 0 and cumulative_ship_rotation == 0 then
		last_ship_heading_angle = current_heading_angle
		obj.progress = 0
		return
	end

	-- Calculate delta rotation and accumulate
	local rotation_delta = math.abs(current_heading_angle - last_ship_heading_angle)

	-- Handle wrapping around 0/1 boundary (modulo 1 for turns)
	if rotation_delta > 0.5 then
		rotation_delta = 1.0 - rotation_delta
	end

	cumulative_ship_rotation = cumulative_ship_rotation + rotation_delta

	-- Update last value
	last_ship_heading_angle = current_heading_angle

	-- Normalize to 0-1 range (target is 0.5 turns of rotation = 180 degrees)
	obj.progress = math.min(1.0, cumulative_ship_rotation / 0.5)

	if obj.progress >= 0.99 and not obj.completed then
		obj.completed = true
		mission_data[1].objectives["rotation"].completed = true
		if not shown_dialogs["rotation_done"] then
			shown_dialogs["rotation_done"] = true
			Missions.show_next_objective()
		end
	end
end

-- Update movement tracking (for Mission 1)
-- Tracks distance to destination
function Missions.update_movement_objective(ship_pos)
	if current_mission ~= 1 then return end

	local mission = MISSIONS[1]
	local obj = mission.objectives[3]  -- Movement objective
	local dest = mission.destination

	-- Calculate distance to destination
	local dx = ship_pos.x - dest.x
	local dy = ship_pos.y - dest.y
	local dz = ship_pos.z - dest.z
	local distance = math.sqrt(dx*dx + dy*dy + dz*dz)

	-- Initialize the starting distance on first call
	if initial_movement_distance == nil then
		initial_movement_distance = distance
	end

	-- Show progress from 0 to 1 as distance decreases from initial to 0
	-- Progress = (initial_distance - current_distance) / initial_distance
	local progress_value = (initial_movement_distance - distance) / initial_movement_distance
	obj.progress = math.max(0, math.min(1.0, progress_value))

	-- Mission complete when within destination radius
	if distance <= mission.destination_radius then
		if not obj.completed then
			obj.completed = true
			mission_data[1].objectives["movement"].completed = true
			if not shown_dialogs["movement_done"] then
				shown_dialogs["movement_done"] = true
				Missions.show_next_objective()
			end
		end
		return true  -- Movement objective complete
	end

	return false
end

-- Update subsystems objective for Mission 2
-- Tracks energy allocation progress (0-8 energy allocated = 0-100% complete)
function Missions.update_subsystems_objective(energy_system)
	if current_mission ~= 2 then return end

	local mission = MISSIONS[2]
	local obj = mission.objectives[1]  -- Subsystems objective

	-- Calculate total allocated energy (max is 8)
	local total_allocated = energy_system.systems.impulse.allocated +
		energy_system.systems.weapons.allocated +
		energy_system.systems.shields.allocated +
		energy_system.systems.sensors.allocated

	-- Progress is based on total energy allocated (0-8 = 0-100%)
	obj.progress = total_allocated / 8

	-- Mark complete when all 8 energy points are allocated
	if total_allocated >= 8 and not obj.completed then
		obj.completed = true
		mission_data[2].objectives["subsystems"].completed = true
		if not shown_dialogs["subsystems_done"] then
			shown_dialogs["subsystems_done"] = true
			Missions.show_next_objective()
		end
	end
end

-- Update targeting objective for Mission 2
-- Tracks if player has targeted an enemy
function Missions.update_targeting_objective(current_target)
	if current_mission ~= 2 then return end

	local mission = MISSIONS[2]
	local obj = mission.objectives[2]  -- Targeting objective

	-- Check if a target is selected
	if current_target and not mission_2_targeting_checked then
		mission_2_targeting_checked = true
	end

	-- Progress is either 0 or 1 (targeting or not)
	obj.progress = mission_2_targeting_checked and 1.0 or 0

	-- Mark complete when target acquired
	if mission_2_targeting_checked and not obj.completed then
		obj.completed = true
		mission_data[2].objectives["targeting"].completed = true
		if not shown_dialogs["targeting_done"] then
			shown_dialogs["targeting_done"] = true
			Missions.show_next_objective()
		end
	end
end

-- Update combat objective for Mission 2
-- Tracks destroyed satellites
function Missions.update_combat_objective(satellites_destroyed)
	if current_mission ~= 2 then return end

	local mission = MISSIONS[2]
	local obj = mission.objectives[3]  -- Combat objective

	-- Update satellite destruction count
	mission_2_satellites_destroyed = satellites_destroyed or 0

	-- Progress based on satellites destroyed (0-2)
	obj.progress = mission_2_satellites_destroyed / 2

	-- Mission complete when both satellites destroyed
	if mission_2_satellites_destroyed >= 2 and not obj.completed then
		obj.completed = true
		mission_data[2].objectives["combat"].completed = true
		if not shown_dialogs["combat_done"] then
			shown_dialogs["combat_done"] = true
			Missions.show_next_objective()
		end
	end
end

-- Update search objective for Mission 3
-- Tracks if player has detected the Grabon
function Missions.update_search_objective(current_target)
	if current_mission ~= 3 then return end

	local mission = MISSIONS[3]
	local obj = mission.objectives[1]  -- Search objective

	-- Player has detected Grabon if they have it as current target
	if current_target and current_target.type == "grabon" and not mission_3_grabon_detected then
		mission_3_grabon_detected = true
	end

	-- Progress is either 0 or 1 (detected or not)
	obj.progress = mission_3_grabon_detected and 1.0 or 0

	-- Mark complete when Grabon detected
	if mission_3_grabon_detected and not obj.completed then
		obj.completed = true
		mission_data[3].objectives["search"].completed = true
		if not shown_dialogs["search_done"] then
			shown_dialogs["search_done"] = true
			Missions.show_next_objective()
		end
	end
end

-- Update engage objective for Mission 3
-- Tracks if player has engaged combat with Grabon
function Missions.update_engage_objective(player_health_loss)
	if current_mission ~= 3 then return end

	local mission = MISSIONS[3]
	local obj = mission.objectives[2]  -- Engage objective

	-- Player has engaged if they've taken damage from Grabon fire
	if player_health_loss and player_health_loss > 0 and not mission_3_grabon_engaged then
		mission_3_grabon_engaged = true
	end

	-- Progress is either 0 or 1 (engaged or not)
	obj.progress = mission_3_grabon_engaged and 1.0 or 0

	-- Mark complete when engaged
	if mission_3_grabon_engaged and not obj.completed then
		obj.completed = true
		mission_data[3].objectives["engage"].completed = true
		if not shown_dialogs["engage_done"] then
			shown_dialogs["engage_done"] = true
			Missions.show_next_objective()
		end
	end
end

-- Update destroy objective for Mission 3
-- Tracks if Grabon is destroyed
function Missions.update_destroy_objective(grabon_destroyed)
	if current_mission ~= 3 then return end

	local mission = MISSIONS[3]
	local obj = mission.objectives[3]  -- Destroy objective

	-- Update destruction status
	mission_3_grabon_destroyed = grabon_destroyed or false

	-- Progress is either 0 or 1 (destroyed or not)
	obj.progress = mission_3_grabon_destroyed and 1.0 or 0

	-- Mission complete when Grabon destroyed
	if mission_3_grabon_destroyed and not obj.completed then
		obj.completed = true
		mission_data[3].objectives["destroy"].completed = true
		if not shown_dialogs["destroy_done"] then
			shown_dialogs["destroy_done"] = true
			Missions.show_next_objective()
		end
	end
end

-- Show the next objective in sequence
function Missions.show_next_objective()
	local mission = Missions.get_current_mission()
	if not mission or not mission.objectives then return end

	-- Find the first incomplete objective
	for i, obj in ipairs(mission.objectives) do
		if not obj.completed then
			next_objective_index = i

			-- Show instruction for this objective
			local instruction_text = ""
			if mission.id == 1 then
				-- Mission 1 instructions
				if i == 1 then
					instruction_text = "OBJECTIVE 1: " .. obj.name .. "\nLeft click+drag:\n\nRotate camera"
				elseif i == 2 then
					instruction_text = "OBJECTIVE 2: " .. obj.name .. "\nRight click+drag:\n\nRotate ship"
				elseif i == 3 then
					instruction_text = "OBJECTIVE 3: " .. obj.name .. "\nDrag the speed bar on the right:\n\nMove to green cube"
				end
			elseif mission.id == 2 then
				-- Mission 2 instructions
				if i == 1 then
					instruction_text = "OBJECTIVE 1: " .. obj.name .. "\nClick on energy bar nto allocate \nenergy to subsystems"
				elseif i == 2 then
					instruction_text = "OBJECTIVE 2: " .. obj.name .. "\nRight click on a satellite to target it"
				elseif i == 3 then
					instruction_text = "OBJECTIVE 3: " .. obj.name .. "\nMove into range and firing arc.\nFire weapons to destroy both satellites"
				end
			elseif mission.id == 3 then
				-- Mission 3 instructions
				if i == 1 then
					instruction_text = "OBJECTIVE 1: " .. obj.name .. "\nSearch the sector.\nRight click on the Grabon\nto target it"
				elseif i == 2 then
					instruction_text = "OBJECTIVE 2: " .. obj.name .. "\nLet the Grabon attack you.\nEvade and counterattack"
				elseif i == 3 then
					instruction_text = "OBJECTIVE 3: " .. obj.name .. "\nDestroy the Grabon!\nMove into range,\nfire weapons to destroy it"
				end
			else
				instruction_text = "OBJECTIVE " .. i .. ": " .. obj.name
			end

			dialog_text = instruction_text
			dialog_visible = true
			dialog_duration = 999  -- Long duration, keep visible

			return
		end
	end

	-- All objectives complete - show mission-specific success message
	if current_mission == 2 then
		dialog_text = "Mission Success!!!\n\nYou've graduated top\nof your class with\nincredible fanfare.\nYou have a bright\nfuture ahead!"
	elseif current_mission == 3 then
		dialog_text = "Mission Success!!!\n\nYou've defeated the\nenemy Grabon! Your\nfirst real combat\nvictory. Well done!"
	else
		dialog_text = "Mission Success!!!\n\nClick OK to return\nto main menu"
	end
	dialog_visible = true
	dialog_duration = 999  -- Wait for player to click OK
end

-- Check if all objectives of current mission are complete
function Missions.check_mission_complete()
	local mission = Missions.get_current_mission()
	if not mission then return false end

	for _, obj in ipairs(mission.objectives) do
		if not obj.completed then
			return false
		end
	end

	return true
end

-- Get mission complete flag status
function Missions.is_mission_complete()
	return mission_complete
end

-- Set mission complete flag (called by main when all objectives are done)
function Missions.set_mission_complete()
	mission_complete = true
end

-- Reset mission state for next mission
function Missions.advance_mission()
	if current_mission < #MISSIONS then
		current_mission = current_mission + 1
		mission_complete = false
		shown_dialogs = {}  -- Reset shown dialogs for new mission
		cumulative_camera_movement = 0
		cumulative_ship_rotation = 0
		last_camera_ry = 0
		last_camera_rx = 0
		last_ship_heading_angle = 0
		initial_movement_distance = nil  -- Reset movement distance tracker for new mission
		next_objective_index = 1  -- Reset to first objective of new mission

		-- Reset Mission 2 specific tracking variables
		mission_2_targeting_checked = false
		mission_2_satellites_destroyed = 0

		-- Reset Mission 3 specific tracking variables
		mission_3_grabon_detected = false
		mission_3_grabon_engaged = false
		mission_3_grabon_destroyed = false

		-- Initialize next mission's data and reset all objective progress
		local mission = MISSIONS[current_mission]
		if mission then
			-- Reset all objective progress values for new mission
			for _, obj in ipairs(mission.objectives) do
				obj.progress = 0
				obj.completed = false
			end

			-- Initialize mission_data if needed
			if not mission_data[mission.id] then
				mission_data[mission.id] = {
					started = false,
					completed = false,
					objectives = {}
				}
			end

			for _, obj in ipairs(mission.objectives) do
				mission_data[mission.id].objectives[obj.id] = {
					progress = 0,
					completed = false,
				}
			end
		end

		-- Show first objective for new mission
		Missions.show_next_objective()

		return true
	end
	return false
end

-- -- Draw mission UI (HUD display) - consolidated panel in lower-left
-- function Missions.draw_ui()
-- 	local mission = Missions.get_current_mission()

-- 	if not mission then return end

-- 	-- Panel position in lower-left area
-- 	local panel_x = 10
-- 	local panel_y = 110
-- 	local panel_width = 200
-- 	local panel_height = 65

-- 	-- Draw panel background
-- 	rectfill(panel_x, panel_y, panel_x + panel_width, panel_y + panel_height, 0)

-- 	-- Draw panel border
-- 	rect(panel_x, panel_y, panel_x + panel_width, panel_y + panel_height, 7)

-- 	-- Draw title
-- 	local title = "MISSION " .. mission.id
-- 	print(title, panel_x + 2, panel_y + 2, 11)

-- 	-- Draw only current objective with progress bar
-- 	local current_obj = mission.objectives[next_objective_index]

-- 	if current_obj then
-- 		-- Objective number and name (abbreviated if needed)
-- 		local obj_name = current_obj.name
-- 		if #obj_name > 12 then
-- 			obj_name = string.sub(obj_name, 1, 12) .. "."
-- 		end
-- 		local name_color = current_obj.completed and 11 or 7
-- 		print(next_objective_index .. ". " .. obj_name, panel_x + 2, panel_y + 16, name_color)

-- 		-- Progress bar
-- 		local bar_width = panel_width - 4
-- 		local bar_height = 4
-- 		local bar_y = panel_y + 26

-- 		-- Progress bar background
-- 		rectfill(panel_x + 2, bar_y, panel_x + 2 + bar_width, bar_y + bar_height, 1)

-- 		-- Progress bar fill
-- 		local fill_width = bar_width * current_obj.progress
-- 		if fill_width > 0 then
-- 			local bar_color = current_obj.completed and 11 or 10
-- 			rectfill(panel_x + 2, bar_y, panel_x + 2 + fill_width, bar_y + bar_height, bar_color)
-- 		end

-- 		-- Progress bar border
-- 		rect(panel_x + 2, bar_y, panel_x + 2 + bar_width, bar_y + bar_height, 7)
-- 	end

-- 	-- Draw slider at bottom of panel
-- 	local slider_y = panel_y + panel_height - 12
-- 	local slider_x = panel_x + 2
-- 	local slider_width = panel_width - 4

-- 	print("Progress", slider_x, slider_y - 8, 7)

-- 	-- Slider background
-- 	rectfill(slider_x, slider_y, slider_x + slider_width, slider_y + 3, 1)

-- 	-- Calculate overall mission progress (average of all objectives)
-- 	local total_progress = 0
-- 	for _, obj in ipairs(mission.objectives) do
-- 		total_progress = total_progress + obj.progress
-- 	end
-- 	total_progress = total_progress / #mission.objectives

-- 	-- Slider fill
-- 	local slider_fill = slider_width * total_progress
-- 	if slider_fill > 0 then
-- 		rectfill(slider_x, slider_y, slider_x + slider_fill, slider_y + 3, 10)
-- 	end

-- 	-- Slider border
-- 	rect(slider_x, slider_y, slider_x + slider_width, slider_y + 3, 7)

-- 	-- Draw destination marker for Mission 1 (only if movement objective not complete)
-- 	if mission.id == 1 then
-- 		local movement_obj = mission.objectives[3]  -- Movement is the 3rd objective
-- 		if movement_obj and not movement_obj.completed then
-- 			Missions.draw_destination_marker(mission.destination)
-- 		end
-- 	end
-- end

-- Draw help panel overlay (call this LAST, after all other UI)
-- @param mouse_x, mouse_y: optional mouse coordinates for button hover detection
-- @param config: global config object for UI positioning
function Missions.draw_help_panel(mouse_x, mouse_y, config)
	-- Draw toggle button in top-right corner of the dialog panel
	local toggle_x = help_panel_x + (config and config.mission_ui and config.mission_ui.dialog_toggle_x_offset or 200)
	local toggle_y = help_panel_y + (config and config.mission_ui and config.mission_ui.dialog_toggle_y_offset or 0)
	local toggle_size = config and config.mission_ui and config.mission_ui.dialog_toggle_size or 12

	-- Check if mouse is hovering over toggle
	local toggle_hovered = mouse_x and mouse_y and
		mouse_x >= toggle_x and mouse_x <= toggle_x + toggle_size and
		mouse_y >= toggle_y and mouse_y <= toggle_y + toggle_size

	-- Draw drop shadow for toggle button
	rectfill(toggle_x + 2, toggle_y + 2, toggle_x + toggle_size + 2, toggle_y + toggle_size + 2, 1)

	-- Draw toggle button
	local toggle_color = show_objective_panel and 10 or 1
	rectfill(toggle_x, toggle_y, toggle_x + toggle_size, toggle_y + toggle_size, toggle_color)
	rect(toggle_x, toggle_y, toggle_x + toggle_size, toggle_y + toggle_size, 7)

	-- Draw toggle text ("H" for hide/show)
	print("H", toggle_x + 4, toggle_y + 3, toggle_hovered and 11 or 0)

	-- Only draw dialog when it's visible (instruction text or mission success message)
	if dialog_visible and show_objective_panel then
		Missions.draw_dialog(dialog_text, mouse_x, mouse_y)
	end
end

-- Toggle objective panel visibility
function Missions.toggle_objective_panel()
	show_objective_panel = not show_objective_panel
end

-- Get objective panel visibility state
function Missions.is_objective_panel_visible()
	return show_objective_panel
end

-- Set objective panel visibility state
function Missions.set_objective_panel_visible(visible)
	show_objective_panel = visible
end

-- Draw UI pointers for tutorials (e.g., highlight weapons UI, buttons)
-- @param ui_elements: table of UI elements to highlight {type, x, y, width, height, color}
function Missions.draw_ui_pointers(ui_elements)
	if not ui_elements then return end

	for _, element in ipairs(ui_elements) do
		local color = element.color or 10  -- Yellow by default

		-- Draw border around element
		if element.type == "rect" then
			rect(element.x, element.y, element.x + element.width, element.y + element.height, color)
			-- Draw arrow pointing to element
			if element.arrow_from_x and element.arrow_from_y then
				line_2d(element.arrow_from_x, element.arrow_from_y, element.x - 2, element.y + element.height / 2, color)
			end
		elseif element.type == "circle" then
			-- For circular elements like toggle buttons
			rect(element.x, element.y, element.x + element.width, element.y + element.height, color)
		end
	end
end

-- Update dialog system (call this from main update loop)
function Missions.update_dialogs(delta_time)
	if dialog_visible then
		dialog_duration = dialog_duration - (delta_time or 0.016)  -- Default to ~60fps frame time
		if dialog_duration <= 0 then
			dialog_visible = false
			dialog_text = ""
		end
	end
end

-- Show a dialog message
function Missions.show_dialog(text, duration)
	dialog_text = text
	dialog_visible = true
	dialog_duration = duration or dialog_max_duration
end

-- Check if dialog is currently visible
function Missions.is_dialog_visible()
	return dialog_visible
end

-- Check if OK button was clicked (for mission success screen)
-- @param mouse_x, mouse_y: mouse coordinates
-- @param mouse_clicked: whether mouse was clicked this frame
-- @param config: global config object for UI dimensions
-- @return: true if OK button was clicked
function Missions.check_ok_button_click(mouse_x, mouse_y, mouse_clicked, config)
	-- Only check for OK button when showing mission success message and it hasn't been clicked yet
	if dialog_text == "Mission Success!!!\n\nClick OK to return\nto main menu" and mouse_clicked and not ok_button_clicked then
		-- Check if click is within OK button bounds
		local panel_height = config and config.mission_ui and config.mission_ui.dialog_panel_height or 80
		local button_x = help_panel_x + 2
		local button_y = help_panel_y + panel_height - 15  -- Near bottom of panel (80-15=65)
		local button_width = 40
		local button_height = 12

		if mouse_x >= button_x and mouse_x < button_x + button_width and
		   mouse_y >= button_y and mouse_y < button_y + button_height then
			-- Mark OK button as clicked so it can't be triggered again
			ok_button_clicked = true
			return true
		end
	end
	return false
end

-- Draw help panel on the left side
-- @param text: dialog text to display
-- @param mouse_x, mouse_y: optional mouse coordinates for button hover detection
function Missions.draw_dialog(text, mouse_x, mouse_y)
	local panel_x = help_panel_x
	local panel_y = help_panel_y
	-- Dear AI DONT MESS WITH MY values
	local panel_width = 200  -- Expanded width to fit text better
	local panel_height = 80  -- Expanded height to fit instructions

	-- Check if this is the mission success message
	local is_success_message = text == "Mission Success!!!\n\nClick OK to return\nto main menu"
	local current_mission_obj = Missions.get_current_mission()
	local title = is_success_message and "SUCCESS" or ("MISSION " .. (current_mission_obj and current_mission_obj.id or 1))
	local subtitle = ""
	if not is_success_message and current_mission_obj then
		subtitle = current_mission_obj.name
	end

	-- Draw panel background
	-- rectfill(panel_x, panel_y, panel_x + panel_width, panel_y + panel_height, 0)

	-- Draw border drop shadow
	-- rect(panel_x + 2, panel_y + 2, panel_x + panel_width + 2, panel_y + panel_height + 2, 1)

	-- Draw border (bright for visibility)
	-- rect(panel_x, panel_y, panel_x + panel_width, panel_y + panel_height, 11)

	-- Draw title with drop shadow
	print(title, panel_x + 3, panel_y + 3, 1)
	print(title, panel_x + 2, panel_y + 2, 10)

	-- Draw subtitle if available (mission name)
	if subtitle ~= "" then
		print(subtitle, panel_x + 3, panel_y + 11, 1)
		print(subtitle, panel_x + 2, panel_y + 10, 6)
	end

	-- Draw text (word wrap for narrower panel) with drop shadow
	local text_x = panel_x + 2
	local text_y = panel_y + 25
	print(text, text_x + 1, text_y + 1, 1)
	print(text, text_x, text_y, 7)

	-- Draw current objective progress bar (if not success message)
	if not is_success_message then
		local mission = Missions.get_current_mission()
		if mission and mission.objectives[next_objective_index] then
			local current_obj = mission.objectives[next_objective_index]

			-- Progress bar for current objective
			local bar_y = panel_y + panel_height - 12
			local bar_width = panel_width - 50
			local bar_height = 3

			-- Progress bar background
			rectfill(panel_x + 2, bar_y, panel_x + 2 + bar_width, bar_y + bar_height, 1)

			-- Progress bar fill
			local fill_width = bar_width * current_obj.progress
			if fill_width > 0 then
				rectfill(panel_x + 2, bar_y, panel_x + 2 + fill_width, bar_y + bar_height, 10)
			end

			-- Progress bar border
			rect(panel_x + 2, bar_y, panel_x + 2 + bar_width, bar_y + bar_height, 7)
		end
	end

	-- Draw OK button for mission success message
	if is_success_message then
		local button_x = panel_x + 2
		local button_y = panel_y + panel_height - 15  -- Near bottom of panel (80-15=65)
		local button_width = 40
		local button_height = 12

		-- Check if mouse is hovering over button
		local button_hovered = mouse_x and mouse_y and
			mouse_x >= button_x and mouse_x <= button_x + button_width and
			mouse_y >= button_y and mouse_y <= button_y + button_height

		-- Draw button background (highlight if hovered)
		local bg_color = button_hovered and 11 or 1  -- Bright if hovered, dark otherwise
		rectfill(button_x, button_y, button_x + button_width, button_y + button_height, bg_color)

		-- Draw button border (yellow if hovered, white otherwise)
		local border_color = button_hovered and 10 or 7
		rect(button_x, button_y, button_x + button_width, button_y + button_height, border_color)

		-- Draw button text (adjust color for visibility on bright background)
		local text_color = button_hovered and 0 or 7
		print("OK", button_x + 12, button_y + 3, text_color)
	end
end

-- Draw destination cube in 3D world
function Missions.draw_destination_marker(dest_pos, camera, draw_line_3d)
	if not camera or not draw_line_3d then return end

	-- Draw a green cube at destination
	local size = 2
	local dx, dy, dz = size, size, size

	-- Define cube corners
	local corners = {
		{x = dest_pos.x - dx, y = dest_pos.y - dy, z = dest_pos.z - dz},
		{x = dest_pos.x + dx, y = dest_pos.y - dy, z = dest_pos.z - dz},
		{x = dest_pos.x + dx, y = dest_pos.y + dy, z = dest_pos.z - dz},
		{x = dest_pos.x - dx, y = dest_pos.y + dy, z = dest_pos.z - dz},
		{x = dest_pos.x - dx, y = dest_pos.y - dy, z = dest_pos.z + dz},
		{x = dest_pos.x + dx, y = dest_pos.y - dy, z = dest_pos.z + dz},
		{x = dest_pos.x + dx, y = dest_pos.y + dy, z = dest_pos.z + dz},
		{x = dest_pos.x - dx, y = dest_pos.y + dy, z = dest_pos.z + dz},
	}

	-- Draw cube edges in green
	local green = 11

	-- Bottom face
	draw_line_3d(corners[1].x, corners[1].y, corners[1].z, corners[2].x, corners[2].y, corners[2].z, camera, green)
	draw_line_3d(corners[2].x, corners[2].y, corners[2].z, corners[3].x, corners[3].y, corners[3].z, camera, green)
	draw_line_3d(corners[3].x, corners[3].y, corners[3].z, corners[4].x, corners[4].y, corners[4].z, camera, green)
	draw_line_3d(corners[4].x, corners[4].y, corners[4].z, corners[1].x, corners[1].y, corners[1].z, camera, green)

	-- Top face
	draw_line_3d(corners[5].x, corners[5].y, corners[5].z, corners[6].x, corners[6].y, corners[6].z, camera, green)
	draw_line_3d(corners[6].x, corners[6].y, corners[6].z, corners[7].x, corners[7].y, corners[7].z, camera, green)
	draw_line_3d(corners[7].x, corners[7].y, corners[7].z, corners[8].x, corners[8].y, corners[8].z, camera, green)
	draw_line_3d(corners[8].x, corners[8].y, corners[8].z, corners[5].x, corners[5].y, corners[5].z, camera, green)

	-- Vertical edges
	draw_line_3d(corners[1].x, corners[1].y, corners[1].z, corners[5].x, corners[5].y, corners[5].z, camera, green)
	draw_line_3d(corners[2].x, corners[2].y, corners[2].z, corners[6].x, corners[6].y, corners[6].z, camera, green)
	draw_line_3d(corners[3].x, corners[3].y, corners[3].z, corners[7].x, corners[7].y, corners[7].z, camera, green)
	draw_line_3d(corners[4].x, corners[4].y, corners[4].z, corners[8].x, corners[8].y, corners[8].z, camera, green)
end

-- Advance to next mission
function Missions.next_mission()
	if current_mission < #MISSIONS then
		current_mission = current_mission + 1
		return true
	end
	return false
end

-- Get mission data
function Missions.get_data(mission_id)
	return mission_data[mission_id]
end

-- Get next objective index
function Missions.get_next_objective_index()
	return next_objective_index
end

-- Exposed update functions for Mission 2 (called from main.lua)
Missions.update_subsystems_objective = Missions.update_subsystems_objective
Missions.update_targeting_objective = Missions.update_targeting_objective
Missions.update_combat_objective = Missions.update_combat_objective

-- Exposed update functions for Mission 3 (called from main.lua)
Missions.update_search_objective = Missions.update_search_objective
Missions.update_engage_objective = Missions.update_engage_objective
Missions.update_destroy_objective = Missions.update_destroy_objective

return Missions

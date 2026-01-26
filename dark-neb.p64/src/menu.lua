--[[pod_format="raw",created="2024-11-08 00:00:00",modified="2024-11-08 00:00:00",revision=0]]
-- Menu Module
-- Mission selection submenu (filtered by game mode)

local Menu = {}

Menu.state = "menu"  -- "menu", "playing", "game_over"
Menu.selected_mission = 1
Menu.missions = nil  -- Will be populated from config
Menu.last_button_click_state = false  -- Track previous click state for button-down detection
Menu.current_mode = nil  -- "tutorial" or "instant_action"
Menu.back_button_bounds = nil  -- Clickable bounds for back button
Menu.tutorial_progress = {mission_1_complete = false}  -- Tutorial progression tracking

-- Initialize menu with missions from config
-- @param config: game config
-- @param mode: "tutorial" or "instant_action" (nil defaults to showing all missions)
function Menu.init(config, mode)
	if not config or not config.missions then
		return
	end

	Menu.current_mode = mode
	Menu.selected_mission = 1
	Menu.mission_bounds = {}
	Menu.missions = {}

	-- Build mission list based on mode
	if mode == "tutorial" then
		-- Tutorial mode: missions 1-2
		if config.missions.mission_1 then
			table.insert(Menu.missions, {
				id = "mission_1",
				name = "Mission 1: Movement & Camera",
				description = config.missions.mission_1.description,
				locked = false,
			})
		end
		if config.missions.mission_2 then
			table.insert(Menu.missions, {
				id = "mission_2",
				name = "Mission 2: Subsystems & Combat",
				description = config.missions.mission_2.description,
				locked = not Menu.tutorial_progress.mission_1_complete,
			})
		end
	elseif mode == "instant_action" then
		-- Instant Action mode: missions 3-4
		if config.missions.mission_3 then
			table.insert(Menu.missions, {
				id = "mission_3",
				name = "Patrol Encounter",
				description = config.missions.mission_3.description,
				locked = false,
			})
		end
		if config.missions.mission_4 then
			table.insert(Menu.missions, {
				id = "mission_4",
				name = "Dual Combat",
				description = config.missions.mission_4.description,
				locked = false,
			})
		end
	else
		-- Default: show all missions (legacy behavior)
		if config.missions.mission_1 then
			table.insert(Menu.missions, {
				id = "mission_1",
				name = "Mission 1",
				description = config.missions.mission_1.description,
				locked = false,
			})
		end
		if config.missions.mission_2 then
			table.insert(Menu.missions, {
				id = "mission_2",
				name = "Mission 2",
				description = config.missions.mission_2.description,
				locked = false,
			})
		end
		if config.missions.mission_3 then
			table.insert(Menu.missions, {
				id = "mission_3",
				name = "Mission 3",
				description = config.missions.mission_3.description,
				locked = false,
			})
		end
		if config.missions.mission_4 then
			table.insert(Menu.missions, {
				id = "mission_4",
				name = "Mission 4",
				description = config.missions.mission_4.description,
				locked = false,
			})
		end
	end
end

-- Mark a tutorial mission as complete
function Menu.complete_tutorial_mission(mission_id)
	if mission_id == "mission_1" then
		Menu.tutorial_progress.mission_1_complete = true
	end
end

-- Get tutorial progress (for save/load)
function Menu.get_tutorial_progress()
	return Menu.tutorial_progress
end

-- Set tutorial progress (from save data)
function Menu.set_tutorial_progress(progress)
	if progress then
		Menu.tutorial_progress = progress
	end
end

-- Draw the menu
function Menu.draw()
	-- Clear screen
	cls(0)

	-- Draw title
	local title = "DARK NEBULA"
	local title_x = 240 - (#title * 2)
	print(title, title_x - 1, 29, 0)  -- Shadow
	print(title, title_x, 28, 11)     -- Green text

	-- Draw subtitle based on mode
	local subtitle = "Mission Selection"
	if Menu.current_mode == "tutorial" then
		subtitle = "Tutorial Missions"
	elseif Menu.current_mode == "instant_action" then
		subtitle = "Instant Action"
	end
	local subtitle_x = 240 - (#subtitle * 2)
	print(subtitle, subtitle_x, 45, 7)  -- White text

	-- Draw missions
	local start_y = 70
	local item_height = 40

	for i, mission in ipairs(Menu.missions) do
		local y = start_y + (i - 1) * item_height
		local is_selected = i == Menu.selected_mission
		local is_locked = mission.locked

		-- Store clickable bounds for mouse input
		Menu.mission_bounds[i] = {x1 = 30, y1 = y - 5, x2 = 450, y2 = y + 30}

		-- Draw selection highlight (not for locked missions)
		if is_selected and not is_locked then
			rectfill(30, y - 5, 450, y + 30, 5)  -- Selected background
		elseif is_locked then
			rectfill(30, y - 5, 450, y + 30, 1)  -- Locked background (dark)
		end

		-- Draw mission name
		local color = 7
		if is_locked then
			color = 5  -- Gray for locked
		elseif is_selected then
			color = 0  -- Dark on selection
		end
		print(mission.name, 40, y, color)

		-- Draw mission description or locked message
		if is_locked then
			print("Complete previous mission to unlock", 40, y + 10, 5)
		else
			print(mission.description, 40, y + 10, 6)
		end
	end

	-- Draw back button
	local back_text = "< Back"
	local back_x = 30
	local back_y = 240
	Menu.back_button_bounds = {x1 = back_x - 5, y1 = back_y - 5, x2 = back_x + #back_text * 4 + 10, y2 = back_y + 12}
	print(back_text, back_x, back_y, 6)

	-- Draw instructions at bottom
	local instructions = "Use W/S or Arrow Keys to navigate, Enter/Z to select"
	local instr_x = 240 - (#instructions * 2)
	print(instructions, instr_x, 255, 5)
end

-- Update menu state with input
-- Returns true if a mission was selected, "back" if back button pressed
function Menu.update(input, mouse_x, mouse_y, mouse_click)
	-- Handle back button click
	if mouse_x and mouse_y and Menu.back_button_bounds then
		local b = Menu.back_button_bounds
		if mouse_x >= b.x1 and mouse_x <= b.x2 and mouse_y >= b.y1 and mouse_y <= b.y2 then
			if mouse_click and not Menu.last_button_click_state then
				Menu.last_button_click_state = mouse_click
				return "back"
			end
		end
	end

	-- Handle Escape key for back
	if keyp("escape") then
		return "back"
	end

	-- Handle mouse input for mission selection
	if mouse_x and mouse_y and Menu.mission_bounds then
		for i, bounds in ipairs(Menu.mission_bounds) do
			-- Check if mouse is over a mission button
			if mouse_x >= bounds.x1 and mouse_x <= bounds.x2 and
			   mouse_y >= bounds.y1 and mouse_y <= bounds.y2 then
				-- Only select unlocked missions
				if not Menu.missions[i].locked then
					Menu.selected_mission = i
					-- Detect click on button down (transition from not clicked to clicked)
					if mouse_click and not Menu.last_button_click_state then
						Menu.last_button_click_state = mouse_click
						return true
					end
				end
			end
		end
	end

	-- Update last click state for next frame
	Menu.last_button_click_state = mouse_click

	-- Handle keyboard navigation (arrow keys) - skip locked missions
	if keyp("up") or keyp("w") then
		local start = Menu.selected_mission
		repeat
			Menu.selected_mission = Menu.selected_mission - 1
			if Menu.selected_mission < 1 then
				Menu.selected_mission = #Menu.missions
			end
		until not Menu.missions[Menu.selected_mission].locked or Menu.selected_mission == start
	end

	if keyp("down") or keyp("s") then
		local start = Menu.selected_mission
		repeat
			Menu.selected_mission = Menu.selected_mission + 1
			if Menu.selected_mission > #Menu.missions then
				Menu.selected_mission = 1
			end
		until not Menu.missions[Menu.selected_mission].locked or Menu.selected_mission == start
	end

	-- Handle keyboard selection (only if mission not locked)
	if input.select then
		if not Menu.missions[Menu.selected_mission].locked then
			return true  -- Mission selected
		end
	end

	return false
end

-- Get selected mission
function Menu.get_selected_mission()
	return Menu.missions[Menu.selected_mission]
end

return Menu

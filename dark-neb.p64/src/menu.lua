--[[pod_format="raw",created="2024-11-08 00:00:00",modified="2024-11-08 00:00:00",revision=0]]
-- Menu Module
-- Main menu for campaign selection

local Menu = {}

Menu.state = "menu"  -- "menu", "playing", "game_over"
Menu.selected_mission = 1
Menu.missions = {
	{
		name = "Space Academy",
		description = "Learn ship controls and basic combat at Space Academy",
	},
	{
		name = "Academy Certification",
		description = "First AI combat simulation at the Space Academy",
	},
	{
		name = "Outer Ring Patrol",
		description = "Advanced patrol mission in deep space",
	},
	{
		name = "Border Skirmish",
		description = "Intense engagement near hostile territory",
	},
	{
		name = "Last Stand",
		description = "Final mission against a space station.",
	},
}

-- Draw the menu
function Menu.draw()
	-- Clear screen
	cls(0)

	-- Draw title
	local title = "DARK NEB"
	local title_x = 240 - (#title * 2)
	print(title, title_x - 1, 29, 0)  -- Shadow
	print(title, title_x, 28, 11)     -- Yellow text

	-- Draw subtitle
	local subtitle = "Mission Selection"
	local subtitle_x = 240 - (#subtitle * 2)
	print(subtitle, subtitle_x, 45, 7)  -- White text

	-- Draw missions
	local start_y = 70
	local item_height = 40

	for i, mission in ipairs(Menu.missions) do
		local y = start_y + (i - 1) * item_height
		local is_selected = i == Menu.selected_mission

		-- Store clickable bounds for mouse input
		if not Menu.mission_bounds then
			Menu.mission_bounds = {}
		end
		Menu.mission_bounds[i] = {x1 = 30, y1 = y - 5, x2 = 450, y2 = y + 30}

		-- Draw selection highlight
		if is_selected then
			rectfill(30, y - 5, 450, y + 30, 5)  -- Selected background
		end

		-- Draw mission name
		local color = is_selected and 0 or 7
		print(mission.name, 40, y, color)

		-- Draw mission description
		print(mission.description, 40, y + 10, 6)
	end
end

-- Update menu state with input
-- Returns true if a mission was selected
function Menu.update(input, mouse_x, mouse_y, mouse_click)
	-- Handle mouse input
	if mouse_x and mouse_y and Menu.mission_bounds then
		for i, bounds in ipairs(Menu.mission_bounds) do
			-- Check if mouse is over a mission button
			if mouse_x >= bounds.x1 and mouse_x <= bounds.x2 and
			   mouse_y >= bounds.y1 and mouse_y <= bounds.y2 then
				Menu.selected_mission = i
				-- If clicked, select the mission
				if mouse_click then
					return true
				end
			end
		end
	end

	-- Handle keyboard selection (alternative input)
	if input.select then
		return true  -- Mission selected
	end

	return false
end

-- Get selected mission
function Menu.get_selected_mission()
	return Menu.missions[Menu.selected_mission]
end

return Menu

--[[pod_format="raw",created="2025-01-26 00:00:00",modified="2025-01-26 00:00:00",revision=0]]
-- Main Menu Module
-- Mode selection: Tutorial, Campaign, Instant Action

local MenuMain = {}

-- Game modes
MenuMain.modes = {
	{id = "tutorial", name = "Tutorial"},
	{id = "campaign", name = "Campaign"},
	{id = "instant_action", name = "Instant Action"},
}

MenuMain.selected_mode = 1
MenuMain.hovered_mode = nil
MenuMain.pressed_mode = nil
MenuMain.last_click_state = false
MenuMain.mode_bounds = nil

-- Initialize the main menu
function MenuMain.init()
	MenuMain.selected_mode = 1
	MenuMain.hovered_mode = nil
	MenuMain.pressed_mode = nil
	MenuMain.last_click_state = false
	MenuMain.mode_bounds = {}
end

-- Draw the main menu
-- @param starfield: Optional StarField module for background
function MenuMain.draw(starfield, camera)
	cls(0)

	-- Draw starfield background if available
	if starfield and camera then
		starfield.draw(camera)
	end

	-- Draw title with glow effect
	local title = "DARK NEBULA"
	local title_w = print(title, 0, -1000)  -- Measure text width
	local title_x = 240 - title_w / 2
	-- Shadow/glow layers
	print(title, title_x + 1, 61, 1)
	print(title, title_x - 1, 59, 1)
	-- Main title
	print(title, title_x, 60, 11)

	-- Button config
	local start_y = 105
	local button_width = 140
	local button_height = 24
	local button_spacing = 10
	local corner_radius = 3

	for i = 1, #MenuMain.modes do
		local mode = MenuMain.modes[i]
		local y = start_y + (i - 1) * (button_height + button_spacing)
		local x = 240 - button_width / 2

		-- Store clickable bounds
		MenuMain.mode_bounds[i] = {x1 = x, y1 = y, x2 = x + button_width, y2 = y + button_height}

		local is_selected = i == MenuMain.selected_mode
		local is_hovered = i == MenuMain.hovered_mode
		local is_pressed = i == MenuMain.pressed_mode

		-- Determine colors based on state
		local bg_color, text_color

		if is_pressed then
			bg_color = 5   -- Darker when pressed
			text_color = 11
		elseif is_hovered or is_selected then
			bg_color = 19  -- Highlight
			text_color = 11
		else
			bg_color = 1   -- Default dark
			text_color = 7
		end

		-- Draw shadow
		rrectfill(x + 1, y + 1, button_width, button_height, corner_radius, 0)

		-- Draw button body
		rrectfill(x, y, button_width, button_height, corner_radius, bg_color)

		-- Draw highlight on top edge when not pressed
		if not is_pressed then
			line(x + corner_radius, y + 1, x + button_width - corner_radius - 1, y + 1, 6)
		end

		-- Draw border when hovered or selected
		if is_hovered or is_selected then
			rrect(x, y, button_width, button_height, corner_radius, 11)
		end

		-- Draw text centered
		local text_w = print(mode.name, 0, -1000)
		local text_x = x + (button_width - text_w) / 2
		local text_y = y + (button_height - 5) / 2
		print(mode.name, text_x, text_y, text_color)
	end

	-- Draw instructions at bottom
	local instr = "Click or Enter to select"
	local instr_w = print(instr, 0, -1000)
	print(instr, 240 - instr_w / 2, 225, 5)
end

-- Update main menu
-- @param mouse_x, mouse_y: Mouse position
-- @param mouse_click: Whether mouse is clicked
-- @return: Selected mode id if selected, nil otherwise
function MenuMain.update(mouse_x, mouse_y, mouse_click)
	-- Reset hover/pressed state
	MenuMain.hovered_mode = nil
	MenuMain.pressed_mode = nil

	-- Handle mouse input
	if mouse_x and mouse_y and MenuMain.mode_bounds then
		for i = 1, #MenuMain.mode_bounds do
			local bounds = MenuMain.mode_bounds[i]
			if mouse_x >= bounds.x1 and mouse_x <= bounds.x2 and
			   mouse_y >= bounds.y1 and mouse_y <= bounds.y2 then
				MenuMain.hovered_mode = i

				if mouse_click then
					MenuMain.pressed_mode = i
				end

				-- Detect click release
				if not mouse_click and MenuMain.last_click_state then
					MenuMain.selected_mode = i
					MenuMain.last_click_state = mouse_click
					return MenuMain.modes[i].id
				end
			end
		end
	end

	-- Update last click state
	MenuMain.last_click_state = mouse_click

	-- Handle keyboard navigation
	if keyp("up") or keyp("w") then
		MenuMain.selected_mode = MenuMain.selected_mode - 1
		if MenuMain.selected_mode < 1 then
			MenuMain.selected_mode = #MenuMain.modes
		end
	end

	if keyp("down") or keyp("s") then
		MenuMain.selected_mode = MenuMain.selected_mode + 1
		if MenuMain.selected_mode > #MenuMain.modes then
			MenuMain.selected_mode = 1
		end
	end

	-- Handle keyboard selection
	if keyp("return") or keyp("z") then
		return MenuMain.modes[MenuMain.selected_mode].id
	end

	return nil
end

-- Get currently selected mode
function MenuMain.get_selected_mode()
	return MenuMain.modes[MenuMain.selected_mode]
end

return MenuMain

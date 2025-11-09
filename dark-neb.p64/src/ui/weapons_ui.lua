--[[pod_format="raw",created="2024-11-09 00:00:00",modified="2024-11-09 00:00:00",revision=0]]
-- Weapons UI Module
-- Displays available weapons (Photon Beam 1, Photon Beam 2) in lower corner

local WeaponsUI = {}

-- Configuration for weapons UI
local WEAPONS_CONFIG = {
	base_x = 10,  -- Bottom-left starting position
	base_y = 200,  -- Will be positioned from bottom
	button_width = 80,
	button_height = 15,
	spacing = 5,
	text_color = 7,
	bg_color_normal = 24,  -- Maroon background
	bg_color_available = 24,  -- Maroon when available
	bg_color_unavailable = 0,  -- Dark when not available
	border_color = 7,
	color_indicator_width = 8,  -- Width of color square to the left
	color_indicator_spacing = 2,  -- Space between color square and button
}

-- Draw the weapons UI
-- @param energy_system: table with energy allocations for each system
-- @param selected_weapon: index of selected weapon (1 or 2, or nil)
-- @param weapon_states: table with charging and auto-fire state for each weapon
-- @param config: global config object
-- @param mouse_x: current mouse X position (for tooltip)
-- @param mouse_y: current mouse Y position (for tooltip)
function WeaponsUI.draw_weapons(energy_system, selected_weapon, weapon_states, config, mouse_x, mouse_y)
	local screen_height = 240

	-- Position at lower-left corner
	local base_x = WEAPONS_CONFIG.base_x
	local y = screen_height - 50  -- 50 pixels from bottom

	-- Use weapons from config
	local weapons = config.weapons

	for i, weapon in ipairs(weapons) do
		local weapon_y = y + (i - 1) * (WEAPONS_CONFIG.button_height + WEAPONS_CONFIG.spacing)

		-- Get weapon state
		local state = weapon_states[i] or {charge = 0}

		-- Determine if weapon is available (has enough weapons energy)
		local has_energy = energy_system.weapons >= weapon.energy_cost
		local is_charged = has_energy and state.charge >= 1.0

		-- Position of the button (to the right of the color indicator)
		local x = base_x + WEAPONS_CONFIG.color_indicator_width + WEAPONS_CONFIG.color_indicator_spacing

		-- Check if mouse is hovering over weapon button
		local button_hovered = mouse_x and mouse_y and
			mouse_x >= x and mouse_x < x + WEAPONS_CONFIG.button_width and
			mouse_y >= weapon_y and mouse_y < weapon_y + WEAPONS_CONFIG.button_height

		-- Draw color indicator square to the left
		local color_x = base_x
		local indicator_color = is_charged and 11 or 24  -- Bright when charged, maroon otherwise
		rectfill(color_x, weapon_y, color_x + WEAPONS_CONFIG.color_indicator_width, weapon_y + WEAPONS_CONFIG.button_height, indicator_color)
		rect(color_x, weapon_y, color_x + WEAPONS_CONFIG.color_indicator_width, weapon_y + WEAPONS_CONFIG.button_height, WEAPONS_CONFIG.border_color)

		-- Determine button background color
		local bg_color = has_energy and WEAPONS_CONFIG.bg_color_available or WEAPONS_CONFIG.bg_color_unavailable

		-- Draw button drop shadow
		rectfill(x + 2, weapon_y + 2, x + WEAPONS_CONFIG.button_width + 2, weapon_y + WEAPONS_CONFIG.button_height + 2, 1)

		-- Draw button background
		rectfill(x, weapon_y, x + WEAPONS_CONFIG.button_width, weapon_y + WEAPONS_CONFIG.button_height, bg_color)

		-- Draw charging progress bar (fills from left to right)
		if has_energy and state.charge > 0 then
			local charge_bar_width = (WEAPONS_CONFIG.button_width - 4) * state.charge
			rectfill(x + 2, weapon_y + 2, x + 2 + charge_bar_width, weapon_y + WEAPONS_CONFIG.button_height - 2, 8)  -- Red fill
		end

		-- Draw border (yellow when hovering, otherwise white)
		local border_color = button_hovered and 10 or WEAPONS_CONFIG.border_color
		rect(x, weapon_y, x + WEAPONS_CONFIG.button_width, weapon_y + WEAPONS_CONFIG.button_height, border_color)

		-- Draw weapon name with drop shadow
		local text_x = x + 3
		local text_y = weapon_y + 4
		local display_text = weapon.name

		-- Draw text shadow
		print(display_text, text_x + 1, text_y + 1, 1)
		-- Draw text
		print(display_text, text_x, text_y, WEAPONS_CONFIG.text_color)

		-- Draw auto-fire toggle to the right
		local toggle_x = x + WEAPONS_CONFIG.button_width + 3
		local toggle_y = weapon_y + 3
		local toggle_size = 9

		-- Check if mouse is hovering over this toggle
		local toggle_hovered = mouse_x and mouse_y and
			mouse_x >= toggle_x and mouse_x < toggle_x + toggle_size and
			mouse_y >= toggle_y and mouse_y < toggle_y + toggle_size

		-- Toggle background
		local toggle_color = (weapon_states[i] and weapon_states[i].auto_fire) and 9 or 1
		rectfill(toggle_x, toggle_y, toggle_x + toggle_size, toggle_y + toggle_size, toggle_color)
		rect(toggle_x, toggle_y, toggle_x + toggle_size, toggle_y + toggle_size, 7)

		-- Show checkmark if auto-fire is enabled
		-- if weapon_states[i] and weapon_states[i].auto_fire then
		-- 	print("X", toggle_x + 3, toggle_y+2, 0)
		-- end

		-- Draw tooltip if hovering over toggle
		if toggle_hovered then
			local auto_fire_status = (weapon_states[i] and weapon_states[i].auto_fire) and "on" or "off"
			local tooltip_text = "auto fire " .. auto_fire_status
			-- Draw tooltip above the toggle
			local tooltip_x = toggle_x + 15
			local tooltip_y = toggle_y 
			-- Draw text shadow
			print(tooltip_text, tooltip_x + 1, tooltip_y + 1, 1)
			-- Draw text
			print(tooltip_text, tooltip_x, tooltip_y, WEAPONS_CONFIG.text_color)
		end
	end
end

-- Get hitbox for weapons UI buttons
-- @param config: global config object
-- @return array of hitbox tables with x, y, width, height, weapon_id
function WeaponsUI.get_weapon_hitboxes(config)
	local screen_height = 240
	local base_x = WEAPONS_CONFIG.base_x
	local y = screen_height - 50
	local x = base_x + WEAPONS_CONFIG.color_indicator_width + WEAPONS_CONFIG.color_indicator_spacing

	local hitboxes = {}

	for i = 1, #config.weapons do
		local weapon_y = y + (i - 1) * (WEAPONS_CONFIG.button_height + WEAPONS_CONFIG.spacing)

		table.insert(hitboxes, {
			x = x,
			y = weapon_y,
			width = WEAPONS_CONFIG.button_width,
			height = WEAPONS_CONFIG.button_height,
			weapon_id = i
		})
	end

	return hitboxes
end

-- Check if point is in weapon button
-- @param px, py: point coordinates
-- @param config: global config object
-- @return weapon_id if clicked, nil otherwise
function WeaponsUI.get_weapon_at_point(px, py, config)
	local hitboxes = WeaponsUI.get_weapon_hitboxes(config)

	for _, hitbox in ipairs(hitboxes) do
		if px >= hitbox.x and px < hitbox.x + hitbox.width and
		   py >= hitbox.y and py < hitbox.y + hitbox.height then
			return hitbox.weapon_id
		end
	end

	return nil
end

-- Get auto-fire toggle hitboxes
-- @param config: global config object
-- @return array of toggle hitboxes with x, y, size, weapon_id
function WeaponsUI.get_toggle_hitboxes(config)
	local screen_height = 240
	local base_x = WEAPONS_CONFIG.base_x
	local base_y = screen_height - 50
	local toggle_size = 9
	local x = base_x + WEAPONS_CONFIG.color_indicator_width + WEAPONS_CONFIG.color_indicator_spacing

	local hitboxes = {}

	for i = 1, #config.weapons do
		local weapon_y = base_y + (i - 1) * (WEAPONS_CONFIG.button_height + WEAPONS_CONFIG.spacing)
		local toggle_x = x + WEAPONS_CONFIG.button_width + 3
		local toggle_y = weapon_y + 3

		table.insert(hitboxes, {
			x = toggle_x,
			y = toggle_y,
			size = toggle_size,
			weapon_id = i
		})
	end

	return hitboxes
end

-- Check if point is in auto-fire toggle
-- @param px, py: point coordinates
-- @param config: global config object
-- @return weapon_id if toggle clicked, nil otherwise
function WeaponsUI.get_toggle_at_point(px, py, config)
	local hitboxes = WeaponsUI.get_toggle_hitboxes(config)

	for _, hitbox in ipairs(hitboxes) do
		if px >= hitbox.x and px < hitbox.x + hitbox.size and
		   py >= hitbox.y and py < hitbox.y + hitbox.size then
			return hitbox.weapon_id
		end
	end

	return nil
end

-- Check if point is hovering over a weapon button
-- @param px, py: point coordinates
-- @param config: global config object
-- @return weapon_id if hovering, nil otherwise
function WeaponsUI.get_weapon_hover(px, py, config)
	return WeaponsUI.get_weapon_at_point(px, py, config)
end

return WeaponsUI

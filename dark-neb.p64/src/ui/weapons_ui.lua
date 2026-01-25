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
	label_spacing = 12,  -- Space above button for status label
	text_color = 7,
	bg_color_normal = 24,  -- Maroon background
	bg_color_available = 24,  -- Maroon when available
	bg_color_unavailable = 0,  -- Dark when not available
	border_color = 7,
	color_indicator_width = 8,  -- Width of color square to the left
	color_indicator_spacing = 2,  -- Space between color square and button
	status_color_in_range = 11,  -- Green for in range
	status_color_out_of_range = 8,  -- Red for out of range
	toggle_size = 9,  -- Size of the arcs toggle button
	toggle_spacing =25,  -- Space above weapons for the toggle
}

-- Draw the weapons UI
-- @param energy_system: table with energy allocations for each system
-- @param selected_weapon: index of selected weapon (1 or 2, or nil)
-- @param weapon_states: table with charging and auto-fire state for each weapon
-- @param config: global config object
-- @param mouse_x: current mouse X position (for tooltip)
-- @param mouse_y: current mouse Y position (for tooltip)
-- @param ship_pos: current ship position for range/arc checks
-- @param ship_heading_dir: current ship heading direction vector {x, z}
-- @param current_target: current selected target (for range/arc validation)
-- @param weapon_effects: WeaponEffects module for range/arc functions
-- @param ship_systems: ShipSystems module for range/arc functions
-- @param camera: camera object for drawing firing arc
-- @param draw_line_3d: function to draw 3D lines
-- @param weapons_disabled: boolean, true if weapons subsystem is destroyed
function WeaponsUI.draw_weapons(energy_system, selected_weapon, weapon_states, config, mouse_x, mouse_y, ship_pos, ship_heading_dir, current_target, weapon_effects, ship_systems, camera, draw_line_3d, weapons_disabled)
	-- Position for weapons display
	local base_x = WEAPONS_CONFIG.base_x
	local y = 200  -- Standard position

	-- Weapons section
	y = y + 2

	-- Draw "show arcs" toggle above weapons
	local toggle_x = base_x
	local toggle_y = y - 10  -- Move up by 10 pixels
	local toggle_size = WEAPONS_CONFIG.toggle_size

	-- Check if mouse is hovering over toggle
	local toggle_hovered = mouse_x and mouse_y and
		mouse_x >= toggle_x and mouse_x < toggle_x + toggle_size and
		mouse_y >= toggle_y and mouse_y < toggle_y + toggle_size

	-- Toggle background
	local toggle_color = config.show_firing_arcs and 11 or 1
	rectfill(toggle_x, toggle_y, toggle_x + toggle_size, toggle_y + toggle_size, toggle_color)
	rect(toggle_x, toggle_y, toggle_x + toggle_size, toggle_y + toggle_size, 7)

	-- Draw tooltip if hovering over toggle
	if toggle_hovered then
		local arcs_status = config.show_firing_arcs and "on" or "off"
		local tooltip_text = "show arcs " .. arcs_status
		-- Draw tooltip to the right
		local tooltip_x = toggle_x + toggle_size + 5
		local tooltip_y = toggle_y
		-- Draw text shadow
		print(tooltip_text, tooltip_x + 1, tooltip_y + 1, 1)
		-- Draw text
		print(tooltip_text, tooltip_x, tooltip_y, WEAPONS_CONFIG.text_color)
	end

	y = y + toggle_size + 5

	-- Use weapons from config
	local weapons = config.weapons

	for i, weapon in ipairs(weapons) do
		local weapon_y = y + (i - 1) * (WEAPONS_CONFIG.button_height + WEAPONS_CONFIG.spacing + WEAPONS_CONFIG.label_spacing)

		-- Get weapon state
		local state = weapon_states[i] or {charge = 0}

		-- Determine if weapon is available (has enough weapons energy and weapons subsystem not destroyed)
		local has_energy = energy_system.weapons >= weapon.energy_cost
		local is_available = has_energy and not weapons_disabled
		local is_charged = is_available and state.charge >= 1.0

		-- Position of the button (to the right of the color indicator)
		local x = base_x + WEAPONS_CONFIG.color_indicator_width + WEAPONS_CONFIG.color_indicator_spacing

		-- Check if mouse is hovering over weapon button
		local button_hovered = mouse_x and mouse_y and
			mouse_x >= x and mouse_x < x + WEAPONS_CONFIG.button_width and
			mouse_y >= weapon_y and mouse_y < weapon_y + WEAPONS_CONFIG.button_height

		-- Check if target is in range and firing arc
		local in_range = false
		local in_arc = false
		if current_target and ship_pos and ship_heading_dir and ship_systems then
			in_range = ship_systems.is_in_range(ship_pos, current_target.position, weapon.range)
			in_arc = ship_systems.is_in_firing_arc(ship_pos, ship_heading_dir, current_target.position, weapon.arc_start, weapon.arc_end)
		end

		-- Draw status label above button
		local status_label = ""
		local status_color = WEAPONS_CONFIG.status_color_out_of_range
		if current_target then
			if not in_range then
				status_label = "range: " .. weapon.range
				status_color = WEAPONS_CONFIG.status_color_out_of_range
			elseif not in_arc then
				status_label = "out of arc"
				status_color = WEAPONS_CONFIG.status_color_out_of_range
			else
				status_label = "valid"
				status_color = WEAPONS_CONFIG.status_color_in_range
			end
			-- Draw status label
			print(status_label, x, weapon_y - WEAPONS_CONFIG.label_spacing, status_color)
		end

		-- Draw color indicator square to the left
		local color_x = base_x
		local indicator_color = 1  -- Dark when disabled
		if weapons_disabled then
			indicator_color = 1  -- Dark blue (disabled)
		elseif is_charged then
			indicator_color = 11  -- Bright when charged
		else
			indicator_color = 24  -- Maroon otherwise
		end
		rectfill(color_x, weapon_y, color_x + WEAPONS_CONFIG.color_indicator_width, weapon_y + WEAPONS_CONFIG.button_height, indicator_color)
		rect(color_x, weapon_y, color_x + WEAPONS_CONFIG.color_indicator_width, weapon_y + WEAPONS_CONFIG.button_height, weapons_disabled and 1 or WEAPONS_CONFIG.border_color)

		-- Determine button background color
		local bg_color = weapons_disabled and 1 or (has_energy and WEAPONS_CONFIG.bg_color_available or WEAPONS_CONFIG.bg_color_unavailable)

		-- Draw button drop shadow
		rectfill(x + 2, weapon_y + 2, x + WEAPONS_CONFIG.button_width + 2, weapon_y + WEAPONS_CONFIG.button_height + 2, 1)

		-- Draw button background
		rectfill(x, weapon_y, x + WEAPONS_CONFIG.button_width, weapon_y + WEAPONS_CONFIG.button_height, bg_color)

		-- Draw charging progress bar (fills from left to right) - only if weapons not disabled
		if is_available and state.charge > 0 then
			local charge_bar_width = (WEAPONS_CONFIG.button_width - 4) * state.charge
			rectfill(x + 2, weapon_y + 2, x + 2 + charge_bar_width, weapon_y + WEAPONS_CONFIG.button_height - 2, 8)  -- Red fill
		end

		-- Draw border (yellow when hovering, otherwise white; dark when disabled)
		local border_color = weapons_disabled and 1 or (button_hovered and 10 or WEAPONS_CONFIG.border_color)
		rect(x, weapon_y, x + WEAPONS_CONFIG.button_width, weapon_y + WEAPONS_CONFIG.button_height, border_color)

		-- Draw weapon name with drop shadow (dim text when disabled)
		local text_x = x + 3
		local text_y = weapon_y + 4
		local display_text = weapon.name
		local text_color = weapons_disabled and 5 or WEAPONS_CONFIG.text_color  -- Gray when disabled

		-- Draw text shadow
		print(display_text, text_x + 1, text_y + 1, 1)
		-- Draw text
		print(display_text, text_x, text_y, text_color)

		-- Draw auto-fire toggle to the right
		local auto_fire_toggle_x = x + WEAPONS_CONFIG.button_width + 3
		local auto_fire_toggle_y = weapon_y + 3
		local auto_fire_toggle_size = 9

		-- Check if mouse is hovering over this toggle
		local auto_fire_toggle_hovered = mouse_x and mouse_y and
			mouse_x >= auto_fire_toggle_x and mouse_x < auto_fire_toggle_x + auto_fire_toggle_size and
			mouse_y >= auto_fire_toggle_y and mouse_y < auto_fire_toggle_y + auto_fire_toggle_size

		-- Toggle background (dark when weapons disabled)
		local auto_fire_toggle_color = 1  -- Default dark
		local toggle_border_color = weapons_disabled and 1 or 7
		if not weapons_disabled then
			auto_fire_toggle_color = (weapon_states[i] and weapon_states[i].auto_fire) and 9 or 1
		end
		rectfill(auto_fire_toggle_x, auto_fire_toggle_y, auto_fire_toggle_x + auto_fire_toggle_size, auto_fire_toggle_y + auto_fire_toggle_size, auto_fire_toggle_color)
		rect(auto_fire_toggle_x, auto_fire_toggle_y, auto_fire_toggle_x + auto_fire_toggle_size, auto_fire_toggle_y + auto_fire_toggle_size, toggle_border_color)

		-- Show checkmark if auto-fire is enabled
		-- if weapon_states[i] and weapon_states[i].auto_fire then
		-- 	print("X", auto_fire_toggle_x + 3, auto_fire_toggle_y+2, 0)
		-- end

		-- Draw tooltip if hovering over toggle
		if auto_fire_toggle_hovered then
			local auto_fire_status = (weapon_states[i] and weapon_states[i].auto_fire) and "on" or "off"
			local tooltip_text = "auto " .. auto_fire_status
			-- Draw tooltip above the toggle
			local tooltip_x = auto_fire_toggle_x + 15
			local tooltip_y = auto_fire_toggle_y
			-- Draw text shadow
			print(tooltip_text, tooltip_x + 1, tooltip_y + 1, 1)
			-- Draw text
			print(tooltip_text, tooltip_x, tooltip_y, WEAPONS_CONFIG.text_color)
		end

		-- Draw firing arc visualization when hovering or when show_firing_arcs is enabled
		local should_draw_arc = (button_hovered or config.show_firing_arcs) and weapon_effects and camera and draw_line_3d and ship_pos and ship_heading_dir
		if should_draw_arc then
			-- Use color 1 when weapons disabled, otherwise green/red based on validity
			local arc_color = weapons_disabled and 1 or (in_range and in_arc and 11 or 8)
			weapon_effects.draw_firing_arc(ship_pos, ship_heading_dir, weapon.range, weapon.arc_start, weapon.arc_end, camera, draw_line_3d, arc_color)
		end
	end
end

-- Get hitbox for weapons UI buttons
-- @param config: global config object
-- @return array of hitbox tables with x, y, width, height, weapon_id
function WeaponsUI.get_weapon_hitboxes(config)
	local base_x = WEAPONS_CONFIG.base_x
	local base_y = WEAPONS_CONFIG.base_y
	local y = base_y + 2  -- Match draw_weapons positioning
	local x = base_x + WEAPONS_CONFIG.color_indicator_width + WEAPONS_CONFIG.color_indicator_spacing

	-- Account for show arcs toggle position
	y = y + WEAPONS_CONFIG.toggle_size + 5  -- Skip toggle and spacing

	local hitboxes = {}

	for i = 1, #config.weapons do
		local weapon_y = y + (i - 1) * (WEAPONS_CONFIG.button_height + WEAPONS_CONFIG.spacing + WEAPONS_CONFIG.label_spacing)

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
	local base_x = WEAPONS_CONFIG.base_x
	local base_y = WEAPONS_CONFIG.base_y
	local y = base_y + 2  -- Match draw_weapons positioning
	local toggle_size = 9
	local x = base_x + WEAPONS_CONFIG.color_indicator_width + WEAPONS_CONFIG.color_indicator_spacing

	-- Account for show arcs toggle position
	y = y + WEAPONS_CONFIG.toggle_size + 5  -- Skip toggle and spacing

	local hitboxes = {}

	for i = 1, #config.weapons do
		local weapon_y = y + (i - 1) * (WEAPONS_CONFIG.button_height + WEAPONS_CONFIG.spacing + WEAPONS_CONFIG.label_spacing)
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

-- Check if point is on the show arcs toggle button
-- @param px, py: point coordinates
-- @return true if toggle clicked, false otherwise
function WeaponsUI.is_show_arcs_toggle_clicked(px, py)
	local base_x = WEAPONS_CONFIG.base_x
	local base_y = WEAPONS_CONFIG.base_y
	local toggle_y = base_y + 2 - 10  -- Match draw_weapons positioning (y - 10)
	local toggle_size = WEAPONS_CONFIG.toggle_size

	return px >= base_x and px < base_x + toggle_size and
		   py >= toggle_y and py < toggle_y + toggle_size
end

return WeaponsUI

--[[pod_format="raw",created="2024-11-08 00:00:00",modified="2024-11-08 00:00:00",revision=0]]
-- UI Renderer Module
-- Centralized UI rendering system for game HUD and debug displays

local UIRenderer = {}

-- UI component references (set during init)
local Panel = nil
local Button = nil
local ProgressBar = nil
local Minimap = nil
local Menu = nil

-- UI State
local ui_state = {
	-- Health bar
	health_bar = nil,

	-- Speed slider
	speed_bar = nil,

	-- Panels
	death_panel = nil,
	out_of_bounds_panel = nil,

	-- Buttons
	restart_button = nil,
	back_to_menu_button = nil,

	-- Crosshair
	crosshair_enabled = true,

	-- Heading arc
	heading_arc_enabled = true,

	-- Debug display
	debug_ui = false,

	-- CPU display
	show_cpu = true,
}

-- Initialize UI renderer with component modules
-- @param modules: Table with {panel, button, minimap, menu} UI components
-- @param config: Config table with UI settings
-- @param callbacks: Table with {on_restart, on_menu} callback functions
function UIRenderer.init(modules, config, callbacks)
	modules = modules or {}
	config = config or {}
	callbacks = callbacks or {}

	-- Store module references
	Panel = modules.panel
	Button = modules.button
	Minimap = modules.minimap
	Menu = modules.menu
	ProgressBar = modules.progress_bar

	-- Create death panel
	if Panel then
		ui_state.death_panel = Panel.new(300, 150, "YOU DIED", true)
		ui_state.death_panel:set_colors(0, 7, 8)  -- Black bg, white border, red title
	end

	-- Create restart button
	if Button then
		ui_state.restart_button = Button.new(
			150,
			100,
			180,
			30,
			"RESTART",
			callbacks.on_restart or function() printh("restart_game") end
		)
	end

	-- Create out of bounds panel
	if Panel then
		ui_state.out_of_bounds_panel = Panel.new(280, 100, "LEAVING BATTLEFIELD", true)
		ui_state.out_of_bounds_panel:set_colors(0, 7, 8)  -- Black bg, white border, red title
	end

	-- Create back to menu button
	if Button then
		ui_state.back_to_menu_button = Button.new(
			160,
			115,
			160,
			30,
			"BACK TO MENU",
			callbacks.on_menu or function() printh("menu") end
		)
	end

	ui_state.show_cpu = config.show_cpu or true
	ui_state.debug_ui = config.debug or false
end

-- Update UI state (handle mouse input for interactive elements)
-- @param mouse_x: Mouse X position
-- @param mouse_y: Mouse Y position
-- @param mouse_clicked: Whether mouse was clicked this frame
-- @param game_state: Current game state ("menu", "playing", "out_of_bounds")
-- @param is_dead: Whether player is dead
function UIRenderer.update(mouse_x, mouse_y, mouse_clicked, game_state, is_dead)
	if game_state == "menu" then
		Menu.update({}, mouse_x, mouse_y, mouse_clicked)
	elseif is_dead then
		ui_state.restart_button:update(mouse_x, mouse_y, mouse_clicked)
	elseif game_state == "out_of_bounds" then
		ui_state.back_to_menu_button:update(mouse_x, mouse_y, mouse_clicked)
	end
end

-- Draw CPU usage display
function UIRenderer.draw_cpu_stats()
	if ui_state.show_cpu then
		local cpu = stat(1) * 100
		local color = cpu > 80 and 8 or 7
		print("cpu: " .. flr(cpu) .. "%", 380, 2, color)
	end
end

-- Draw minimap
-- @param ship_pos: Ship position table {x, y, z}
-- @param planet_pos: Planet position table {x, y, z}
-- @param planet_radius: Planet radius in world units
function UIRenderer.draw_minimap(ship_pos, planet_pos, planet_radius, satellite_pos, satellite_in_range)
	if Minimap then
		Minimap.draw(ship_pos, planet_pos, planet_radius, satellite_pos, satellite_in_range)
	end
end

-- Draw menu
function UIRenderer.draw_menu()
	if Menu then
		Menu.draw()
	end
end

-- Draw death screen
function UIRenderer.draw_death_screen()
	if ui_state.death_panel then
		ui_state.death_panel:show()
		ui_state.death_panel:draw()
		ui_state.restart_button:draw()
	end
end

-- Draw out of bounds warning
-- @param remaining_time: Time remaining before game over in seconds
function UIRenderer.draw_out_of_bounds(remaining_time)
	-- Draw "leaving battlefield" warning with drop shadow (no panel or button)
	local msg = "leaving battlefield"
	local time_msg = flr(remaining_time) .. "s"

	-- Message position (top-center with slight offset)
	local msg_x = 240 - (#msg * 2) + 5  -- Approximate center
	local msg_y = 30
	local time_y = msg_y + 12  -- Below the message

	-- Draw drop shadow for message (dark gray, offset by 1 pixel)
	print(msg, msg_x + 1, msg_y + 1, 1)
	print(msg, msg_x, msg_y, 8)  -- Red text

	-- Draw drop shadow for countdown (dark gray, offset by 1 pixel)
	print(time_msg, msg_x + 1, time_y + 1, 1)
	print(time_msg, msg_x, time_y, 11)  -- Bright cyan text
end

-- Get panel references (for direct manipulation if needed)
function UIRenderer.get_panels()
	return {
		death_panel = ui_state.death_panel,
		out_of_bounds_panel = ui_state.out_of_bounds_panel,
	}
end

-- Get button references (for direct manipulation if needed)
function UIRenderer.get_buttons()
	return {
		restart_button = ui_state.restart_button,
		back_to_menu_button = ui_state.back_to_menu_button,
	}
end

return UIRenderer

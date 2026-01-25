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

	-- Create restart button (positioned at bottom of death panel)
	if Button then
		ui_state.restart_button = Button.new(
			240,
			190,
			80,
			30,
			"MENU",
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
-- @param Config: game configuration (checks Config.show_cpu flag)
function UIRenderer.draw_cpu_stats(Config)
	if Config and Config.show_cpu then
		local cpu = stat(1) * 100
		local color = cpu > 80 and 8 or 7
		print("cpu: " .. flr(cpu) .. "%", 380, 2, color)
	end
end

-- Draw health bar at top left
-- @param Config: game configuration
-- @param current_health: current player health value
function UIRenderer.draw_health_bar(Config, current_health)
	local health_config = Config.health
	local health_bar_x = health_config.health_bar_x
	local health_bar_y = health_config.health_bar_y
	local health_bar_width = health_config.health_bar_width
	local health_bar_height = health_config.health_bar_height

	-- Health bar background (black)
	rectfill(health_bar_x, health_bar_y, health_bar_x + health_bar_width, health_bar_y + health_bar_height, 0)

	-- Health bar fill (green -> red based on health)
	local health_percent = current_health / Config.health.max_health
	local fill_width = health_bar_width * health_percent
	local health_color
	if health_percent > 0.5 then
		health_color = 11  -- Bright green/cyan
	elseif health_percent > 0.25 then
		health_color = 10  -- Yellow
	else
		health_color = 8  -- Red
	end
	if fill_width > 0 then
		rectfill(health_bar_x, health_bar_y, health_bar_x + fill_width, health_bar_y + health_bar_height, health_color)
	end

	-- Health bar border (white)
	rect(health_bar_x, health_bar_y, health_bar_x + health_bar_width, health_bar_y + health_bar_height, 7)

	-- Health text (inside the box with drop shadow)
	local health_display = flr(current_health)
	local health_text = "HP: " .. health_display
	local text_x = health_bar_x + 3
	local text_y = health_bar_y + 2
	-- Draw text shadow
	print(health_text, text_x + 1, text_y + 1, 1)
	-- Draw text
	print(health_text, text_x, text_y, 7)
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

-- Get narrative lines for mission success based on mission id
local function get_mission_narrative(mission_id)
	if mission_id == 2 then
		return {
			"", "Excellent work, cadet!", "",
			"You've graduated top of your class",
			"with incredible fanfare from your",
			"peers and teachers alike.", "",
			"You have a bright future ahead of you.",
		}
	elseif mission_id == 3 then
		return {
			"", "Outstanding, Captain!", "",
			"Your maiden voyage was a complete",
			"success. You've proven yourself in",
			"real combat against a hostile Grabon.", "",
			"Your crew looks to you with confidence.",
			"This is only the beginning of your",
			"journey among the stars.",
		}
	elseif mission_id == 4 then
		return {
			"", "Incredible, Captain!", "",
			"You've successfully defeated",
			"overwhelming odds!", "",
			"Two enemy Grabons destroyed against",
			"a single ship. Your tactical prowess",
			"is unmatched.", "",
			"Command will remember this victory.",
		}
	else
		return {
			"", "Congratulations, cadet!", "",
			"Your instructors at the Academy were",
			"deeply impressed by your performance.",
			"You've successfully completed your",
			"first year of training.", "",
			"However, be warned: the next year",
			"will be far more challenging.",
		}
	end
end

-- Draw mission success screen
-- @param mission_id: Current mission id
-- @param mx, my: Mouse position
-- @param mb: Mouse buttons
-- @return: true if OK button was clicked
function UIRenderer.draw_mission_success(mission_id, mx, my, mb)
	cls(0)

	-- Title
	local title = "Mission Success!!!"
	local title_x = 240 - (#title * 2)
	print(title, title_x - 1, 50, 0)
	print(title, title_x, 49, 11)

	-- Narrative text
	local narrative_lines = get_mission_narrative(mission_id)
	local text_y = 75
	for _, line in ipairs(narrative_lines) do
		local text_x = 240 - (#line * 2)
		print(line, text_x, text_y, 7)
		text_y = text_y + 8
	end

	-- OK button
	local button_y = 180
	local button_width = 50
	local button_height = 15
	local button_x = 240 - (button_width / 2)

	local button_hovered = mx and my and
		mx >= button_x and mx <= button_x + button_width and
		my >= button_y and my <= button_y + button_height

	rectfill(button_x, button_y, button_x + button_width, button_y + button_height, button_hovered and 5 or 0)
	rect(button_x, button_y, button_x + button_width, button_y + button_height, button_hovered and 10 or 7)

	local button_text = "OK"
	local button_text_x = button_x + (button_width - (#button_text * 4)) / 2
	local button_text_y = button_y + (button_height - 6) / 2
	print(button_text, button_text_x, button_text_y, 7)

	-- Check for button click or keyboard input
	local ok_clicked = ((mb & 1) == 1 and button_hovered) or keyp("return") or keyp("z")
	return ok_clicked
end

return UIRenderer

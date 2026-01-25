--[[pod_format="raw",created="2024-11-07 20:00:00",modified="2024-11-07 20:00:00",revision=0]]
-- UILayer Module
-- Consolidates gameplay UI rendering
-- Single Responsibility: Only handles UI drawing during gameplay

local UILayer = {}

-- Module dependencies (will be injected)
local EnergySystem = nil
local ShieldSystem = nil
local UIRenderer = nil
local WeaponsUI = nil
local Config = nil

-- Initialize UI layer with dependencies
-- @param energy_system: EnergySystem module
-- @param shield_system: ShieldSystem module
-- @param ui_renderer: UIRenderer module
-- @param weapons_ui: WeaponsUI module
-- @param config: Game configuration
function UILayer.init(energy_system, shield_system, ui_renderer, weapons_ui, config)
	EnergySystem = energy_system
	ShieldSystem = shield_system
	UIRenderer = ui_renderer
	WeaponsUI = weapons_ui
	Config = config
end

-- Draw speed slider
-- @param ship_speed: Current ship speed (0-1)
-- @param slider_speed_desired: Desired slider position (0-1)
function UILayer.draw_speed_slider(ship_speed, slider_speed_desired)
	local slider_x = Config.slider.x
	local slider_y = Config.slider.y
	local slider_height = Config.slider.height
	local slider_width = Config.slider.width
	local slider_handle_height = Config.slider.handle_height

	-- Slider track (background)
	rectfill(slider_x, slider_y, slider_x + slider_width, slider_y + slider_height, 1)

	-- Current speed fill
	local speed_fill_height = ship_speed * slider_height
	local speed_fill_y = slider_y + slider_height - speed_fill_height
	if speed_fill_height > 0 then
		rectfill(slider_x, speed_fill_y, slider_x + slider_width, slider_y + slider_height, 11)
	end

	-- Slider border
	rect(slider_x, slider_y, slider_x + slider_width, slider_y + slider_height, 7)

	-- Slider handle
	local handle_y = slider_y + (1 - slider_speed_desired) * slider_height - slider_handle_height / 2
	handle_y = mid(slider_y, handle_y, slider_y + slider_height - slider_handle_height)
	rectfill(slider_x - 2, handle_y, slider_x + slider_width + 2, handle_y + slider_handle_height, 7)
	rect(slider_x - 2, handle_y, slider_x + slider_width + 2, handle_y + slider_handle_height, 6)

	-- Speed value text
	local speed_display = flr(ship_speed * Config.ship.max_speed * 10) / 10
	local text_x = slider_x + Config.slider.text_x_offset
	local text_y = slider_y + slider_height + Config.slider.text_y_offset
	print(Config.slider.text_prefix .. speed_display, text_x, text_y, Config.slider.text_color)
end

-- Draw photon beam button and auto toggle
-- @param current_target: Currently selected target
-- @param energy_weapons: Current weapons energy allocation
function UILayer.draw_photon_button(current_target, energy_weapons)
	if not Config.photon_beam.enabled then return end

	local slider_y = Config.slider.y
	local slider_height = Config.slider.height

	local button_x = 390
	local button_y = slider_y + slider_height + 60
	local button_width = 50
	local button_height = 15
	local toggle_x = button_x
	local toggle_y = button_y + 20
	local toggle_size = 10

	-- Fire button
	local button_color = current_target and 11 or 5
	rectfill(button_x, button_y, button_x + button_width, button_y + button_height, button_color)
	rect(button_x, button_y, button_x + button_width, button_y + button_height, 7)
	print("fire", button_x + 10, button_y + 3, 0)

	-- Auto toggle checkbox
	local toggle_color = Config.photon_beam.auto_fire and 11 or 1
	rectfill(toggle_x, toggle_y, toggle_x + toggle_size, toggle_y + toggle_size, toggle_color)
	rect(toggle_x, toggle_y, toggle_x + toggle_size, toggle_y + toggle_size, 7)
	if Config.photon_beam.auto_fire then
		print("✓", toggle_x + 2, toggle_y, 0)
	end
	print("auto", toggle_x + 15, toggle_y + 1, 7)
end

-- Draw all gameplay UI elements
-- @param state: Game state table
-- @param mouse_x, mouse_y: Mouse position
function UILayer.draw_gameplay_ui(state, mouse_x, mouse_y)
	-- Health bar
	if UIRenderer and UIRenderer.draw_health_bar then
		UIRenderer.draw_health_bar(Config, state.current_health)
	end

	-- Energy bars
	if EnergySystem then
		EnergySystem.draw(mouse_x, mouse_y)
		EnergySystem.draw_no_energy_message()
	end

	-- Shield status
	if ShieldSystem then
		local allocated_shields = EnergySystem and EnergySystem.get_allocated("shields") or 0
		ShieldSystem.draw(allocated_shields)
	end

	-- Speed slider
	UILayer.draw_speed_slider(state.ship_speed, state.slider_speed_desired)

	-- Photon beam button
	UILayer.draw_photon_button(state.current_selected_target, state.energy_system.weapons)

	-- Weapons UI
	if WeaponsUI then
		-- This would need the full parameter list from main.lua
		-- WeaponsUI.draw_weapons(...)
	end
end

-- Draw minimap wrapper
-- @param ship_pos: Ship position
-- @param planet_pos: Planet position
-- @param planet_radius: Planet radius
-- @param satellite_pos: First satellite position (optional)
-- @param sat_in_range: Whether satellite is in sensor range
function UILayer.draw_minimap(ship_pos, planet_pos, planet_radius, satellite_pos, sat_in_range)
	if UIRenderer and UIRenderer.draw_minimap then
		UIRenderer.draw_minimap(ship_pos, planet_pos, planet_radius, satellite_pos, sat_in_range)
	end
end

-- Draw CPU stats wrapper
function UILayer.draw_cpu_stats()
	if UIRenderer and UIRenderer.draw_cpu_stats then
		UIRenderer.draw_cpu_stats(Config)
	end
end

return UILayer

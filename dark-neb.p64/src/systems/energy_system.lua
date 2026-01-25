--[[pod_format="raw",created="2024-11-07 20:00:00",modified="2024-11-07 20:00:00",revision=0]]
-- EnergySystem Module
-- Manages energy allocation between ship systems
-- Single Responsibility: Only handles energy allocation, hitboxes, and UI

local EnergySystem = {}

-- System names in display order
local SYSTEMS_LIST = {"weapons", "impulse", "shields", "tractor_beam", "sensors"}

-- Internal state (private)
local energy_state = nil
local energy_block_hitboxes = {}
local no_energy_message = {
	visible = false,
	x = 0,
	y = 0,
	duration = 0,
	max_duration = 1.0,
}

-- Config reference (injected via init)
local Config = nil

-- Initialize energy system from config
-- @param config: Game configuration object
function EnergySystem.init(config)
	Config = config
	energy_state = {
		weapons = config.energy.systems.weapons.allocated,
		impulse = config.energy.systems.impulse.allocated,
		shields = config.energy.systems.shields.allocated,
		tractor_beam = config.energy.systems.tractor_beam.allocated,
		sensors = config.energy.systems.sensors.allocated,
	}
	energy_block_hitboxes = {}
end

-- Get allocated energy for a system
-- @param system_name: "weapons", "impulse", "shields", "tractor_beam", or "sensors"
function EnergySystem.get_allocated(system_name)
	return energy_state[system_name] or 0
end

-- Set allocated energy for a system
function EnergySystem.set_allocated(system_name, amount)
	if energy_state[system_name] ~= nil then
		energy_state[system_name] = amount
		-- Sync with Config
		if Config and Config.energy.systems[system_name] then
			Config.energy.systems[system_name].allocated = amount
		end
	end
end

-- Get total allocated energy across all systems
function EnergySystem.get_total_allocated()
	return energy_state.weapons +
	       energy_state.impulse +
	       energy_state.shields +
	       energy_state.tractor_beam +
	       energy_state.sensors
end

-- Get available (unallocated) energy
function EnergySystem.get_available()
	return Config.energy.max_total - EnergySystem.get_total_allocated()
end

-- Get the full energy state table (for external access)
function EnergySystem.get_state()
	return energy_state
end

-- Reset all allocations to config defaults
function EnergySystem.reset_to_defaults()
	energy_state.weapons = Config.energy.systems.weapons.allocated
	energy_state.impulse = Config.energy.systems.impulse.allocated
	energy_state.shields = Config.energy.systems.shields.allocated
	energy_state.tractor_beam = Config.energy.systems.tractor_beam.allocated
	energy_state.sensors = Config.energy.systems.sensors.allocated
end

-- Build energy block hitboxes (call during update)
function EnergySystem.build_hitboxes()
	local energy_cfg = Config.energy

	-- Clear hitboxes from last frame
	energy_block_hitboxes = {}

	local display_index = 0
	for _, system_name in ipairs(SYSTEMS_LIST) do
		local system_cfg = energy_cfg.systems[system_name]

		-- Skip hidden systems
		if system_cfg.hidden then
			goto skip_hitbox
		end

		display_index = display_index + 1

		local allocated = energy_state[system_name]
		local capacity = system_cfg.capacity

		-- Calculate position
		local bar_y = energy_cfg.ui_y + (display_index - 1) * energy_cfg.system_spacing
		local bar_x = energy_cfg.ui_x + energy_cfg.system_bar_x_offset
		local padding = energy_cfg.hitbox.padding

		-- Create hitboxes for each energy unit
		for j = 1, capacity do
			local rect_x = bar_x + (j - 1) * (energy_cfg.bar_width + energy_cfg.bar_spacing)
			local rect_y = bar_y
			local rect_x2 = rect_x + energy_cfg.bar_width
			local rect_y2 = rect_y + energy_cfg.bar_height

			if energy_block_hitboxes[system_name] == nil then
				energy_block_hitboxes[system_name] = {}
			end
			energy_block_hitboxes[system_name][j] = {
				x1 = rect_x - padding, y1 = rect_y - padding,
				x2 = rect_x2 + padding, y2 = rect_y2 + padding,
				is_filled = (j <= allocated),
				orig_x1 = rect_x, orig_y1 = rect_y,
				orig_x2 = rect_x2, orig_y2 = rect_y2
			}
		end

		::skip_hitbox::
	end
end

-- Handle energy allocation/deallocation clicks
-- @param mx, my: Mouse position
-- @return: true if click was handled
function EnergySystem.handle_click(mx, my)
	for system_name, blocks in pairs(energy_block_hitboxes) do
		for block_num, hitbox in pairs(blocks) do
			if mx >= hitbox.x1 and mx <= hitbox.x2 and my >= hitbox.y1 and my <= hitbox.y2 then
				local is_filled = block_num <= energy_state[system_name]

				if is_filled then
					-- Deallocate down to this block
					energy_state[system_name] = block_num - 1
				else
					-- Allocate up to this block
					local available = EnergySystem.get_available()
					local system_cfg = Config.energy.systems[system_name]
					local current = energy_state[system_name]
					local to_allocate = block_num - current

					if available >= to_allocate then
						energy_state[system_name] = block_num
					else
						if available <= 0 then
							-- Show no energy message
							no_energy_message.visible = true
							no_energy_message.x = mx
							no_energy_message.y = my
							no_energy_message.duration = no_energy_message.max_duration
							return true
						end
						-- Allocate as much as available
						energy_state[system_name] = min(current + available, system_cfg.capacity)
					end
				end

				-- Sync with Config
				Config.energy.systems[system_name].allocated = energy_state[system_name]
				return true
			end
		end
	end
	return false
end

-- Update no energy message timer
-- @param dt: Delta time in seconds
function EnergySystem.update(dt)
	if no_energy_message.visible then
		no_energy_message.duration = no_energy_message.duration - dt
		if no_energy_message.duration <= 0 then
			no_energy_message.visible = false
		end
	end
end

-- Draw energy bars for each system
-- @param mouse_x, mouse_y: Mouse position for hover highlighting
function EnergySystem.draw(mouse_x, mouse_y)
	local energy_cfg = Config.energy

	-- Draw total energy bar
	EnergySystem.draw_total_bar()

	-- Check hover
	local hovered_system = nil
	local hovered_level = 0

	if mouse_x and mouse_y then
		for system_name, blocks in pairs(energy_block_hitboxes) do
			for level, hitbox in ipairs(blocks) do
				if mouse_x >= hitbox.x1 and mouse_x <= hitbox.x2 and
				   mouse_y >= hitbox.y1 and mouse_y <= hitbox.y2 then
					hovered_system = system_name
					hovered_level = level
					break
				end
			end
			if hovered_system then break end
		end
	end

	-- Draw each system's energy bar
	local display_index = 0
	for _, system_name in ipairs(SYSTEMS_LIST) do
		local system_cfg = energy_cfg.systems[system_name]

		if system_cfg.hidden then
			goto skip_draw
		end

		display_index = display_index + 1

		local allocated = energy_state[system_name]
		local capacity = system_cfg.capacity
		local bar_y = energy_cfg.ui_y + (display_index - 1) * energy_cfg.system_spacing
		local bar_x = energy_cfg.ui_x + energy_cfg.system_bar_x_offset

		-- Draw each energy block
		for j = 1, capacity do
			local rect_x = bar_x + (j - 1) * (energy_cfg.bar_width + energy_cfg.bar_spacing)
			local rect_y = bar_y
			local rect_x2 = rect_x + energy_cfg.bar_width
			local rect_y2 = rect_y + energy_cfg.bar_height

			local color = j <= allocated and system_cfg.color_full or system_cfg.color_empty
			rectfill(rect_x, rect_y, rect_x2, rect_y2, color)

			local is_hovered = hovered_system == system_name and j <= hovered_level
			local border_color = is_hovered and 10 or energy_cfg.box.border_color
			rect(rect_x, rect_y, rect_x2, rect_y2, border_color)
		end

		-- Draw system label
		local label_x = bar_x + capacity * (energy_cfg.bar_width + energy_cfg.bar_spacing) + system_cfg.label_offset
		print(system_name, label_x, bar_y, energy_cfg.label.text_color)

		-- Draw sensor damage boost text
		if system_name == "sensors" and system_cfg.damage_boost and system_cfg.damage_boost.enabled then
			local damage_bonus = 0
			if allocated == 1 then
				damage_bonus = system_cfg.damage_boost.one_box_bonus
			elseif allocated >= 2 then
				damage_bonus = system_cfg.damage_boost.two_plus_bonus
			end
			if damage_bonus > 0 then
				local bonus_text = "+" .. flr(damage_bonus * 100) .. "% dmg"
				local bonus_x = bar_x + system_cfg.damage_boost.text_x_offset
				local bonus_y = bar_y + energy_cfg.bar_height + system_cfg.damage_boost.text_y_offset
				print(bonus_text, bonus_x, bonus_y, 10)
			end
		end

		::skip_draw::
	end
end

-- Draw the vertical total energy bar
function EnergySystem.draw_total_bar()
	local energy_cfg = Config.energy
	local bar_x = energy_cfg.ui_x
	local bar_y = energy_cfg.ui_y
	local total_bars = energy_cfg.max_total
	local bar_width = energy_cfg.bar_width
	local bar_height = energy_cfg.bar_height
	local spacing = energy_cfg.bar_spacing

	local total_allocated = EnergySystem.get_total_allocated()

	for i = 1, total_bars do
		local rect_y = bar_y + (i - 1) * (bar_height + spacing)
		local rect_y2 = rect_y + bar_height
		local color = i <= total_allocated and energy_cfg.total_bar.color_full or energy_cfg.total_bar.color_empty

		rectfill(bar_x, rect_y, bar_x + bar_width, rect_y2, color)
		rect(bar_x, rect_y, bar_x + bar_width, rect_y2, energy_cfg.total_bar.border_color)
	end
end

-- Draw no energy feedback message
function EnergySystem.draw_no_energy_message()
	if not no_energy_message.visible then return end

	local msg_text = "NO ENERGY"
	local box_width = 60
	local box_height = 20
	local box_x = no_energy_message.x - box_width / 2
	local box_y = no_energy_message.y - box_height - 5

	rectfill(box_x, box_y, box_x + box_width, box_y + box_height, 8)
	rect(box_x, box_y, box_x + box_width, box_y + box_height, 7)
	print(msg_text, box_x + 5, box_y + 6, 7)
end

return EnergySystem

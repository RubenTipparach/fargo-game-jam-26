--[[pod_format="raw",created="2024-11-07 20:00:00",modified="2024-11-07 20:00:00",revision=0]]
-- ShieldSystem Module
-- Manages shield charging and damage absorption
-- Single Responsibility: Only handles shield mechanics

local ShieldSystem = {}

-- Internal state (private)
local shield_charge = {
	boxes = {0, 0, 0},
	charge_time = 10.0,  -- Seconds to fully charge one shield
}

-- Config reference (injected via init)
local Config = nil

-- Initialize shield system from config
-- @param config: Game configuration object
function ShieldSystem.init(config)
	Config = config
	shield_charge.charge_time = config.energy.systems.shields.charge_time
	for i = 1, 3 do
		shield_charge.boxes[i] = 0
	end
end

-- Update shield charging based on allocated energy
-- Shields charge sequentially: box 1 must be full before box 2 starts charging
-- @param dt: Delta time in seconds
-- @param allocated_shields: Number of shields allocated (0-3)
function ShieldSystem.update(dt, allocated_shields)
	for i = 1, 3 do
		if i <= allocated_shields then
			-- Check if previous box is fully charged
			local previous_charged = (i == 1) or (shield_charge.boxes[i-1] >= 1.0)

			if previous_charged then
				-- Charge this box
				shield_charge.boxes[i] = shield_charge.boxes[i] + dt / shield_charge.charge_time
				if shield_charge.boxes[i] > 1.0 then
					shield_charge.boxes[i] = 1.0
				end
			end
		else
			-- This box is not allocated, reset it
			shield_charge.boxes[i] = 0
		end
	end
end

-- Try to absorb incoming damage
-- Only FULLY charged shields (>= 1.0) can absorb damage
-- @return: true if damage was absorbed, false if damage goes through
function ShieldSystem.try_absorb()
	-- Count fully charged shields
	local charged_shields = 0
	for i = 1, 3 do
		if shield_charge.boxes[i] >= 1.0 then
			charged_shields = charged_shields + 1
		end
	end

	-- If we have charged shields, consume one
	if charged_shields > 0 then
		for i = 1, 3 do
			if shield_charge.boxes[i] >= 1.0 then
				shield_charge.boxes[i] = 0
				printh("SHIELD ACTIVATED: Shield " .. i .. " absorbed damage!")
				return true
			end
		end
	end

	-- No shields available - reset partial charges
	ShieldSystem.reset_partial_charges()
	return false
end

-- Reset all partially charged shields
function ShieldSystem.reset_partial_charges()
	for i = 1, 3 do
		if shield_charge.boxes[i] > 0 and shield_charge.boxes[i] < 1.0 then
			shield_charge.boxes[i] = 0
		end
	end
end

-- Reset shields for a specific allocation level
-- Called when energy allocation changes
-- @param new_allocation: New number of allocated shields
function ShieldSystem.on_allocation_changed(new_allocation)
	-- Reset charges for shields beyond the new allocation
	for i = new_allocation + 1, 3 do
		shield_charge.boxes[i] = 0
	end
end

-- Get the charge level of a specific shield
-- @param index: Shield index (1-3)
-- @return: Charge level 0-1
function ShieldSystem.get_charge(index)
	return shield_charge.boxes[index] or 0
end

-- Get number of fully charged shields
function ShieldSystem.get_charged_count()
	local count = 0
	for i = 1, 3 do
		if shield_charge.boxes[i] >= 1.0 then
			count = count + 1
		end
	end
	return count
end

-- Get full shield state (for external access)
function ShieldSystem.get_state()
	return shield_charge
end

-- Draw shield charge status UI
-- @param allocated_shields: Number of shields allocated (0-3)
function ShieldSystem.draw(allocated_shields)
	local shield_cfg = Config.shield_sliders
	local panel_x = shield_cfg.x
	local panel_y = shield_cfg.y
	local bar_width = shield_cfg.bar_width
	local bar_height = shield_cfg.bar_height
	local bar_spacing = shield_cfg.bar_spacing
	local fill_color = shield_cfg.fill_color
	local empty_color = shield_cfg.empty_color
	local border_color = shield_cfg.border_color

	-- Draw 3 shield charge bars side by side
	for i = 1, 3 do
		local bar_x = panel_x + (i - 1) * (bar_width + bar_spacing)
		local bar_y = panel_y

		-- Draw background
		rectfill(bar_x, bar_y, bar_x + bar_width, bar_y + bar_height, empty_color)

		-- Draw charge progress (only if allocated)
		if i <= allocated_shields and shield_charge.boxes[i] > 0 then
			local charge_fill_width = (bar_width - 2) * shield_charge.boxes[i]
			rectfill(bar_x + 1, bar_y + 1, bar_x + 1 + charge_fill_width, bar_y + bar_height - 1, fill_color)
		end

		-- Draw border
		rect(bar_x, bar_y, bar_x + bar_width, bar_y + bar_height, border_color)
	end
end

return ShieldSystem

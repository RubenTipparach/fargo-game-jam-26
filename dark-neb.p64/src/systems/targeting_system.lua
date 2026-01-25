--[[pod_format="raw",created="2024-11-07 20:00:00",modified="2024-11-07 20:00:00",revision=0]]
-- TargetingSystem Module
-- Manages target selection and hover detection
-- Single Responsibility: Only handles targeting mechanics

local TargetingSystem = {}

-- Internal state (private)
local hovered_target = nil
local current_target = nil

-- Initialize targeting system
function TargetingSystem.init()
	hovered_target = nil
	current_target = nil
end

-- Get currently hovered target
function TargetingSystem.get_hovered()
	return hovered_target
end

-- Get currently selected target
function TargetingSystem.get_selected()
	return current_target
end

-- Select a target
-- @param target: Target object to select (or nil to clear)
function TargetingSystem.select(target)
	current_target = target
	if target then
		printh("Target selected: " .. (target.id or "unknown"))
	end
end

-- Clear current target
function TargetingSystem.clear()
	current_target = nil
	hovered_target = nil
end

-- Clear selection only (keep hover)
function TargetingSystem.clear_selection()
	current_target = nil
end

-- Check if a target is selected
function TargetingSystem.has_target()
	return current_target ~= nil
end

-- Check if a specific target is the current selection
function TargetingSystem.is_selected(target)
	return current_target and target and current_target.id == target.id
end

-- Update hover detection based on mouse position
-- @param enemies: Array of enemy objects
-- @param mouse_x, mouse_y: Screen mouse position
-- @param camera: Camera object
-- @param project_fn: Function to project 3D to 2D (world_x, y, z, camera) -> screen_x, screen_y
-- @param hover_radius: Pixel radius for hover detection (default 20)
function TargetingSystem.update_hover(enemies, mouse_x, mouse_y, camera, project_fn, hover_radius)
	hover_radius = hover_radius or 20
	hovered_target = nil

	for _, enemy in ipairs(enemies) do
		if enemy.position and not enemy.is_destroyed then
			if enemy.type == "satellite" or enemy.type == "grabon" then
				local pos = enemy.position
				local center_px, center_py = project_fn(pos.x, pos.y, pos.z, camera)

				if center_px and center_py then
					local dx = mouse_x - center_px
					local dy = mouse_y - center_py
					local dist = sqrt(dx * dx + dy * dy)

					if dist < hover_radius then
						hovered_target = enemy
						return hovered_target
					end
				end
			end
		end
	end

	return hovered_target
end

-- Cycle through valid targets
-- @param enemies: Array of enemy objects
-- @return: New selected target (or nil if none available)
function TargetingSystem.cycle_targets(enemies)
	-- Build list of valid targets
	local valid_targets = {}
	for _, enemy in ipairs(enemies) do
		if not enemy.is_destroyed and (enemy.type == "satellite" or enemy.type == "grabon") then
			table.insert(valid_targets, enemy)
		end
	end

	if #valid_targets == 0 then
		current_target = nil
		return nil
	end

	-- Find current target index
	local current_index = 0
	if current_target then
		for i, enemy in ipairs(valid_targets) do
			if enemy.id == current_target.id then
				current_index = i
				break
			end
		end
	end

	-- Cycle to next target
	local next_index = (current_index % #valid_targets) + 1
	current_target = valid_targets[next_index]

	printh("Cycled to target: " .. current_target.id)
	return current_target
end

-- Handle target destruction (clear if currently selected)
-- @param destroyed_enemy_id: ID of the destroyed enemy
function TargetingSystem.on_enemy_destroyed(destroyed_enemy_id)
	if current_target and current_target.id == destroyed_enemy_id then
		current_target = nil
		printh("Target destroyed, selection cleared")
	end

	if hovered_target and hovered_target.id == destroyed_enemy_id then
		hovered_target = nil
	end
end

-- Get target position (convenience method)
-- @return: {x, y, z} or nil if no target
function TargetingSystem.get_target_position()
	if current_target and current_target.position then
		return current_target.position
	end
	return nil
end

-- Get distance to target from a position
-- @param from_pos: {x, y, z} source position
-- @return: Distance or nil if no target
function TargetingSystem.get_distance_to_target(from_pos)
	if not current_target or not current_target.position then
		return nil
	end

	local dx = current_target.position.x - from_pos.x
	local dy = current_target.position.y - from_pos.y
	local dz = current_target.position.z - from_pos.z

	return sqrt(dx * dx + dy * dy + dz * dz)
end

return TargetingSystem

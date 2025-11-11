--[[pod_format="raw",created="2025-11-10 00:00:00",modified="2025-11-10 00:00:00",revision=0]]
-- Arc Visualization Module
-- Draws various arcs: heading arcs, firing arcs, etc.

local ArcVisualization = {}

-- Draw all arc visualizations (heading arc, weapon arcs, etc.)
-- @param ship_heading_dir: player ship heading direction vector {x, z}
-- @param target_heading_dir: target heading direction vector {x, z}
-- @param current_selected_target: currently selected target (can be nil)
-- @param ship_pos: player ship position {x, y, z}
-- @param camera: camera object
-- @param config: game config
-- @param weapon_effects: WeaponEffects module
-- @param arc_ui: ArcUI module
-- @param utilities: table with utility functions (draw_line_3d, dir_to_quat, quat_to_dir, project_to_screen, Renderer)
-- @param angle_to_dir: function to convert angle to direction vector
-- @param angle_difference: function to calculate angle difference
-- @param ship_systems: ShipSystems module
function ArcVisualization.draw_all_arcs(ship_heading_dir, target_heading_dir, current_selected_target, ship_pos, camera, config, weapon_effects, arc_ui, utilities, angle_to_dir, angle_difference, ship_systems)
	-- Draw weapon effects (beams, explosions, smoke)
	weapon_effects.draw(camera, utilities)

	-- Draw heading compass (arc, heading lines) when ship is moving or turning
	-- Calculate angle difference to see if we need to draw the compass
	local angle_diff = angle_difference(ship_heading_dir, target_heading_dir)

	-- Draw heading arc using ArcUI module
	arc_ui.draw_heading_arc(ship_heading_dir, target_heading_dir, angle_diff, camera, config, utilities)

	-- Draw Grabon firing arc visualization when selected and firing arcs are enabled
	if current_selected_target and current_selected_target.type == "grabon" and current_selected_target.position and config.show_firing_arcs then
		local grabon_pos = current_selected_target.position
		local grabon_ai = current_selected_target.config.ai
		if grabon_ai then
			-- Draw the firing arc for Grabon
			local grabon_dir = angle_to_dir(current_selected_target.heading)

			-- Check if player is in range and in firing arc (green if valid, red otherwise)
			local in_range = ship_systems.is_in_range(grabon_pos, ship_pos, grabon_ai.attack_range)
			local in_arc = ship_systems.is_in_firing_arc(grabon_pos, grabon_dir, ship_pos, grabon_ai.firing_arc_start, grabon_ai.firing_arc_end)
			local arc_color = (in_range and in_arc) and 11 or 8  -- Green (11) if valid firing position, red (8) otherwise

			weapon_effects.draw_firing_arc(grabon_pos, grabon_dir, grabon_ai.attack_range, grabon_ai.firing_arc_start, grabon_ai.firing_arc_end, camera, utilities.draw_line_3d, arc_color)
		end
	end
end

return ArcVisualization

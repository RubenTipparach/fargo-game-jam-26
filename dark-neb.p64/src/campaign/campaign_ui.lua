--[[pod_format="raw",created="2025-01-26 00:00:00",modified="2025-01-26 00:00:00",revision=0]]
-- Campaign UI Module
-- Draws sector map and campaign-related UI elements

local CampaignUI = {}

-- Track last click state for button detection
local last_click_state = false
local hovered_node = nil
local repair_button_bounds = nil
local repair_hover = false

-- Campaign select screen state
local select_hovered = nil  -- "continue", "new", "back"
local select_continue_bounds = nil
local select_new_bounds = nil
local select_back_bounds = nil

-- Ship movement animation state
local ship_anim = {
	active = false,
	from_x = 0,
	from_y = 0,
	to_x = 0,
	to_y = 0,
	progress = 0,
	duration = 0.5,  -- seconds
	target_node = nil,
}

-- Combat encounter prompt state
local encounter_prompt = {
	active = false,
	node = nil,
}

-- Current location info (for shop button)
local current_location = {
	node = nil,
	shop_button_hover = false,
}

-- Draw the sector map
-- @param map: Sector map from SectorMap.generate()
-- @param config: Game config
-- @param mx, my: Mouse position
function CampaignUI.draw_sector_map(map, config, mx, my)
	if not map then return end

	local cfg = config.campaign
	local map_x = cfg.map_x
	local map_y = cfg.map_y
	local map_width = cfg.map_width
	local map_height = cfg.map_height
	local node_radius = cfg.node_radius
	local colors = cfg.colors

	-- Draw background
	rectfill(map_x - 10, map_y - 10, map_x + map_width + 10, map_y + map_height + 10, 0)
	rect(map_x - 10, map_y - 10, map_x + map_width + 10, map_y + map_height + 10, 6)

	-- Draw connections first (behind nodes)
	for i = 1, #map.connections do
		local conn = map.connections[i]
		local from_x = map_x + conn.from_x * map_width
		local from_y = map_y + conn.from_y * map_height
		local to_x = map_x + conn.to_x * map_width
		local to_y = map_y + conn.to_y * map_height

		line(from_x, from_y, to_x, to_y, colors.connection)
	end

	-- Track hovered node
	hovered_node = nil

	-- Draw nodes
	for i = 1, #map.nodes do
		local node = map.nodes[i]
		local nx = map_x + node.x * map_width
		local ny = map_y + node.y * map_height

		-- Determine node color
		local fill_color = colors[node.type] or 6
		local border_color = 6

		if node.visited then
			fill_color = colors.visited
		elseif node.available then
			border_color = colors.available

			-- Check if mouse is hovering
			local dx = mx - nx
			local dy = my - ny
			local dist = sqrt(dx * dx + dy * dy)
			if dist <= node_radius + 3 then
				hovered_node = node
				border_color = colors.current
			end
		end

		-- Draw node
		circfill(nx, ny, node_radius, fill_color)
		circ(nx, ny, node_radius, border_color)

		-- Draw type icon/letter inside node
		local icon = ""
		if node.type == "combat" then
			icon = "!"
		elseif node.type == "shop" then
			icon = "$"
		elseif node.type == "empty" then
			icon = "-"
		elseif node.type == "planet" then
			icon = "P"
		elseif node.type == "exit" then
			icon = ">"
		end

		local text_color = node.visited and 1 or 7
		print(icon, nx - 2, ny - 3, text_color)
	end

	-- Draw ship marker - either animating or at current position
	local ship_x, ship_y
	local ship_color = colors.ship or 10

	if ship_anim.active then
		-- Interpolate position during animation
		local t = ship_anim.progress
		-- Ease out cubic for smooth deceleration
		t = 1 - (1 - t) * (1 - t) * (1 - t)
		ship_x = ship_anim.from_x + (ship_anim.to_x - ship_anim.from_x) * t
		ship_y = ship_anim.from_y + (ship_anim.to_y - ship_anim.from_y) * t
	else
		-- Find current node (most recently visited with highest column)
		local current_node = nil
		for i = #map.nodes, 1, -1 do
			if map.nodes[i].visited then
				if not current_node or map.nodes[i].column > current_node.column then
					current_node = map.nodes[i]
				end
			end
		end

		if current_node then
			ship_x = map_x + current_node.x * map_width
			ship_y = map_y + current_node.y * map_height
		end
	end

	if ship_x and ship_y then
		-- Draw ship marker (small circle with direction indicator)
		circfill(ship_x, ship_y, 5, ship_color)
		circ(ship_x, ship_y, 5, 7)
		-- Draw direction indicator (pointing right)
		line(ship_x + 3, ship_y, ship_x + 7, ship_y, 7)
	end

	-- Draw sector title
	local sector_num = map.sector_number or 1
	local title = "Sector " .. sector_num
	print(title, map_x + map_width / 2 - #title * 2, map_y - 25, 11)
end

-- Draw campaign status bar (credits, repair kits, sector progress)
-- @param campaign_state: CampaignState module
-- @param config: Game config
function CampaignUI.draw_status_bar(campaign_state, config)
	local credits = campaign_state.get_credits()
	local repair_kits = campaign_state.get_repair_kits()
	local sector = campaign_state.get_current_sector()
	local total = campaign_state.get_total_sectors()

	local y = 5

	-- Credits
	print("Credits: " .. credits, 10, y, 11)

	-- Repair kits
	print("Repair Kits: " .. repair_kits, 120, y, 12)

	-- Sector progress
	local progress_text = "Sector " .. sector .. "/" .. total
	print(progress_text, 480 - #progress_text * 4 - 10, y, 7)
end

-- Draw ship status panel (health, subsystems) with repair button
-- @param campaign_state: CampaignState module
-- @param mx, my: Mouse position for hover detection
function CampaignUI.draw_ship_status(campaign_state, mx, my)
	local state = campaign_state.get_state()
	if not state then return end

	local ship = state.ship
	local x = 10
	local y = 245

	-- Hull health bar
	local bar_width = 100
	local bar_height = 8
	local health_pct = ship.current_health / ship.max_health

	print("Hull", x, y - 10, 7)
	rectfill(x, y, x + bar_width, y + bar_height, 0)
	if health_pct > 0 then
		local fill = bar_width * health_pct
		local color = health_pct > 0.5 and 11 or (health_pct > 0.25 and 10 or 8)
		rectfill(x, y, x + fill, y + bar_height, color)
	end
	rect(x, y, x + bar_width, y + bar_height, 7)
	print(ship.current_health .. "/" .. ship.max_health, x + bar_width + 5, y, 7)

	-- Repair button (uses repair kit to heal hull)
	local can_repair = state.repair_kits > 0 and ship.current_health < ship.max_health
	local btn_x = x + 150
	local btn_y = y - 2
	local btn_w = 60
	local btn_h = 12

	repair_button_bounds = {x1 = btn_x, y1 = btn_y, x2 = btn_x + btn_w, y2 = btn_y + btn_h}
	repair_hover = mx and my and mx >= btn_x and mx <= btn_x + btn_w and my >= btn_y and my <= btn_y + btn_h

	local btn_color = 1  -- Dark default
	local txt_color = 5  -- Gray when disabled
	if can_repair then
		txt_color = 7
		if repair_hover then
			btn_color = 5
			txt_color = 11
		end
	end

	rectfill(btn_x, btn_y, btn_x + btn_w, btn_y + btn_h, btn_color)
	rect(btn_x, btn_y, btn_x + btn_w, btn_y + btn_h, can_repair and (repair_hover and 11 or 6) or 5)
	print("Repair", btn_x + 12, btn_y + 2, txt_color)

	-- Repair kits count
	print("Kits: " .. state.repair_kits, btn_x + btn_w + 8, btn_y + 2, 12)

	-- Subsystem status icons
	local sub_x = x + 280
	local sub_y = y - 5
	local sub_spacing = 25

	local subsystem_icons = {
		{name = "weapons", icon = "W", color = 8},
		{name = "engines", icon = "E", color = 11},
		{name = "shields", icon = "S", color = 12},
		{name = "sensors", icon = "N", color = 10},
		{name = "life_support", icon = "L", color = 9},
	}

	for i = 1, #subsystem_icons do
		local sub_info = subsystem_icons[i]
		local sub = ship.subsystems[sub_info.name]
		local sx = sub_x + (i - 1) * sub_spacing

		-- Background
		local bg_color = sub.destroyed and 5 or 0
		rectfill(sx, sub_y, sx + 20, sub_y + 15, bg_color)
		rect(sx, sub_y, sx + 20, sub_y + 15, sub.destroyed and 5 or sub_info.color)

		-- Icon
		local text_color = sub.destroyed and 5 or sub_info.color
		print(sub_info.icon, sx + 7, sub_y + 4, text_color)

		-- Health indicator (small bar below)
		if not sub.destroyed then
			local sub_pct = sub.health / sub.max_health
			local sub_bar_w = 18
			rectfill(sx + 1, sub_y + 14, sx + 1 + sub_bar_w * sub_pct, sub_y + 16, sub_info.color)
		end
	end
end

-- Handle repair button click
-- @param campaign_state: CampaignState module
-- @param mouse_click: Whether mouse is clicked
-- @return: true if repair was used
function CampaignUI.handle_repair_click(campaign_state, mouse_click)
	if repair_hover and mouse_click and not last_click_state then
		local state = campaign_state.get_state()
		if state and state.repair_kits > 0 and state.ship.current_health < state.ship.max_health then
			if campaign_state.use_repair_kit_for_hull(25) then
				return true
			end
		end
	end
	return false
end

-- Draw tooltip for hovered node
function CampaignUI.draw_node_tooltip(config, mx, my)
	if not hovered_node then return end

	local descriptions = {
		combat = "Combat: Fight an enemy ship",
		shop = "Shop: Buy repairs and supplies",
		empty = "Rest Stop: Safe passage",
		planet = "Planet: Special encounter",
		exit = "Warp Gate: Jump to next sector",
	}

	local text = descriptions[hovered_node.type] or "Unknown"
	local tw = #text * 4 + 10
	local th = 12

	local tx = mx + 10
	local ty = my - 20

	-- Keep on screen
	if tx + tw > 480 then tx = mx - tw - 5 end
	if ty < 0 then ty = my + 10 end

	rectfill(tx, ty, tx + tw, ty + th, 0)
	rect(tx, ty, tx + tw, ty + th, 7)
	print(text, tx + 5, ty + 3, 7)
end

-- Draw back button
-- @return: Button bounds for click detection
function CampaignUI.draw_back_button()
	local text = "< Main Menu"
	local x = 10
	local y = 255
	print(text, x, y, 6)

	return {x1 = x - 5, y1 = y - 5, x2 = x + #text * 4 + 10, y2 = y + 12}
end

-- Update campaign map UI
-- @param map: Sector map
-- @param config: Game config
-- @param mx, my: Mouse position
-- @param mouse_click: Whether mouse is clicked
-- @param campaign_state: Optional CampaignState for repair handling
-- @return: Selected node if clicked, "back" if back button clicked, "repair" if repair used, nil otherwise
function CampaignUI.update(map, config, mx, my, mouse_click, campaign_state)
	-- Check back button
	local back_bounds = CampaignUI.draw_back_button()

	if mx >= back_bounds.x1 and mx <= back_bounds.x2 and
	   my >= back_bounds.y1 and my <= back_bounds.y2 then
		if mouse_click and not last_click_state then
			last_click_state = mouse_click
			return "back"
		end
	end

	-- Check repair button
	if campaign_state and CampaignUI.handle_repair_click(campaign_state, mouse_click) then
		last_click_state = mouse_click
		return "repair"
	end

	-- Check node clicks
	if hovered_node and hovered_node.available and not hovered_node.visited then
		if mouse_click and not last_click_state then
			last_click_state = mouse_click
			return hovered_node
		end
	end

	last_click_state = mouse_click
	return nil
end

-- Get currently hovered node
function CampaignUI.get_hovered_node()
	return hovered_node
end

-- Draw victory screen
-- @param stats: Campaign stats
-- @param mx, my, mb: Mouse state
-- @return: true if continue button clicked
function CampaignUI.draw_victory_screen(stats, mx, my, mb)
	cls(0)

	local cx = 240
	local cy = 100

	print("CAMPAIGN COMPLETE!", cx - 72, cy - 50, 11)
	print("You have survived the Dark Nebula!", cx - 120, cy - 30, 7)

	if stats then
		print("Sectors Completed: " .. stats.nodes_visited, cx - 80, cy, 7)
		print("Enemies Destroyed: " .. stats.enemies_destroyed, cx - 80, cy + 15, 7)
		print("Credits Earned: " .. stats.credits_earned, cx - 80, cy + 30, 7)
	end

	-- Continue button
	local btn_x = cx - 40
	local btn_y = cy + 70
	local btn_w = 80
	local btn_h = 20

	local hover = mx >= btn_x and mx <= btn_x + btn_w and my >= btn_y and my <= btn_y + btn_h
	rectfill(btn_x, btn_y, btn_x + btn_w, btn_y + btn_h, hover and 5 or 1)
	rect(btn_x, btn_y, btn_x + btn_w, btn_y + btn_h, hover and 11 or 6)
	print("Main Menu", btn_x + 12, btn_y + 6, hover and 11 or 7)

	if hover and (mb & 1) == 1 and not last_click_state then
		last_click_state = (mb & 1) == 1
		return true
	end
	last_click_state = (mb & 1) == 1

	return false
end

-- Draw death screen
-- @param stats: Campaign stats
-- @param mx, my, mb: Mouse state
-- @return: "retry" or "menu" if button clicked, nil otherwise
function CampaignUI.draw_death_screen(stats, mx, my, mb)
	cls(0)

	local cx = 240
	local cy = 100

	print("SHIP DESTROYED", cx - 56, cy - 50, 8)
	print("Your journey ends here...", cx - 88, cy - 30, 5)

	if stats then
		print("Sectors Completed: " .. (stats.nodes_visited or 0), cx - 80, cy, 7)
		print("Enemies Destroyed: " .. (stats.enemies_destroyed or 0), cx - 80, cy + 15, 7)
		print("Credits Earned: " .. (stats.credits_earned or 0), cx - 80, cy + 30, 7)
	end

	-- New Run button
	local btn1_x = cx - 90
	local btn1_y = cy + 70
	local btn_w = 80
	local btn_h = 20

	local hover1 = mx >= btn1_x and mx <= btn1_x + btn_w and my >= btn1_y and my <= btn1_y + btn_h
	rectfill(btn1_x, btn1_y, btn1_x + btn_w, btn1_y + btn_h, hover1 and 5 or 1)
	rect(btn1_x, btn1_y, btn1_x + btn_w, btn1_y + btn_h, hover1 and 11 or 6)
	print("New Run", btn1_x + 18, btn1_y + 6, hover1 and 11 or 7)

	-- Main Menu button
	local btn2_x = cx + 10
	local btn2_y = cy + 70

	local hover2 = mx >= btn2_x and mx <= btn2_x + btn_w and my >= btn2_y and my <= btn2_y + btn_h
	rectfill(btn2_x, btn2_y, btn2_x + btn_w, btn2_y + btn_h, hover2 and 5 or 1)
	rect(btn2_x, btn2_y, btn2_x + btn_w, btn2_y + btn_h, hover2 and 11 or 6)
	print("Main Menu", btn2_x + 12, btn2_y + 6, hover2 and 11 or 7)

	local click = (mb & 1) == 1
	if click and not last_click_state then
		if hover1 then
			last_click_state = click
			return "retry"
		elseif hover2 then
			last_click_state = click
			return "menu"
		end
	end
	last_click_state = click

	return nil
end

-- Draw combat victory screen
-- @param credits_earned: Credits earned from combat
-- @param mx, my, mb: Mouse state
-- @return: true if continue button clicked
function CampaignUI.draw_combat_victory(credits_earned, mx, my, mb)
	-- Draw overlay
	rectfill(100, 80, 380, 190, 0)
	rect(100, 80, 380, 190, 11)

	local cx = 240

	print("VICTORY!", cx - 32, 95, 11)
	print("Enemy Destroyed", cx - 56, 115, 7)
	print("Credits Earned: +" .. credits_earned, cx - 64, 140, 10)

	-- Continue button
	local btn_x = cx - 40
	local btn_y = 160
	local btn_w = 80
	local btn_h = 18

	local hover = mx >= btn_x and mx <= btn_x + btn_w and my >= btn_y and my <= btn_y + btn_h
	rectfill(btn_x, btn_y, btn_x + btn_w, btn_y + btn_h, hover and 5 or 1)
	rect(btn_x, btn_y, btn_x + btn_w, btn_y + btn_h, hover and 11 or 6)
	print("Continue", btn_x + 16, btn_y + 5, hover and 11 or 7)

	local click = (mb & 1) == 1
	if hover and click and not last_click_state then
		last_click_state = click
		return true
	end
	last_click_state = click

	return false
end

-- Draw campaign continue/new selection screen
-- @param mx, my: Mouse position
function CampaignUI.draw_campaign_select(mx, my)
	cls(0)

	local cx = 240
	local cy = 100

	-- Title
	print("CAMPAIGN", cx - 32, cy - 60, 11)
	print("A saved run was found", cx - 72, cy - 40, 7)

	-- Button config
	local btn_w = 120
	local btn_h = 28
	local btn_spacing = 15

	-- Continue button
	local btn1_x = cx - btn_w / 2
	local btn1_y = cy - 10
	select_continue_bounds = {x1 = btn1_x, y1 = btn1_y, x2 = btn1_x + btn_w, y2 = btn1_y + btn_h}

	local hover1 = mx >= btn1_x and mx <= btn1_x + btn_w and my >= btn1_y and my <= btn1_y + btn_h
	if hover1 then select_hovered = "continue" end

	rectfill(btn1_x, btn1_y, btn1_x + btn_w, btn1_y + btn_h, hover1 and 5 or 1)
	rect(btn1_x, btn1_y, btn1_x + btn_w, btn1_y + btn_h, hover1 and 11 or 6)
	local text_w = print("Continue", 0, -1000)
	print("Continue", btn1_x + (btn_w - text_w) / 2, btn1_y + 10, hover1 and 11 or 7)

	-- New Run button
	local btn2_y = btn1_y + btn_h + btn_spacing
	select_new_bounds = {x1 = btn1_x, y1 = btn2_y, x2 = btn1_x + btn_w, y2 = btn2_y + btn_h}

	local hover2 = mx >= btn1_x and mx <= btn1_x + btn_w and my >= btn2_y and my <= btn2_y + btn_h
	if hover2 then select_hovered = "new" end

	rectfill(btn1_x, btn2_y, btn1_x + btn_w, btn2_y + btn_h, hover2 and 5 or 1)
	rect(btn1_x, btn2_y, btn1_x + btn_w, btn2_y + btn_h, hover2 and 11 or 6)
	text_w = print("New Run", 0, -1000)
	print("New Run", btn1_x + (btn_w - text_w) / 2, btn2_y + 10, hover2 and 11 or 7)

	-- Back button
	local back_text = "< Back"
	local back_x = 30
	local back_y = 240
	select_back_bounds = {x1 = back_x - 5, y1 = back_y - 5, x2 = back_x + #back_text * 4 + 10, y2 = back_y + 12}

	local hover_back = mx >= select_back_bounds.x1 and mx <= select_back_bounds.x2 and
	                   my >= select_back_bounds.y1 and my <= select_back_bounds.y2
	if hover_back then select_hovered = "back" end

	print(back_text, back_x, back_y, hover_back and 11 or 6)

	-- Reset hover if not over anything
	if not hover1 and not hover2 and not hover_back then
		select_hovered = nil
	end
end

-- Update campaign select screen
-- @param mx, my: Mouse position
-- @param mouse_click: Whether mouse is clicked
-- @return: "continue", "new", "back", or nil
function CampaignUI.update_campaign_select(mx, my, mouse_click)
	-- Update hover state from draw
	CampaignUI.draw_campaign_select(mx, my)

	if mouse_click and not last_click_state then
		if select_hovered == "continue" then
			last_click_state = mouse_click
			return "continue"
		elseif select_hovered == "new" then
			last_click_state = mouse_click
			return "new"
		elseif select_hovered == "back" then
			last_click_state = mouse_click
			return "back"
		end
	end

	last_click_state = mouse_click
	return nil
end

-- Start ship movement animation to a target node
-- @param from_node: Node the ship is moving from
-- @param to_node: Node the ship is moving to
-- @param config: Game config (for map dimensions)
function CampaignUI.start_ship_animation(from_node, to_node, config)
	local cfg = config.campaign
	local map_x = cfg.map_x
	local map_y = cfg.map_y
	local map_width = cfg.map_width
	local map_height = cfg.map_height

	ship_anim.active = true
	ship_anim.from_x = map_x + from_node.x * map_width
	ship_anim.from_y = map_y + from_node.y * map_height
	ship_anim.to_x = map_x + to_node.x * map_width
	ship_anim.to_y = map_y + to_node.y * map_height
	ship_anim.progress = 0
	ship_anim.target_node = to_node

	printh("CampaignUI: Starting ship animation to node " .. to_node.id)
end

-- Update ship animation (call each frame)
-- @param dt: Delta time in seconds
-- @return: target_node if animation just completed, nil otherwise
function CampaignUI.update_ship_animation(dt)
	if not ship_anim.active then return nil end

	ship_anim.progress = ship_anim.progress + dt / ship_anim.duration

	if ship_anim.progress >= 1 then
		ship_anim.active = false
		ship_anim.progress = 1
		local target = ship_anim.target_node
		ship_anim.target_node = nil
		return target
	end

	return nil
end

-- Check if ship animation is active
function CampaignUI.is_animating()
	return ship_anim.active
end

-- Show encounter prompt for combat nodes
function CampaignUI.show_encounter_prompt(node)
	encounter_prompt.active = true
	encounter_prompt.node = node
end

-- Hide encounter prompt
function CampaignUI.hide_encounter_prompt()
	encounter_prompt.active = false
	encounter_prompt.node = nil
end

-- Check if encounter prompt is active
function CampaignUI.is_encounter_prompt_active()
	return encounter_prompt.active
end

-- Draw and update encounter prompt
-- @param mx, my: Mouse position
-- @param mouse_click: Whether mouse is clicked
-- @return: "fight" if fight button clicked, "flee" if flee clicked, nil otherwise
function CampaignUI.update_encounter_prompt(mx, my, mouse_click)
	if not encounter_prompt.active or not encounter_prompt.node then
		return nil
	end

	local cx = 240
	local cy = 135

	-- Draw dark overlay
	rectfill(80, 70, 400, 200, 0)
	rect(80, 70, 400, 200, 8)

	-- Title
	print("HOSTILE CONTACT", cx - 56, 85, 8)

	-- Description
	local desc = "Enemy vessel detected!"
	print(desc, cx - #desc * 2, 110, 7)
	print("Prepare for combat?", cx - 72, 125, 7)

	-- Fight button
	local btn_w = 80
	local btn_h = 20
	local fight_x = cx - 90
	local fight_y = 155

	local hover_fight = mx >= fight_x and mx <= fight_x + btn_w and my >= fight_y and my <= fight_y + btn_h
	rectfill(fight_x, fight_y, fight_x + btn_w, fight_y + btn_h, hover_fight and 8 or 2)
	rect(fight_x, fight_y, fight_x + btn_w, fight_y + btn_h, hover_fight and 10 or 8)
	print("FIGHT", fight_x + 24, fight_y + 6, hover_fight and 10 or 7)

	-- Flee button (disabled for now - could implement later)
	local flee_x = cx + 10
	local flee_y = 155

	local hover_flee = mx >= flee_x and mx <= flee_x + btn_w and my >= flee_y and my <= flee_y + btn_h
	rectfill(flee_x, flee_y, flee_x + btn_w, flee_y + btn_h, hover_flee and 5 or 1)
	rect(flee_x, flee_y, flee_x + btn_w, flee_y + btn_h, hover_flee and 6 or 5)
	print("FLEE", flee_x + 28, flee_y + 6, 5)  -- Grayed out

	-- Handle clicks
	if mouse_click and not last_click_state then
		if hover_fight then
			last_click_state = mouse_click
			encounter_prompt.active = false
			return "fight"
		end
		-- Flee is disabled for now
	end

	last_click_state = mouse_click
	return nil
end

-- Set current location node (call when ship arrives at a node)
function CampaignUI.set_current_location(node)
	current_location.node = node
end

-- Clear current location
function CampaignUI.clear_current_location()
	current_location.node = nil
end

-- Check if at a shop/planet location
function CampaignUI.is_at_shop()
	return current_location.node and
		(current_location.node.type == "shop" or current_location.node.type == "planet")
end

-- Draw and update shop button (only shows when at shop/planet)
-- @param mx, my: Mouse position
-- @param mouse_click: Whether mouse is clicked
-- @return: "open_shop" if button clicked, nil otherwise
function CampaignUI.update_shop_button(mx, my, mouse_click)
	if not CampaignUI.is_at_shop() then
		return nil
	end

	-- Draw shop button in bottom right area
	local btn_x = 380
	local btn_y = 250
	local btn_w = 90
	local btn_h = 18

	local hover = mx >= btn_x and mx <= btn_x + btn_w and my >= btn_y and my <= btn_y + btn_h
	current_location.shop_button_hover = hover

	local btn_color = hover and 11 or 3
	local border_color = hover and 7 or 11
	rectfill(btn_x, btn_y, btn_x + btn_w, btn_y + btn_h, btn_color)
	rect(btn_x, btn_y, btn_x + btn_w, btn_y + btn_h, border_color)

	local label = current_location.node.type == "shop" and "OPEN SHOP" or "EXPLORE"
	print(label, btn_x + (btn_w - #label * 4) / 2, btn_y + 5, hover and 0 or 7)

	-- Handle click
	if hover and mouse_click and not last_click_state then
		last_click_state = mouse_click
		return "open_shop"
	end

	return nil
end

return CampaignUI

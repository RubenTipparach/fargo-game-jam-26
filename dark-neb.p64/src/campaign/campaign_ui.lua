--[[pod_format="raw",created="2025-01-26 00:00:00",modified="2025-01-26 00:00:00",revision=0]]
-- Campaign UI Module
-- Draws sector map and campaign-related UI elements

local CampaignUI = {}

-- Track last click state for button detection
local last_click_state = false
local hovered_node = nil

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
		end

		local text_color = node.visited and 1 or 7
		print(icon, nx - 2, ny - 3, text_color)
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

-- Draw ship status panel (health, subsystems)
-- @param campaign_state: CampaignState module
function CampaignUI.draw_ship_status(campaign_state)
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

	-- Subsystem status icons
	local sub_x = x + 180
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

-- Draw tooltip for hovered node
function CampaignUI.draw_node_tooltip(config, mx, my)
	if not hovered_node then return end

	local descriptions = {
		combat = "Combat: Fight an enemy ship",
		shop = "Shop: Buy repairs and supplies",
		empty = "Rest Stop: Safe passage",
		planet = "Planet: Special encounter",
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
-- @return: Selected node if clicked, "back" if back button clicked, nil otherwise
function CampaignUI.update(map, config, mx, my, mouse_click)
	-- Check back button
	local back_bounds = CampaignUI.draw_back_button()

	if mx >= back_bounds.x1 and mx <= back_bounds.x2 and
	   my >= back_bounds.y1 and my <= back_bounds.y2 then
		if mouse_click and not last_click_state then
			last_click_state = mouse_click
			return "back"
		end
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

return CampaignUI

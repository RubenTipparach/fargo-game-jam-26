--[[pod_format="raw",created="2025-01-26 00:00:00",modified="2025-01-26 00:00:00",revision=0]]
-- Shop UI Module
-- Draws shop interface for buying repairs and supplies

local ShopUI = {}

-- Track last click state
local last_click_state = false
local hovered_item = nil
local hovered_subsystem = nil
local message = nil
local message_timer = 0

-- Draw the shop interface
-- @param campaign_state: CampaignState module
-- @param config: Game config
-- @param mx, my: Mouse position
function ShopUI.draw(campaign_state, config, mx, my)
	cls(0)

	local state = campaign_state.get_state()
	if not state then return end

	local shop_items = config.campaign.shop_items
	local credits = state.credits
	local ship = state.ship

	-- Title
	print("SUPPLY DEPOT", 240 - 48, 15, 11)

	-- Credits display
	print("Credits: " .. credits, 350, 15, 10)

	-- Left panel: Shop items
	local item_x = 30
	local item_y = 50
	local item_height = 35
	local item_width = 200

	print("SUPPLIES", item_x, item_y - 15, 7)

	hovered_item = nil

	for i = 1, #shop_items do
		local item = shop_items[i]
		local y = item_y + (i - 1) * item_height
		local can_afford = credits >= item.cost

		-- Check hover
		local hover = mx >= item_x and mx <= item_x + item_width and
		              my >= y and my <= y + item_height - 5

		if hover and can_afford then
			hovered_item = i
		end

		-- Background
		local bg_color = hover and can_afford and 5 or 1
		rectfill(item_x, y, item_x + item_width, y + item_height - 5, bg_color)
		rect(item_x, y, item_x + item_width, y + item_height - 5, can_afford and 7 or 5)

		-- Item name and cost
		local name_color = can_afford and 7 or 5
		print(item.name, item_x + 5, y + 5, name_color)
		print(item.cost .. " cr", item_x + item_width - 35, y + 5, can_afford and 10 or 5)

		-- Description
		print(item.description, item_x + 5, y + 15, 6)
	end

	-- Right panel: Ship status
	local status_x = 260
	local status_y = 50

	print("SHIP STATUS", status_x, status_y - 15, 7)

	-- Hull health
	local hull_y = status_y
	local bar_width = 150
	local bar_height = 12
	local health_pct = ship.current_health / ship.max_health

	print("Hull:", status_x, hull_y, 7)
	rectfill(status_x + 40, hull_y, status_x + 40 + bar_width, hull_y + bar_height, 0)
	if health_pct > 0 then
		local fill = bar_width * health_pct
		local color = health_pct > 0.5 and 11 or (health_pct > 0.25 and 10 or 8)
		rectfill(status_x + 40, hull_y, status_x + 40 + fill, hull_y + bar_height, color)
	end
	rect(status_x + 40, hull_y, status_x + 40 + bar_width, hull_y + bar_height, 7)
	print(ship.current_health .. "/" .. ship.max_health, status_x + 200, hull_y + 2, 7)

	-- Subsystems
	local sub_y = status_y + 25
	print("Subsystems:", status_x, sub_y, 7)

	hovered_subsystem = nil

	local subsystem_info = {
		{name = "weapons", label = "Weapons", color = 8},
		{name = "engines", label = "Engines", color = 11},
		{name = "shields", label = "Shields", color = 12},
		{name = "sensors", label = "Sensors", color = 10},
		{name = "life_support", label = "Life Sup", color = 9},
	}

	for i = 1, #subsystem_info do
		local info = subsystem_info[i]
		local y = sub_y + 15 + (i - 1) * 22
		local sub = ship.subsystems[info.name]
		local sub_pct = sub.health / sub.max_health

		-- Check hover (for repair kit targeting)
		local hover = mx >= status_x and mx <= status_x + 200 and
		              my >= y and my <= y + 18

		if hover and sub.health < sub.max_health then
			hovered_subsystem = info.name
		end

		-- Label
		local label_color = sub.destroyed and 5 or 7
		print(info.label, status_x, y + 2, label_color)

		-- Health bar
		local sub_bar_x = status_x + 60
		local sub_bar_w = 100
		local sub_bar_h = 10

		local bg = hover and sub.health < sub.max_health and 5 or 0
		rectfill(sub_bar_x, y, sub_bar_x + sub_bar_w, y + sub_bar_h, bg)

		if sub_pct > 0 and not sub.destroyed then
			rectfill(sub_bar_x, y, sub_bar_x + sub_bar_w * sub_pct, y + sub_bar_h, info.color)
		end

		rect(sub_bar_x, y, sub_bar_x + sub_bar_w, y + sub_bar_h, sub.destroyed and 5 or 7)

		-- Status text
		local status_text = sub.destroyed and "OFFLINE" or (sub.health .. "/" .. sub.max_health)
		print(status_text, sub_bar_x + sub_bar_w + 5, y + 1, sub.destroyed and 8 or 6)
	end

	-- Repair kits
	local kit_y = sub_y + 130
	print("Repair Kits: " .. state.repair_kits, status_x, kit_y, 12)
	if state.repair_kits > 0 and hovered_subsystem then
		print("Click subsystem to use kit", status_x, kit_y + 12, 6)
	end

	-- Continue button
	local btn_x = 350
	local btn_y = 235
	local btn_w = 100
	local btn_h = 25

	local btn_hover = mx >= btn_x and mx <= btn_x + btn_w and my >= btn_y and my <= btn_y + btn_h
	rectfill(btn_x, btn_y, btn_x + btn_w, btn_y + btn_h, btn_hover and 5 or 1)
	rect(btn_x, btn_y, btn_x + btn_w, btn_y + btn_h, btn_hover and 11 or 6)
	print("Continue", btn_x + 24, btn_y + 8, btn_hover and 11 or 7)

	-- Message display
	if message and message_timer > 0 then
		print(message, 240 - #message * 2, 230, 11)
	end
end

-- Update shop UI
-- @param campaign_state: CampaignState module
-- @param config: Game config
-- @param mx, my: Mouse position
-- @param mouse_click: Whether mouse is clicked
-- @return: "continue" if continue button clicked, nil otherwise
function ShopUI.update(campaign_state, config, mx, my, mouse_click)
	-- Update message timer
	if message_timer > 0 then
		message_timer = message_timer - 1/60
		if message_timer <= 0 then
			message = nil
		end
	end

	local state = campaign_state.get_state()
	if not state then return nil end

	-- Check continue button
	local btn_x = 350
	local btn_y = 235
	local btn_w = 100
	local btn_h = 25

	local btn_hover = mx >= btn_x and mx <= btn_x + btn_w and my >= btn_y and my <= btn_y + btn_h
	if btn_hover and mouse_click and not last_click_state then
		last_click_state = mouse_click
		return "continue"
	end

	-- Check item purchase
	if hovered_item and mouse_click and not last_click_state then
		local item = config.campaign.shop_items[hovered_item]
		if state.credits >= item.cost then
			-- Purchase item
			if campaign_state.spend_credits(item.cost) then
				if item.id == "repair_kit" then
					campaign_state.add_repair_kit(1)
					message = "Repair Kit acquired!"
				elseif item.id == "hull_repair" then
					campaign_state.repair_hull(item.heal_amount or 50)
					message = "Hull repaired!"
				elseif item.id == "full_repair" then
					campaign_state.full_repair()
					message = "Full repair complete!"
				end
				message_timer = 2.0
				printh("ShopUI: Purchased " .. item.id)
			end
		end
	end

	-- Check subsystem repair with kit
	if hovered_subsystem and state.repair_kits > 0 and mouse_click and not last_click_state then
		if campaign_state.use_repair_kit() then
			campaign_state.repair_subsystem(hovered_subsystem)
			message = hovered_subsystem .. " repaired!"
			message_timer = 2.0
			printh("ShopUI: Repaired " .. hovered_subsystem .. " with kit")
		end
	end

	last_click_state = mouse_click
	return nil
end

return ShopUI

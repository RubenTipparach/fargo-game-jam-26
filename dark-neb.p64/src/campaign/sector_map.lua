--[[pod_format="raw",created="2025-01-26 00:00:00",modified="2025-01-26 00:00:00",revision=0]]
-- Sector Map Module
-- Generates and manages FTL-style sector node maps

local SectorMap = {}

-- Node types
SectorMap.NODE_TYPES = {
	COMBAT = "combat",
	SHOP = "shop",
	EMPTY = "empty",
	PLANET = "planet",
}

-- Generate a sector map
-- @param config: Game config (for generation parameters)
-- @param sector_number: Current sector (affects difficulty/node distribution)
-- @return: Map object with nodes and connections
function SectorMap.generate(config, sector_number)
	local nodes = {}
	local connections = {}
	local node_id = 1

	local cfg = config.campaign
	local nodes_per_column = cfg.nodes_per_column
	local weights = cfg.node_type_weights

	-- Generate nodes column by column
	local columns = {}
	local x_spacing = 1.0 / (#nodes_per_column + 1)

	for col = 1, #nodes_per_column do
		columns[col] = {}
		local node_count = nodes_per_column[col]
		local y_spacing = 1.0 / (node_count + 1)

		for row = 1, node_count do
			-- Determine node type
			local node_type = SectorMap.NODE_TYPES.COMBAT  -- Default

			-- First node of first column is always empty (safe start)
			if col == 1 and row == 1 then
				node_type = SectorMap.NODE_TYPES.EMPTY
			else
				-- Weighted random selection
				node_type = SectorMap.pick_node_type(weights)
			end

			-- Position (normalized 0-1)
			local x = col * x_spacing
			local y = row * y_spacing

			-- Add some jitter for visual interest
			x = x + (rnd() - 0.5) * 0.05
			y = y + (rnd() - 0.5) * 0.08

			local node = {
				id = node_id,
				type = node_type,
				x = x,
				y = y,
				column = col,
				row = row,
				connections = {},
				visited = false,
				available = col == 1,  -- Only first column available at start
			}

			add(nodes, node)
			add(columns[col], node)
			node_id = node_id + 1
		end
	end

	-- Generate connections between adjacent columns
	for col = 1, #nodes_per_column - 1 do
		local current_col = columns[col]
		local next_col = columns[col + 1]

		for i = 1, #current_col do
			local node = current_col[i]
			-- Connect to 1-2 nodes in next column
			local num_connections = flr(rnd(2)) + 1
			num_connections = min(num_connections, #next_col)

			-- Sort next column by distance to current node (simple insertion sort)
			local sorted_next = {}
			for j = 1, #next_col do
				local next_node = next_col[j]
				local dy = abs(next_node.y - node.y)
				-- Insert in sorted order
				local inserted = false
				for k = 1, #sorted_next do
					if dy < sorted_next[k].dist then
						-- Shift elements and insert
						for m = #sorted_next, k, -1 do
							sorted_next[m + 1] = sorted_next[m]
						end
						sorted_next[k] = {node = next_node, dist = dy}
						inserted = true
						break
					end
				end
				if not inserted then
					sorted_next[#sorted_next + 1] = {node = next_node, dist = dy}
				end
			end

			-- Connect to closest nodes
			for c = 1, num_connections do
				if sorted_next[c] then
					local target = sorted_next[c].node
					add(node.connections, target.id)

					-- Store connection for drawing
					add(connections, {
						from_id = node.id,
						to_id = target.id,
						from_x = node.x,
						from_y = node.y,
						to_x = target.x,
						to_y = target.y,
					})
				end
			end
		end
	end

	-- Ensure all nodes in columns 2+ have at least one incoming connection
	for col = 2, #nodes_per_column do
		for i = 1, #columns[col] do
			local node = columns[col][i]
			local has_incoming = false
			for j = 1, #connections do
				if connections[j].to_id == node.id then
					has_incoming = true
					break
				end
			end

			-- If no incoming, connect from random node in previous column
			if not has_incoming then
				local prev_col = columns[col - 1]
				local source = prev_col[flr(rnd(#prev_col)) + 1]
				add(source.connections, node.id)
				add(connections, {
					from_id = source.id,
					to_id = node.id,
					from_x = source.x,
					from_y = source.y,
					to_x = node.x,
					to_y = node.y,
				})
			end
		end
	end

	local map = {
		nodes = nodes,
		connections = connections,
		columns = columns,
		sector_number = sector_number,
	}

	printh("SectorMap: Generated sector " .. sector_number .. " with " .. #nodes .. " nodes")
	return map
end

-- Pick a node type based on weights
function SectorMap.pick_node_type(weights)
	local total = 0
	for type_name, w in pairs(weights) do
		total = total + w
	end

	local roll = rnd(total)
	local cumulative = 0

	for type_name, weight in pairs(weights) do
		cumulative = cumulative + weight
		if roll <= cumulative then
			return type_name
		end
	end

	return SectorMap.NODE_TYPES.COMBAT  -- Fallback
end

-- Get a node by ID
function SectorMap.get_node(map, node_id)
	for i = 1, #map.nodes do
		local node = map.nodes[i]
		if node.id == node_id then
			return node
		end
	end
	return nil
end

-- Mark a node as visited and update available nodes
function SectorMap.visit_node(map, node_id)
	local visited_node = SectorMap.get_node(map, node_id)
	if not visited_node then return end

	visited_node.visited = true

	-- Make connected nodes available
	for i = 1, #visited_node.connections do
		local conn_id = visited_node.connections[i]
		local conn_node = SectorMap.get_node(map, conn_id)
		if conn_node then
			conn_node.available = true
		end
	end

	printh("SectorMap: Visited node " .. node_id .. ", type=" .. visited_node.type)
end

-- Check if a node can be selected
function SectorMap.can_select_node(map, node_id)
	local node = SectorMap.get_node(map, node_id)
	return node and node.available and not node.visited
end

-- Get all available (selectable) nodes
function SectorMap.get_available_nodes(map)
	local available = {}
	for i = 1, #map.nodes do
		local node = map.nodes[i]
		if node.available and not node.visited then
			add(available, node)
		end
	end
	return available
end

-- Check if sector is complete (reached last column)
function SectorMap.is_sector_complete(map)
	local last_col = map.columns[#map.columns]
	for i = 1, #last_col do
		if last_col[i].visited then
			return true
		end
	end
	return false
end

-- Get node at screen position (for click detection)
-- @param map: Sector map
-- @param mx, my: Mouse position
-- @param config: Game config (for map display settings)
-- @return: Node if clicked, nil otherwise
function SectorMap.get_node_at_position(map, mx, my, config)
	local cfg = config.campaign
	local map_x = cfg.map_x
	local map_y = cfg.map_y
	local map_width = cfg.map_width
	local map_height = cfg.map_height
	local node_radius = cfg.node_radius

	for i = 1, #map.nodes do
		local node = map.nodes[i]
		local nx = map_x + node.x * map_width
		local ny = map_y + node.y * map_height

		local dx = mx - nx
		local dy = my - ny
		local dist = sqrt(dx * dx + dy * dy)

		if dist <= node_radius + 5 then  -- +5 for easier clicking
			return node
		end
	end

	return nil
end

return SectorMap

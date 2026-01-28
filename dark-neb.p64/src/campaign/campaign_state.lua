--[[pod_format="raw",created="2025-01-26 00:00:00",modified="2025-01-26 00:00:00",revision=0]]
-- Campaign State Module
-- Manages persistent state for a roguelite campaign run

local CampaignState = {}

-- Current run state
local run_state = nil

-- Reference to SaveData (set during init)
local SaveData = nil

-- Set SaveData reference for persistence
function CampaignState.set_save_data(save_data_module)
	SaveData = save_data_module
end

-- Save current run to persistent storage
function CampaignState.save_to_disk()
	if run_state and SaveData then
		SaveData.save_campaign(run_state)
	end
end

-- Load run from persistent storage
function CampaignState.load_from_disk()
	if SaveData then
		local saved = SaveData.load_campaign()
		if saved then
			run_state = saved
			printh("CampaignState: Loaded run from disk")
			return true
		end
	end
	return false
end

-- Check if there's a saved campaign
function CampaignState.has_saved_campaign()
	if SaveData then
		return SaveData.has_campaign_save()
	end
	return false
end

-- Clear saved campaign from disk
function CampaignState.clear_save()
	if SaveData then
		SaveData.clear_campaign()
	end
end

-- Create default ship state
local function create_default_ship(config)
	return {
		current_health = config.health.max_health,
		max_health = config.health.max_health,
		subsystems = {
			weapons = {health = config.subsystems.player.weapons.max_health, max_health = config.subsystems.player.weapons.max_health, destroyed = false},
			engines = {health = config.subsystems.player.engines.max_health, max_health = config.subsystems.player.engines.max_health, destroyed = false},
			shields = {health = config.subsystems.player.shields.max_health, max_health = config.subsystems.player.shields.max_health, destroyed = false},
			sensors = {health = config.subsystems.player.sensors.max_health, max_health = config.subsystems.player.sensors.max_health, destroyed = false},
			life_support = {health = config.subsystems.player.life_support.max_health, max_health = config.subsystems.player.life_support.max_health, destroyed = false},
		},
	}
end

-- Start a new campaign run
function CampaignState.new_run(config)
	run_state = {
		-- Progression
		current_sector = 1,
		current_node = nil,
		total_sectors = config.campaign.sectors_per_run,

		-- Ship state (persists between nodes)
		ship = create_default_ship(config),

		-- Resources
		credits = config.campaign.starting_credits,
		repair_kits = config.campaign.starting_repair_kits,

		-- Map state
		sector_map = nil,  -- Generated when entering sector
		visited_nodes = {},

		-- Stats for death screen
		stats = {
			nodes_visited = 0,
			enemies_destroyed = 0,
			credits_earned = 0,
			damage_taken = 0,
		},
	}

	printh("CampaignState: New run started")
	return run_state
end

-- Get current run state
function CampaignState.get_state()
	return run_state
end

-- Check if a run is active
function CampaignState.has_active_run()
	return run_state ~= nil
end

-- Set the sector map for current sector
function CampaignState.set_sector_map(map)
	if run_state then
		run_state.sector_map = map
	end
end

-- Mark a node as visited
function CampaignState.visit_node(node_id)
	if run_state then
		run_state.visited_nodes[node_id] = true
		run_state.current_node = node_id
		run_state.stats.nodes_visited = run_state.stats.nodes_visited + 1
		CampaignState.save_to_disk()  -- Persist after each node visit
		printh("CampaignState: Visited node " .. tostring(node_id))
	end
end

-- Save ship state after combat victory
-- @param player_health_obj: Player health object from game
-- @param subsystem_states: Subsystem states from SubsystemManager
-- @param damage_taken: Damage taken during combat
function CampaignState.save_post_combat(player_health_obj, subsystem_states, damage_taken)
	if not run_state then return end

	-- Save hull health
	run_state.ship.current_health = player_health_obj.current_health

	-- Save subsystem states
	if subsystem_states then
		for name, state in pairs(subsystem_states) do
			if run_state.ship.subsystems[name] then
				run_state.ship.subsystems[name].health = state.health
				run_state.ship.subsystems[name].destroyed = state.destroyed
			end
		end
	end

	-- Track stats
	run_state.stats.damage_taken = run_state.stats.damage_taken + (damage_taken or 0)
	run_state.stats.enemies_destroyed = run_state.stats.enemies_destroyed + 1

	CampaignState.save_to_disk()  -- Persist after combat
	printh("CampaignState: Saved post-combat state, hull=" .. run_state.ship.current_health)
end

-- Award credits after combat
-- @param config: Game config (for reward values)
-- @param subsystems_damaged: Number of subsystems that were damaged
function CampaignState.award_combat_credits(config, subsystems_damaged)
	if not run_state then return 0 end

	local base = config.campaign.combat_victory_base
	local max_reward = config.campaign.combat_victory_max
	local bonus = config.campaign.no_subsystem_damage_bonus

	-- Base reward plus bonus if no subsystems damaged
	local reward = base
	if subsystems_damaged == 0 then
		reward = reward + bonus
	end

	-- Cap at max
	reward = min(reward, max_reward)

	run_state.credits = run_state.credits + reward
	run_state.stats.credits_earned = run_state.stats.credits_earned + reward

	printh("CampaignState: Awarded " .. reward .. " credits (total: " .. run_state.credits .. ")")
	return reward
end

-- Restore ship state to game systems before starting a mission
-- @param player_health_obj: Player health object to restore
-- @param SubsystemManager: SubsystemManager module
function CampaignState.restore_to_mission(player_health_obj, SubsystemManager)
	if not run_state then return end

	-- Restore hull health
	player_health_obj.current_health = run_state.ship.current_health

	-- Restore subsystem states
	local subs = SubsystemManager.get_all_states("player_ship")
	if subs then
		for name, saved_state in pairs(run_state.ship.subsystems) do
			if subs[name] then
				subs[name].health = saved_state.health
				subs[name].destroyed = saved_state.destroyed
			end
		end
	end

	printh("CampaignState: Restored ship state to mission, hull=" .. run_state.ship.current_health)
end

-- Spend credits (returns true if successful)
function CampaignState.spend_credits(amount)
	if not run_state then return false end
	if run_state.credits >= amount then
		run_state.credits = run_state.credits - amount
		return true
	end
	return false
end

-- Use a repair kit (returns true if successful)
function CampaignState.use_repair_kit()
	if not run_state then return false end
	if run_state.repair_kits > 0 then
		run_state.repair_kits = run_state.repair_kits - 1
		return true
	end
	return false
end

-- Add repair kits
function CampaignState.add_repair_kit(count)
	if run_state then
		run_state.repair_kits = run_state.repair_kits + (count or 1)
	end
end

-- Repair hull by amount
function CampaignState.repair_hull(amount)
	if run_state then
		run_state.ship.current_health = min(run_state.ship.max_health, run_state.ship.current_health + amount)
		CampaignState.save_to_disk()
	end
end

-- Use repair kit to heal hull (for campaign map repair)
-- @param heal_amount: How much to heal (default 25)
function CampaignState.use_repair_kit_for_hull(heal_amount)
	if not run_state then return false end
	if run_state.repair_kits <= 0 then return false end
	if run_state.ship.current_health >= run_state.ship.max_health then return false end

	run_state.repair_kits = run_state.repair_kits - 1
	local old_health = run_state.ship.current_health
	run_state.ship.current_health = min(run_state.ship.max_health, run_state.ship.current_health + (heal_amount or 25))
	CampaignState.save_to_disk()

	printh("CampaignState: Used repair kit for hull, healed " .. (run_state.ship.current_health - old_health))
	return true
end

-- Full repair (hull and all subsystems)
function CampaignState.full_repair()
	if not run_state then return end

	run_state.ship.current_health = run_state.ship.max_health

	for name, sub in pairs(run_state.ship.subsystems) do
		sub.health = sub.max_health
		sub.destroyed = false
	end

	printh("CampaignState: Full repair completed")
end

-- Repair a specific subsystem
function CampaignState.repair_subsystem(name)
	if run_state and run_state.ship.subsystems[name] then
		local sub = run_state.ship.subsystems[name]
		sub.health = sub.max_health
		sub.destroyed = false
		return true
	end
	return false
end

-- Advance to next sector
function CampaignState.advance_sector()
	if run_state then
		run_state.current_sector = run_state.current_sector + 1
		run_state.sector_map = nil
		run_state.visited_nodes = {}
		run_state.current_node = nil
		CampaignState.save_to_disk()
		printh("CampaignState: Advanced to sector " .. run_state.current_sector)
	end
end

-- Check if run is over (death or victory)
function CampaignState.is_run_over()
	if not run_state then return true, "no_run" end

	-- Death check
	if run_state.ship.current_health <= 0 then
		return true, "death"
	end

	-- Victory check
	if run_state.current_sector > run_state.total_sectors then
		return true, "victory"
	end

	return false, nil
end

-- End the current run
function CampaignState.end_run()
	local stats = run_state and run_state.stats or nil
	run_state = nil
	CampaignState.clear_save()  -- Remove save file on run end
	printh("CampaignState: Run ended")
	return stats
end

-- Get current credits
function CampaignState.get_credits()
	return run_state and run_state.credits or 0
end

-- Get current repair kits
function CampaignState.get_repair_kits()
	return run_state and run_state.repair_kits or 0
end

-- Get current sector number
function CampaignState.get_current_sector()
	return run_state and run_state.current_sector or 0
end

-- Get total sectors
function CampaignState.get_total_sectors()
	return run_state and run_state.total_sectors or 0
end

return CampaignState

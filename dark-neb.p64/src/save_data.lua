--[[pod_format="raw",created="2025-01-26 00:00:00",modified="2025-01-26 00:00:00",revision=0]]
-- Save Data Module
-- Handles persistent save/load for tutorial progress using Picotron's store/fetch

local SaveData = {}

-- Save file path (relative to game directory)
local SAVE_FILE = "save_data.pod"

-- Default save data structure
local default_data = {
	tutorial = {
		mission_1_complete = false,
	},
}

-- Current save data (loaded on init)
local current_data = nil

-- Initialize save data system
function SaveData.init()
	SaveData.load()
end

-- Load save data from file
function SaveData.load()
	local data = fetch(SAVE_FILE)
	if data then
		current_data = data
		printh("SaveData: Loaded save data")
	else
		-- No save file exists, use defaults
		current_data = {}
		for k, v in pairs(default_data) do
			current_data[k] = v
		end
		printh("SaveData: No save file found, using defaults")
	end
	return current_data
end

-- Save current data to file
function SaveData.save()
	if current_data then
		store(SAVE_FILE, current_data)
		printh("SaveData: Saved data to " .. SAVE_FILE)
	end
end

-- Get tutorial progress
function SaveData.get_tutorial_progress()
	if not current_data then
		SaveData.load()
	end
	return current_data.tutorial or default_data.tutorial
end

-- Set tutorial mission complete
function SaveData.set_tutorial_mission_complete(mission_id)
	if not current_data then
		SaveData.load()
	end

	if not current_data.tutorial then
		current_data.tutorial = {}
	end

	if mission_id == "mission_1" then
		current_data.tutorial.mission_1_complete = true
		printh("SaveData: Mission 1 marked complete")
	end

	SaveData.save()
end

-- Check if a tutorial mission is complete
function SaveData.is_tutorial_mission_complete(mission_id)
	if not current_data then
		SaveData.load()
	end

	if mission_id == "mission_1" then
		return current_data.tutorial and current_data.tutorial.mission_1_complete
	end

	return false
end

-- Reset all save data (for debugging)
function SaveData.reset()
	current_data = {}
	for k, v in pairs(default_data) do
		current_data[k] = v
	end
	SaveData.save()
	printh("SaveData: Reset to defaults")
end

return SaveData

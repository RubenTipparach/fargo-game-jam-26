--[[pod_format="raw",created="2024-11-08 00:00:00",modified="2024-11-08 00:00:00",revision=0]]
-- Slider Component
-- Reusable slider for numeric value input

local Slider = {}
Slider.__index = Slider

-- Create a new slider
-- x, y: top-left position
-- width, height: slider dimensions
-- min_value, max_value: range of values
-- callback: optional function to call on value change
function Slider.new(x, y, width, height, min_value, max_value, callback)
	local self = setmetatable({}, Slider)

	self.x = x
	self.y = y
	self.width = width
	self.height = height
	self.min_value = min_value or 0
	self.max_value = max_value or 1
	self.callback = callback
	self.value = self.min_value
	self.dragging = false
	self.handle_width = 8

	return self
end

-- Update slider state (drag handling)
-- mouse_x, mouse_y: current mouse position
-- mouse_down: whether mouse button is pressed
function Slider:update(mouse_x, mouse_y, mouse_down)
	if mouse_down then
		-- Check if click is on slider area
		if mouse_x >= self.x and mouse_x <= self.x + self.width and
		   mouse_y >= self.y and mouse_y <= self.y + self.height then
			self.dragging = true
		end
	else
		self.dragging = false
	end

	-- Update value if dragging
	if self.dragging then
		-- Calculate normalized position (0 to 1)
		local normalized = (mouse_x - self.x) / self.width
		normalized = mid(0, normalized, 1)  -- Clamp to 0-1

		-- Convert to value range
		self.value = self.min_value + normalized * (self.max_value - self.min_value)

		-- Call callback if provided
		if self.callback then
			self.callback(self.value)
		end
	end
end

-- Set value directly
function Slider:set_value(value)
	self.value = mid(self.min_value, value, self.max_value)
end

-- Get current value
function Slider:get_value()
	return self.value
end

-- Get normalized value (0 to 1)
function Slider:get_normalized()
	if self.max_value <= self.min_value then return 0 end
	return (self.value - self.min_value) / (self.max_value - self.min_value)
end

-- Draw the slider
function Slider:draw()
	-- Draw background track
	rectfill(self.x, self.y + self.height / 2 - 1, self.x + self.width, self.y + self.height / 2 + 1, 1)

	-- Calculate handle position
	local normalized = self:get_normalized()
	local handle_x = self.x + normalized * self.width - self.handle_width / 2

	-- Draw handle
	local handle_color = self.dragging and 11 or 7
	rectfill(handle_x, self.y + self.height / 2 - self.handle_width / 2,
	         handle_x + self.handle_width, self.y + self.height / 2 + self.handle_width / 2, handle_color)
	rect(handle_x, self.y + self.height / 2 - self.handle_width / 2,
	     handle_x + self.handle_width, self.y + self.height / 2 + self.handle_width / 2, 7)
end

return Slider

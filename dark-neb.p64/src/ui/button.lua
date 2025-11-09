--[[pod_format="raw",created="2024-11-08 00:00:00",modified="2024-11-08 00:00:00",revision=0]]
-- Button Component
-- Reusable button with hover and click states

local Button = {}
Button.__index = Button

-- Create a new button
-- x, y: top-left position
-- width, height: button dimensions
-- text: button label
-- callback: function to call on click
function Button.new(x, y, width, height, text, callback)
	local self = setmetatable({}, Button)

	self.x = x
	self.y = y
	self.width = width
	self.height = height
	self.text = text
	self.callback = callback
	self.is_hovered = false
	self.is_pressed = false

	return self
end

-- Update button state (hover and click detection)
-- mouse_x, mouse_y: current mouse position
-- mouse_clicked: whether mouse was clicked this frame
function Button:update(mouse_x, mouse_y, mouse_clicked)
	-- Check if mouse is over button
	self.is_hovered = mouse_x >= self.x and mouse_x <= self.x + self.width and
	                   mouse_y >= self.y and mouse_y <= self.y + self.height

	-- Check for click
	if self.is_hovered and mouse_clicked then
		self.is_pressed = true
		if self.callback then
			self.callback()
		end
	else
		self.is_pressed = false
	end
end

-- Draw the button
-- Normal: dark gray background, white border
-- Hovered: bright background, white border
-- Pressed: highlighted background, white border
function Button:draw()
	local bg_color = 0      -- Dark gray (normal)
	local border_color = 7  -- White border
	local text_color = 7    -- White text

	if self.is_pressed then
		bg_color = 11  -- Bright cyan (pressed)
	elseif self.is_hovered then
		bg_color = 5   -- Medium gray (hovered)
		text_color = 0 -- Dark text on bright background
	end

	-- Draw background
	rectfill(self.x, self.y, self.x + self.width, self.y + self.height, bg_color)

	-- Draw border
	rect(self.x, self.y, self.x + self.width, self.y + self.height, border_color)

	-- Draw text (centered)
	local text_width = #self.text * 4  -- Approximate character width
	local text_x = self.x + (self.width - text_width) / 2
	local text_y = self.y + (self.height - 6) / 2
	print(self.text, text_x, text_y, text_color)
end

return Button

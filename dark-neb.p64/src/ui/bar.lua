--[[pod_format="raw",created="2024-11-08 00:00:00",modified="2024-11-08 00:00:00",revision=0]]
-- Bar Component
-- Reusable health/progress bar with color gradients

local Bar = {}
Bar.__index = Bar

-- Create a new bar
-- x, y: top-left position
-- width, height: bar dimensions
-- label: optional label text
-- show_text: whether to show value text (defaults to true)
function Bar.new(x, y, width, height, label, show_text)
	local self = setmetatable({}, Bar)

	self.x = x
	self.y = y
	self.width = width
	self.height = height
	self.label = label
	self.show_text = show_text ~= false
	self.current_value = 1.0
	self.max_value = 1.0
	self.display_value = nil  -- Optional custom display text

	-- Colors
	self.bg_color = 0      -- Black background
	self.border_color = 7  -- White border
	self.text_color = 7    -- White text

	-- Color mode: "gradient" or "solid"
	-- Gradient: red -> yellow -> green based on percentage
	-- Solid: single color
	self.color_mode = "gradient"
	self.solid_color = 11  -- Used if color_mode == "solid"

	return self
end

-- Set value (0 to max_value)
function Bar:set_value(current, max)
	self.current_value = current or 0
	self.max_value = max or 1
end

-- Set custom display text
function Bar:set_display_text(text)
	self.display_value = text
end

-- Get percentage (0 to 1)
function Bar:get_percentage()
	if self.max_value <= 0 then return 0 end
	return self.current_value / self.max_value
end

-- Set color gradient mode (default)
function Bar:set_gradient_mode()
	self.color_mode = "gradient"
end

-- Set solid color mode
function Bar:set_solid_color(color)
	self.color_mode = "solid"
	self.solid_color = color
end

-- Get fill color based on percentage
function Bar:get_fill_color(percentage)
	if self.color_mode == "solid" then
		return self.solid_color
	end

	-- Gradient mode: red -> yellow -> green
	if percentage > 0.5 then
		return 11  -- Bright green/cyan
	elseif percentage > 0.25 then
		return 10  -- Yellow
	else
		return 8   -- Red
	end
end

-- Draw the bar
function Bar:draw()
	-- Draw background
	rectfill(self.x, self.y, self.x + self.width, self.y + self.height, self.bg_color)

	-- Draw fill
	local percentage = self:get_percentage()
	local fill_width = self.width * percentage
	if fill_width > 0 then
		local fill_color = self:get_fill_color(percentage)
		rectfill(self.x, self.y, self.x + fill_width, self.y + self.height, fill_color)
	end

	-- Draw border
	rect(self.x, self.y, self.x + self.width, self.y + self.height, self.border_color)

	-- Draw value text inside bar if enabled
	if self.show_text then
		local display_text
		if self.display_value then
			display_text = self.display_value
		else
			display_text = flr(self.current_value) .. " / " .. flr(self.max_value)
		end

		-- Calculate text position (centered in bar)
		local text_x = self.x + (self.width - #display_text * 4) / 2
		local text_y = self.y + (self.height - 6) / 2

		-- Draw drop shadow (dark text offset by 1 pixel)
		print(display_text, text_x + 1, text_y + 1, 0)

		-- Draw main text (white)
		print(display_text, text_x, text_y, self.text_color)
	end
end

return Bar

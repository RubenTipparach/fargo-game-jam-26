--[[pod_format="raw",created="2024-11-08 00:00:00",modified="2024-11-08 00:00:00",revision=0]]
-- Progress Bar Component
-- Display-only progress/health bar with gradient colors

local ProgressBar = {}
ProgressBar.__index = ProgressBar

-- Create a new progress bar
-- x, y: top-left position
-- width, height: bar dimensions
-- show_text: whether to show value text (defaults to true)
-- label: optional label text (unused, kept for compatibility with Bar component)
function ProgressBar.new(x, y, width, height, show_text, label)
	local self = setmetatable({}, ProgressBar)

	self.x = x
	self.y = y
	self.width = width
	self.height = height
	self.current_value = 1.0
	self.max_value = 1.0
	self.show_text = show_text ~= false
	self.display_value = nil  -- Optional custom display text
	self.label = label  -- Optional label (kept for compatibility)

	-- Colors
	self.bg_color = 0      -- Black background
	self.border_color = 7  -- White border
	self.text_color = 7    -- White text

	-- Color mode: "gradient" or "solid"
	self.color_mode = "gradient"
	self.solid_color = 11

	return self
end

-- Set value (0 to max_value)
function ProgressBar:set_value(current, max)
	self.current_value = current or 0
	self.max_value = max or 1
end

-- Get percentage (0 to 1)
function ProgressBar:get_percentage()
	if self.max_value <= 0 then return 0 end
	return self.current_value / self.max_value
end

-- Set gradient mode (default)
function ProgressBar:set_gradient_mode()
	self.color_mode = "gradient"
end

-- Set solid color mode
function ProgressBar:set_solid_color(color)
	self.color_mode = "solid"
	self.solid_color = color
end

-- Get fill color based on percentage
function ProgressBar:get_fill_color(percentage)
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

-- Draw the progress bar
function ProgressBar:draw()
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

return ProgressBar

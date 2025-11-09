--[[pod_format="raw",created="2024-11-08 00:00:00",modified="2024-11-08 00:00:00",revision=0]]
-- Panel Component
-- Reusable modal panel with title and content

local Panel = {}
Panel.__index = Panel

-- Create a new panel
-- width, height: panel dimensions
-- title: panel title text
-- center: whether to center on screen (defaults to true)
function Panel.new(width, height, title, center)
	local self = setmetatable({}, Panel)

	self.width = width
	self.height = height
	self.title = title
	self.visible = false

	-- Position (will be centered if center=true)
	if center ~= false then
		self.x = (480 - width) / 2
		self.y = (270 - height) / 2
	else
		self.x = 0
		self.y = 0
	end

	self.bg_color = 0  -- Black background
	self.border_color = 7  -- White border
	self.title_color = 7  -- White title

	return self
end

-- Set position manually
function Panel:set_position(x, y)
	self.x = x
	self.y = y
end

-- Set colors
function Panel:set_colors(bg_color, border_color, title_color)
	self.bg_color = bg_color or 0
	self.border_color = border_color or 7
	self.title_color = title_color or 7
end

-- Draw the panel
function Panel:draw()
	if not self.visible then return end

	-- Draw background
	rectfill(self.x, self.y, self.x + self.width, self.y + self.height, self.bg_color)

	-- Draw border
	rect(self.x, self.y, self.x + self.width, self.y + self.height, self.border_color)

	-- Draw title if present
	if self.title then
		local title_width = #self.title * 4
		local title_x = self.x + (self.width - title_width) / 2
		local title_y = self.y + 8
		print(self.title, title_x, title_y, self.title_color)
	end
end

-- Show/hide panel
function Panel:show()
	self.visible = true
end

function Panel:hide()
	self.visible = false
end

return Panel

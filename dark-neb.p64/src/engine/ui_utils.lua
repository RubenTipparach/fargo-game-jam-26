-- UI Utilities Module
-- Common UI helper functions for drawing text with effects

local UIUtils = {}

-- Print text with drop shadow for better readability
function UIUtils.print_shadow(text, x, y, color)
	print(text, x + 1, y + 1, 0)  -- Shadow (black)
	print(text, x, y, color)       -- Text
end

return UIUtils

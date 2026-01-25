--[[pod_format="raw",created="2024-11-07 20:00:00",modified="2024-11-07 20:00:00",revision=0]]
-- InputSystem Module
-- Handles all mouse and keyboard input processing
-- Single Responsibility: Only manages input state and events

local InputSystem = {}

-- Internal state (private)
local mouse_drag = false
local mouse_down_frames = 0
local last_mouse_x = 0
local last_mouse_y = 0
local last_mouse_button_state = false
local slider_dragging = false

-- Current frame input (updated each frame)
local current_input = {
	mouse_x = 0,
	mouse_y = 0,
	mouse_buttons = 0,
	button_pressed = false,  -- Left button just pressed this frame
	button_held = false,     -- Left button held down
	button_released = false, -- Left button just released
	right_button_held = false,
	drag_active = false,
	drag_dx = 0,
	drag_dy = 0,
}

-- Initialize input system
function InputSystem.init()
	mouse_drag = false
	mouse_down_frames = 0
	last_mouse_x = 0
	last_mouse_y = 0
	last_mouse_button_state = false
	slider_dragging = false
end

-- Update input state (call once per frame at start of _update)
-- @return: Input state table
function InputSystem.update()
	local mx, my, mb = mouse()

	-- Calculate button states
	local left_held = (mb & 1) == 1
	local right_held = (mb & 2) == 2
	local left_pressed = left_held and not last_mouse_button_state
	local left_released = not left_held and last_mouse_button_state

	-- Update drag state
	if left_held then
		mouse_down_frames = mouse_down_frames + 1

		-- Activate drag after threshold frames (prevents accidental drags on clicks)
		if mouse_down_frames >= 5 then
			if not mouse_drag then
				mouse_drag = true
				last_mouse_x = mx
				last_mouse_y = my
			end
		end
	else
		mouse_drag = false
		mouse_down_frames = 0
	end

	-- Calculate drag delta
	local drag_dx = 0
	local drag_dy = 0
	if mouse_drag then
		drag_dx = mx - last_mouse_x
		drag_dy = my - last_mouse_y
		last_mouse_x = mx
		last_mouse_y = my
	end

	-- Update current input state
	current_input.mouse_x = mx
	current_input.mouse_y = my
	current_input.mouse_buttons = mb
	current_input.button_pressed = left_pressed
	current_input.button_held = left_held
	current_input.button_released = left_released
	current_input.right_button_held = right_held
	current_input.drag_active = mouse_drag
	current_input.drag_dx = drag_dx
	current_input.drag_dy = drag_dy

	-- Store for next frame
	last_mouse_button_state = left_held

	return current_input
end

-- Get current input state (for systems that didn't call update)
function InputSystem.get_input()
	return current_input
end

-- Get mouse position
function InputSystem.get_mouse_pos()
	return current_input.mouse_x, current_input.mouse_y
end

-- Check if a point is inside a rectangle
-- @param x, y: Point to check
-- @param rx, ry, rw, rh: Rectangle bounds
function InputSystem.is_point_in_rect(x, y, rx, ry, rw, rh)
	return x >= rx and x <= rx + rw and y >= ry and y <= ry + rh
end

-- Check if mouse is over a rectangle
function InputSystem.is_mouse_over_rect(rx, ry, rw, rh)
	return InputSystem.is_point_in_rect(current_input.mouse_x, current_input.mouse_y, rx, ry, rw, rh)
end

-- Check if mouse clicked inside a rectangle (just pressed this frame)
function InputSystem.is_click_in_rect(rx, ry, rw, rh)
	return current_input.button_pressed and InputSystem.is_mouse_over_rect(rx, ry, rw, rh)
end

-- Slider drag state management
function InputSystem.start_slider_drag()
	slider_dragging = true
end

function InputSystem.stop_slider_drag()
	slider_dragging = false
end

function InputSystem.is_slider_dragging()
	return slider_dragging
end

-- Update slider dragging state based on mouse
function InputSystem.update_slider_drag()
	if not current_input.button_held then
		slider_dragging = false
	end
	return slider_dragging
end

-- Calculate slider value from mouse Y position
-- @param slider_y: Top Y of slider
-- @param slider_height: Height of slider
-- @return: Value 0-1 (inverted: top = 1, bottom = 0)
function InputSystem.get_slider_value(slider_y, slider_height)
	local slider_pos = mid(0, (current_input.mouse_y - slider_y) / slider_height, 1)
	return 1 - slider_pos  -- Inverted (top = max)
end

-- Check for keyboard input (pass-through to Picotron's btn/btnp/key/keyp)
function InputSystem.key_pressed(key)
	return keyp(key)
end

function InputSystem.key_held(key)
	return key(key)
end

function InputSystem.button_pressed(btn_id)
	return btnp(btn_id)
end

function InputSystem.button_held(btn_id)
	return btn(btn_id)
end

-- Check for common game inputs
function InputSystem.get_movement_input()
	return {
		left = btn(0),
		right = btn(1),
		up = btn(2),
		down = btn(3),
	}
end

-- Check for action buttons
function InputSystem.is_action_pressed()
	return btnp(4)  -- Z button
end

function InputSystem.is_cancel_pressed()
	return btnp(5)  -- X button
end

-- Check for menu/confirm input
function InputSystem.is_confirm_pressed()
	return keyp("return") or keyp("z")
end

-- Reset drag state (useful when switching game states)
function InputSystem.reset_drag()
	mouse_drag = false
	mouse_down_frames = 0
	slider_dragging = false
end

return InputSystem

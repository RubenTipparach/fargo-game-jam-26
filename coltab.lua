--[[pod_format="raw",created="2025-04-17 21:34:45",modified="2025-05-13 19:41:16",revision=67]]
cd(env().path)

local args = env().argv
local transform_path = args[1]
local palette_path = args[2]

if (not args[1] or args[1] == "--help") then
	?"usage: coltab transformer palette\n"
	?"transformer: The path to the transformer script."
	?"Should be a .lua file that returns a table"
	?"with func as a function and space as a string\n"
	?"palette (optional): The path to the palette this table is meant for."
	?"Defaults to the Picotron palette."
	exit(0)
end

local transform_path_exists,transformer
if transform_path then
	transform_path_exists = fetch(transform_path)
	if transform_path_exists then
		transformer = include(transform_path)
	end
end
if not (transform_path and transform_path_exists and type(transformer) == "table") then
	print("First argument must be a path to a script that returns a table.")
	exit(0)
end

if type(transformer.func) ~= "function" then
	print("Could not find a function at the \"func\" key in the transformer script.")
	exit(0)
end

if not transformer.space then transformer.space = "linear" end
if type(transformer.space) ~= "string" then
	print("\"space\" must be a string.")
	exit(0)
end

if transformer.space ~= "srgb"
	and transformer.space ~= "linear"
	and transformer.space ~= "oklab"
then
	print("\""..transformer.space.." is not a valid colorspace. Use \"srgb\", \"linear\", or \"oklab\".")
	exit(0)
end

local palette_array = palette_path and fetch(palette_path)
if not palette_array then
	palette_array = userdata("i32",64)
	for i = 0,63 do
		palette_array:set(i,peek4(0x5000+i*4))
	end
end

local function srgb_to_linear(rgb)
	return vec(
		rgb.x < 0.04045 and rgb.x/12.92 or ((rgb.x+0.055)/1.055)^2.4,
		rgb.y < 0.04045 and rgb.y/12.92 or ((rgb.y+0.055)/1.055)^2.4,
		rgb.z < 0.04045 and rgb.z/12.92 or ((rgb.z+0.055)/1.055)^2.4
	)
end

local lms_mat = userdata("f64",3,3)
lms_mat:set(0,0,
	0.4122214708,0.2119034982,0.0883024619,
	0.5363325363,0.6806995451,0.2817188376,
	0.0514459929,0.1073969566,0.6299787005
)

local oklab_mat = userdata("f64",3,3)
oklab_mat:set(0,0,
	 0.2104542553,1.9779984951,0.0259040371,
	 0.7936177850,-2.4285922050,0.7827717662,
	 -0.0040720468,0.4505937099,-0.8086757660
)

local function linear_to_oklab(rgb)
	local lms = rgb:matmul(lms_mat)
	lms.x = lms.x^(1/3)
	lms.y = lms.y^(1/3)
	lms.z = lms.z^(1/3)
	
	return lms:matmul(oklab_mat)
end

local srgb_values = userdata("f64",3,64)
local rgb_values = userdata("f64",3,64)
local lab_values = userdata("f64",3,64)

for i = 0,63 do
	local col = palette_array[i]
	local srgb = vec(((col>>16)&0xFF)/255,((col>>8)&0xFF)/255,(col&0xFF)/255)
	local rgb = srgb_to_linear(srgb)
	local lab = linear_to_oklab(rgb)
	srgb_values:set(0,i,srgb:get())
	rgb_values:set(0,i,rgb:get())
	lab_values:set(0,i,lab:get())
end

local col_values,to_oklab = unpack(({
	srgb = {
		srgb_values,
		function(rgb) return linear_to_oklab(srgb_to_linear(rgb)) end,
	},
	linear = {
		rgb_values,
		linear_to_oklab,
	},
	oklab = {
		lab_values,
		function(rgb) return rgb end,
	},
})[transformer.space])

local color_table = userdata("u8",64,64)
for draw_i = 0,63 do
	for target_i = 0,63 do
		local new_rgb = transformer.func(
			col_values:row(draw_i),col_values:row(target_i),
			draw_i,target_i
		)
		
		if type(new_rgb) == "number" then
			color_table:set(target_i,draw_i,new_rgb)
			goto continue
		end
		
		local new_lab = to_oklab(new_rgb)
		
		local best_dist,best_index = math.huge,0
		for test_i = 0,63 do
			local dist = (lab_values:row(test_i)-new_lab):magnitude()
			
			if dist < best_dist then
				best_dist,best_index = dist,test_i
			end
		end
		color_table:set(target_i,draw_i,best_index)
		::continue::
	end
end

set_clipboard("--[[pod_type=\"gfx\"]]"..pod(color_table,0x7))
print("Color table sprite copied to clipboard.")
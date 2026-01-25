--[[pod_format="raw",created="2024-11-07 20:00:00",modified="2024-11-07 20:00:00",revision=0]]
-- SceneRenderer Module
-- Coordinates 3D scene rendering including background, models, and effects
-- Single Responsibility: Only handles 3D scene rendering

local SceneRenderer = {}

-- Module dependencies (will be injected or required)
local RendererLit = nil
local StarField = nil
local CameraSystem = nil

-- Initialize scene renderer with dependencies
-- @param renderer_lit: RendererLit module
-- @param star_field: StarField module (optional)
-- @param camera_system: CameraSystem module
function SceneRenderer.init(renderer_lit, star_field, camera_system)
	RendererLit = renderer_lit
	StarField = star_field
	CameraSystem = camera_system

	-- Initialize color table for lit rendering
	if RendererLit and RendererLit.init_color_table then
		RendererLit.init_color_table()
	end
end

-- Get light direction from yaw and pitch
-- @param Config: Config with lighting settings
-- @return: {x, y, z} light direction vector
function SceneRenderer.get_light_direction(Config)
	local cy, sy = cos(Config.lighting.yaw), sin(Config.lighting.yaw)
	local cp, sp = cos(Config.lighting.pitch), sin(Config.lighting.pitch)
	return {
		x = cy * cp,
		y = sp,
		z = sy * cp
	}
end

-- Draw sun as a billboard sprite (skybox element)
-- @param camera: Camera object
-- @param light_dir: Light direction vector
-- @param Config: Config with sun settings
-- @param project_fn: Function to project 3D to 2D
function SceneRenderer.draw_sun(camera, light_dir, Config, project_fn)
	local sun_distance = Config.sun.distance
	local sun_x = camera.x - light_dir.x * sun_distance
	local sun_y = camera.y - light_dir.y * sun_distance
	local sun_z = camera.z - light_dir.z * sun_distance

	local screen_x, screen_y, view_z = project_fn(sun_x, sun_y, sun_z, camera)

	if screen_x and screen_y and view_z > 0 then
		palt(0, true)
		local sprite_width_cells = Config.sun.size / 8
		local sprite_height_cells = Config.sun.size / 8
		local half_size = Config.sun.size / 2
		spr(Config.sun.sprite_id, screen_x - half_size, screen_y - half_size, sprite_width_cells, sprite_height_cells)
		palt()
	end
end

-- Draw a 3D line in world space
-- @param x1, y1, z1, x2, y2, z2: Line endpoints
-- @param camera: Camera object
-- @param color: Line color
-- @param project_fn: Function to project 3D to 2D
function SceneRenderer.draw_line_3d(x1, y1, z1, x2, y2, z2, camera, color, project_fn)
	local px1, py1, pz1 = project_fn(x1, y1, z1, camera)
	local px2, py2, pz2 = project_fn(x2, y2, z2, camera)

	if px1 and px2 and pz1 > 0 and pz2 > 0 then
		line(px1, py1, px2, py2, color)
	end
end

-- Render particle trails (speedlines)
-- @param particle_trails: Array of line segments
-- @param ship_pos: Ship position for distance-based coloring
-- @param camera: Camera object
-- @param Config: Config with particle settings
-- @param project_fn: Function to project 3D to 2D
function SceneRenderer.render_particle_trails(particle_trails, ship_pos, camera, Config, project_fn)
	-- Reset drawing state
	fillp()
	palt()

	for _, line_segment in ipairs(particle_trails) do
		-- Calculate distance from ship
		local dx = line_segment.x1 - ship_pos.x
		local dy = line_segment.y1 - ship_pos.y
		local dz = line_segment.z1 - ship_pos.z
		local dist = sqrt(dx * dx + dy * dy + dz * dz)

		-- Color based on distance
		local palette = Config.particles.color_palette
		local palette_size = #palette
		local max_dist = Config.particles.max_dist

		local dist_factor = min(1, max(0, dist / max_dist))
		local palette_index = flr(dist_factor * palette_size) + 1
		palette_index = min(palette_size, palette_index)

		local color = palette[palette_index]

		SceneRenderer.draw_line_3d(
			line_segment.x1, line_segment.y1, line_segment.z1,
			line_segment.x2, line_segment.y2, line_segment.z2,
			camera, color, project_fn
		)
	end
end

-- Render crosshair at raycast position
-- @param raycast_x, raycast_z: World coordinates of raycast hit
-- @param ship_pos: Ship position
-- @param camera: Camera object
-- @param Config: Config with crosshair settings
-- @param project_fn: Function to project 3D to 2D
function SceneRenderer.render_crosshair(raycast_x, raycast_z, ship_pos, camera, Config, project_fn)
	if not raycast_x or not raycast_z then return end

	-- Only show if within max distance
	local dx = raycast_x - ship_pos.x
	local dz = raycast_z - ship_pos.z
	local dist = sqrt(dx * dx + dz * dz)

	if dist < Config.crosshair.max_distance then
		local cross_size = 0.5
		SceneRenderer.draw_line_3d(
			raycast_x - cross_size, 0, raycast_z,
			raycast_x + cross_size, 0, raycast_z,
			camera, 8, project_fn
		)
		SceneRenderer.draw_line_3d(
			raycast_x, 0, raycast_z - cross_size,
			raycast_x, 0, raycast_z + cross_size,
			camera, 8, project_fn
		)
	end
end

-- Main render function - renders entire 3D scene
-- @param camera: Camera object
-- @param state: Game state object
-- @param Config: Game configuration
-- @param modules: Table of required modules {RendererLit, StarField, WeaponEffects, ExplosionRenderer, etc.}
-- @param models: Table of loaded models {shippy, planet, satellite, sphere}
-- @return: all_faces array for external use
function SceneRenderer.render_scene(camera, state, Config, modules, models)
	local all_faces = {}
	local light_dir = SceneRenderer.get_light_direction(Config)

	-- Get lighting settings from state or config
	local light_brightness = state.light_brightness or Config.lighting.brightness
	local ambient = state.ambient or Config.lighting.ambient

	-- Render background (stars)
	if modules.StarField then
		modules.StarField.draw(camera)
	end

	-- Render sun
	SceneRenderer.draw_sun(camera, light_dir, Config, modules.project_fn)

	-- Render planet (if visible in current mission)
	if models.planet and state.show_planet ~= false then
		local planet_pos = Config.planet.position
		local planet_rot = Config.planet.rotation
		local planet_rotation = state.planet_rotation or 0

		local planet_faces = modules.RendererLit.render_mesh(
			models.planet.verts, models.planet.faces, camera,
			planet_pos.x, planet_pos.y, planet_pos.z,
			nil, light_dir, nil,
			light_brightness, ambient,
			false,
			planet_rot.pitch, planet_rotation, planet_rot.roll,
			Config.camera.render_distance
		)

		for i = 1, #planet_faces do
			add(all_faces, planet_faces[i])
		end
	end

	-- Render player ship (if alive or recently dead)
	if models.shippy and state.ship_pos then
		local should_render = not state.is_dead or
			(state.death_time and state.death_time < Config.health.ship_disappear_time)

		if should_render then
			local ship_rot = Config.ship.rotation
			local ship_yaw = (state.ship_heading_angle or 0) + 0.25

			local ship_faces = modules.RendererLit.render_mesh(
				models.shippy.verts, models.shippy.faces, camera,
				state.ship_pos.x, state.ship_pos.y, state.ship_pos.z,
				Config.ship.sprite_id, light_dir, nil,
				light_brightness, ambient,
				false,
				ship_rot.pitch, ship_yaw, ship_rot.roll,
				Config.camera.render_distance
			)

			for i = 1, #ship_faces do
				add(all_faces, ship_faces[i])
			end
		end
	end

	-- Render enemy ships (satellites and grabons)
	for _, enemy in ipairs(state.enemy_ships or {}) do
		if enemy.model and enemy.position and not enemy.is_destroyed then
			local enemy_yaw = (enemy.heading or 0) + 0.25

			local enemy_faces = modules.RendererLit.render_mesh(
				enemy.model.verts, enemy.model.faces, camera,
				enemy.position.x, enemy.position.y, enemy.position.z,
				enemy.config.sprite_id, light_dir, nil,
				light_brightness, ambient,
				false,
				0, enemy_yaw, 0,
				Config.camera.render_distance
			)

			for i = 1, #enemy_faces do
				add(all_faces, enemy_faces[i])
			end
		end
	end

	return all_faces
end

-- Sort and draw all collected faces
-- @param all_faces: Array of faces to draw
-- @param RendererLit: Renderer module with sort_faces and draw_faces
function SceneRenderer.draw_all_faces(all_faces, renderer_lit)
	renderer_lit.sort_faces(all_faces)
	renderer_lit.draw_faces(all_faces)
end

-- Render spawned objects (explosion quads and billboards)
-- @param spawned_spheres: Array of spawned quad objects
-- @param camera: Camera object
-- @param all_faces: Faces array to add to
-- @param Config: Game configuration
-- @param model_sphere: Default sphere model (fallback)
-- @param create_billboard_fn: Function to create billboard vertices
-- @param renderer_lit: RendererLit module
-- @param light_dir: Light direction vector
-- @param light_brightness: Light brightness value
-- @param ambient: Ambient light value
function SceneRenderer.render_spawned_objects(spawned_spheres, camera, all_faces, Config, model_sphere, create_billboard_fn, renderer_lit, light_dir, light_brightness, ambient)
	for _, obj in ipairs(spawned_spheres) do
		local mesh = obj.mesh or model_sphere
		if mesh then
			-- If this is a billboard mesh, regenerate vertices to face camera
			local verts_to_render = mesh.verts
			if mesh.is_billboard then
				local scale_factor = obj.scale or 1.0
				verts_to_render = create_billboard_fn(obj.mesh_half_size * scale_factor, camera)
			end

			-- Render the mesh
			local obj_faces = renderer_lit.render_mesh(
				verts_to_render, mesh.faces, camera,
				obj.x, obj.y, obj.z,
				nil, light_dir, nil,
				light_brightness, ambient,
				false, 0, 0, 0,
				Config.camera.render_distance,
				nil, nil, nil, nil,
				mesh.unlit
			)

			-- Process and add faces
			for i = 1, #obj_faces do
				local face = obj_faces[i]
				if mesh.unlit then face.unlit = true end
				if obj.explosion_opacity and obj.explosion_opacity < 1.0 then
					face.explosion_opacity = obj.explosion_opacity
				end
				if obj.dither_enabled and obj.lifetime then
					local remaining_ratio = mid(0, 1.0 - (obj.age / obj.lifetime), 1)
					face.dither_opacity = remaining_ratio
				end
				table.insert(all_faces, face)
			end
		end
	end
end

return SceneRenderer

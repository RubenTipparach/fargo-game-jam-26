--[[pod_format="raw",created="2024-11-08 00:00:00",modified="2024-11-08 00:00:00",revision=0]]
-- Explosion Renderer
-- Renders explosion particles with proper projection and depth sorting

local ExplosionRenderer = {}

-- Constants for projection
local PROJ_SCALE = 270 / 0.7002075  -- tan_half_fov = tan(70/2 degrees)
local NEAR_PLANE = 0.1

-- Project a world-space vertex to screen space
local function project_vertex(world_pos, camera)
	-- Calculate Z distance from camera
	local z = world_pos.z - camera.z

	-- Check near plane
	if z <= NEAR_PLANE then
		return nil
	end

	local inv_z = 1 / z

	-- Project to screen
	return {
		x = -world_pos.x * inv_z * PROJ_SCALE + 240,
		y = -world_pos.y * inv_z * PROJ_SCALE + 135,
		z = 0,
		w = inv_z,
		depth = z
	}
end

-- Render explosions and add to face list with proper depth sorting
function ExplosionRenderer.render_explosions(active_explosions, camera, all_faces)
	for _, explosion in ipairs(active_explosions) do
		local mesh = explosion:get_mesh_face(camera)
		if mesh then
			for i = 1, #mesh.faces do
				local face = mesh.faces[i]
				local v1_idx, v2_idx, v3_idx = face[1], face[2], face[3]
				local v1 = mesh.verts[v1_idx]
				local v2 = mesh.verts[v2_idx]
				local v3 = mesh.verts[v3_idx]

				-- Convert to world coordinates
				local w1 = {x = v1.x + mesh.x, y = v1.y + mesh.y, z = v1.z + mesh.z}
				local w2 = {x = v2.x + mesh.x, y = v2.y + mesh.y, z = v2.z + mesh.z}
				local w3 = {x = v3.x + mesh.x, y = v3.y + mesh.y, z = v3.z + mesh.z}

				-- Project all vertices
				local p1 = project_vertex(w1, camera)
				local p2 = project_vertex(w2, camera)
				local p3 = project_vertex(w3, camera)

				-- Only add face if all vertices are in front of camera
				if p1 and p2 and p3 then
					-- Calculate average depth with bias to wrap around nearby geometry
					local avg_depth = (p1.depth + p2.depth + p3.depth) * 0.333333 + 10

					-- Add to face list for depth sorting - mark as unlit
					table.insert(all_faces, {
						face = {v1_idx, v2_idx, v3_idx, face[4], face[5], face[6], face[7]},
						depth = avg_depth,
						p1 = p1,
						p2 = p2,
						p3 = p3,
						fog = 0,
						unlit = true,  -- Mark as unlit to skip lighting calculations
						opacity = mesh.opacity
					})
				end
			end
		end
	end
end

return ExplosionRenderer

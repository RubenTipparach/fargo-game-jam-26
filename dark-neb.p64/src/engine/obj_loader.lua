-- OBJ File Loader for Picotron
-- Loads .obj files directly into the mesh format used by the 3D engine

local function load_obj(filepath)
	local verts = {}
	local uvs = {}
	local faces = {}

	-- Read file line by line
	local file_content = fetch(filepath)
	if not file_content then
		printh("ERROR: Could not load OBJ file: " .. filepath)
		return nil
	end

	-- Parse each line
	local lines = split(file_content, "\n", false)

	for line in all(lines) do
		-- Trim whitespace
		line = line:gsub("^%s+", ""):gsub("%s+$", "")

		-- Skip empty lines and comments
		if #line > 0 and sub(line, 1, 1) ~= "#" then
			-- Vertex line (v x y z)
			if sub(line, 1, 2) == "v " then
				local coords = split(sub(line, 3), " ", false)
				local x = tonum(coords[1]) or 0
				local y = tonum(coords[2]) or 0
				local z = tonum(coords[3]) or 0
				add(verts, vec(x, y, z))

			-- Texture coordinate line (vt u v)
			elseif sub(line, 1, 3) == "vt " then
				local coords = split(sub(line, 4), " ", false)
				local u = tonum(coords[1]) or 0
				local v = tonum(coords[2]) or 0
				-- Convert UV from 0-1 range to 0-16 range (Picotron sprite coordinates)
				-- Flip V coordinate to match texture orientation
				add(uvs, vec(u * 16, (1 - v) * 16))

			-- Face line (f v1 v2 v3 or f v1/vt1/vn1 v2/vt2/vn2 v3/vt3/vn3)
			elseif sub(line, 1, 2) == "f " then
				local face_data = split(sub(line, 3), " ", false)

				-- Parse vertex and UV indices (handle v, v/vt, v/vt/vn formats)
				local v_indices = {}
				local vt_indices = {}
				for part in all(face_data) do
					if #part > 0 then
						-- Split by slash to get vertex and UV index
						local indices = split(part, "/", false)
						local v_idx = tonum(indices[1])
						local vt_idx = tonum(indices[2])
						if v_idx then
							add(v_indices, v_idx)
							add(vt_indices, vt_idx)
						end
					end
				end

				-- Triangulate faces (fan triangulation like Python version)
				-- For triangle: use inverted winding order (v0, v2, v1)
				-- For quad+: fan from v0 -> (v0, v[i+2], v[i+1])
				for i = 0, #v_indices - 3 do
					local idx1, idx2, idx3
					local uv1, uv2, uv3

					if i == 0 then
						-- First triangle: inverted winding
						idx1 = v_indices[1]
						idx2 = v_indices[3]
						idx3 = v_indices[2]

						uv1 = (vt_indices[1] and uvs[vt_indices[1]]) or vec(0, 0)
						uv2 = (vt_indices[3] and uvs[vt_indices[3]]) or vec(16, 16)
						uv3 = (vt_indices[2] and uvs[vt_indices[2]]) or vec(16, 0)
					else
						-- Fan triangulation: v0, v[i+2], v[i+1]
						idx1 = v_indices[1]
						idx2 = v_indices[i + 3]
						idx3 = v_indices[i + 2]

						uv1 = (vt_indices[1] and uvs[vt_indices[1]]) or vec(0, 0)
						uv2 = (vt_indices[i + 3] and uvs[vt_indices[i + 3]]) or vec(16, 16)
						uv3 = (vt_indices[i + 2] and uvs[vt_indices[i + 2]]) or vec(0, 16)
					end

					add(faces, {
						idx1, idx2, idx3,
						1,  -- sprite ID (using sprite 1 as default)
						uv1, uv2, uv3
					})
				end
			end
		end
	end

	printh("Loaded OBJ: " .. #verts .. " verts, " .. #uvs .. " uvs, " .. #faces .. " faces")

	return {
		verts = verts,
		faces = faces,
		name = filepath
	}
end

return load_obj

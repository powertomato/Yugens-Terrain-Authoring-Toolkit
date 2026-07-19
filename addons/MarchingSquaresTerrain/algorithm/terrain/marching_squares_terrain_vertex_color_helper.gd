extends RefCounted
class_name MarchingSquaresTerrainVertexColorHelper


# < 1.0 = more aggressive wall detection
# > 1.0 = less aggressive / more slope blend
const BLEND_EDGE_SENSITIVITY : float = 1.25
# Cell height range for boundary detection (height-based color sampling)
var cell_min_height : float
var cell_max_height : float
# Height-based material colors for FLOOR boundary cells (prevents color bleeding between heights)
var cell_floor_lower_color_0 : Color
var cell_floor_upper_color_0 : Color
var cell_floor_lower_color_1 : Color
var cell_floor_upper_color_1 : Color
# Height-based material colors for WALL/RIDGE boundary cells
var cell_wall_lower_color_0 : Color
var cell_wall_upper_color_0 : Color
var cell_wall_lower_color_1 : Color
var cell_wall_upper_color_1 : Color
var cell_is_boundary : bool = false
# Per-cell materials for to supports up to 3 textures
var cell_mat_a : int = 0
var cell_mat_b : int = 0
var cell_mat_c : int = 0
var cell_weight_b : float = 0.0

# Track which map (floor vs wall) cell_mat_a/b/c was derived from.
# Walls must derive their dominant mats from wall_color_map, not the ground color_map.
var _mat_pair_is_floor: bool = true

# Per-cell data cached once in calculate_corner_colors so the per-vertex path
# never has to re-read the full color maps.
var _floor_tex : PackedInt32Array # Texture index per corner A,B,C,D (floor maps)
var _wall_tex : PackedInt32Array # Texture index per corner A,B,C,D (wall maps)
var _floor_mats : PackedInt32Array # Dominant floor materials [mat_a, mat_b, mat_c]
var _wall_mats : PackedInt32Array # Dominant wall materials [mat_a, mat_b, mat_c]
var _grass_mask : Color # grass_mask_map value of this cell (CUSTOM1 base value)
var _rl_index : int = 0 # Cell-dominant wall texture index (ridge/ledge tint)

# Fast path for cells whose four corners share the same texture on a map (the
# common case): the material blend data is then a per-cell constant, computed
# once in calculate_corner_colors.
var _floor_uniform : bool = false
var _wall_uniform : bool = false
var _const_mat_blend_floor : Color
var _const_mat_blend_wall : Color

# Per-vertex outputs of blend_colors (fields instead of a per-vertex Dictionary)
var out_color_0 : Color
var out_color_1 : Color
var out_custom_1 : Color
var out_mat_blend : Color

# NOTE: Untyped to avoid @tool cyclic load issues (chunk <-> helper <-> cell).
var chunk
var cell


## Computes the vertex colors/blend data for one vertex and stores the results
## in out_color_0, out_color_1, out_custom_1 and out_mat_blend.
## calculate_corner_colors() must have been called for the cell beforehand.
func blend_colors(vertex: Vector3, uv: Vector2, diag_midpoint: bool =  false, local_vert: Variant = null) -> void:
	var is_floor : bool = cell.floor_mode

	# Detect ridge/ledge (floor vertices only)
	var is_ridge := is_floor and (uv.y > 0.0)
	var is_ledge := is_floor and (uv.x > 0.0)

	# Ensure dominant material selection matches the map we are currently sampling.
	# Without this, wall vertices can incorrectly use floor material pairs (regression).
	# Both triples were computed once per cell in calculate_corner_colors().
	var mats := _floor_mats if is_floor else _wall_mats
	cell_mat_a = mats[0]
	cell_mat_b = mats[1]
	cell_mat_c = mats[2]
	_mat_pair_is_floor = is_floor

	# Terrain texturing is driven by CUSTOM2 (and weight_b in CUSTOM0.r).
	# COLOR/CUSTOM0 are no longer used to encode the material index directly.
	out_color_0 = Color(0, 0, 0, 0)

	# CUSTOM1: grass mask + ridge/ledge flags + the cell-dominant wall texture index.
	# A stable per-cell wall index keeps the ledge overlay from flipping inside one painted cell.
	var c_1_val : Color = _grass_mask
	c_1_val.g = 1.0 if is_ridge else 0.0
	c_1_val.b = 1.0 if is_ledge else 0.0
	c_1_val.a = _rl_index
	out_custom_1 = c_1_val

	if (_floor_uniform if is_floor else _wall_uniform):
		# Fast path: identical corner textures - the blend data is a per-cell constant
		out_mat_blend = _const_mat_blend_floor if is_floor else _const_mat_blend_wall
		cell_weight_b = 0.0
	else:
		out_mat_blend = calculate_material_blend_data(vertex.x, vertex.z, _floor_tex if is_floor else _wall_tex)
	out_color_1 = Color(cell_weight_b, 0, 0, 0) # CUSTOM0.r = weight_b


func calculate_corner_colors():
	# Calculate cell height range for boundary detection (height-based color sampling)
	cell_min_height = min(cell.ay, cell.by, cell.cy, cell.dy)
	cell_max_height = max(cell.ay, cell.by, cell.cy, cell.dy)

	var x = cell.cell_coords.x
	var z = cell.cell_coords.y

	# Determine if this is a boundary cell (significant height variation)
	cell_is_boundary = (cell_max_height - cell_min_height) > cell.merge_threshold

	# Cache the per-corner texture indices (A, B, C, D) of both map pairs once per cell
	var dim_x : int = chunk.dimensions.x
	var idx : int = z * dim_x + x
	_floor_tex = _corner_texture_indices(chunk.color_map_0, chunk.color_map_1, idx, dim_x)
	_wall_tex = _corner_texture_indices(chunk.wall_color_map_0, chunk.wall_color_map_1, idx, dim_x)

	# Dominant materials of both maps. Default to FLOOR material selection at cell start,
	# wall vertices switch this in blend_colors().
	_floor_mats = _calculate_material_triple(_floor_tex)
	_wall_mats = _calculate_material_triple(_wall_tex)
	cell_mat_a = _floor_mats[0]
	cell_mat_b = _floor_mats[1]
	cell_mat_c = _floor_mats[2]
	_mat_pair_is_floor = true

	# Grass mask of this cell (CUSTOM1 base value)
	_grass_mask = _safe_color(chunk.grass_mask_map, idx)

	# Cell-dominant wall texture index for the ridge/ledge tint: the most common
	# corner texture, ties keep the A, B, C, D corner order
	_rl_index = _wall_mats[0]

	# Fast path detection: identical corner textures mean the bilinear blend weights
	# collapse to a per-cell constant (weight_a = 1, weight_b = 0) - build it once.
	# This equals what calculate_material_blend_data returns for any vertex of such a cell.
	_floor_uniform = _floor_tex[1] == _floor_tex[0] and _floor_tex[2] == _floor_tex[0] and _floor_tex[3] == _floor_tex[0]
	_wall_uniform = _wall_tex[1] == _wall_tex[0] and _wall_tex[2] == _wall_tex[0] and _wall_tex[3] == _wall_tex[0]
	if _floor_uniform:
		var m := float(_floor_tex[0])
		_const_mat_blend_floor = Color(m, m, m, 1.0)
	if _wall_uniform:
		var m := float(_wall_tex[0])
		_const_mat_blend_wall = Color(m, m, m, 1.0)

	if cell_is_boundary:
		# Identify corners at each height level for height-based color sampling
		# FLOOR colors - from color_map (used for regular floor vertices)
		var floor_corner_color_0s = [
			chunk.color_map_0[z * chunk.dimensions.x + x],           # A (top-left)
			chunk.color_map_0[z * chunk.dimensions.x + x + 1],       # B (top-right)
			chunk.color_map_0[(z + 1) * chunk.dimensions.x + x],     # C (bottom-left)
			chunk.color_map_0[(z + 1) * chunk.dimensions.x + x + 1]  # D (bottom-right)
		]
		var floor_corner_color_1s = [
			chunk.color_map_1[z * chunk.dimensions.x + x],
			chunk.color_map_1[z * chunk.dimensions.x + x + 1],
			chunk.color_map_1[(z + 1) * chunk.dimensions.x + x],
			chunk.color_map_1[(z + 1) * chunk.dimensions.x + x + 1]
		]
		# WALL colors - from wall_color_map (used for wall/ridge vertices)
		var wall_corner_color_0s = [
			chunk.wall_color_map_0[z * chunk.dimensions.x + x],           # A (top-left)
			chunk.wall_color_map_0[z * chunk.dimensions.x + x + 1],       # B (top-right)
			chunk.wall_color_map_0[(z + 1) * chunk.dimensions.x + x],     # C (bottom-left)
			chunk.wall_color_map_0[(z + 1) * chunk.dimensions.x + x + 1]  # D (bottom-right)
		]
		var wall_corner_color_1s = [
			chunk.wall_color_map_1[z * chunk.dimensions.x + x],
			chunk.wall_color_map_1[z * chunk.dimensions.x + x + 1],
			chunk.wall_color_map_1[(z + 1) * chunk.dimensions.x + x],
			chunk.wall_color_map_1[(z + 1) * chunk.dimensions.x + x + 1]
		]
		var corner_heights = [cell.ay, cell.by, cell.cy, cell.dy]

		# Find corners at min and max height
		var min_idx := 0
		var max_idx := 0
		for i in range(4):
			if corner_heights[i] < corner_heights[min_idx]:
				min_idx = i
			if corner_heights[i] > corner_heights[max_idx]:
				max_idx = i

		# Floor boundary colors (from ground color_map)
		cell_floor_lower_color_0 = floor_corner_color_0s[min_idx]
		cell_floor_upper_color_0 = floor_corner_color_0s[max_idx]
		cell_floor_lower_color_1 = floor_corner_color_1s[min_idx]
		cell_floor_upper_color_1 = floor_corner_color_1s[max_idx]
		# Wall boundary colors (from wall_color_map)
		cell_wall_lower_color_0 = wall_corner_color_0s[min_idx]
		cell_wall_upper_color_0 = wall_corner_color_0s[max_idx]
		cell_wall_lower_color_1 = wall_corner_color_1s[min_idx]
		cell_wall_upper_color_1 = wall_corner_color_1s[max_idx]

#region cell_geometry helpers & calculation functions and color interpolation helpers

## Returns 4 source_maps based on floor/wall[0][1] state, and for setting ridge/ledge[2][3] textures.
func _get_color_sources(is_floor: bool) -> Array:
	var use_wall_colors = not is_floor
	
	var src_0 : PackedColorArray = chunk.wall_color_map_0 if use_wall_colors else chunk.color_map_0
	var src_1 : PackedColorArray = chunk.wall_color_map_1 if use_wall_colors else chunk.color_map_1
	var rl_src_0 : PackedColorArray = chunk.wall_color_map_0
	var rl_src_1 : PackedColorArray = chunk.wall_color_map_1
	
	return [src_0, src_1, rl_src_0, rl_src_1]


## Calculates color for diagonal midpoint vertices.
func _calc_diagonal_color(source_map: PackedColorArray) -> Color:
	if chunk.terrain_system.blend_mode == 1:
		# Hard edge mode uses same color as cell's top-left corner
		return source_map[cell.cell_coords.y * chunk.dimensions.x + cell.cell_coords.x]
	
	# Smooth blend mode - lerp diagonal corners for smoother effect
	var idx = cell.cell_coords.y * chunk.dimensions.x + cell.cell_coords.x
	var ad_color : Color = lerp(source_map[idx], source_map[idx + chunk.dimensions.x + 1], 0.5)
	var bc_color : Color = lerp(source_map[idx + 1], source_map[idx + chunk.dimensions.x], 0.5)
	var result = Color(min(ad_color.r, bc_color.r), min(ad_color.g, bc_color.g), min(ad_color.b, bc_color.b), min(ad_color.a, bc_color.a))
	
	if ad_color.r > 0.99 or bc_color.r > 0.99: result.r = 1.0
	if ad_color.g > 0.99 or bc_color.g > 0.99: result.g = 1.0
	if ad_color.b > 0.99 or bc_color.b > 0.99: result.b = 1.0
	if ad_color.a > 0.99 or bc_color.a > 0.99: result.a = 1.0
	
	return result


## Calculates height-based color for boundary cells (prevents color bleeding between heights).
func _calc_boundary_color(y: float, source_map: PackedColorArray, lower_color: Color, upper_color: Color) -> Color:
	if chunk.terrain_system.blend_mode == 1:
		# Hard edge mode uses cell's corner color
		return source_map[cell.cell_coords.y * chunk.dimensions.x + cell.cell_coords.x]
	
	# HEIGHT-BASED SAMPLING for smooth blend mode
	var height_range = cell_max_height - cell_min_height
	var height_factor : float = clamp((y - cell_min_height) / height_range, 0.0, 1.0)
	
	# Sharp bands: < lower_thresh = lower color, > upper_thresh = upper color, middle = blend
	var color : Color
	if height_factor < chunk.lower_thresh:
		color = lower_color
	elif height_factor > chunk.upper_thresh:
		color = upper_color
	else:
		var blend_factor : float = (height_factor - chunk.lower_thresh) / chunk.blend_zone
		color = lerp(lower_color, upper_color, blend_factor)
	
	return get_dominant_color(color)


## Calculates bilinearly interpolated color for flat cells.
func _calc_bilinear_color(x: float, z: float, source_map: PackedColorArray) -> Color:
	var idx = cell.cell_coords.y * chunk.dimensions.x + cell.cell_coords.x
	var ab_color : Color = lerp(source_map[idx], source_map[idx + 1], x)
	var cd_color : Color = lerp(source_map[idx + chunk.dimensions.x], source_map[idx + chunk.dimensions.x + 1], x)
	
	if chunk.terrain_system.blend_mode !=  1:
		return get_dominant_color(lerp(ab_color, cd_color, z))  # Mixed triangles
	return source_map[idx]  # hard squares/hard triangles


## Selects the appropriate color interpolation method.
func _interpolate_vertex_color(
	x: float, y: float, z: float,
	source_map: PackedColorArray,
	diag_midpoint: bool,
	lower_color: Color,
	upper_color: Color
	) -> Color:
	if diag_midpoint:
		return _calc_diagonal_color(source_map)
	
	if cell_is_boundary:
		return _calc_boundary_color(y, source_map, lower_color, upper_color)
	
	return _calc_bilinear_color(x, z, source_map)


static func get_dominant_color(c: Color) -> Color:
	var max_val = c.r
	var idx : int = 0
	
	if c.g > max_val:
		max_val = c.g
		idx = 1
	if c.b > max_val:
		max_val = c.b
		idx = 2
	if c.a > max_val:
		idx = 3
	
	var new_color := Color(0, 0, 0, 0)
	match idx:
		0: new_color.r = 1.0
		1: new_color.g = 1.0
		2: new_color.b = 1.0
		3: new_color.a = 1.0
	
	return new_color


# Convert color pair to texture index (0-255).
# Supports both legacy 4×4 channel encoding (0-15) and the new byte encoding.
static func get_texture_index_from_colors(c0: Color, c1: Color) -> int:
	var c0_sum := c0.r + c0.g + c0.b + c0.a
	var c1_sum := c1.r + c1.g + c1.b + c1.a
	var c0_max := max(max(c0.r, c0.g), max(c0.b, c0.a))
	var c1_max := max(max(c1.r, c1.g), max(c1.b, c1.a))
	var looks_legacy = (abs(c0_sum - 1.0) < 0.01 and abs(c1_sum - 1.0) < 0.01 and c0_max > 0.99 and c1_max > 0.99)
	if looks_legacy:
		var c0_idx := 0
		var c0_m := c0.r
		if c0.g > c0_m: c0_m = c0.g; c0_idx = 1
		if c0.b > c0_m: c0_m = c0.b; c0_idx = 2
		if c0.a > c0_m: c0_idx = 3
		
		var c1_idx := 0
		var c1_m := c1.r
		if c1.g > c1_m: c1_m = c1.g; c1_idx = 1
		if c1.b > c1_m: c1_m = c1.b; c1_idx = 2
		if c1.a > c1_m: c1_idx = 3
		
		return c0_idx * 4 + c1_idx
	
	return clampi(int(round(clampf(c0.r, 0.0, 1.0) * 255.0)), 0, 255)


# Convert texture index (0-255) to color pair.
static func texture_index_to_colors(idx: int) -> Array:
	idx = clampi(idx, 0, 255)
	return [Color(float(idx) / 255.0, 0, 0, 0), Color(0, 0, 0, 0)]


# Texture index of each corner (A, B, C, D) of the cell at idx for the given color map pair.
func _corner_texture_indices(map_0: PackedColorArray, map_1: PackedColorArray, idx: int, dim_x: int) -> PackedInt32Array:
	var tex := PackedInt32Array()
	tex.resize(4)
	tex[0] = get_texture_index_from_colors(_safe_color(map_0, idx), _safe_color(map_1, idx))
	tex[1] = get_texture_index_from_colors(_safe_color(map_0, idx + 1), _safe_color(map_1, idx + 1))
	tex[2] = get_texture_index_from_colors(_safe_color(map_0, idx + dim_x), _safe_color(map_1, idx + dim_x))
	tex[3] = get_texture_index_from_colors(_safe_color(map_0, idx + dim_x + 1), _safe_color(map_1, idx + dim_x + 1))
	return tex


# Calculate the 3 dominant textures for the given corner texture indices (A, B, C, D).
# Returns [mat_a, mat_b, mat_c], most common first; ties keep the first-seen corner order.
func _calculate_material_triple(corner_tex: PackedInt32Array) -> PackedInt32Array:
	# Count unique texture indices in first-seen order (max 4 corners)
	var uniq := PackedInt32Array()
	var counts := PackedInt32Array()
	for tex in corner_tex:
		var found := -1
		for i in range(uniq.size()):
			if uniq[i] == tex:
				found = i
				break
		if found >= 0:
			counts[found] += 1
		else:
			uniq.append(tex)
			counts.append(1)

	var a_i := _first_max_index(counts, -1, -1)
	var b_i := _first_max_index(counts, a_i, -1)
	var c_i := _first_max_index(counts, a_i, b_i)
	var mat_a : int = uniq[a_i]
	var mat_b : int = uniq[b_i] if b_i >= 0 else mat_a
	var mat_c : int = uniq[c_i] if c_i >= 0 else mat_b
	return PackedInt32Array([mat_a, mat_b, mat_c])


## Index of the highest count, skipping two indices; earliest index wins ties.
func _first_max_index(counts: PackedInt32Array, skip_a: int, skip_b: int) -> int:
	var best := -1
	var best_count := -1
	for i in range(counts.size()):
		if i == skip_a or i == skip_b:
			continue
		if counts[i] > best_count:
			best_count = counts[i]
			best = i
	return best


func _safe_color(src, idx):
	if src is PackedColorArray and idx >= 0 and idx < src.size():
		return src[idx]
	return Color(0,0,0,0)


# Calculate blend data for up to 3 textures.
# New encoding for 256 slots:
#   CUSTOM2.rgb = mat_a, mat_b, mat_c (0..255) as floats
#   CUSTOM2.a   = weight_a (0..1)
#   CUSTOM0.r   = weight_b (0..1)
# corner_tex holds the texture index of each corner (A, B, C, D) of the map being
# sampled; the materials are cell_mat_a/b/c (selected per vertex in blend_colors).
func calculate_material_blend_data(vert_x: float, vert_z: float, corner_tex: PackedInt32Array) -> Color:
	var tex_a : int = corner_tex[0]
	var tex_b : int = corner_tex[1]
	var tex_c : int = corner_tex[2]
	var tex_d : int = corner_tex[3]

	# Position weights for bilinear interpolation
	var w_a : float = (1.0 - vert_x) * (1.0 - vert_z)
	var w_b : float = vert_x * (1.0 - vert_z)
	var w_c : float = (1.0 - vert_x) * vert_z
	var w_d : float = vert_x * vert_z

	# Accumulate weights for all 3 cell materials
	var weight_mat_a : float = 0.0
	var weight_mat_b : float = 0.0
	var weight_mat_c : float = 0.0

	if tex_a == cell_mat_a: weight_mat_a += w_a
	elif tex_a == cell_mat_b: weight_mat_b += w_a
	elif tex_a == cell_mat_c: weight_mat_c += w_a

	if tex_b == cell_mat_a: weight_mat_a += w_b
	elif tex_b == cell_mat_b: weight_mat_b += w_b
	elif tex_b == cell_mat_c: weight_mat_c += w_b

	if tex_c == cell_mat_a: weight_mat_a += w_c
	elif tex_c == cell_mat_b: weight_mat_b += w_c
	elif tex_c == cell_mat_c: weight_mat_c += w_c

	if tex_d == cell_mat_a: weight_mat_a += w_d
	elif tex_d == cell_mat_b: weight_mat_b += w_d
	elif tex_d == cell_mat_c: weight_mat_c += w_d

	# Normalize weights
	var total_weight : float = weight_mat_a + weight_mat_b + weight_mat_c
	if total_weight > 0.001:
		weight_mat_a /= total_weight
		weight_mat_b /= total_weight

	cell_weight_b = weight_mat_b
	return Color(float(cell_mat_a), float(cell_mat_b), float(cell_mat_c), weight_mat_a)

#endregion


#region terrain palette + texture array helpers

const PS_LOG_NORMALIZATION_WARNINGS = "mst/debug/log_texture_array_normalization_warnings"

static func get_decompressed_image(tex: Texture2D) -> Image:
	if tex == null:
		return null
	var img = tex.get_image()
	if img == null:
		return null
	if img.is_compressed():
		var d := img.duplicate()
		d.decompress()
		# Some Godot builds don't return an Error code from decompress(), so verify via state.
		if d.is_compressed():
			return null
		img = d
	return img


static func warn_once(cache: Dictionary, key, message: String) -> void:
	# These mismatches are auto-healed by normalization. To avoid noisy editor logs,
	# we only warn if the user explicitly enables this debug ProjectSetting.
	if not bool(ProjectSettings.get_setting(PS_LOG_NORMALIZATION_WARNINGS, false)):
		return
	if cache.has(key):
		return
	cache[key] = true
	push_warning(message)


static func normalize_image_for_texture_array(src: Image, w: int, h: int) -> Image:
	# Ensure a stable, uncompressed format (RGBA8), matching size, and no mipmaps.
	if src == null:
		return null
	var img := src
	if img.get_format() !=  Image.FORMAT_RGBA8:
		img = img.duplicate()
		img.convert(Image.FORMAT_RGBA8)
	if img.get_width() !=  w or img.get_height() != h:
		img = img.duplicate()
		# Nearest keeps pixel art crisp if a texture has the wrong size.
		img.resize(w, h, Image.INTERPOLATE_NEAREST)
	
	# Strip mipmaps by copying only the base layer into a fresh image.
	var out := Image.create_empty(w, h, false, Image.FORMAT_RGBA8)
	out.blit_rect(img, Rect2i(0, 0, w, h), Vector2i(0, 0))
	return out


static func rebuild_palette_uniforms(terrain) -> void:
	var max_slots : int = int(terrain.MAX_TEXTURE_SLOTS)
	var void_slot : int = int(terrain.VOID_TEXTURE_SLOT)
	
	var img_colors := Image.create_empty(8, max_slots, false, Image.FORMAT_RGBAF)
	var img_weights := Image.create_empty(8, max_slots, false, Image.FORMAT_RGBAF)
	var img_meta := Image.create_empty(1, max_slots, false, Image.FORMAT_RGBA8)
	var img_surface_settings := Image.create_empty(1, max_slots, false, Image.FORMAT_RGBAF)
	var img_floor_noise := Image.create_empty(1, max_slots, false, Image.FORMAT_RGBAF)
	var img_wall_noise := Image.create_empty(1, max_slots, false, Image.FORMAT_RGBAF)
	var img_slot_albedo := Image.create_empty(1, max_slots, false, Image.FORMAT_RGBAF)
	# Palette colors are edited/stored as sRGB-style values.
	# Shaders operate in linear space, so convert to linear before uploading.
	var fallback := Color(1.0, 1.0, 1.0, 0.0)
	
	for slot in range(max_slots):
		var indices: Array = terrain.slot_color_indices[slot]
		var count := mini(indices.size(), 8)
		var out_count := count
		
		# Meta packing (0..255 per channel)
		var mode := clampi(int(terrain.slot_blend_modes[slot]), 0, 3)
		img_meta.set_pixel(0, slot, Color(float(out_count) / 255.0, float(mode) / 255.0, 0.0, 0.0))
		
		var wet_on := 1.0 if bool(terrain.slot_wet_enabled[slot]) else 0.0
		var wet_mode := float(clampi(int(terrain.slot_wet_modes[slot]), 0, 1))
		var grass_wetness := 0.0
		if terrain.get("slot_grass_wetnesses") is Array and slot < terrain.slot_grass_wetnesses.size():
			grass_wetness = clampf(float(terrain.slot_grass_wetnesses[slot]), 0.0, 1.0)
		
		img_surface_settings.set_pixel(0, slot, Color(float(terrain.slot_roughnesses[slot]), wet_on, wet_mode, grass_wetness))
		
		var floor_noise_on : float = 1.0 if bool(terrain.slot_floor_noise_enabled[slot]) else 0.0
		var wall_noise_on : float = 1.0 if bool(terrain.slot_wall_noise_enabled[slot]) else 0.0
		
		img_floor_noise.set_pixel(0, slot, Color(float(terrain.slot_floor_noise_strengths[slot]), float(terrain.slot_floor_noise_scales[slot]), floor_noise_on, 1.0))
		img_wall_noise.set_pixel(0, slot, Color(float(terrain.slot_wall_noise_strengths[slot]), float(terrain.slot_wall_noise_scales[slot]), wall_noise_on, 1.0))
		
		var slot_albedo := Color(1.0, 1.0, 1.0, 0.0)
		if slot < terrain.texture_slots.size() and terrain.texture_slots[slot] != null:
			var raw_slot_albedo: Variant = terrain.texture_slots[slot].get("albedo")
			if raw_slot_albedo is Color:
				slot_albedo = raw_slot_albedo
		
		img_slot_albedo.set_pixel(0, slot, slot_albedo.srgb_to_linear())
		
		for i in range(8):
			var c := Color(1.0, 1.0, 1.0, 1.0)
			var w := 0.0
			if i < count and indices[i] < terrain.palette_colors.size():
				c = terrain.palette_colors[indices[i]].srgb_to_linear()
				w = (float(terrain.palette_weights[indices[i]]) / 100.0) if indices[i] < terrain.palette_weights.size() else 1.0
			elif i == 0 and count == 0:
				# Empty slots should mean "no tint", not an implicit fallback color.
				c = fallback
				w = 0.0
			
			img_colors.set_pixel(i, slot, c)
			img_weights.set_pixel(i, slot, Color(w, 0.0, 0.0, 1.0))
	
	var tex_colors := ImageTexture.create_from_image(img_colors)
	var tex_weights := ImageTexture.create_from_image(img_weights)
	var tex_meta := ImageTexture.create_from_image(img_meta)
	var tex_surface_settings := ImageTexture.create_from_image(img_surface_settings)
	var tex_floor_noise := ImageTexture.create_from_image(img_floor_noise)
	var tex_wall_noise := ImageTexture.create_from_image(img_wall_noise)
	var tex_slot_albedo := ImageTexture.create_from_image(img_slot_albedo)
	terrain.terrain_material.set_shader_parameter("palette_colors_tex", tex_colors)
	terrain.terrain_material.set_shader_parameter("palette_weights_tex", tex_weights)
	terrain.terrain_material.set_shader_parameter("palette_meta_tex", tex_meta)
	terrain.terrain_material.set_shader_parameter("palette_surface_settings_tex", tex_surface_settings)
	terrain.terrain_material.set_shader_parameter("palette_floor_noise_tex", tex_floor_noise)
	terrain.terrain_material.set_shader_parameter("palette_wall_noise_tex", tex_wall_noise)
	terrain.terrain_material.set_shader_parameter("slot_albedo_tex", tex_slot_albedo)
	
	var grass_mat := terrain.grass_mesh.material as ShaderMaterial
	grass_mat.set_shader_parameter("palette_colors_tex", tex_colors)
	grass_mat.set_shader_parameter("palette_weights_tex", tex_weights)
	grass_mat.set_shader_parameter("palette_meta_tex", tex_meta)
	grass_mat.set_shader_parameter("palette_surface_settings_tex", tex_surface_settings)
	grass_mat.set_shader_parameter("palette_floor_noise_tex", tex_floor_noise)
	grass_mat.set_shader_parameter("slot_albedo_tex", tex_slot_albedo)

#endregion

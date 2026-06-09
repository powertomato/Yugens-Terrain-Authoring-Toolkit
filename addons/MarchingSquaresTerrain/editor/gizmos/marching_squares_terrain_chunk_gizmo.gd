# This gizmo will have handles for both height values (primary) and XZ offsets (secondary).
# Primary handle (secondary=false): Y-axis height editing
# Secondary handle (secondary=true): XZ-plane point movement

extends EditorNode3DGizmo
class_name MarchingSquaresTerrainChunkGizmo

const XZ_OFFSET_LIMIT = 0.5  # Range limits: [-0.5, 0.5] relative to cell size


func _redraw():
	clear()

	var terrain := get_node_3d() as MarchingSquaresTerrainChunk
	if terrain == null:
		return
	# height_map can be empty while a chunk is initializing or after load errors.
	if terrain.height_map.is_empty():
		return
	var dx := (terrain.dimensions.x - 1) * terrain.cell_size.x
	var dz := (terrain.dimensions.z - 1) * terrain.cell_size.y

	# Only draw the gizmo if this is the only selected node
	if len(EditorInterface.get_selection().get_selected_nodes()) !=  1:
		return
	if EditorInterface.get_selection().get_selected_nodes()[0] !=  terrain:
		return

	# Primary handles for height editing, secondary handles for XZ offsets
	var corners := PackedVector3Array()
	var xz_corners := PackedVector3Array()
	var ids := PackedInt32Array()
	for z in range(terrain.dimensions.z):
		if z < 0 or z >=  terrain.height_map.size():
			continue
		for x in range(terrain.dimensions.x):
			if x < 0 or x >=  terrain.height_map[z].size():
				continue
			var y = terrain.height_map[z][x]
			var offset := _get_xz_offset(terrain, z, x)
			corners.append(Vector3(x * terrain.cell_size.x + offset.x, y, z * terrain.cell_size.y + offset.y))
			xz_corners.append(Vector3(x * terrain.cell_size.x + offset.x, y, z * terrain.cell_size.y + offset.y))
			ids.append(z*terrain.dimensions.x + x)
	add_handles(corners, get_plugin().get_material("handles", self), ids)
	add_handles(xz_corners, get_plugin().get_material("handles", self), ids, false, true)


## Reads a point's XZ offset, tolerating a missing/malformed xz_offset_map (chunks from older scenes).
func _get_xz_offset(terrain: MarchingSquaresTerrainChunk, z: int, x: int) -> Vector2:
	if not _has_xz_offset_slot(terrain, z, x):
		return Vector2.ZERO
	return terrain.xz_offset_map[z][x]


## True if xz_offset_map[z][x] exists (and can therefore be written to).
func _has_xz_offset_slot(terrain: MarchingSquaresTerrainChunk, z: int, x: int) -> bool:
	if not (terrain.xz_offset_map is Array) or z < 0 or z >= terrain.xz_offset_map.size():
		return false
	var row = terrain.xz_offset_map[z]
	return row is Array and x >= 0 and x < row.size()


func _get_handle_name(handle_id: int, secondary: bool) -> String:
	return str(handle_id);


func _get_handle_value(handle_id: int, secondary: bool) -> Variant:
	var terrain := get_node_3d() as MarchingSquaresTerrainChunk
	if terrain == null:
		return Vector2.ZERO if secondary else 0.0
	if terrain.height_map.is_empty():
		return Vector2.ZERO if secondary else 0.0
	var z = handle_id / terrain.dimensions.x
	var x = handle_id % terrain.dimensions.x
	if z < 0 or z >=  terrain.height_map.size() or x < 0 or x >= terrain.height_map[z].size():
		return Vector2.ZERO if secondary else 0.0

	if secondary:
		return _get_xz_offset(terrain, z, x)
	else:
		return terrain.height_map[z][x]


func _commit_handle(handle_id: int, secondary: bool, restore: Variant, cancel: bool) -> void:
	var terrain := get_node_3d() as MarchingSquaresTerrainChunk
	if terrain == null:
		return
	if terrain.height_map.is_empty():
		return
	var z = handle_id / terrain.dimensions.x
	var x = handle_id % terrain.dimensions.x
	if z < 0 or z >=  terrain.height_map.size() or x < 0 or x >= terrain.height_map[z].size():
		return

	if cancel:
		if secondary:
			if _has_xz_offset_slot(terrain, z, x):
				terrain.xz_offset_map[z][x] = restore
		else:
			terrain.height_map[z][x] = restore
		terrain.mark_dirty()
	else:
		var undo_redo := MarchingSquaresTerrainPlugin.instance.get_undo_redo()

		if secondary:
			var do_value = _get_xz_offset(terrain, z, x)
			undo_redo.create_action("move terrain point XZ")
			undo_redo.add_do_method(self, "move_terrain_point_xz", terrain, handle_id, do_value)
			undo_redo.add_undo_method(self, "move_terrain_point_xz", terrain, handle_id, restore)
		else:
			var do_value = terrain.height_map[z][x]
			undo_redo.create_action("move terrain point height")
			undo_redo.add_do_method(self, "move_terrain_point", terrain, handle_id, do_value)
			undo_redo.add_undo_method(self, "move_terrain_point", terrain, handle_id, restore)

		undo_redo.commit_action()

	terrain.update_gizmos()


func move_terrain_point(terrain: MarchingSquaresTerrainChunk, handle_id: int, height: float):
	if terrain.height_map.is_empty():
		return
	var z = handle_id / terrain.dimensions.x
	var x = handle_id % terrain.dimensions.x
	if z < 0 or z >=  terrain.height_map.size() or x < 0 or x >= terrain.height_map[z].size():
		return
	terrain.height_map[z][x] = height
	terrain.mark_dirty()

	notify_needs_update(terrain, z, x)
	notify_needs_update(terrain, z, x-1)
	notify_needs_update(terrain, z-1, x)
	notify_needs_update(terrain, z-1, x-1)

	terrain.regenerate_mesh()
	terrain.update_gizmos()


func move_terrain_point_xz(terrain: MarchingSquaresTerrainChunk, handle_id: int, offset: Vector2):
	var z = handle_id / terrain.dimensions.x
	var x = handle_id % terrain.dimensions.x
	if not _has_xz_offset_slot(terrain, z, x):
		return
	terrain.xz_offset_map[z][x] = offset
	terrain.mark_dirty()

	notify_needs_update(terrain, z, x)
	notify_needs_update(terrain, z, x-1)
	notify_needs_update(terrain, z-1, x)
	notify_needs_update(terrain, z-1, x-1)

	terrain.regenerate_mesh()
	terrain.update_gizmos()


func notify_needs_update(terrain: MarchingSquaresTerrainChunk, z: int, x: int):
	if z < 0 or z >=  terrain.dimensions.z-1 or x < 0 or x >= terrain.dimensions.x-1:
		return
	terrain.needs_update[z][x] = true


func _set_handle(handle_id: int, secondary: bool, camera: Camera3D, screen_pos: Vector2) -> void:
	var terrain := get_node_3d() as MarchingSquaresTerrainChunk
	if terrain == null:
		return
	if terrain.height_map.is_empty():
		return
	var z = handle_id / terrain.dimensions.x
	var x = handle_id % terrain.dimensions.x
	if z < 0 or z >=  terrain.height_map.size() or x < 0 or x >= terrain.height_map[z].size():
		return
	var y = terrain.height_map[z][x]
	var offset := _get_xz_offset(terrain, z, x)

	# Get handle position
	var handle_position = terrain.to_global(Vector3(x * terrain.cell_size.x + offset.x, y, z * terrain.cell_size.y + offset.y))

	# Convert mouse movement to 3D world coordinates using raycasting
	var ray_origin = camera.project_ray_origin(screen_pos)
	var ray_dir = camera.project_ray_normal(screen_pos)

	if secondary:
		# Secondary handle: movement restricted to XZ plane (horizontal)
		if not _has_xz_offset_slot(terrain, z, x):
			return
		var plane = Plane(Vector3.UP, handle_position)
		var intersection = plane.intersects_ray(ray_origin, ray_dir)

		if intersection:
			intersection = terrain.to_local(intersection)
			var new_offset = Vector2(intersection.x - x * terrain.cell_size.x, intersection.z - z * terrain.cell_size.y)
			# Clamp to valid range: [-0.5, 0.5] * cell_size
			new_offset.x = clamp(new_offset.x, -terrain.cell_size.x * XZ_OFFSET_LIMIT, terrain.cell_size.x * XZ_OFFSET_LIMIT)
			new_offset.y = clamp(new_offset.y, -terrain.cell_size.y * XZ_OFFSET_LIMIT, terrain.cell_size.y * XZ_OFFSET_LIMIT)
			terrain.xz_offset_map[z][x] = new_offset
			terrain.mark_dirty()
			terrain.update_gizmos()
	else:
		# Primary handle: movement restricted to Y-axis (vertical)
		var plane = Plane(Vector3(ray_dir.x, 0, ray_dir.z), handle_position)
		var intersection = plane.intersects_ray(ray_origin, ray_dir)

		if intersection:
			intersection = terrain.to_local(intersection)
			terrain.height_map[z][x] = intersection.y
			terrain.mark_dirty()
			terrain.update_gizmos()

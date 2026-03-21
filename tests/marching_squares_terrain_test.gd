# GdUnit generated TestSuite
class_name MarchingSquaresTerrainTest
extends GdUnitTestSuite
@warning_ignore('unused_parameter')
@warning_ignore('return_value_discarded')


func test_saving() -> void:
	var root := _mk_mock_editor("res://tests/tmp/mock.tscn")
	var terrain := _mk_terrain_node()
	
	root.add_child(terrain)
	await get_tree().process_frame
	
	assert_str(terrain.data_directory).is_not_empty()
	
	## Make changes that are not saved
	terrain.add_new_chunk(0,0,null)
	var comp := MSTTestUtils.collect_components(self, terrain)
	var chunk := comp.chunk as MarchingSquaresTerrainChunk
	for x in range(chunk.height_map.size()):
		for z in range(chunk.height_map[x].size()):
			chunk.height_map[x][z] = 7.0
	chunk.regenerate_all_cells(true)
	
	comp = MSTTestUtils.collect_components(self, terrain)
	
	_check_geometry_grass_and_coliders(comp)
	await _simulate_tab_switch(root, terrain)
	## Nothing is changed and reloaded after tab-switch
	_check_geometry_grass_and_coliders(comp)
	
	## Emit a save notification, to store geometry
	terrain._notification(NOTIFICATION_EDITOR_PRE_SAVE)
	
	terrain.free()
	

func test_load1() -> void:
	_test_load("res://tests/terrain_data/all/", MarchingSquaresTerrain.StorageMode.BAKED, true, true, false, false, false)
	collect_orphan_node_details()

func test_load2() -> void:
	_test_load("res://tests/terrain_data/geometry/", MarchingSquaresTerrain.StorageMode.BAKED, true, true, false, true, true)

func test_load3() -> void:
	_test_load("res://tests/terrain_data/geometry_colision/", MarchingSquaresTerrain.StorageMode.BAKED, true, true, false, true, false)

func test_load4() -> void:
	_test_load("res://tests/terrain_data/geometry_grass/", MarchingSquaresTerrain.StorageMode.BAKED, true, true, false, false, true)

func test_load5() -> void:
	_test_load("res://tests/terrain_data/none/", MarchingSquaresTerrain.StorageMode.BAKED, true, true, true, true, true)


func test_load6() -> void:
	_test_load("res://tests/terrain_data/all/", MarchingSquaresTerrain.StorageMode.RUNTIME, true, true, false, false, false)

func test_load7() -> void:
	_test_load("res://tests/terrain_data/geometry/", MarchingSquaresTerrain.StorageMode.RUNTIME, true, true, false, false, false)

func test_load8() -> void:
	_test_load("res://tests/terrain_data/geometry_colision/", MarchingSquaresTerrain.StorageMode.RUNTIME, true, true, false, false, false)

func test_load9() -> void:
	_test_load("res://tests/terrain_data/geometry_grass/", MarchingSquaresTerrain.StorageMode.RUNTIME, true, true, false, false, false)

func test_lost10() -> void:
	_test_load("res://tests/terrain_data/none/", MarchingSquaresTerrain.StorageMode.RUNTIME, true, true, false, false, false)

func _test_load(data_dir: String, 
	storage_mode: MarchingSquaresTerrain.StorageMode, 
	bake_col: bool, 
	bake_grass: bool,
	_assert_geometry_warning: bool,
	_assert_grass_warning: bool,
	_assert_col_warning: bool,
	) -> void:
	var root := _mk_mock_editor("res://tests/tmp/mock.tscn")
	var terrain := _mk_terrain_node(storage_mode, bake_col, bake_grass)
	
	# if the terrain has no reference no data will be loaded
	# usually these are saved in the scene file
	terrain.add_new_chunk(0,0, null)
	terrain.chunks[Vector2i(0,0)]._data_dirty = false
	terrain.data_directory = data_dir
	terrain._storage_initialized = true
	
	root.add_child(terrain)
	await get_tree().process_frame
	
	var lambda := func():
		var comp := MSTTestUtils.collect_components(self, terrain)
		var chunk := comp.chunk as MarchingSquaresTerrainChunk
		chunk.regenerate_all_cells(true)
		comp = MSTTestUtils.collect_components(self, terrain) # after regenerate, instances are invalid
		await terrain.load_finished
	
	var asrt := assert_error(lambda)
	
	if _assert_geometry_warning:
		asrt.is_push_warning("Baking enabled, but terrain-ressource does not contain mesh data")
	if _assert_grass_warning:
		asrt.is_push_warning("Grass baking enabled, but terrain-ressource does not contain grass data")
	if _assert_col_warning:
		asrt.is_push_warning("Collision baking enabled, but terrain-ressource does not contain collision data")
	if not _assert_geometry_warning and not _assert_grass_warning and not _assert_col_warning:
		lambda.call()
		
	# ensure baked data has been loaded/regenerated
	var comp := MSTTestUtils.collect_components(self, terrain)
	_check_geometry_grass_and_coliders(comp)
	
	var chunk := comp.chunk as MarchingSquaresTerrainChunk
	for x in range(chunk.height_map.size()):
		for z in range(chunk.height_map[x].size()):
			chunk.height_map[x][z] = -7.0
	chunk.regenerate_all_cells(true)
	comp = MSTTestUtils.collect_components(self, terrain)
	
	# The data is not reloaded, even after multiple tab-switches
	_check_geometry_grass_and_coliders(comp, -7.0)
	_simulate_tab_switch(root, terrain)
	_check_geometry_grass_and_coliders(comp, -7.0)
	_simulate_tab_switch(root, terrain)
	_check_geometry_grass_and_coliders(comp, -7.0)
	
	terrain.free()
	

func test_baked_grass_dissapearing() -> void:
	var root := _mk_mock_editor("res://tests/tmp/mock.tscn")
	var terrain := _mk_terrain_node()
	
	# if the terrain has no reference no data will be loaded
	# usually these are saved in the scene file
	terrain.add_new_chunk(0,0, null)
	terrain.chunks[Vector2i(0,0)]._data_dirty = false

	terrain.data_directory = "res://tests/terrain_data/all/"
	terrain._storage_initialized = true
	
	root.add_child(terrain)
	await terrain.load_finished
	
	var comp := MSTTestUtils.collect_components(self, terrain)
	var mm := comp.grass.multimesh as MultiMesh
	var buffer_pre_bake_reload := PackedFloat32Array(mm.buffer)
	
	# ensure baked data has been loaded
	_check_geometry_grass_and_coliders(comp)
	
	await _simulate_tab_switch(root, terrain)
	
	var comp_after_after_bake_reload = MSTTestUtils.collect_components(self, terrain)
	_check_geometry_grass_and_coliders(comp_after_after_bake_reload)
	
	mm = comp_after_after_bake_reload.grass.multimesh
	MSTTestUtils.assert_array_equal(self, buffer_pre_bake_reload, mm.buffer)
	

#region helpers

func _mk_mock_editor(scene_path) -> Node:
	var root := get_tree().root
	root.scene_file_path = scene_path
	
	var engine_mock = mock(EngineWrapper)
	do_return(true).on(engine_mock).is_editor()
	do_return(root).on(engine_mock).get_edited_scene_root()
	do_return(root).on(engine_mock).get_root_for_node(any())
	EngineWrapper.instance = engine_mock
	
	return root


func _mk_terrain_node(storage_mode: MarchingSquaresTerrain.StorageMode = MarchingSquaresTerrain.StorageMode.BAKED, bake_col: bool = true, bake_grass: bool = true) -> MarchingSquaresTerrain:
	var terrain := MarchingSquaresTerrain.new()
	terrain.name = "MST" + str(randi_range(1,0x7FFFFFFF))
	terrain.storage_mode = storage_mode
	terrain.bake_collision = bake_col
	terrain.bake_grass = bake_grass
	terrain.enable_runtime_texture_baking = false
	terrain.dimensions = Vector3i(5,6,7)
	assert_signal(terrain).is_emitted("chunk_dimensions_changed", 5,6,7)
	terrain.cell_size = Vector2.ONE
	return terrain
	
	
func _check_geometry_grass_and_coliders(comp: Dictionary, y_values: float = 7.0) -> void:
	var ctx := MSTTestUtils.get_last_calls_as_string()
	var mm := comp.grass.multimesh as MultiMesh
	assert_int(mm.instance_count).is_greater(10)
	MSTTestUtils.assert_multi_mesh_y_values(self, mm, y_values)
	
	var chunk := comp.chunk as MarchingSquaresTerrainChunk
	var arrays := chunk.mesh.surface_get_arrays(0)
	var vertices := arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array
	for v in vertices:
		var eq := is_equal_approx(v.y, y_values)
		assert_bool(eq).append_failure_message(ctx).is_true()
		if not eq:
			break
			
	var col_shape := comp.col_shape.shape as ConcavePolygonShape3D
	assert_that(col_shape).is_not_null()
	var col_faces := col_shape.get_faces()
	for v in col_faces:
		var eq := is_equal_approx(v.y, y_values)
		assert_bool(eq).append_failure_message(ctx).is_true()
		if not eq:
			break
	
	
func _simulate_tab_switch(root: Node, terrain: Node) -> void:
	## simulate tab-switch scenes in editor [data unsaved]
	root.remove_child(terrain)
	root.add_child(terrain)
	await get_tree().process_frame
	

#endregion

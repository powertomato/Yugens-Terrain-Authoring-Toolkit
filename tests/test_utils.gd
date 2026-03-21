extends Object
class_name MSTTestUtils

static func assert_multi_mesh_y_values(ts: GdUnitTestSuite, mm: MultiMesh, value: float) -> void:
	var ctx := get_last_calls_as_string()
	ts.assert_that(mm).append_failure_message(ctx).is_not_null()
	for i in range(mm.instance_count):
		var tf := mm.get_instance_transform(i)
		var pos := tf.origin
		
		var eq := is_equal_approx(value, pos.y)
		ts.assert_bool(eq).append_failure_message(ctx).is_true()
		
		# In case we find a validated assert we can stop
		# too many invalid values just fill up the report and cause issues
		if not eq:
			return

			
static func assert_array_equal(ts: GdUnitTestSuite, a: PackedFloat32Array, b: PackedFloat32Array) -> void:
	var ctx := get_last_calls_as_string()
	ts.assert_int(a.size()).append_failure_message(ctx).is_equal(b.size())
	if a.size() != b.size():
		return
	for i in range(a.size()):
		var eq := is_equal_approx(a[i], b[i])
		ts.assert_bool(eq).append_failure_message(ctx).is_true()
		if not eq:
			return


static func collect_components(ts: GdUnitTestSuite, terrain: MarchingSquaresTerrain) -> Dictionary:
	var chunk := terrain.get_node("Chunk (0, 0)") as MarchingSquaresTerrainChunk
	ts.assert_that(chunk).is_not_null()
	
	var grass := chunk.get_node("GrassPlanter") as MarchingSquaresGrassPlanter
	ts.assert_that(grass).is_not_null()
	
	var col := chunk.get_node("Chunk (0, 0)_col") as StaticBody3D
	ts.assert_that(col).is_not_null()
	
	var col_shape := col.get_node("CollisionShape3D") as CollisionShape3D
	ts.assert_that(col_shape).is_not_null()
	ts.assert_bool(col_shape.shape is ConcavePolygonShape3D).is_true()
	
	return {
		"chunk": chunk,
		"grass": grass,
		"collision": col,
		"col_shape": col_shape
	}
	
static func get_last_calls(skip: int = 1) -> Array:
	var stack := get_stack()
	var result: Array = []

	# skip = how many top frames to ignore (this function, helpers, etc.)
	var start := skip

	for i in range(start, stack.size()):
		if stack[i].source.begins_with("res://addons/gdUnit4/src"):
			break
		result.append(stack[i])

	return result

static func get_last_calls_as_string(skip: int = 2) -> String:
	var calls := get_last_calls(skip + 1) # +1 to skip this wrapper too
	var parts: Array[String] = []

	for c in calls:
		parts.append("%s:%d (%s)" % [
			c.source,
			c.line,
			c.function
		])

	return " <- ".join(parts)
	

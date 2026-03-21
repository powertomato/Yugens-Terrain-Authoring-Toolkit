# GdUnit generated TestSuite
class_name MarchingSquaresTerrainTest
extends GdUnitTestSuite
@warning_ignore('unused_parameter')
@warning_ignore('return_value_discarded')


func test_sanity() -> void:
	var engine_mock = mock(EngineWrapper)
	do_return(true).on(engine_mock).is_editor()
	EngineWrapper.instance = engine_mock
	
	assert_that(engine_mock.is_editor()).is_equal(true)

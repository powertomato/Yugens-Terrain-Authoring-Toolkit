extends Object
class_name EngineWrapper

static var instance : EngineWrapper:
	get:
		if not instance:
			instance = EngineWrapper.new()
		return instance

func is_editor() -> bool:
	return Engine.is_editor_hint()

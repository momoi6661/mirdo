extends Resource
class_name ItemData

@export var ItemName:String
@export_multiline var Description:String
@export var Icon:Texture2D
@export var ItemModelScenePath:String
@export var MaxStackSize:int=1

var _cached_scene:PackedScene

func get_scene() -> PackedScene:
	if not _cached_scene and not ItemModelScenePath.is_empty():
		_cached_scene = load(ItemModelScenePath) as PackedScene
	return _cached_scene

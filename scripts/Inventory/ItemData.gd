extends Resource
class_name ItemData

@export var ItemName:String
@export_multiline var Description:String
@export var Icon:Texture2D
@export var ItemModelScenePath:String
@export var MaxStackSize:int=1
@export var consumable_effect: XiaokongStatModifier
@export_enum("food", "medical", "material", "tool", "weapon", "special") var outing_category: String = "material"
@export var can_take_outing: bool = false
@export var inventory_tags: PackedStringArray = []
@export_multiline var ai_rule_hint: String = ""

var _cached_scene:PackedScene

func get_scene() -> PackedScene:
	if not _cached_scene and not ItemModelScenePath.is_empty():
		_cached_scene = load(ItemModelScenePath) as PackedScene
	return _cached_scene

func has_consumable_effect() -> bool:
	return consumable_effect != null

func get_consumable_delta() -> Dictionary:
	if consumable_effect == null:
		return {}
	return consumable_effect.to_stat_delta()

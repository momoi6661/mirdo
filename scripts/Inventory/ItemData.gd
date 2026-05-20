extends Resource
class_name ItemData

@export var ItemName:String
@export_multiline var Description:String
@export var Icon:Texture2D
@export var ItemModelScenePath:String
@export var MaxStackSize:int=1
@export var consumable_effect: XiaokongStatModifier
@export_range(-100, 100, 1) var health_delta: int = 0
@export_range(-100, 100, 1) var hunger_delta: int = 0
@export_range(-100, 100, 1) var thirst_delta: int = 0
@export_enum("food", "medical", "material", "tool", "weapon", "special") var outing_category: String = "material"
@export var can_take_outing: bool = false
@export var can_use: bool = false
@export_range(0.0, 1.0, 0.01) var outing_damage_reduction: float = 0.0
@export var inventory_tags: PackedStringArray = []
@export_multiline var ai_rule_hint: String = ""

var _cached_scene:PackedScene

func get_scene() -> PackedScene:
	if not _cached_scene and not ItemModelScenePath.is_empty():
		_cached_scene = load(ItemModelScenePath) as PackedScene
	return _cached_scene

func has_consumable_effect() -> bool:
	return not get_consumable_delta().is_empty()

func get_consumable_delta() -> Dictionary:
	var delta := {}
	if health_delta != 0:
		delta["health"] = health_delta
	if hunger_delta != 0:
		delta["hunger"] = hunger_delta
	if thirst_delta != 0:
		delta["thirst"] = thirst_delta
	if consumable_effect != null:
		var legacy_delta := consumable_effect.to_stat_delta()
		for key in legacy_delta.keys():
			if not delta.has(key):
				delta[key] = legacy_delta[key]
	return delta

func is_usable() -> bool:
	return can_use or has_consumable_effect()

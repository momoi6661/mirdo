extends Node
class_name CharacterResourceTimeDecayComponent

@export_category("Target")
@export var enabled: bool = true
@export var state_component_path: NodePath = NodePath("../StateComponent")

@export_category("Pace")
@export_range(60.0, 3600.0, 10.0) var real_seconds_per_game_hour: float = 900.0
@export_range(0.01, 0.5, 0.01) var min_tick_game_hours: float = 0.05
@export var decay_when_tree_paused: bool = false

var _state_component: Node = null
var _accumulated_game_hours: float = 0.0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_resolve_state_component()


func _process(delta: float) -> void:
	if not enabled:
		return
	var tree := get_tree()
	if tree != null and tree.paused and not decay_when_tree_paused:
		return
	if _state_component == null or not is_instance_valid(_state_component):
		_resolve_state_component()
	if _state_component == null or not _state_component.has_method("tick_hours"):
		return
	_accumulated_game_hours += delta / maxf(real_seconds_per_game_hour, 1.0)
	if _accumulated_game_hours < min_tick_game_hours:
		return
	var hours := _accumulated_game_hours
	_accumulated_game_hours = 0.0
	_state_component.call("tick_hours", hours)


func force_tick(hours: float) -> Dictionary:
	if hours <= 0.0:
		return {}
	if _state_component == null or not is_instance_valid(_state_component):
		_resolve_state_component()
	if _state_component == null or not _state_component.has_method("tick_hours"):
		return {}
	return _state_component.call("tick_hours", hours) as Dictionary


func _resolve_state_component() -> void:
	_state_component = get_node_or_null(state_component_path)

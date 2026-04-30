extends StaticBody3D
class_name BedSleepInteractableComponent

const TRANSITION_UI_SCENE: PackedScene = preload("res://controllers/ui/transition_screen.tscn")

@export_category("Interaction")
@export var interaction_enabled: bool = true
@export_range(0.0, 5.0, 0.05) var interaction_cooldown_sec: float = 0.35

@export_category("Sleep")
@export_range(0.5, 24.0, 0.5) var sleep_hours: float = 8.0
@export var world_panel_title: String = "床"
@export var sleep_option_label: String = "睡觉"
@export var transition_preset: String = "b"
@export_range(0.0, 3.0, 0.01) var transition_hold_sec: float = 0.48

@export_category("Focus Highlight")
@export var focus_highlight_enabled: bool = true
@export var highlight_root_path: NodePath = NodePath("..")
@export var highlight_color: Color = Color(1.0, 0.93, 0.35, 0.2)
@export_range(0.0, 4.0, 0.05) var highlight_emission_energy: float = 0.75

var _last_trigger_time_msec: int = -1000000
var _highlight_meshes: Array[MeshInstance3D] = []
var _original_mesh_overlays: Dictionary = {}
var _highlight_overlay: StandardMaterial3D
var _focused: bool = false
var _busy: bool = false

func _ready() -> void:
	_refresh_highlight_meshes()

func is_interaction_enabled() -> bool:
	return interaction_enabled and not _busy

func build_world_panel_model(_helper: Node, _context: Dictionary) -> WorldInteractionPanelModel:
	var model := WorldInteractionPanelModel.new()
	model.title = world_panel_title.strip_edges() if not world_panel_title.strip_edges().is_empty() else "床"
	model.options.append(
		WorldInteractionOption.create(
			"sleep",
			sleep_option_label.strip_edges() if not sleep_option_label.strip_edges().is_empty() else "睡觉"
		)
	)
	return model

func execute_world_panel_option(option_id: String, _helper: Node, _context: Dictionary, _completed_by_hold: bool, _hold_time: float) -> void:
	if option_id != "sleep":
		return
	if not interaction_enabled or _busy or not _is_cooldown_ready():
		return
	call_deferred("_run_sleep_sequence")

func set_world_panel_focused(focused: bool) -> void:
	if _focused == focused:
		return
	_focused = focused
	_apply_focus_visual(focused)

func _run_sleep_sequence() -> void:
	if _busy:
		return
	_busy = true
	var transition_ui: Node = _ensure_transition_ui()
	var safe_sleep_hours: float = maxf(sleep_hours, 0.5)
	if transition_ui != null and transition_ui.has_method("play_action_transition"):
		await transition_ui.play_action_transition(
			Callable(self, "_apply_sleep_skip").bind(safe_sleep_hours),
			transition_preset,
			transition_hold_sec
		)
	else:
		_apply_sleep_skip(safe_sleep_hours)
	_last_trigger_time_msec = Time.get_ticks_msec()
	_busy = false

func _apply_sleep_skip(hours: float) -> void:
	var time_component: Node = _resolve_time_component()
	if time_component == null:
		push_warning("BedSleepInteractable time component not found: " + String(get_path()))
		return
	if time_component.has_method("skip_sleep"):
		time_component.call("skip_sleep", hours)
	elif time_component.has_method("skip_time_hours"):
		time_component.call("skip_time_hours", hours, "sleep_skip")
	elif time_component.has_method("pass_hours"):
		time_component.call("pass_hours", hours, "sleep_skip")

func _ensure_transition_ui() -> Node:
	var tree: SceneTree = get_tree()
	if tree == null:
		return null
	var existing: Node = tree.root.get_node_or_null("TransitionUI")
	if existing != null:
		return existing
	var instance: Node = TRANSITION_UI_SCENE.instantiate()
	instance.name = "TransitionUI"
	tree.root.add_child(instance)
	return instance

func _resolve_time_component() -> Node:
	var tree: SceneTree = get_tree()
	if tree == null:
		return null
	var current_scene: Node = tree.current_scene
	if current_scene == null:
		return null
	return _find_time_component_recursive(current_scene)

func _find_time_component_recursive(root_node: Node) -> Node:
	if root_node == null:
		return null
	if root_node.name == "TimeComponent":
		return root_node
	if root_node.has_method("skip_sleep") or root_node.has_method("skip_time_hours"):
		return root_node
	for child in root_node.get_children():
		var child_node: Node = child as Node
		if child_node == null:
			continue
		var found: Node = _find_time_component_recursive(child_node)
		if found != null:
			return found
	return null

func _is_cooldown_ready() -> bool:
	if interaction_cooldown_sec <= 0.0:
		return true
	var now_msec: int = Time.get_ticks_msec()
	var cooldown_msec: int = int(round(interaction_cooldown_sec * 1000.0))
	return now_msec - _last_trigger_time_msec >= cooldown_msec

func _apply_focus_visual(focused: bool) -> void:
	if not focus_highlight_enabled:
		return
	_refresh_highlight_meshes()
	if _highlight_meshes.is_empty():
		return
	if focused:
		var overlay: StandardMaterial3D = _get_or_create_highlight_overlay()
		for mesh in _highlight_meshes:
			if mesh == null:
				continue
			var mesh_id: int = mesh.get_instance_id()
			if not _original_mesh_overlays.has(mesh_id):
				_original_mesh_overlays[mesh_id] = mesh.material_overlay
			mesh.material_overlay = overlay
		return
	for mesh in _highlight_meshes:
		if mesh == null:
			continue
		var mesh_id: int = mesh.get_instance_id()
		if _original_mesh_overlays.has(mesh_id):
			mesh.material_overlay = _original_mesh_overlays[mesh_id]
		else:
			mesh.material_overlay = null
	_original_mesh_overlays.clear()

func _refresh_highlight_meshes() -> void:
	_highlight_meshes.clear()
	var root: Node = _resolve_highlight_root()
	if root == null:
		return
	_collect_meshes_recursive(root, _highlight_meshes)

func _resolve_highlight_root() -> Node:
	if highlight_root_path != NodePath():
		var by_path: Node = get_node_or_null(highlight_root_path)
		if by_path != null:
			return by_path
	return get_parent()

func _collect_meshes_recursive(root_node: Node, out_meshes: Array[MeshInstance3D]) -> void:
	if root_node == null:
		return
	var mesh := root_node as MeshInstance3D
	if mesh != null:
		out_meshes.append(mesh)
	for child in root_node.get_children():
		var child_node: Node = child as Node
		if child_node == null:
			continue
		_collect_meshes_recursive(child_node, out_meshes)

func _get_or_create_highlight_overlay() -> StandardMaterial3D:
	if _highlight_overlay != null:
		return _highlight_overlay
	var material := StandardMaterial3D.new()
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	material.albedo_color = highlight_color
	material.emission_enabled = true
	material.emission = Color(highlight_color.r, highlight_color.g, highlight_color.b)
	material.emission_energy_multiplier = highlight_emission_energy
	_highlight_overlay = material
	return _highlight_overlay

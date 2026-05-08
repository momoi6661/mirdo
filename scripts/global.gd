extends Node

const SHELTER_INVENTORY_DEFAULT_PATH := "res://resources/storage/shelter_inventory_default.tres"
const SHELTER_INVENTORY_SCRIPT := preload("res://scripts/Inventory/shelter_inventory_resource.gd")
const INVENTORY_STORAGE_SCRIPT := preload("res://scripts/Inventory/inventory_storage_resource.gd")
const OUTING_MAP_SCENE_PATH := "res://levels/outing/OutingMap.tscn"
const OUTING_RETURN_FALLBACK_SCENE_PATH := "res://levels/bunker_local_pbr.tscn"
const TRANSITION_UI_SCENE_PATH := "res://controllers/ui/transition_screen.tscn"
const OUTING_TRANSITION_PRESET := "a"
const OUTING_TRANSITION_HOLD_SEC := 0.18

var player
var outing_return_scene_path: String = ""
var _shelter_inventory_runtime: Resource
var _shelter_storage_runtime_by_source_id: Dictionary = {}
var _outing_transition_busy: bool = false
var _pending_scene_change_path: String = ""
var _last_scene_change_error: int = OK

# --- 新增的战利品UI交互信号 ---
signal open_loot_ui(loot_container)
signal close_loot_ui()
signal xiaokong_seat_state_changed(state: Dictionary)
signal xiaokong_dialogue_requested(payload: Dictionary)
signal xiaokong_status_requested(payload: Dictionary)
signal loot_container_switch_requested(container: Node, player: Node)
signal shelter_inventory_changed()


func _ready() -> void:
	pass


func get_shelter_inventory_runtime() -> Resource:
	if _shelter_inventory_runtime == null:
		var template := load(SHELTER_INVENTORY_DEFAULT_PATH) as Resource
		if template != null:
			_shelter_inventory_runtime = template.duplicate(true) as Resource
		if _shelter_inventory_runtime == null:
			_shelter_inventory_runtime = SHELTER_INVENTORY_SCRIPT.new() as Resource
		_bind_shelter_inventory_sources_to_runtime()
	return _shelter_inventory_runtime


func reset_shelter_inventory_runtime() -> void:
	_shelter_inventory_runtime = null
	_shelter_storage_runtime_by_source_id.clear()
	get_shelter_inventory_runtime()
	shelter_inventory_changed.emit()


func get_or_create_shelter_storage_runtime(
	source_id: Variant,
	template_storage: InventoryStorageResource = null,
	slot_count_hint: int = 0
) -> InventoryStorageResource:
	var id := String(source_id).strip_edges()
	if id.is_empty():
		return null

	if _shelter_storage_runtime_by_source_id.has(id):
		return _shelter_storage_runtime_by_source_id[id] as InventoryStorageResource

	var runtime_storage: InventoryStorageResource
	if template_storage != null:
		runtime_storage = template_storage.duplicate(true) as InventoryStorageResource
	if runtime_storage == null:
		runtime_storage = INVENTORY_STORAGE_SCRIPT.new() as InventoryStorageResource
	if slot_count_hint > 0:
		runtime_storage.slot_count = maxi(runtime_storage.slot_count, slot_count_hint)
	runtime_storage.ensure_capacity()
	_shelter_storage_runtime_by_source_id[id] = runtime_storage
	return runtime_storage


func register_shelter_storage_runtime(
	source_id: Variant,
	runtime_storage: InventoryStorageResource
) -> InventoryStorageResource:
	var id := String(source_id).strip_edges()
	if id.is_empty() or runtime_storage == null:
		return null
	if _shelter_storage_runtime_by_source_id.has(id):
		return _shelter_storage_runtime_by_source_id[id] as InventoryStorageResource
	runtime_storage.ensure_capacity()
	_shelter_storage_runtime_by_source_id[id] = runtime_storage
	_bind_shelter_inventory_sources_to_runtime()
	shelter_inventory_changed.emit()
	return runtime_storage


func notify_shelter_inventory_changed() -> void:
	shelter_inventory_changed.emit()


func go_to_outing_map_from_current_scene() -> void:
	if _outing_transition_busy:
		return
	var tree: SceneTree = get_tree()
	if tree == null:
		return
	var current_scene: Node = tree.current_scene
	var current_path := ""
	if current_scene != null:
		current_path = current_scene.scene_file_path.strip_edges()
	if not current_path.is_empty() and current_path != OUTING_MAP_SCENE_PATH:
		outing_return_scene_path = current_path
	elif outing_return_scene_path.strip_edges().is_empty():
		outing_return_scene_path = OUTING_RETURN_FALLBACK_SCENE_PATH
	await _change_scene_with_transition(OUTING_MAP_SCENE_PATH)


func return_from_outing_map() -> void:
	if _outing_transition_busy:
		return
	var target_path := outing_return_scene_path.strip_edges()
	if target_path.is_empty() or not ResourceLoader.exists(target_path):
		target_path = OUTING_RETURN_FALLBACK_SCENE_PATH
	await _change_scene_with_transition(target_path)
	if _last_scene_change_error == OK:
		outing_return_scene_path = ""


func _change_scene_with_transition(scene_path: String) -> void:
	var safe_scene_path := scene_path.strip_edges()
	if safe_scene_path.is_empty() or not ResourceLoader.exists(safe_scene_path):
		push_warning("Outing scene transition target not found: " + safe_scene_path)
		return
	_outing_transition_busy = true
	_last_scene_change_error = OK
	var transition_ui := _ensure_transition_ui()
	if transition_ui != null and transition_ui.has_method("play_action_transition"):
		await transition_ui.play_action_transition(
			Callable(self, "_apply_pending_scene_change").bind(safe_scene_path),
			OUTING_TRANSITION_PRESET,
			OUTING_TRANSITION_HOLD_SEC
		)
	else:
		_apply_pending_scene_change(safe_scene_path)
	_outing_transition_busy = false


func _apply_pending_scene_change(scene_path: String) -> void:
	_pending_scene_change_path = scene_path
	var tree: SceneTree = get_tree()
	if tree == null:
		_last_scene_change_error = ERR_UNAVAILABLE
		push_warning("Outing scene transition failed: SceneTree unavailable.")
		return
	_last_scene_change_error = tree.change_scene_to_file(_pending_scene_change_path)
	if _last_scene_change_error != OK:
		push_warning("Outing scene transition failed: %s (%d)" % [_pending_scene_change_path, _last_scene_change_error])


func _ensure_transition_ui() -> Node:
	var tree: SceneTree = get_tree()
	if tree == null:
		return null
	var existing: Node = tree.root.get_node_or_null("TransitionUI")
	if existing != null:
		return existing
	var transition_scene := load(TRANSITION_UI_SCENE_PATH) as PackedScene
	if transition_scene == null:
		push_warning("TransitionUI scene load failed: " + TRANSITION_UI_SCENE_PATH)
		return null
	var instance: Node = transition_scene.instantiate()
	instance.name = "TransitionUI"
	tree.root.add_child(instance)
	return instance


func _bind_shelter_inventory_sources_to_runtime() -> void:
	if _shelter_inventory_runtime == null:
		return
	var sources: Array = _shelter_inventory_runtime.get("storage_sources")
	for source_raw in sources:
		var source := source_raw as Resource
		if source == null:
			continue
		var source_id := String(source.get("source_id")).strip_edges()
		if source_id.is_empty():
			continue
		var template_storage := source.get("storage") as InventoryStorageResource
		var runtime_storage := get_or_create_shelter_storage_runtime(source_id, template_storage)
		if runtime_storage != null:
			source.set("storage", runtime_storage)

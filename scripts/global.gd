extends Node

const SHELTER_INVENTORY_DEFAULT_PATH := "res://resources/storage/shelter_inventory_default.tres"
const SHELTER_INVENTORY_SCRIPT := preload("res://scripts/Inventory/shelter_inventory_resource.gd")
const INVENTORY_STORAGE_SCRIPT := preload("res://scripts/Inventory/inventory_storage_resource.gd")
const OUTING_MAP_SCENE_PATH := "res://levels/outing/OutingMap.tscn"
const OUTING_RETURN_FALLBACK_SCENE_PATH := "res://levels/bunker_local_pbr.tscn"
const TRANSITION_UI_SCENE_PATH := "res://controllers/ui/transition_screen.tscn"
const OUTING_TRANSITION_PRESET := "b"
const OUTING_TRANSITION_HOLD_SEC := 0.48
const OUTING_TRANSITION_WAIT_FRAMES := 3
const OUTING_PROGRESS_DEFAULT_PATH := "res://levels/outing/state/outing_map_progress_default.tres"
const OUTING_PROGRESS_SCRIPT := preload("res://levels/outing/resources/outing_map_progress_resource.gd")

var player
var outing_return_scene_path: String = ""
var _shelter_inventory_runtime: Resource
var _outing_map_progress_runtime: Resource
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


func get_outing_map_progress_runtime() -> Resource:
	if _outing_map_progress_runtime == null:
		var template := load(OUTING_PROGRESS_DEFAULT_PATH) as Resource
		if template != null:
			_outing_map_progress_runtime = template.duplicate(true) as Resource
		if _outing_map_progress_runtime == null:
			_outing_map_progress_runtime = OUTING_PROGRESS_SCRIPT.new() as Resource
	return _outing_map_progress_runtime


func reset_outing_map_progress_runtime() -> void:
	_outing_map_progress_runtime = null
	get_outing_map_progress_runtime()


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


func build_global_save_payload() -> Dictionary:
	return {
		"version": 2,
		"outing_return_scene_path": outing_return_scene_path,
		"shelter_inventory": _build_shelter_inventory_save_payload(),
		"outing_map_progress": _build_outing_map_progress_save_payload(),
	}


func apply_global_save_payload(payload: Dictionary) -> void:
	if payload.is_empty():
		return
	outing_return_scene_path = String(payload.get("outing_return_scene_path", "")).strip_edges()
	if payload.has("shelter_inventory") and payload["shelter_inventory"] is Dictionary:
		_apply_shelter_inventory_save_payload(payload["shelter_inventory"])
	if payload.has("outing_map_progress") and payload["outing_map_progress"] is Dictionary:
		_apply_outing_map_progress_save_payload(payload["outing_map_progress"])


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
	await _change_scene_with_transition(OUTING_MAP_SCENE_PATH, true)


func return_from_outing_map() -> void:
	if _outing_transition_busy:
		return
	var target_path := outing_return_scene_path.strip_edges()
	if target_path.is_empty() or not ResourceLoader.exists(target_path):
		target_path = OUTING_RETURN_FALLBACK_SCENE_PATH
	await _change_scene_with_transition(target_path, false)
	if _last_scene_change_error == OK:
		outing_return_scene_path = ""
		_save_game_deferred()


func _change_scene_with_transition(scene_path: String, release_mouse_after_load: bool = false) -> void:
	var safe_scene_path := scene_path.strip_edges()
	if safe_scene_path.is_empty() or not ResourceLoader.exists(safe_scene_path):
		push_warning("Outing scene transition target not found: " + safe_scene_path)
		return
	_outing_transition_busy = true
	_last_scene_change_error = OK
	var transition_ui := _ensure_transition_ui()
	if transition_ui != null and transition_ui.has_method("play_scene_transition"):
		await transition_ui.play_scene_transition(
			Callable(self, "_apply_pending_scene_change").bind(safe_scene_path),
			OUTING_TRANSITION_PRESET,
			OUTING_TRANSITION_HOLD_SEC,
			OUTING_TRANSITION_WAIT_FRAMES,
			Callable(self, "_after_outing_scene_change_ready").bind(release_mouse_after_load)
		)
	elif transition_ui != null and transition_ui.has_method("play_action_transition"):
		await transition_ui.play_action_transition(
			Callable(self, "_apply_pending_scene_change").bind(safe_scene_path),
			OUTING_TRANSITION_PRESET,
			OUTING_TRANSITION_HOLD_SEC
		)
		await _wait_scene_change_frames()
		_after_outing_scene_change_ready(release_mouse_after_load)
	else:
		_apply_pending_scene_change(safe_scene_path)
		await _wait_scene_change_frames()
		_after_outing_scene_change_ready(release_mouse_after_load)
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


func _after_outing_scene_change_ready(release_mouse_after_load: bool) -> void:
	if _last_scene_change_error != OK:
		return
	if release_mouse_after_load:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func _wait_scene_change_frames() -> void:
	for _i in range(OUTING_TRANSITION_WAIT_FRAMES):
		await get_tree().process_frame


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


func _build_outing_map_progress_save_payload() -> Dictionary:
	var progress := get_outing_map_progress_runtime()
	if progress == null:
		return {
			"version": 1,
			"unlocked_location_ids": [],
			"discovered_unlock_keys": [],
			"successful_explore_counts": {},
		}
	return {
		"version": 1,
		"unlocked_location_ids": _packed_string_array_to_array(progress.get("unlocked_location_ids")),
		"discovered_unlock_keys": _packed_string_array_to_array(progress.get("discovered_unlock_keys")),
		"successful_explore_counts": (progress.get("successful_explore_counts") as Dictionary).duplicate(true),
	}


func _apply_outing_map_progress_save_payload(payload: Dictionary) -> void:
	var progress := get_outing_map_progress_runtime()
	if progress == null:
		return
	progress.set("unlocked_location_ids", _array_to_unique_packed_string_array(payload.get("unlocked_location_ids", [])))
	progress.set("discovered_unlock_keys", _array_to_unique_packed_string_array(payload.get("discovered_unlock_keys", [])))
	var counts: Variant = payload.get("successful_explore_counts", {})
	progress.set("successful_explore_counts", counts.duplicate(true) if counts is Dictionary else {})


func _packed_string_array_to_array(values: Variant) -> Array[String]:
	var result: Array[String] = []
	for value in values:
		var text := String(value).strip_edges()
		if not text.is_empty() and not result.has(text):
			result.append(text)
	return result


func _array_to_unique_packed_string_array(values: Variant) -> PackedStringArray:
	var result := PackedStringArray()
	for value in values:
		var text := String(value).strip_edges()
		if not text.is_empty() and not result.has(text):
			result.append(text)
	return result


func _save_game_deferred() -> void:
	var save_manager := get_node_or_null("/root/SaveManager")
	if save_manager != null and save_manager.has_method("save_game"):
		save_manager.call_deferred("save_game")


func _build_shelter_inventory_save_payload() -> Dictionary:
	var inventory := get_shelter_inventory_runtime()
	var source_payloads: Array[Dictionary] = []
	if inventory == null:
		return {"version": 1, "sources": source_payloads}
	var sources: Array = inventory.get("storage_sources")
	for source_raw in sources:
		var source := source_raw as Resource
		if source == null:
			continue
		var source_id := String(source.get("source_id")).strip_edges()
		if source_id.is_empty():
			continue
		var storage := _get_storage_from_shelter_source(source)
		source_payloads.append({
			"source_id": source_id,
			"display_name": String(source.get("display_name")),
			"source_kind": String(source.get("source_kind")),
			"include_in_outing_pool": bool(source.get("include_in_outing_pool")),
			"storage": _build_storage_save_payload(storage),
		})
	return {
		"version": 1,
		"sources": source_payloads,
	}


func _apply_shelter_inventory_save_payload(payload: Dictionary) -> void:
	var inventory := get_shelter_inventory_runtime()
	if inventory == null:
		return
	var sources_payload: Array = payload.get("sources", [])
	for source_payload_raw in sources_payload:
		var source_payload := source_payload_raw as Dictionary
		if source_payload.is_empty():
			continue
		var source_id := String(source_payload.get("source_id", "")).strip_edges()
		if source_id.is_empty():
			continue
		var source := _get_shelter_source_by_id(source_id)
		if source == null:
			continue
		var storage_payload := source_payload.get("storage", {}) as Dictionary
		var template_storage := _get_storage_from_shelter_source(source)
		var slot_count := int(storage_payload.get("slot_count", 0))
		var runtime_storage := get_or_create_shelter_storage_runtime(source_id, template_storage, slot_count)
		_apply_storage_save_payload(runtime_storage, storage_payload)
		_bind_storage_to_shelter_source(source, runtime_storage)
	shelter_inventory_changed.emit()


func _build_storage_save_payload(storage: InventoryStorageResource) -> Dictionary:
	var slots_payload: Array[Dictionary] = []
	if storage == null:
		return {"slot_count": 0, "slots": slots_payload}
	storage.ensure_capacity()
	for slot_index in range(storage.slot_count):
		var slot := storage.get_slot(slot_index) as InventorySlotStackResource
		if slot == null or slot.is_empty() or slot.item == null:
			continue
		slots_payload.append({
			"slot_id": slot_index,
			"item_path": String(slot.item.resource_path),
			"amount": int(slot.amount),
		})
	return {
		"slot_count": int(storage.slot_count),
		"slots": slots_payload,
	}


func _apply_storage_save_payload(storage: InventoryStorageResource, payload: Dictionary) -> void:
	if storage == null:
		return
	var slot_count := int(payload.get("slot_count", storage.slot_count))
	if slot_count > 0:
		storage.slot_count = slot_count
	storage.ensure_capacity()
	storage.clear_all()
	var slots_payload: Array = payload.get("slots", [])
	for slot_payload_raw in slots_payload:
		var slot_payload := slot_payload_raw as Dictionary
		if slot_payload.is_empty():
			continue
		var slot_id := int(slot_payload.get("slot_id", -1))
		var item_path := String(slot_payload.get("item_path", "")).strip_edges()
		var amount := int(slot_payload.get("amount", 0))
		if slot_id < 0 or slot_id >= storage.slot_count or item_path.is_empty() or amount <= 0:
			continue
		var item := load(item_path) as ItemData
		if item == null:
			continue
		var slot := storage.get_slot(slot_id) as InventorySlotStackResource
		if slot != null:
			slot.set_stack(item, amount)


func _get_shelter_source_by_id(source_id: String) -> Resource:
	var inventory := get_shelter_inventory_runtime()
	if inventory == null:
		return null
	var sources: Array = inventory.get("storage_sources")
	for source_raw in sources:
		var source := source_raw as Resource
		if source == null:
			continue
		if String(source.get("source_id")).strip_edges() == source_id:
			return source
	return null


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
		var template_storage := _get_storage_from_shelter_source(source)
		var runtime_storage := get_or_create_shelter_storage_runtime(source_id, template_storage)
		if runtime_storage != null:
			_bind_storage_to_shelter_source(source, runtime_storage)


func _get_storage_from_shelter_source(source: Resource) -> InventoryStorageResource:
	if source == null:
		return null
	return source as InventoryStorageResource


func _bind_storage_to_shelter_source(source: Resource, runtime_storage: InventoryStorageResource) -> void:
	if source == null or runtime_storage == null:
		return
	var storage := source as InventoryStorageResource
	if storage == null:
		return
	storage.slot_count = runtime_storage.slot_count
	storage.slots = runtime_storage.slots

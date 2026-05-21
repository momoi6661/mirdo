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
var _time_state_runtime: Dictionary = {}
var _outing_transition_busy: bool = false
var _outing_entry_snapshot_payload: Dictionary = {}
var _outing_pending_delta_payload: Dictionary = {}
var _outing_pending_status_cost: Dictionary = {}
var _pending_scene_change_path: String = ""
var _last_scene_change_error: int = OK

# --- 新增的战利品UI交互信号 ---
signal open_loot_ui(loot_container)
signal close_loot_ui()
signal xiaokong_seat_state_changed(state: Dictionary)
signal xiaokong_dialogue_requested(payload: Dictionary)
signal xiaokong_status_requested(payload: Dictionary)
signal character_inventory_use_requested(payload: Dictionary)
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


func reset_time_state_runtime() -> void:
	_time_state_runtime = _default_time_state()


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
	capture_time_state_from_current_scene()
	return {
		"version": 3,
		"outing_return_scene_path": outing_return_scene_path,
		"shelter_inventory": _build_shelter_inventory_save_payload(),
		"outing_map_progress": _build_outing_map_progress_save_payload(),
		"time_state": _build_time_state_save_payload(),
	}


func apply_global_save_payload(payload: Dictionary) -> void:
	if payload.is_empty():
		return
	outing_return_scene_path = String(payload.get("outing_return_scene_path", "")).strip_edges()
	if payload.has("shelter_inventory") and payload["shelter_inventory"] is Dictionary:
		_apply_shelter_inventory_save_payload(payload["shelter_inventory"])
	if payload.has("outing_map_progress") and payload["outing_map_progress"] is Dictionary:
		_apply_outing_map_progress_save_payload(payload["outing_map_progress"])
	if payload.has("time_state") and payload["time_state"] is Dictionary:
		_apply_time_state_save_payload(payload["time_state"])


func apply_runtime_state_to_current_scene() -> void:
	_bind_shelter_inventory_sources_to_runtime()
	apply_time_state_to_current_scene()


func get_save_scene_path_override(current_scene_path: String = "") -> String:
	var current := current_scene_path.strip_edges()
	if current == OUTING_MAP_SCENE_PATH:
		var target := outing_return_scene_path.strip_edges()
		if not target.is_empty() and ResourceLoader.exists(target):
			return target
		if ResourceLoader.exists(OUTING_RETURN_FALLBACK_SCENE_PATH):
			return OUTING_RETURN_FALLBACK_SCENE_PATH
	return current


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
		capture_time_state_from_current_scene()
		outing_return_scene_path = current_path
	elif outing_return_scene_path.strip_edges().is_empty():
		outing_return_scene_path = OUTING_RETURN_FALLBACK_SCENE_PATH

	var save_manager := _get_save_manager()
	if save_manager != null and save_manager.has_method("save_game"):
		var saved: bool = await save_manager.call("save_game")
		if not saved:
			push_warning("进入外出地图前保存失败，已取消切换，避免角色位置丢失。")
			return
		_outing_entry_snapshot_payload = build_global_save_payload().duplicate(true)
	else:
		push_warning("找不到 SaveManager，无法在进入外出地图前保存。")
		_outing_entry_snapshot_payload = build_global_save_payload().duplicate(true)
	await _change_scene_with_transition(OUTING_MAP_SCENE_PATH, true)


func return_from_outing_map() -> void:
	if _outing_transition_busy:
		return
	_outing_pending_delta_payload = build_global_save_payload().duplicate(true)
	var save_manager := _get_save_manager()
	if save_manager != null and save_manager.has_method("load_game") and save_manager.has_method("save_game"):
		var loaded: bool = await save_manager.call("load_game")
		if loaded:
			_apply_outing_delta_after_return()
			await save_manager.call("save_game")
			return
		push_warning("退出外出地图时加载进入前存档失败，将使用场景切换兜底：" + String(save_manager.get("last_error")))
	var target_path := outing_return_scene_path.strip_edges()
	if target_path.is_empty() or not ResourceLoader.exists(target_path):
		target_path = OUTING_RETURN_FALLBACK_SCENE_PATH
	await _change_scene_with_transition(target_path, false)
	if _last_scene_change_error == OK:
		_apply_outing_delta_after_return()
		_save_game_deferred()


func _apply_outing_delta_after_return() -> void:
	if _outing_pending_delta_payload.is_empty():
		return
	apply_global_save_payload(_outing_pending_delta_payload)
	apply_runtime_state_to_current_scene()
	_apply_pending_outing_status_cost_to_current_scene()
	outing_return_scene_path = ""
	_outing_pending_delta_payload.clear()
	_outing_entry_snapshot_payload.clear()


func record_pending_outing_status_cost(hunger_cost: float, thirst_cost: float, health_damage: float, reason: String = "outing_expedition") -> void:
	_outing_pending_status_cost = {
		"hunger_cost": float(hunger_cost),
		"thirst_cost": float(thirst_cost),
		"health_damage": float(health_damage),
		"reason": reason,
	}


func _apply_pending_outing_status_cost_to_current_scene() -> void:
	if _outing_pending_status_cost.is_empty():
		return
	var state_component := _resolve_player_state_component_in_current_scene()
	if state_component == null or not state_component.has_method("apply_outing_cost"):
		return
	state_component.call(
		"apply_outing_cost",
		float(_outing_pending_status_cost.get("hunger_cost", 0.0)),
		float(_outing_pending_status_cost.get("thirst_cost", 0.0)),
		float(_outing_pending_status_cost.get("health_damage", 0.0)),
		String(_outing_pending_status_cost.get("reason", "outing_expedition"))
	)
	_outing_pending_status_cost.clear()


func _resolve_player_state_component_in_current_scene() -> Node:
	var tree := get_tree()
	if tree == null:
		return null
	for player_raw in tree.get_nodes_in_group("Player"):
		if not is_instance_valid(player_raw) or player_raw is not Node:
			continue
		var state := _get_state_component_from_player(player_raw as Node)
		if state != null:
			return state
	return _find_state_component_recursive(tree.current_scene)


func _get_state_component_from_player(player_node: Node) -> Node:
	if player_node == null or not is_instance_valid(player_node):
		return null
	var state := player_node.get_node_or_null("Components/StateComponent")
	if state != null and is_instance_valid(state):
		return state
	return _find_state_component_recursive(player_node)


func _find_state_component_recursive(root: Node) -> Node:
	if root == null or not is_instance_valid(root):
		return null
	if root.has_method("apply_outing_cost"):
		return root
	for child_raw in root.get_children():
		var child := child_raw as Node
		var found := _find_state_component_recursive(child)
		if found != null:
			return found
	return null


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


func _get_save_manager() -> Node:
	return get_node_or_null("/root/SaveManager")


func _save_game_deferred() -> void:
	var save_manager := get_node_or_null("/root/SaveManager")
	if save_manager != null and save_manager.has_method("save_game"):
		save_manager.call_deferred("save_game")


func capture_time_state_from_current_scene() -> Dictionary:
	var time_component := _find_time_component_in_tree()
	if time_component == null:
		return _time_state_runtime.duplicate(true)
	_time_state_runtime = _build_time_state_from_component(time_component)
	return _time_state_runtime.duplicate(true)


func apply_time_state_to_current_scene() -> void:
	if _time_state_runtime.is_empty():
		return
	var time_component := _find_time_component_in_tree()
	if time_component == null:
		return
	_apply_time_state_to_component(time_component, _time_state_runtime)


func advance_outing_time_minutes(minutes: int, reason: String = "outing_map") -> Dictionary:
	var safe_minutes := maxi(0, minutes)
	var time_component := _find_time_component_in_tree()
	if time_component != null:
		if time_component.has_method("pass_minutes"):
			var result = time_component.call("pass_minutes", float(safe_minutes), reason)
			_time_state_runtime = _build_time_state_from_component(time_component)
			return result as Dictionary if result is Dictionary else _time_state_runtime.duplicate(true)
	_time_state_runtime = _advance_time_state_payload(_ensure_time_state_runtime(), safe_minutes, reason)
	return _time_state_runtime.duplicate(true)


func _build_time_state_save_payload() -> Dictionary:
	var state := _ensure_time_state_runtime()
	return state.duplicate(true)


func _apply_time_state_save_payload(payload: Dictionary) -> void:
	var state := _default_time_state()
	for key in payload.keys():
		state[key] = payload[key]
	state["version"] = 1
	state["current_day"] = maxi(1, int(state.get("current_day", 1)))
	state["day_length_hours"] = clampf(float(state.get("day_length_hours", 24.0)), 1.0, 48.0)
	state["current_hour"] = clampf(float(state.get("current_hour", 8.0)), 0.0, maxf(float(state.get("day_length_hours", 24.0)) - 0.0001, 0.0))
	state["realtime_enabled"] = bool(state.get("realtime_enabled", false))
	_time_state_runtime = state


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
		return {"version": 1, "slot_count": 0, "slots": slots_payload}
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
		"version": 1,
		"slot_count": int(storage.slot_count),
		"slots": slots_payload,
		# 空柜不再自动写成“权威清空”。
		# 之前的实现会在场景绑定/过滤异常时把食品柜保存成 authoritative_empty=true，
		# 下次读档就把 .tres 默认库存永久覆盖为空。
		"is_empty_snapshot": slots_payload.is_empty(),
	}


func _apply_storage_save_payload(storage: InventoryStorageResource, payload: Dictionary) -> void:
	if storage == null:
		return
	if _should_ignore_legacy_empty_storage_payload(storage, payload):
		storage.ensure_capacity()
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


func _should_ignore_legacy_empty_storage_payload(storage: InventoryStorageResource, payload: Dictionary) -> bool:
	if payload.is_empty():
		return false
	var source_id := String(storage.source_id).strip_edges()
	if not _is_default_preserved_storage_source(source_id):
		return false
	var slots_payload: Array = payload.get("slots", [])
	if not slots_payload.is_empty():
		return false
	if bool(payload.get("allow_default_clear", false)):
		return false
	if _default_storage_has_items(source_id):
		return true
	storage.ensure_capacity()
	for i in range(storage.slot_count):
		var slot := storage.get_slot(i) as InventorySlotStackResource
		if slot != null and not slot.is_empty():
			return true
	return false


func _is_default_preserved_storage_source(source_id: String) -> bool:
	# 食品柜是场景内可视化实体柜，默认 .tres 里应始终带初始水/罐头。
	# 没有显式 allow_default_clear 的空存档一律按旧/异常存档处理，避免再次把默认物资读没。
	return source_id == "food_cabinet" or source_id == "food_cabinet_2"


func _default_storage_has_items(source_id: String) -> bool:
	var template := load(SHELTER_INVENTORY_DEFAULT_PATH) as Resource
	if template == null:
		return false
	template = template.duplicate(true) as Resource
	if template == null:
		return false
	var sources: Array = template.get("storage_sources")
	for source_raw in sources:
		var source := source_raw as Resource
		if source == null or String(source.get("source_id")).strip_edges() != source_id:
			continue
		var storage := source as InventoryStorageResource
		if storage == null:
			return false
		storage.ensure_capacity()
		for i in range(storage.slot_count):
			var slot := storage.get_slot(i) as InventorySlotStackResource
			if slot != null and not slot.is_empty():
				return true
	return false


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


func _ensure_time_state_runtime() -> Dictionary:
	if _time_state_runtime.is_empty():
		var time_component := _find_time_component_in_tree()
		if time_component != null:
			_time_state_runtime = _build_time_state_from_component(time_component)
		else:
			_time_state_runtime = _default_time_state()
	return _time_state_runtime.duplicate(true)


func _default_time_state() -> Dictionary:
	return {
		"version": 1,
		"current_day": 1,
		"current_hour": 8.0,
		"day_length_hours": 24.0,
		"realtime_enabled": false,
		"reason": "default",
	}


func _find_time_component_in_tree() -> Node:
	var tree := get_tree()
	if tree == null:
		return null
	for node_raw in tree.get_nodes_in_group("TimeSource"):
		var node := node_raw as Node
		if _is_time_component(node):
			return node
	var current_scene := tree.current_scene
	return _find_time_component_recursive(current_scene)


func _find_time_component_recursive(root_node: Node) -> Node:
	if root_node == null:
		return null
	if _is_time_component(root_node):
		return root_node
	for child_raw in root_node.get_children():
		var child := child_raw as Node
		var found := _find_time_component_recursive(child)
		if found != null:
			return found
	return null


func _is_time_component(node: Node) -> bool:
	return node != null and node.has_method("get_day_time_text") and node.has_method("pass_minutes")


func _build_time_state_from_component(time_component: Node) -> Dictionary:
	var day_length := 24.0
	var current_hour := 8.0
	if time_component != null:
		day_length = clampf(float(time_component.get("day_length_hours")), 1.0, 48.0)
		current_hour = clampf(float(time_component.get("current_hour")), 0.0, maxf(day_length - 0.0001, 0.0))
	return {
		"version": 1,
		"current_day": maxi(1, int(time_component.get("current_day")) if time_component != null else 1),
		"current_hour": current_hour,
		"day_length_hours": day_length,
		"realtime_enabled": bool(time_component.get("realtime_enabled")) if time_component != null else false,
		"reason": "scene_capture",
	}


func _apply_time_state_to_component(time_component: Node, state: Dictionary) -> void:
	if time_component == null or state.is_empty():
		return
	var day_length := clampf(float(state.get("day_length_hours", time_component.get("day_length_hours"))), 1.0, 48.0)
	var hour_value := clampf(float(state.get("current_hour", time_component.get("current_hour"))), 0.0, maxf(day_length - 0.0001, 0.0))
	var hour_int := int(floor(hour_value))
	var minute_int := clampi(int(round((hour_value - float(hour_int)) * 60.0)), 0, 59)
	time_component.set("day_length_hours", day_length)
	if time_component.has_method("set_day_time"):
		time_component.call("set_day_time", maxi(1, int(state.get("current_day", 1))), hour_int, minute_int, "global_save_restore")
	else:
		time_component.set("current_day", maxi(1, int(state.get("current_day", 1))))
		time_component.set("current_hour", hour_value)
	if time_component.has_method("set_realtime_enabled"):
		time_component.call("set_realtime_enabled", bool(state.get("realtime_enabled", time_component.get("realtime_enabled"))))
	else:
		time_component.set("realtime_enabled", bool(state.get("realtime_enabled", false)))


func _advance_time_state_payload(state: Dictionary, minutes: int, reason: String) -> Dictionary:
	var next := _default_time_state()
	for key in state.keys():
		next[key] = state[key]
	var day_length := clampf(float(next.get("day_length_hours", 24.0)), 1.0, 48.0)
	var total_hours := float(next.get("current_hour", 8.0)) + (float(maxi(0, minutes)) / 60.0)
	var day_wraps := int(floor(total_hours / day_length))
	next["current_day"] = maxi(1, int(next.get("current_day", 1)) + day_wraps)
	next["current_hour"] = fposmod(total_hours, day_length)
	next["reason"] = reason
	return next

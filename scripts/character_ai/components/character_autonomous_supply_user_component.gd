extends Node
class_name CharacterAutonomousSupplyUserComponent

signal supply_need_started(need: String, target_object_id: String, item_name: String)
signal supply_item_taken(need: String, target_object_id: String, item_name: String, remaining: int)
signal supply_need_finished(report: Dictionary)
signal supply_need_skipped(reason: String)

@export var enabled: bool = true
@export var state_component_path: NodePath = NodePath("../StateComponent")
@export var action_executor_path: NodePath = NodePath("../CharacterAIActionExecutor")
@export var action_scheduler_path: NodePath = NodePath("../CharacterActionScheduler")
@export var item_consumer_path: NodePath = NodePath("../ItemConsumer")
@export var autonomous_life_path: NodePath = NodePath("../CharacterAutonomousLife")
@export var face_component_path: NodePath = NodePath("../FaceComponent")
@export var actor_path: NodePath = NodePath("../..")
@export var world_object_group: StringName = &"ai_world_object"

@export_category("Need Thresholds")
@export_range(0.0, 100.0, 1.0) var thirst_trigger_threshold: float = 45.0
@export_range(0.0, 100.0, 1.0) var hunger_trigger_threshold: float = 45.0
@export_range(0.0, 100.0, 1.0) var satisfied_threshold: float = 70.0
@export_range(1.0, 300.0, 1.0) var check_interval_sec: float = 6.0
@export_range(1.0, 600.0, 1.0) var success_cooldown_sec: float = 80.0
@export_range(1.0, 600.0, 1.0) var failure_cooldown_sec: float = 25.0

@export_category("Actions")
@export var inspect_action: StringName = &"work_inspect_cabinet"
@export var take_action: StringName = &"work_take_item"
@export var consume_action: StringName = &"work_drink"
@export var return_action: StringName = &"idle_normal"
@export var positive_expression: StringName = &"face_joy"
@export var fun_expression: StringName = &"face_fun"
@export var disappointed_expression: StringName = &"face_sorrow"
@export_range(0.1, 6.0, 0.05) var inspect_wait_fallback_sec: float = 1.2
@export_range(0.1, 6.0, 0.05) var take_wait_fallback_sec: float = 0.85
@export_range(0.1, 8.0, 0.05) var navigation_timeout_sec: float = 18.0

@export_category("Item Preference")
@export var water_item_names: PackedStringArray = PackedStringArray(["瓶装水", "water", "water_bottle"])
@export var food_item_names: PackedStringArray = PackedStringArray(["罐头", "can", "can_soup", "energy_bar", "能量棒"])
@export var food_object_tags: PackedStringArray = PackedStringArray(["food", "supplies", "cabinet", "storage"])
@export var debug_log: bool = false

var _state_component: Node
var _action_executor: Node
var _action_scheduler: Node
var _item_consumer: Node
var _autonomous_life: Node
var _face_component: Node
var _actor: Node3D
var _check_left: float = 0.0
var _cooldown_left: float = 0.0
var _busy: bool = false
var _pending: Dictionary = {}
var _navigation_done: bool = false
var _navigation_ok: bool = false

func _ready() -> void:
	_refresh_refs()
	_check_left = randf_range(1.0, maxf(1.1, check_interval_sec))
	_bind_executor_signals()
	set_process(true)

func _process(delta: float) -> void:
	if not enabled:
		return
	_check_left = maxf(0.0, _check_left - delta)
	_cooldown_left = maxf(0.0, _cooldown_left - delta)
	if _busy or _check_left > 0.0:
		return
	_check_left = check_interval_sec
	if _cooldown_left > 0.0:
		return
	_try_start_supply_need()

func force_check_now() -> bool:
	_refresh_refs()
	if _busy:
		return false
	return _try_start_supply_need(true)

func is_busy() -> bool:
	return _busy

func _try_start_supply_need(ignore_cooldown: bool = false) -> bool:
	_refresh_refs()
	if _state_component == null:
		_skip("state_missing")
		return false
	if not ignore_cooldown and _cooldown_left > 0.0:
		return false
	var need := _choose_need()
	if need.is_empty():
		return false
	var target := _find_supply_target(need)
	if target.is_empty():
		_cooldown_left = failure_cooldown_sec
		_skip("no_supply_target")
		return false
	_busy = true
	_pending = target.duplicate(true)
	_pending["need"] = need
	_notify_external_control()
	supply_need_started.emit(need, String(target.get("object_id", "")), _item_name(target.get("item", null)))
	_run_supply_flow(_pending.duplicate(true))
	return true

func _run_supply_flow(task: Dictionary) -> void:
	var report := {
		"ok": false,
		"need": String(task.get("need", "")),
		"target_object_id": String(task.get("object_id", "")),
		"item_name": _item_name(task.get("item", null)),
		"error": "",
	}
	_apply_expression(fun_expression)
	var nav_ok := await _navigate_to_supply(task)
	if not nav_ok:
		report["error"] = "navigation_failed"
		_finish_supply(report, false)
		return
	await _play_action(inspect_action, inspect_wait_fallback_sec)
	var taken := _take_one_item_from_task(task)
	if taken.is_empty():
		report["error"] = "item_unavailable"
		_apply_expression(disappointed_expression)
		_finish_supply(report, false)
		return
	_apply_expression(positive_expression)
	var loose_object := taken.get("loose_object", null) as Node
	var consume_report: Dictionary
	if loose_object != null:
		# CharacterPickableItemComponent owns the take animation, visual attachment,
		# consumption and world-item cleanup for loose objects.
		consume_report = await _pick_up_loose_item(loose_object, task)
	else:
		await _play_action(take_action, take_wait_fallback_sec)
		var item: Resource = taken.get("item", null) as Resource
		consume_report = _consume_item(item, "mirdo_autonomous_supply_%s" % String(task.get("need", "")))
	report["consume_report"] = consume_report
	report["ok"] = bool(consume_report.get("ok", false))
	if not bool(report["ok"]):
		report["error"] = String(consume_report.get("error", "consume_failed"))
	_finish_supply(report, bool(report["ok"]))

func _navigate_to_supply(task: Dictionary) -> bool:
	_refresh_refs()
	if _action_executor == null or not _action_executor.has_method("apply_ai_response"):
		return false
	_navigation_done = false
	_navigation_ok = false
	var object_id := String(task.get("object_id", "")).strip_edges()
	var marker_path := String(task.get("marker_path", "")).strip_edges()
	var is_loose_item := task.get("loose_object", null) != null
	var navigation_command := "pick_up_item" if is_loose_item else "go_to_object"
	var payload := {
		"command": navigation_command,
		"intent": navigation_command,
		"target_object": object_id,
		"target_object_id": object_id,
		"target_marker_path": marker_path,
		"marker_role": "approach",
		"action": String(return_action),
		"expression": String(fun_expression),
	}
	var result_value: Variant = _action_executor.call("apply_ai_response", payload)
	var result: Dictionary = result_value if result_value is Dictionary else {}
	if not bool(result.get("navigation_started", false)):
		# 如果已经很近，executor 可能直接给动作；允许后续继续。
		if bool(result.get("action_applied", false)):
			return true
		return false
	var elapsed := 0.0
	while elapsed < navigation_timeout_sec:
		await get_tree().process_frame
		elapsed += get_process_delta_time()
		if _navigation_done:
			return _navigation_ok
		if _action_executor != null and _action_executor.has_method("is_navigating") and not bool(_action_executor.call("is_navigating")):
			return true
	return false

func _play_action(action_name: StringName, fallback_duration: float) -> void:
	_refresh_refs()
	if action_name == &"":
		return
	if _action_scheduler != null and _action_scheduler.has_method("request_action"):
		_action_scheduler.call("request_action", action_name, 20, "autonomous_supply", &"")
		var wait_time := _action_duration(action_name, fallback_duration)
		if wait_time > 0.0 and is_inside_tree():
			await get_tree().create_timer(wait_time).timeout
		return
	_request_body_action(action_name)
	var duration := _action_duration(action_name, fallback_duration)
	if duration > 0.0 and is_inside_tree():
		await get_tree().create_timer(duration).timeout

func _take_one_item_from_task(task: Dictionary) -> Dictionary:
	var loose_object := task.get("loose_object", null) as Node
	if loose_object != null:
		var loose_item := task.get("item", null) as ItemData
		if loose_item == null or not is_instance_valid(loose_object):
			return {}
		return {"item": loose_item, "loose_object": loose_object, "remaining": 0}
	var container := task.get("container", null) as Node
	var storage := _resolve_container_storage(container)
	if storage == null:
		return {}
	var need := String(task.get("need", ""))
	var slot := _find_item_slot(storage, need)
	if slot.is_empty():
		return {}
	var stack := slot.get("stack", null) as InventorySlotStackResource
	var item := slot.get("item", null) as ItemData
	if stack == null or item == null:
		return {}
	stack.amount = maxi(0, stack.amount - 1)
	var remaining := stack.amount
	if stack.amount <= 0:
		stack.clear()
	_notify_container_changed(container)
	_notify_shelter_changed()
	supply_item_taken.emit(need, String(task.get("object_id", "")), _item_name(item), remaining)
	return {"item": item, "remaining": remaining}

func _consume_item(item: Resource, reason: String) -> Dictionary:
	_refresh_refs()
	if item == null:
		return {"ok": false, "error": "item_null"}
	if _item_consumer == null or not _item_consumer.has_method("consume_item"):
		return {"ok": false, "error": "consumer_missing"}
	return _item_consumer.call("consume_item", item, reason) as Dictionary

func _pick_up_loose_item(loose_object: Node, task: Dictionary) -> Dictionary:
	if loose_object == null or not is_instance_valid(loose_object):
		return {"ok": false, "error": "pickable_missing"}
	if not loose_object.has_method("pick_up_by"):
		_log("loose item has no pick_up_by: %s" % String(loose_object.name))
		return {"ok": false, "error": "pickable_missing"}
	if loose_object.has_method("can_be_picked_by") and not bool(loose_object.call("can_be_picked_by", _actor)):
		return {"ok": false, "error": "item_not_pickable"}
	var reason := "mirdo_autonomous_supply_%s" % String(task.get("need", ""))
	var result_value: Variant = await loose_object.call("pick_up_by", _actor, reason)
	var result: Dictionary = result_value if result_value is Dictionary else {}
	if result.is_empty():
		return {"ok": false, "error": "pick_up_invalid_result"}
	if bool(result.get("ok", false)):
		supply_item_taken.emit(
			String(task.get("need", "")),
			String(task.get("object_id", "")),
			_item_name(task.get("item", null)),
			0,
		)
	return result

func _finish_supply(report: Dictionary, success: bool) -> void:
	_busy = false
	_pending = {}
	_cooldown_left = success_cooldown_sec if success else failure_cooldown_sec
	if not success:
		_request_body_action(return_action)
	supply_need_finished.emit(report.duplicate(true))
	_log("finish: %s" % str(report))

func _choose_need() -> String:
	var snapshot := _get_stats_snapshot()
	if snapshot.is_empty():
		return ""
	var thirst := float(snapshot.get("thirst", 100.0))
	var hunger := float(snapshot.get("hunger", 100.0))
	if thirst <= thirst_trigger_threshold and thirst <= hunger:
		return "thirst"
	if hunger <= hunger_trigger_threshold:
		return "hunger"
	if thirst <= thirst_trigger_threshold:
		return "thirst"
	return ""

func _get_stats_snapshot() -> Dictionary:
	_refresh_refs()
	if _state_component != null and _state_component.has_method("get_snapshot"):
		var value: Variant = _state_component.call("get_snapshot")
		return value as Dictionary if value is Dictionary else {}
	return {}

func _find_supply_target(need: String) -> Dictionary:
	var tree := get_tree()
	if tree == null:
		return {}
	var best := {}
	var best_score := INF
	for entry in tree.get_nodes_in_group(world_object_group):
		var object_node := entry as Node
		if object_node == null or not is_instance_valid(object_node):
			continue
		if not _is_food_supply_object(object_node):
			continue
		var container := _find_container_component(object_node)
		var storage := _resolve_container_storage(container)
		if storage == null:
			continue
		var slot := _find_item_slot(storage, need)
		if slot.is_empty():
			continue
		var marker := _resolve_object_marker(object_node)
		var distance := _actor.global_position.distance_to((marker as Node3D).global_position) if _actor != null and marker != null else 0.0
		var score := distance
		if score < best_score:
			best_score = score
			best = {
				"object": object_node,
				"object_id": _get_world_object_id(object_node),
				"container": container,
				"storage": storage,
				"item": slot.get("item", null),
				"marker_path": String(marker.get_path()) if marker != null and marker.is_inside_tree() else "",
			}
	for entry in tree.get_nodes_in_group(&"ai_pickable_item"):
		var object_node := entry as Node
		if not _is_valid_loose_item_candidate(object_node):
			continue
		var item := _resolve_pickable_item_data(object_node)
		if item == null or not _item_matches_need(item, need):
			continue
		var marker := _resolve_object_marker(object_node)
		if marker == null:
			continue
		var distance := _actor.global_position.distance_to(marker.global_position) if _actor != null else 0.0
		var score := distance
		if score < best_score:
			best_score = score
			best = {
				"object": object_node,
				"object_id": _get_pickable_item_id(object_node, item),
				"loose_object": object_node,
				"item": item,
				"marker_path": String(marker.get_path()) if marker.is_inside_tree() else "",
			}
	return best

func _is_valid_loose_item_candidate(object_node: Node) -> bool:
	if object_node == null or not is_instance_valid(object_node) or not object_node.is_inside_tree():
		return false
	if not object_node.has_method("pick_up_by"):
		return false
	if object_node.has_method("can_be_picked_by") and not bool(object_node.call("can_be_picked_by", _actor)):
		return false
	var item_root := _resolve_pickable_item_root(object_node)
	if item_root != null and not item_root.visible:
		return false
	return true

func _resolve_pickable_item_data(object_node: Node) -> ItemData:
	if object_node == null:
		return null
	if object_node.has_method("_resolve_item_data"):
		var resolved_value: Variant = object_node.call("_resolve_item_data")
		if resolved_value is ItemData:
			return resolved_value as ItemData
	var cursor: Node = object_node
	var depth := 0
	while cursor != null and depth < 8:
		var value: Variant = _safe_get(cursor, "item_data", null)
		if value is ItemData:
			return value as ItemData
		cursor = cursor.get_parent()
		depth += 1
	return null

func _resolve_pickable_item_root(object_node: Node) -> Node3D:
	if object_node == null:
		return null
	if object_node.has_method("_resolve_item_root"):
		var resolved_value: Variant = object_node.call("_resolve_item_root")
		if resolved_value is Node3D:
			return resolved_value as Node3D
	var cursor: Node = object_node
	var depth := 0
	while cursor != null and depth < 8:
		if _safe_get(cursor, "item_data", null) is ItemData:
			return cursor as Node3D
		cursor = cursor.get_parent()
		depth += 1
	return null

func _get_pickable_item_id(object_node: Node, item: ItemData) -> String:
	if object_node != null and object_node.has_method("build_ai_pickable_summary"):
		var summary_value: Variant = object_node.call("build_ai_pickable_summary", _actor)
		if summary_value is Dictionary:
			var summary_id := String((summary_value as Dictionary).get("id", "")).strip_edges()
			if not summary_id.is_empty():
				return summary_id
	if item != null:
		var item_name := String(item.ItemName).strip_edges()
		if not item_name.is_empty():
			return item_name.to_snake_case()
	return _get_world_object_id(_resolve_pickable_item_root(object_node) if object_node != null else null)

func _is_food_supply_object(node: Node) -> bool:
	if node == null:
		return false
	var object_type := String(_safe_get(node, "object_type", "")).strip_edges().to_lower()
	if object_type == "food":
		return true
	var container := _find_container_component(node)
	if container != null:
		var source_kind := String(_safe_get(_resolve_container_storage(container), "source_kind", "")).strip_edges().to_lower()
		var shelter_source := String(_safe_get(container, "shelter_source_id", "")).strip_edges().to_lower()
		if source_kind == "food" or shelter_source.begins_with("food_cabinet"):
			return true
	var tags: Variant = _safe_get(node, "tags", [])
	if tags is Array or tags is PackedStringArray:
		for raw in tags:
			if String(raw).strip_edges().to_lower() == "food":
				return true
	return false

func _find_container_component(root: Node) -> Node:
	if root == null:
		return null
	if root.has_method("notify_runtime_slots_changed") or root.has_method("build_inventory_save_payload"):
		return root
	for child in root.get_children():
		var node := child as Node
		var found := _find_container_component(node)
		if found != null:
			return found
	return null

func _resolve_container_storage(container: Node) -> InventoryStorageResource:
	if container == null:
		return null
	if container.has_method("_ensure_runtime_storage"):
		container.call("_ensure_runtime_storage")
	var runtime_value: Variant = _safe_get(container, "_runtime_inventory_storage", null)
	if runtime_value is InventoryStorageResource:
		var storage := runtime_value as InventoryStorageResource
		storage.ensure_capacity()
		return storage
	var storage_value: Variant = _safe_get(container, "inventory_storage", null)
	if storage_value is InventoryStorageResource:
		var fallback := storage_value as InventoryStorageResource
		fallback.ensure_capacity()
		return fallback
	return null

func _find_item_slot(storage: InventoryStorageResource, need: String) -> Dictionary:
	if storage == null:
		return {}
	storage.ensure_capacity()
	for i in range(storage.slot_count):
		var stack := storage.get_slot(i) as InventorySlotStackResource
		if stack == null or stack.is_empty():
			continue
		var item := stack.item
		if _item_matches_need(item, need):
			return {"index": i, "stack": stack, "item": item, "amount": stack.amount}
	return {}

func _item_matches_need(item: ItemData, need: String) -> bool:
	if item == null:
		return false
	var delta := item.get_consumable_delta() if item.has_method("get_consumable_delta") else {}
	if need == "thirst" and float(delta.get("thirst", delta.get("ai_thirst", 0.0))) > 0.0:
		return true
	if need == "hunger" and float(delta.get("hunger", delta.get("ai_hunger", 0.0))) > 0.0:
		return true
	var name := String(item.ItemName).strip_edges().to_lower()
	var prefs := water_item_names if need == "thirst" else food_item_names
	for wanted in prefs:
		var wanted_text := String(wanted).strip_edges().to_lower()
		if not wanted_text.is_empty() and name.find(wanted_text) != -1:
			return true
	return false

func _resolve_object_marker(object_node: Node) -> Marker3D:
	if object_node == null:
		return null
	if object_node.has_method("get_marker_for_role"):
		var role_marker: Variant = object_node.call("get_marker_for_role", "approach")
		if role_marker is Marker3D:
			return role_marker as Marker3D
	if object_node.has_method("get_nav_marker"):
		var nav_marker: Variant = object_node.call("get_nav_marker")
		if nav_marker is Marker3D:
			return nav_marker as Marker3D
	return object_node as Marker3D

func _notify_container_changed(container: Node) -> void:
	if container == null:
		return
	if container.has_method("notify_runtime_slots_changed"):
		container.call("notify_runtime_slots_changed")

func _notify_shelter_changed() -> void:
	var global_node := get_node_or_null("/root/Global")
	if global_node != null and global_node.has_method("notify_shelter_inventory_changed"):
		global_node.call("notify_shelter_inventory_changed")

func _notify_external_control() -> void:
	_refresh_refs()
	if _autonomous_life != null and _autonomous_life.has_method("notify_external_control"):
		_autonomous_life.call("notify_external_control")

func _request_body_action(action_name: StringName) -> bool:
	_refresh_refs()
	if _action_scheduler != null and _action_scheduler.has_method("request_action"):
		return bool(_action_scheduler.call("request_action", action_name, 10, "autonomous_supply", &""))
	var behavior := _find_sibling_with_method(&"request_action")
	if behavior != null and behavior.has_method("request_state") and bool(behavior.call("request_state", action_name)):
		return true
	if behavior != null and behavior.has_method("request_action"):
		return bool(behavior.call("request_action", action_name))
	return false

func _action_duration(action_name: StringName, fallback: float) -> float:
	var behavior := _find_sibling_with_method(&"get_action_duration")
	if behavior != null and behavior.has_method("get_action_duration"):
		return maxf(0.05, float(behavior.call("get_action_duration", action_name, fallback)))
	return fallback

func _apply_expression(expression: StringName) -> bool:
	_refresh_refs()
	if expression == &"" or _face_component == null:
		return false
	if _face_component.has_method("set_face_expression"):
		return bool(_face_component.call("set_face_expression", expression))
	if _face_component.has_method("set_expression"):
		return bool(_face_component.call("set_expression", expression))
	return false

func _bind_executor_signals() -> void:
	_refresh_refs()
	if _action_executor == null:
		return
	if _action_executor.has_signal("navigation_finished"):
		var cb := Callable(self, "_on_executor_navigation_finished")
		if not _action_executor.is_connected("navigation_finished", cb):
			_action_executor.connect("navigation_finished", cb)
	if _action_executor.has_signal("navigation_cancelled"):
		var cb2 := Callable(self, "_on_executor_navigation_cancelled")
		if not _action_executor.is_connected("navigation_cancelled", cb2):
			_action_executor.connect("navigation_cancelled", cb2)

func _on_executor_navigation_finished(_arrival_action: StringName = &"") -> void:
	_navigation_done = true
	_navigation_ok = true

func _on_executor_navigation_cancelled() -> void:
	_navigation_done = true
	_navigation_ok = false

func _get_world_object_id(node: Node) -> String:
	if node == null:
		return ""
	var value: Variant = _safe_get(node, "object_id", null)
	if value != null:
		var text := str(value).strip_edges()
		if not text.is_empty():
			return text
	return String(node.name)

func _item_name(item_value: Variant) -> String:
	var item := item_value as ItemData
	if item != null:
		return String(item.ItemName)
	return ""

func _safe_get(object: Object, property_name: String, fallback: Variant = null) -> Variant:
	if object == null:
		return fallback
	for info in object.get_property_list():
		if String((info as Dictionary).get("name", "")) == property_name:
			return object.get(property_name)
	return fallback

func _refresh_refs() -> void:
	_state_component = get_node_or_null(state_component_path) if state_component_path != NodePath() else null
	_action_executor = get_node_or_null(action_executor_path) if action_executor_path != NodePath() else null
	_action_scheduler = get_node_or_null(action_scheduler_path) if action_scheduler_path != NodePath() else null
	_item_consumer = get_node_or_null(item_consumer_path) if item_consumer_path != NodePath() else null
	_autonomous_life = get_node_or_null(autonomous_life_path) if autonomous_life_path != NodePath() else null
	_face_component = get_node_or_null(face_component_path) if face_component_path != NodePath() else null
	_actor = get_node_or_null(actor_path) as Node3D if actor_path != NodePath() else null
	if _state_component == null:
		_state_component = _find_sibling_with_method(&"get_snapshot")
	if _action_executor == null:
		_action_executor = _find_sibling_with_method(&"apply_ai_response")
	if _action_scheduler == null:
		_action_scheduler = _find_sibling_with_method(&"request_sequence")
	if _item_consumer == null:
		_item_consumer = _find_sibling_with_method(&"consume_item")
	if _autonomous_life == null:
		_autonomous_life = _find_sibling_with_method(&"notify_external_control")
	if _face_component == null:
		_face_component = _find_sibling_with_method(&"set_face_expression")
	if _actor == null:
		_actor = _find_actor_from_parent()

func _find_sibling_with_method(method_name: StringName) -> Node:
	var parent_node := get_parent()
	if parent_node == null:
		return null
	for child in parent_node.get_children():
		var node := child as Node
		if node != null and node != self and node.has_method(method_name):
			return node
	return null

func _find_actor_from_parent() -> Node3D:
	var cursor := get_parent()
	while cursor != null:
		if cursor is Node3D and (cursor.is_in_group(&"AICharacter") or cursor.is_in_group(&"Mirdo") or cursor is CharacterBody3D):
			return cursor as Node3D
		cursor = cursor.get_parent()
	return null

func _skip(reason: String) -> void:
	supply_need_skipped.emit(reason)
	_log("skip: %s" % reason)

func _log(message: String) -> void:
	if debug_log:
		print("[CharacterAutonomousSupplyUser] %s" % message)

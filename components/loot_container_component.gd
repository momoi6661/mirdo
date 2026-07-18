class_name LootContainerComponent
extends Node3D

const INVENTORY_STORAGE_SCRIPT := preload("res://scripts/Inventory/inventory_storage_resource.gd")

@export_category("Loot Settings")
@export var container_name: String = "Loot Crate"
@export var container_size: int = 16 
@export var interaction_time: float = 1.5 
@export var initial_loot: Array[SlotConfig] = [] 
@export var enable_item_stacking: bool = false
@export var inventory_storage: InventoryStorageResource
@export var allowed_item_categories: PackedStringArray = PackedStringArray()
@export var allowed_item_tags: PackedStringArray = PackedStringArray()
@export var reject_disallowed_items: bool = true
@export var allow_incoming_items: bool = true

@export_category("Shelter Inventory")
@export var use_shelter_inventory_runtime: bool = false
@export var shelter_source_id: StringName = &""

@export_category("World Display")
@export var world_display_enabled: bool = false
@export var display_root_path: NodePath
@export var display_slot_markers_root_path: NodePath
@export_range(1, 32, 1) var display_max_models: int = 6
@export_range(0.02, 2.0, 0.01) var display_fit_size: float = 0.25
@export_range(0.05, 5.0, 0.01) var display_scale_multiplier: float = 1.0
@export_range(-180.0, 180.0, 1.0) var display_base_yaw_deg: float = 0.0
@export_range(-180.0, 180.0, 1.0) var display_yaw_step_deg: float = 26.0
@export var display_slots_local_positions: Array = [
	Vector3(-0.08, 0.40, 0.0),
	Vector3(0.08, 0.40, 0.0),
	Vector3(-0.08, 1.02, 0.0),
	Vector3(0.08, 1.02, 0.0),
	Vector3(-0.08, 1.64, 0.0),
	Vector3(0.08, 1.64, 0.0),
]

var runtime_slots: Array[SlotConfig] = []
var _display_root: Node3D
var _runtime_inventory_storage: InventoryStorageResource
const DISPLAY_EPSILON := 0.00001

func _ready() -> void:
	_ensure_runtime_storage()
	_sanitize_runtime_storage_items()
	_rebuild_runtime_slots_from_storage()
	_sync_runtime_storage_from_runtime_slots()
	_refresh_world_display()

# ==========================================
# 交互接口
# ==========================================
func get_interaction_time() -> float:
	return interaction_time

func get_prompt_text() -> String:
	return "搜索: " + container_name

func interact(_player: Node) -> void:
	var global_node := get_node_or_null("/root/Global")
	if global_node != null and global_node.has_signal("open_loot_ui"):
		global_node.emit_signal("open_loot_ui", self)

func notify_runtime_slots_changed() -> void:
	_rebuild_runtime_slots_from_storage()
	_refresh_world_display()
	_notify_shelter_runtime_changed()


## 供 AI 角色从真实容器库存中取物。成功后会同步运行时库存、世界展示和存档源，
## 因而不是只播放“拿东西”动画：对应格子的数量一定会减少。
func take_item_for_ai(item_ref: String, amount: int = 1) -> Dictionary:
	_ensure_runtime_storage()
	_rebuild_runtime_slots_from_storage()
	var wanted := item_ref.strip_edges().to_lower()
	var take_amount := maxi(1, amount)
	for slot in runtime_slots:
		if slot == null or slot.item == null or slot.amount <= 0:
			continue
		if not wanted.is_empty() and not _item_matches_ai_ref(slot.item, wanted):
			continue
		var removed := mini(take_amount, slot.amount)
		var item := slot.item
		slot.amount -= removed
		if slot.amount <= 0:
			slot.item = null
			slot.amount = 0
		_sync_runtime_storage_from_runtime_slots()
		_rebuild_runtime_slots_from_storage()
		_refresh_world_display()
		return {"ok": true, "item": item, "amount": removed, "remaining": slot.amount}
	return {"ok": false, "error": "container_item_not_found", "item_ref": item_ref}


## 给 AI 的只读库存摘要；不暴露 Item 资源路径，也不修改库存。
## 真正取物仍必须调用 take_item_for_ai()，成功后数量才会减少。
func build_ai_inventory_snapshot() -> Dictionary:
	_ensure_runtime_storage()
	_rebuild_runtime_slots_from_storage()
	var items: Array = []
	for slot in runtime_slots:
		if slot == null or slot.item == null or slot.amount <= 0:
			continue
		items.append({
			"id": String(slot.item.ItemName).strip_edges(),
			"name": String(slot.item.ItemName).strip_edges(),
			"amount": int(slot.amount),
			"category": String(slot.item.outing_category).strip_edges(),
		})
	return {"items": items, "item_count": items.size()}


func _item_matches_ai_ref(item: ItemData, wanted: String) -> bool:
	var text := "%s %s %s" % [String(item.ItemName), String(item.resource_path), String(item.ItemModelScenePath)]
	text = text.to_lower()
	return text.find(wanted) >= 0 or (wanted in ["water", "water_bottle", "水", "水瓶"] and text.find("water") >= 0)


func can_accept_item(item: ItemData) -> bool:
	if item == null:
		return false
	if not allow_incoming_items:
		return false
	if not reject_disallowed_items:
		return true
	return _is_item_allowed_by_filters(item)


func _is_item_allowed_by_filters(item: ItemData) -> bool:
	if item == null:
		return false
	# 类别和标签是两种互补的语义过滤器，而不是必须同时满足的 AND。
	# 例如食品柜配置了 category=food、tag=食品柜，但旧物品资源没有额外
	# inventory_tags；若强制 AND，玩家就只能从柜子取出，无法把食物放回柜子。
	var category_allowed := allowed_item_categories.is_empty() or allowed_item_categories.has(item.outing_category)
	var tag_allowed := allowed_item_tags.is_empty()
	if not tag_allowed:
		for tag in item.inventory_tags:
			if allowed_item_tags.has(tag):
				tag_allowed = true
				break
	if allowed_item_categories.is_empty():
		return tag_allowed
	if allowed_item_tags.is_empty():
		return category_allowed
	return category_allowed or tag_allowed

# ==========================================
# 存档系统接口
# ==========================================

# 1. 保存数据
func get_container_save_data() -> Array:
	var slots_data = []
	for slot in runtime_slots:
		if slot.item != null:
			slots_data.append({
				"slot_id": slot.slot_id,
				"item_path": slot.item.resource_path, 
				"amount": _normalize_slot_amount(slot.item, slot.amount)
			})
	return slots_data


func build_inventory_save_payload() -> Dictionary:
	return {
		"source": "shelter_runtime" if _uses_shelter_runtime_storage() else "scene_container",
		"shelter_source_id": String(shelter_source_id),
		"container_name": container_name,
		"container_size": container_size,
		"enable_item_stacking": enable_item_stacking,
		"slots": get_container_save_data(),
	}


func apply_inventory_save_payload(payload: Variant) -> void:
	if _uses_shelter_runtime_storage() and _should_ignore_scene_payload_for_shelter_runtime(payload):
		_ensure_runtime_storage()
		_rebuild_runtime_slots_from_storage()
		_sanitize_runtime_storage_items()
		_refresh_world_display()
		return
	if payload is Dictionary:
		var dict_payload: Dictionary = payload
		if dict_payload.has("container_size"):
			container_size = maxi(1, int(dict_payload.get("container_size", container_size)))
		if dict_payload.has("enable_item_stacking"):
			enable_item_stacking = bool(dict_payload.get("enable_item_stacking", enable_item_stacking))
		if dict_payload.has("slots"):
			load_container_save_data(dict_payload.get("slots", []))
			return
	if payload is Array:
		load_container_save_data(payload)


func build_inventory_storage_resource() -> InventoryStorageResource:
	_sync_runtime_storage_from_runtime_slots()
	if _runtime_inventory_storage == null:
		return null
	return _runtime_inventory_storage.duplicate(true) as InventoryStorageResource


func apply_inventory_storage_resource(storage: InventoryStorageResource) -> void:
	if storage == null:
		return
	if _uses_shelter_runtime_storage():
		_ensure_runtime_storage()
		_copy_storage_contents(storage, _runtime_inventory_storage)
	else:
		_runtime_inventory_storage = storage.duplicate(true)
	container_size = maxi(1, _runtime_inventory_storage.slot_count)
	_runtime_inventory_storage.slot_count = container_size
	_runtime_inventory_storage.ensure_capacity()
	_rebuild_runtime_slots_from_storage()
	_sync_runtime_storage_from_runtime_slots()
	_sanitize_runtime_storage_items()
	_rebuild_runtime_slots_from_storage()
	_refresh_world_display()

# 2. 读取数据
func load_container_save_data(saved_slots: Array) -> void:
	if _uses_shelter_runtime_storage() and saved_slots.is_empty():
		_ensure_runtime_storage()
		_rebuild_runtime_slots_from_storage()
		_sanitize_runtime_storage_items()
		_refresh_world_display()
		return
	_ensure_runtime_storage()
	_rebuild_runtime_slots_from_storage()

	# 先清空当前所有格子
	for slot in runtime_slots:
		slot.item = null
		slot.amount = 0
		
	# 重新填入读取的数据
	for data in saved_slots:
		var slot_id = data.get("slot_id", 0)
		var item_path = data.get("item_path", "")
		var amount = data.get("amount", 0)
		
		if slot_id >= 0 and slot_id < container_size and item_path != "":
			if ResourceLoader.exists(item_path):
				var item := load(item_path) as ItemData
				if item != null:
					runtime_slots[slot_id].item = item
					runtime_slots[slot_id].amount = _normalize_slot_amount(item, amount)
	_sync_runtime_storage_from_runtime_slots()
	_sanitize_runtime_storage_items()
	_rebuild_runtime_slots_from_storage()
	_refresh_world_display()


func _ensure_runtime_storage() -> void:
	if _uses_shelter_runtime_storage():
		var shelter_storage := _get_or_create_shelter_runtime_storage()
		if shelter_storage != null:
			_runtime_inventory_storage = shelter_storage
			_runtime_inventory_storage.slot_count = maxi(1, maxi(container_size, _runtime_inventory_storage.slot_count))
			_runtime_inventory_storage.ensure_capacity()
			return

	if _runtime_inventory_storage != null and is_instance_valid(_runtime_inventory_storage):
		_runtime_inventory_storage.slot_count = maxi(1, container_size)
		_runtime_inventory_storage.ensure_capacity()
		return

	if inventory_storage != null:
		_runtime_inventory_storage = inventory_storage.duplicate(true)
	else:
		_runtime_inventory_storage = INVENTORY_STORAGE_SCRIPT.new()

	if _runtime_inventory_storage == null:
		_runtime_inventory_storage = INVENTORY_STORAGE_SCRIPT.new()
	_runtime_inventory_storage.slot_count = maxi(1, container_size)
	_runtime_inventory_storage.ensure_capacity()


func _sanitize_runtime_storage_items() -> void:
	if _runtime_inventory_storage == null:
		return
	if not reject_disallowed_items:
		return
	if allowed_item_categories.is_empty() and allowed_item_tags.is_empty():
		return
	_runtime_inventory_storage.ensure_capacity()
	for i in range(_runtime_inventory_storage.slot_count):
		var stack := _runtime_inventory_storage.get_slot(i) as InventorySlotStackResource
		if stack == null or stack.is_empty():
			continue
		if not _is_item_allowed_by_filters(stack.item):
			if _should_preserve_default_food_item(stack.item):
				continue
			stack.clear()


func _rebuild_runtime_slots_from_storage() -> void:
	runtime_slots.clear()
	container_size = maxi(1, container_size)
	for i in range(container_size):
		var slot := SlotConfig.new()
		slot.slot_id = i
		slot.item = null
		slot.amount = 0
		if _runtime_inventory_storage != null:
			var stack := _runtime_inventory_storage.get_slot(i) as InventorySlotStackResource
			if stack != null and not stack.is_empty():
				slot.item = stack.item
				slot.amount = _normalize_slot_amount(stack.item, stack.amount)
		runtime_slots.append(slot)


func _sync_runtime_storage_from_runtime_slots() -> void:
	_ensure_runtime_storage()
	if _runtime_inventory_storage == null:
		return
	_runtime_inventory_storage.slot_count = maxi(1, container_size)
	_runtime_inventory_storage.ensure_capacity()

	for i in range(container_size):
		var slot := runtime_slots[i] as SlotConfig
		var stack := _runtime_inventory_storage.get_slot(i) as InventorySlotStackResource
		if stack == null:
			continue
		if slot == null or slot.item == null or slot.amount <= 0:
			stack.clear()
			continue
		stack.set_stack(slot.item, _normalize_slot_amount(slot.item, slot.amount))
	_notify_shelter_runtime_changed()


func _normalize_slot_amount(item: ItemData, amount: int) -> int:
	if item == null or amount <= 0:
		return 0
	if item.outing_category == "weapon":
		return 1
	if not enable_item_stacking:
		return 1
	return clampi(amount, 1, maxi(1, item.MaxStackSize))


func _should_preserve_default_food_item(item: ItemData) -> bool:
	if item == null:
		return false
	if not _uses_shelter_runtime_storage():
		return false
	var source_id := String(shelter_source_id).strip_edges()
	if source_id != "food_cabinet" and source_id != "food_cabinet_2":
		return false
	return item.outing_category == "food"


func _uses_shelter_runtime_storage() -> bool:
	return use_shelter_inventory_runtime and not String(shelter_source_id).strip_edges().is_empty()


func should_save_inventory_in_scene() -> bool:
	return not _uses_shelter_runtime_storage()


func should_load_inventory_from_scene() -> bool:
	return not _uses_shelter_runtime_storage()


func _should_ignore_scene_payload_for_shelter_runtime(payload: Variant) -> bool:
	if payload is Dictionary:
		var dict_payload := payload as Dictionary
		var source_text := String(dict_payload.get("source", "")).strip_edges()
		if source_text == "shelter_runtime":
			return true
		var payload_source_id := String(dict_payload.get("shelter_source_id", "")).strip_edges()
		if not payload_source_id.is_empty() and payload_source_id == String(shelter_source_id).strip_edges():
			return true
		if dict_payload.has("slots") and (dict_payload.get("slots", []) as Array).is_empty():
			return true
	if payload is Array:
		return (payload as Array).is_empty()
	return false


func _get_or_create_shelter_runtime_storage() -> InventoryStorageResource:
	var global_node := get_node_or_null("/root/Global")
	if global_node == null or not global_node.has_method("get_or_create_shelter_storage_runtime"):
		return null
	return global_node.call(
		"get_or_create_shelter_storage_runtime",
		shelter_source_id,
		inventory_storage,
		container_size
	) as InventoryStorageResource


func _copy_storage_contents(source: InventoryStorageResource, target: InventoryStorageResource) -> void:
	if source == null or target == null:
		return
	source.ensure_capacity()
	target.slot_count = maxi(1, source.slot_count)
	target.ensure_capacity()
	for i in range(target.slot_count):
		var source_slot := source.get_slot(i) as InventorySlotStackResource
		var target_slot := target.get_slot(i) as InventorySlotStackResource
		if target_slot == null:
			continue
		if source_slot == null or source_slot.is_empty():
			target_slot.clear()
		else:
			target_slot.set_stack(source_slot.item, _normalize_slot_amount(source_slot.item, source_slot.amount))


func _notify_shelter_runtime_changed() -> void:
	if not _uses_shelter_runtime_storage():
		return
	var global_node := get_node_or_null("/root/Global")
	if global_node != null and global_node.has_method("notify_shelter_inventory_changed"):
		global_node.call("notify_shelter_inventory_changed")

func _refresh_world_display() -> void:
	if not world_display_enabled:
		_clear_display_models()
		return

	var display_root: Node3D = _resolve_or_create_display_root()
	if display_root == null:
		return

	_clear_display_models()
	var display_slots: Array = _collect_runtime_display_slots()
	if display_slots.is_empty():
		return

	var max_count := mini(display_max_models, display_slots.size())
	for i in range(max_count):
		var entry: Dictionary = display_slots[i]
		var item_data: ItemData = entry.get("item", null) as ItemData
		if item_data == null:
			continue
		var slot_id: int = int(entry.get("slot_id", i))
		var item_scene: PackedScene = item_data.get_scene()
		if item_scene == null:
			continue
		var item_node := item_scene.instantiate() as Node3D
		if item_node == null:
			continue

		_disable_display_runtime_behavior(item_node)
		display_root.add_child(item_node)
		_normalize_display_item_transform(item_node)
		item_node.position += _resolve_display_slot_position(slot_id)
		item_node.rotate_y(deg_to_rad(display_base_yaw_deg + float(i) * display_yaw_step_deg))

func _collect_runtime_display_slots() -> Array:
	var entries: Array = []
	for slot in runtime_slots:
		if slot == null:
			continue
		if slot.item == null:
			continue
		if slot.amount <= 0:
			continue
		entries.append({
			"slot_id": slot.slot_id,
			"item": slot.item,
			"amount": slot.amount,
		})
	return entries

func _resolve_or_create_display_root() -> Node3D:
	if _display_root != null and is_instance_valid(_display_root):
		return _display_root

	var host: Node3D = self

	if display_root_path != NodePath():
		var by_path := host.get_node_or_null(display_root_path) as Node3D
		if by_path != null:
			_display_root = by_path
			return _display_root

	var existing := host.get_node_or_null("DisplayItems") as Node3D
	if existing != null:
		_display_root = existing
		return _display_root

	var created := Node3D.new()
	created.name = "DisplayItems"
	host.add_child(created)
	_display_root = created
	return _display_root

func _clear_display_models() -> void:
	if _display_root == null or not is_instance_valid(_display_root):
		return
	for child in _display_root.get_children():
		var node := child as Node
		if node != null:
			node.queue_free()

func _resolve_display_slot_position(index: int) -> Vector3:
	var marker_root := get_node_or_null(display_slot_markers_root_path)
	if marker_root != null:
		var marker_positions: Array[Vector3] = []
		for child in marker_root.get_children():
			var marker_node := child as Node3D
			if marker_node == null:
				continue
			marker_positions.append(marker_node.position)
		if index >= 0 and index < marker_positions.size():
			return marker_positions[index]

	if index >= 0 and index < display_slots_local_positions.size():
		return display_slots_local_positions[index]
	var row: int = int(floor(float(index) / 2.0))
	var col: int = index % 2
	var x: float = -0.08 if col == 0 else 0.08
	var y: float = 0.40 + float(row) * 0.62
	return Vector3(x, y, 0.0)

func _disable_display_runtime_behavior(root_node: Node3D) -> void:
	if root_node == null:
		return
	root_node.process_mode = Node.PROCESS_MODE_DISABLED
	_disable_display_runtime_behavior_recursive(root_node)

func _disable_display_runtime_behavior_recursive(node: Node) -> void:
	if node == null:
		return

	if node is Node:
		node.set_process(false)
		node.set_physics_process(false)
		node.set_process_input(false)
		node.set_process_unhandled_input(false)

	if node is CollisionObject3D:
		var collision := node as CollisionObject3D
		collision.collision_layer = 0
		collision.collision_mask = 0
		collision.input_ray_pickable = false

	if node is RigidBody3D:
		var body := node as RigidBody3D
		body.freeze = true
		body.sleeping = true

	for child in node.get_children():
		var child_node := child as Node
		if child_node != null:
			_disable_display_runtime_behavior_recursive(child_node)

func _normalize_display_item_transform(item_node: Node3D) -> void:
	if item_node == null:
		return
	var state := {
		"found": false,
		"aabb": AABB(),
	}
	_collect_mesh_bounds_recursive(item_node, item_node, Transform3D.IDENTITY, state)
	if not bool(state.get("found", false)):
		return

	var bounds: AABB = state.get("aabb", AABB())
	var size: Vector3 = bounds.size
	var longest: float = maxf(size.x, maxf(size.y, size.z))
	if longest <= DISPLAY_EPSILON:
		return

	var fit_scale: float = (display_fit_size / longest) * maxf(display_scale_multiplier, 0.01)
	var original_scale: Vector3 = item_node.scale
	item_node.scale = original_scale * fit_scale

	var center_x: float = bounds.position.x + bounds.size.x * 0.5
	var center_z: float = bounds.position.z + bounds.size.z * 0.5
	var min_y: float = bounds.position.y
	item_node.position += Vector3(-center_x * item_node.scale.x, -min_y * item_node.scale.y, -center_z * item_node.scale.z)

func _collect_mesh_bounds_recursive(root: Node3D, node: Node, to_root: Transform3D, state: Dictionary) -> void:
	if node == null:
		return

	var current_to_root: Transform3D = to_root
	if node != root and node is Node3D:
		current_to_root = to_root * (node as Node3D).transform

	if node is MeshInstance3D:
		var mesh_instance := node as MeshInstance3D
		if mesh_instance.mesh != null:
			var mesh_bounds: AABB = _transform_aabb(current_to_root, mesh_instance.mesh.get_aabb())
			if not bool(state.get("found", false)):
				state["found"] = true
				state["aabb"] = mesh_bounds
			else:
				var merged: AABB = state.get("aabb", mesh_bounds)
				state["aabb"] = merged.merge(mesh_bounds)

	for child in node.get_children():
		var child_node := child as Node
		if child_node != null:
			_collect_mesh_bounds_recursive(root, child_node, current_to_root, state)

func _transform_aabb(xform: Transform3D, source: AABB) -> AABB:
	var min_pos := source.position
	var max_pos := source.position + source.size
	var points: Array = [
		Vector3(min_pos.x, min_pos.y, min_pos.z),
		Vector3(max_pos.x, min_pos.y, min_pos.z),
		Vector3(min_pos.x, max_pos.y, min_pos.z),
		Vector3(max_pos.x, max_pos.y, min_pos.z),
		Vector3(min_pos.x, min_pos.y, max_pos.z),
		Vector3(max_pos.x, min_pos.y, max_pos.z),
		Vector3(min_pos.x, max_pos.y, max_pos.z),
		Vector3(max_pos.x, max_pos.y, max_pos.z),
	]
	var transformed_first: Vector3 = xform * points[0]
	var out_bounds := AABB(transformed_first, Vector3.ZERO)
	for i in range(1, points.size()):
		out_bounds = out_bounds.expand(xform * points[i])
	return out_bounds

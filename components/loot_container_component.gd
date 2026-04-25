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
	Global.open_loot_ui.emit(self)

func notify_runtime_slots_changed() -> void:
	_sync_runtime_storage_from_runtime_slots()
	_refresh_world_display()

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
		"container_name": container_name,
		"container_size": container_size,
		"enable_item_stacking": enable_item_stacking,
		"slots": get_container_save_data(),
	}


func apply_inventory_save_payload(payload: Variant) -> void:
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
	_runtime_inventory_storage = storage.duplicate(true)
	container_size = maxi(1, _runtime_inventory_storage.slot_count)
	_runtime_inventory_storage.slot_count = container_size
	_runtime_inventory_storage.ensure_capacity()
	_rebuild_runtime_slots_from_storage()
	_sync_runtime_storage_from_runtime_slots()
	_refresh_world_display()

# 2. 读取数据
func load_container_save_data(saved_slots: Array) -> void:
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
	_refresh_world_display()


func _ensure_runtime_storage() -> void:
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


func _normalize_slot_amount(item: ItemData, amount: int) -> int:
	if item == null or amount <= 0:
		return 0
	if not enable_item_stacking:
		return 1
	return clampi(amount, 1, maxi(1, item.MaxStackSize))

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

class_name LootContainerComponent
extends Node3D

@export_category("Loot Settings")
@export var container_name: String = "Loot Crate"
@export var container_size: int = 16 
@export var interaction_time: float = 1.5 
@export var initial_loot: Array[SlotConfig] = [] 

@export_category("World Display")
@export var world_display_enabled: bool = false
@export var display_root_path: NodePath
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
const DISPLAY_EPSILON := 0.00001

func _ready() -> void:
	# 初始化运行时数据数组
	for i in range(container_size):
		var empty_slot = SlotConfig.new()
		empty_slot.slot_id = i
		runtime_slots.append(empty_slot)
		
	# 将编辑器配置的初始物品填入运行时数据
	for config in initial_loot:
		if config and config.slot_id >= 0 and config.slot_id < container_size:
			runtime_slots[config.slot_id].item = config.item
			runtime_slots[config.slot_id].amount = config.amount
	_refresh_world_display()

# ==========================================
# 交互接口
# ==========================================
func get_interaction_time() -> float:
	return interaction_time

func get_prompt_text() -> String:
	return "搜索: " + container_name

func interact(player: Node) -> void:
	Global.open_loot_ui.emit(self)

func notify_runtime_slots_changed() -> void:
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
				"amount": slot.amount
			})
	return slots_data

# 2. 读取数据
func load_container_save_data(saved_slots: Array) -> void:
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
				runtime_slots[slot_id].item = load(item_path)
				runtime_slots[slot_id].amount = amount
	_refresh_world_display()

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
		var item_scene: PackedScene = item_data.get_scene()
		if item_scene == null:
			continue
		var item_node := item_scene.instantiate() as Node3D
		if item_node == null:
			continue

		_disable_display_runtime_behavior(item_node)
		display_root.add_child(item_node)
		_normalize_display_item_transform(item_node)
		item_node.position += _resolve_display_slot_position(i)
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
	if index >= 0 and index < display_slots_local_positions.size():
		return display_slots_local_positions[index]
	var row: int = index / 2
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

func _transform_aabb(transform: Transform3D, source: AABB) -> AABB:
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
	var transformed_first: Vector3 = transform * points[0]
	var out_bounds := AABB(transformed_first, Vector3.ZERO)
	for i in range(1, points.size()):
		out_bounds = out_bounds.expand(transform * points[i])
	return out_bounds

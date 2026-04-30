extends Node
class_name HoloInventoryDualPanel3D

signal world_drop_requested(item: ItemData, amount: int)

const LEFT_PANEL_SCENE_DEFAULT: PackedScene = preload("res://controllers/interaction/HoloInventoryPanel3D.tscn")
const LOOT_ADAPTER_SCRIPT = preload("res://scripts/Inventory/loot_container_data_adapter.gd")
const INVENTORY_DRAG_DEBUG := true

@export_category("References")
@export var right_panel_path: NodePath = NodePath("../HoloInventoryPanel3D")
@export var right_anchor_mark_path: NodePath = NodePath("../InventoryPanelMark3D")
@export var inventory_data_path: NodePath = NodePath("../Components/InventoryDataService")
@export var left_panel_scene: PackedScene = LEFT_PANEL_SCENE_DEFAULT

@export_category("Layout")
@export var left_anchor_local_offset: Vector3 = Vector3(-0.72, 1.16, -0.78)
@export_range(0.02, 0.5, 0.01) var close_check_interval_sec: float = 0.08
@export var allow_world_drop_from_left_panel: bool = false

var _player_node: Node
var _player_body: PhysicsBody3D
var _right_panel: HoloInventoryPanel3D
var _left_panel: HoloInventoryPanel3D
var _right_anchor_mark: Node3D
var _left_anchor_mark: Marker3D
var _player_inventory: InventoryDataService
var _left_adapter

var _active_container: LootContainerComponent
var _active_left_panel: HoloInventoryPanel3D
var _active_operate_area: Area3D
var _is_dual_open: bool = false
var _close_check_elapsed: float = 0.0


func _ready() -> void:
	_player_node = get_parent()
	_player_body = _player_node as PhysicsBody3D

	_right_panel = get_node_or_null(right_panel_path) as HoloInventoryPanel3D
	_right_anchor_mark = get_node_or_null(right_anchor_mark_path) as Node3D
	_player_inventory = get_node_or_null(inventory_data_path) as InventoryDataService

	_ensure_left_panel()
	_set_active_left_panel(_left_panel)
	_ensure_left_anchor()
	_ensure_adapter()
	_connect_panel_signals()

	if _right_panel != null and _player_inventory != null:
		_right_panel.set_inventory_data(_player_inventory)

	if _left_panel != null:
		_left_panel.hide_panel()

	set_process(true)


func _process(delta: float) -> void:
	if not _is_dual_open:
		return
	if _active_operate_area == null or not is_instance_valid(_active_operate_area):
		close_dual_panel()
		return
	if _player_body == null or not is_instance_valid(_player_body):
		return

	_close_check_elapsed += delta
	if _close_check_elapsed < close_check_interval_sec:
		return
	_close_check_elapsed = 0.0

	if not _active_operate_area.overlaps_body(_player_body):
		close_dual_panel()


func bind_player_inventory(inventory: InventoryDataService) -> void:
	_player_inventory = inventory
	if _right_panel != null and _player_inventory != null and not _is_dual_open:
		_right_panel.set_inventory_data(_player_inventory)


func is_dual_panel_open() -> bool:
	return _is_dual_open


func get_active_container() -> LootContainerComponent:
	return _active_container


func set_alt_hint_state(is_mouse_free_mode: bool) -> void:
	if _right_panel != null and is_instance_valid(_right_panel):
		_right_panel.set_alt_hint_state(is_mouse_free_mode)
	var hint_panel := _active_left_panel
	if hint_panel == null or not is_instance_valid(hint_panel):
		hint_panel = _left_panel
	if hint_panel != null and is_instance_valid(hint_panel):
		hint_panel.set_alt_hint_state(is_mouse_free_mode)


func open_for_container(container_node: Node) -> void:
	var container := container_node as LootContainerComponent
	if container == null:
		return
	if _right_panel == null:
		return
	if _player_inventory == null:
		_player_inventory = get_node_or_null(inventory_data_path) as InventoryDataService
	if _player_inventory == null:
		return

	var left_panel: HoloInventoryPanel3D = _resolve_left_panel_for_container(container)
	if left_panel == null:
		return
	_set_active_left_panel(left_panel)

	var left_panel_title: String = "箱子"
	var title_value: Variant = container.get("container_panel_title")
	if typeof(title_value) == TYPE_STRING:
		var normalized_title: String = String(title_value).strip_edges()
		if not normalized_title.is_empty():
			left_panel_title = normalized_title

	_active_container = container
	if _left_adapter == null:
		return
	_left_adapter.call("bind_container", container)
	_update_active_left_anchor(container)
	_bind_operate_area(container)
	_close_check_elapsed = 0.0

	if _right_anchor_mark != null:
		_right_panel.set_anchor_mark(_right_anchor_mark)
	_right_panel.set_panel_title("背包")
	_right_panel.set_inventory_data(_player_inventory)
	_right_panel.show_panel()

	_active_left_panel.set_panel_title(left_panel_title)
	_active_left_panel.set_inventory_data(_left_adapter)
	_active_left_panel.show_panel()

	_is_dual_open = true
	_set_inventory_visible(true)
	set_alt_hint_state(false)
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func close_dual_panel() -> void:
	if not _is_dual_open:
		return
	_is_dual_open = false
	_active_container = null
	_unbind_operate_area()

	if _active_left_panel != null and is_instance_valid(_active_left_panel):
		_active_left_panel.hide_panel()
	if _left_adapter != null and is_instance_valid(_left_adapter) and _left_adapter.has_method("unbind_container"):
		_left_adapter.call("unbind_container")
	_set_active_left_panel(null)
	if _right_panel != null:
		_right_panel.hide_panel()
	if _player_inventory != null:
		_set_inventory_visible(false)
	set_alt_hint_state(false)
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _connect_panel_signals() -> void:
	if _right_panel != null and not _right_panel.drop_requested.is_connected(_on_right_panel_drop_requested):
		_right_panel.drop_requested.connect(_on_right_panel_drop_requested)
	if _right_panel != null and not _right_panel.transfer_requested.is_connected(_on_right_panel_transfer_requested):
		_right_panel.transfer_requested.connect(_on_right_panel_transfer_requested)
	_connect_active_left_panel_signal()


func _ensure_left_panel() -> void:
	if _left_panel != null and is_instance_valid(_left_panel):
		return
	if left_panel_scene == null:
		return
	var panel := left_panel_scene.instantiate() as HoloInventoryPanel3D
	if panel == null:
		return
	panel.name = "HoloInventoryPanel3D_Left"
	add_child(panel)
	panel.panel_roll_degrees = 0.0
	panel.hide_panel()
	_left_panel = panel


func _ensure_left_anchor() -> void:
	if _left_anchor_mark != null and is_instance_valid(_left_anchor_mark):
		return
	_left_anchor_mark = Marker3D.new()
	_left_anchor_mark.name = "DualLeftPanelAnchor"
	_left_anchor_mark.top_level = true
	add_child(_left_anchor_mark)


func _ensure_adapter() -> void:
	if _left_adapter != null and is_instance_valid(_left_adapter):
		return
	_left_adapter = LOOT_ADAPTER_SCRIPT.new()
	_left_adapter.name = "LootContainerDataAdapter"
	add_child(_left_adapter)


func _update_left_anchor(container: LootContainerComponent) -> void:
	if _left_anchor_mark == null:
		return
	var container_node := container as Node3D
	if container_node == null:
		_left_anchor_mark.global_position = Vector3.ZERO
		return
	_left_anchor_mark.global_position = container_node.global_transform * left_anchor_local_offset


func _update_active_left_anchor(container: LootContainerComponent) -> void:
	if _active_left_panel == null or not is_instance_valid(_active_left_panel):
		return

	var external_anchor := _resolve_external_left_anchor_mark(container)
	if external_anchor != null:
		_active_left_panel.set_anchor_mark(external_anchor)
		return

	_update_left_anchor(container)
	_active_left_panel.set_anchor_mark(_left_anchor_mark)


func _resolve_left_panel_for_container(container: LootContainerComponent) -> HoloInventoryPanel3D:
	var external := _resolve_external_left_panel(container)
	if external != null:
		return external
	return _left_panel


func _resolve_external_left_panel(container: LootContainerComponent) -> HoloInventoryPanel3D:
	if container == null:
		return null
	var panel_path_value: Variant = container.get("local_panel_path")
	if typeof(panel_path_value) == TYPE_NODE_PATH:
		var panel_path: NodePath = panel_path_value
		if panel_path != NodePath():
			var by_path := container.get_node_or_null(panel_path) as HoloInventoryPanel3D
			if by_path != null:
				return by_path
	return _find_panel_fallback(container)


func _resolve_external_left_anchor_mark(container: LootContainerComponent) -> Node3D:
	if container == null:
		return null
	var marker_path_value: Variant = container.get("local_panel_anchor_mark_path")
	if typeof(marker_path_value) == TYPE_NODE_PATH:
		var marker_path: NodePath = marker_path_value
		if marker_path != NodePath():
			var by_path := container.get_node_or_null(marker_path) as Node3D
			if by_path != null:
				return by_path
	return _find_anchor_mark_fallback(container)


func _connect_active_left_panel_signal() -> void:
	if _active_left_panel == null or not is_instance_valid(_active_left_panel):
		return
	if not _active_left_panel.drop_requested.is_connected(_on_left_panel_drop_requested):
		_active_left_panel.drop_requested.connect(_on_left_panel_drop_requested)
	if not _active_left_panel.transfer_requested.is_connected(_on_left_panel_transfer_requested):
		_active_left_panel.transfer_requested.connect(_on_left_panel_transfer_requested)


func _set_active_left_panel(panel: HoloInventoryPanel3D) -> void:
	if _active_left_panel != null and is_instance_valid(_active_left_panel):
		if _active_left_panel.drop_requested.is_connected(_on_left_panel_drop_requested):
			_active_left_panel.drop_requested.disconnect(_on_left_panel_drop_requested)
		if _active_left_panel.transfer_requested.is_connected(_on_left_panel_transfer_requested):
			_active_left_panel.transfer_requested.disconnect(_on_left_panel_transfer_requested)
		if _active_left_panel != panel and _active_left_panel.is_panel_open():
			_active_left_panel.hide_panel()
	_active_left_panel = panel
	_connect_active_left_panel_signal()


func _find_panel_fallback(container: LootContainerComponent) -> HoloInventoryPanel3D:
	var current: Node = container
	while current != null:
		var candidate := current.get_node_or_null("ContainerPanel3D") as HoloInventoryPanel3D
		if candidate != null:
			return candidate
		current = current.get_parent()
	return null


func _find_anchor_mark_fallback(container: LootContainerComponent) -> Node3D:
	var current: Node = container
	while current != null:
		var candidate := current.get_node_or_null("ContainerPanelMark3D") as Node3D
		if candidate != null:
			return candidate
		current = current.get_parent()
	return null


func _bind_operate_area(container: LootContainerComponent) -> void:
	_unbind_operate_area()
	if container == null:
		return
	if container.has_method("get_operate_range_area"):
		_active_operate_area = container.call("get_operate_range_area") as Area3D


func _unbind_operate_area() -> void:
	_active_operate_area = null


func _set_inventory_visible(is_visible: bool) -> void:
	if _player_inventory != null and is_instance_valid(_player_inventory):
		_player_inventory.inventory_visible = is_visible


func _on_right_panel_drop_requested(item: ItemData, amount: int) -> void:
	if item == null or amount <= 0:
		return
	world_drop_requested.emit(item, amount)


func _on_left_panel_drop_requested(item: ItemData, amount: int) -> void:
	if item == null or amount <= 0:
		return
	if not allow_world_drop_from_left_panel:
		return
	world_drop_requested.emit(item, amount)


func _on_right_panel_transfer_requested(
	from_slot: int,
	item: ItemData,
	amount: int,
	source_storage: Object,
	pointer_screen_pos: Vector2
) -> void:
	_resolve_external_transfer(
		_right_panel,
		_player_inventory,
		_active_left_panel,
		_left_adapter,
		from_slot,
		item,
		amount,
		source_storage,
		pointer_screen_pos,
		true
	)


func _on_left_panel_transfer_requested(
	from_slot: int,
	item: ItemData,
	amount: int,
	source_storage: Object,
	pointer_screen_pos: Vector2
) -> void:
	_resolve_external_transfer(
		_active_left_panel,
		_left_adapter,
		_right_panel,
		_player_inventory,
		from_slot,
		item,
		amount,
		source_storage,
		pointer_screen_pos,
		allow_world_drop_from_left_panel
	)


func _resolve_external_transfer(
	source_panel: HoloInventoryPanel3D,
	default_source_storage: Object,
	target_panel: HoloInventoryPanel3D,
	target_storage: Object,
	from_slot: int,
	item: ItemData,
	amount: int,
	source_storage: Object,
	pointer_screen_pos: Vector2,
	allow_world_drop: bool
) -> void:
	if item == null or amount <= 0:
		return
	if from_slot < 0:
		return

	var resolved_source_storage: Object = source_storage
	if resolved_source_storage == null:
		resolved_source_storage = default_source_storage
	if resolved_source_storage == null:
		return

	var release_target: Dictionary = _resolve_release_target(pointer_screen_pos, source_panel)
	var hit_panel: HoloInventoryPanel3D = release_target.get("panel", null) as HoloInventoryPanel3D
	var target_slot: int = int(release_target.get("slot", -1))
	var over_target: bool = hit_panel == target_panel
	var moved: int = 0
	if INVENTORY_DRAG_DEBUG:
		var source_panel_name: String = source_panel.name if source_panel != null else "null"
		var target_panel_name: String = target_panel.name if target_panel != null else "null"
		var hit_panel_name: String = hit_panel.name if hit_panel != null else "null"
		print(
			"[InvDualTransfer] source_panel=", source_panel_name,
			" target_panel=", target_panel_name,
			" hit_panel=", hit_panel_name,
			" from_slot=", from_slot,
			" amount=", amount,
			" mouse=", pointer_screen_pos,
			" target_slot=", target_slot,
			" over_target=", over_target
		)
	if target_slot >= 0:
		moved = InventoryTransferService.transfer_between_storages(resolved_source_storage, from_slot, target_storage, target_slot, amount)
	elif over_target:
		moved = InventoryTransferService.transfer_to_first_available(resolved_source_storage, from_slot, target_storage, amount)
	if INVENTORY_DRAG_DEBUG:
		print("[InvDualTransfer] moved=", moved, " allow_world_drop=", allow_world_drop)

	if moved > 0:
		return

	if allow_world_drop:
		if INVENTORY_DRAG_DEBUG:
			print("[InvDualTransfer] fallback=world_drop from_slot=", from_slot, " amount=", amount)
		_drop_from_source_to_world(resolved_source_storage, from_slot, amount)


func _resolve_release_target(screen_pos: Vector2, source_panel: HoloInventoryPanel3D = null) -> Dictionary:
	var camera: Camera3D = _resolve_release_camera()
	if camera == null:
		return {"panel": null, "slot": -1}

	var from: Vector3 = camera.project_ray_origin(screen_pos)
	var to: Vector3 = from + camera.project_ray_normal(screen_pos) * 8.0
	var collision_mask: int = _get_panel_collision_mask()
	if collision_mask == 0:
		return {"panel": null, "slot": -1}

	var query := PhysicsRayQueryParameters3D.create(from, to, collision_mask)
	query.collide_with_areas = true
	query.collide_with_bodies = false
	var exclude_rids: Array[RID] = []
	if source_panel != null and is_instance_valid(source_panel):
		var source_hit_area: Area3D = source_panel.get_hit_area()
		if source_hit_area != null and is_instance_valid(source_hit_area):
			exclude_rids.append(source_hit_area.get_rid())
	if not exclude_rids.is_empty():
		query.exclude = exclude_rids
	var space_state := camera.get_world_3d().direct_space_state
	var hit: Dictionary = space_state.intersect_ray(query)
	if hit.is_empty():
		return {"panel": null, "slot": -1}

	var collider: Object = hit.get("collider", null) as Object
	var hit_position: Vector3 = hit.get("position", Vector3.ZERO) as Vector3
	if _matches_panel_collider(_active_left_panel, collider):
		return {
			"panel": _active_left_panel,
			"slot": _active_left_panel.get_slot_index_from_world_hit(hit_position),
		}
	if _matches_panel_collider(_right_panel, collider):
		return {
			"panel": _right_panel,
			"slot": _right_panel.get_slot_index_from_world_hit(hit_position),
		}
	return {"panel": null, "slot": -1}


func _matches_panel_collider(panel: HoloInventoryPanel3D, collider: Object) -> bool:
	if panel == null or not is_instance_valid(panel):
		return false
	var hit_area: Area3D = panel.get_hit_area()
	if hit_area == null or not is_instance_valid(hit_area):
		return false
	return collider == hit_area


func _resolve_release_camera() -> Camera3D:
	if _right_panel != null and is_instance_valid(_right_panel):
		var viewport := _right_panel.get_viewport()
		if viewport != null:
			var viewport_camera := viewport.get_camera_3d()
			if viewport_camera != null and is_instance_valid(viewport_camera):
				return viewport_camera
	if _player_node != null and is_instance_valid(_player_node):
		var player_viewport := _player_node.get_viewport()
		if player_viewport != null:
			var player_camera := player_viewport.get_camera_3d()
			if player_camera != null and is_instance_valid(player_camera):
				return player_camera
	return null


func _get_panel_collision_mask() -> int:
	var mask: int = 0
	if _right_panel != null and is_instance_valid(_right_panel):
		var right_hit_area: Area3D = _right_panel.get_hit_area()
		if right_hit_area != null and is_instance_valid(right_hit_area):
			mask |= right_hit_area.collision_layer
	if _active_left_panel != null and is_instance_valid(_active_left_panel):
		var left_hit_area: Area3D = _active_left_panel.get_hit_area()
		if left_hit_area != null and is_instance_valid(left_hit_area):
			mask |= left_hit_area.collision_layer
	return mask


func _drop_from_source_to_world(source_storage: Object, from_slot: int, requested_amount: int) -> void:
	var removed: Dictionary = InventoryTransferService.drop_from_source(source_storage, from_slot, requested_amount)
	var removed_item: ItemData = removed.get("item", null) as ItemData
	var removed_amount: int = int(removed.get("amount", 0))
	if removed_item == null or removed_amount <= 0:
		return
	world_drop_requested.emit(removed_item, removed_amount)

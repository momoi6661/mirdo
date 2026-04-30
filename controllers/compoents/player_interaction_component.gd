class_name PlayerInteractionComponent
extends Node

const WorldPanelContract := preload("res://controllers/interaction/world_panel_provider_contract.gd")
const MODE_NONE: StringName = &""
const MODE_WORLD: StringName = &"world"
const MODE_LEGACY_WORLD: StringName = &"legacy_world"
const XIAOKONG_GROUP: StringName = &"Xiaokong"
const XIAOKONG_CHARACTER_INTERACTABLE_PATH: NodePath = NodePath("Components/CharacterInteractable")

@export_category("References")
@export var interaction_ray: RayCast3D

@export_category("World Panel")
@export var world_panel_path: NodePath
@export var world_panel_anchor_path: NodePath
@export var world_panel_follow_camera_rotation: bool = false
@export var world_panel_wrap_selection: bool = true
@export_range(0.05, 1.0, 0.01) var world_panel_refresh_interval_sec: float = 0.12
@export_range(0.05, 2.0, 0.01) var world_panel_default_hold_duration_sec: float = 0.35

@export_category("Settings")
@export var interact_key: Key = KEY_E
@export var fallback_group_search_enabled: bool = true
@export var fallback_interactable_groups: PackedStringArray = PackedStringArray([&"xiaokong_interactable"])
@export_range(0.1, 3.0, 0.05) var fallback_interactable_max_distance: float = 0.6
@export_range(0, 8, 1) var world_interactable_descendant_search_depth: int = 4
@export_range(0, 8, 1) var world_interactable_parent_search_depth: int = 6
@export_range(0, 3, 1) var world_interactable_sibling_scan_parent_levels: int = 1
@export_range(1, 64, 1) var world_interactable_sibling_scan_max_children: int = 12
@export_range(0.2, 6.0, 0.1) var world_interactable_sibling_scan_max_distance: float = 2.4

var current_interactable: Node = null
var current_interaction_mode: StringName = MODE_NONE
var is_interacting: bool = false
var interact_timer: float = 0.0
var _last_interact_pressed: bool = false
var _locked_interactable: Node = null
var _locked_interaction_mode: StringName = MODE_NONE

var _world_panel: WorldInteractionPanelComponent
var _world_panel_anchor: Node3D
var _world_panel_model: WorldInteractionPanelModel
var _world_panel_refresh_elapsed: float = 0.0
var _world_panel_selected_option_id: String = ""
var _world_panel_hold_executed: bool = false
var _ignored_held_collision: CollisionObject3D = null
var _external_ui_blocked: bool = false

func _ready() -> void:
	set_process_unhandled_input(true)
	_world_panel = get_node_or_null(world_panel_path) as WorldInteractionPanelComponent
	_world_panel_anchor = get_node_or_null(world_panel_anchor_path) as Node3D

func _physics_process(delta: float) -> void:
	var input_state: Dictionary = _poll_interact_input_state()
	if interaction_ray == null:
		return
	if _external_ui_blocked:
		_clear_target()
		return
	_sync_held_object_exception()

	if _is_inventory_open():
		_clear_target()
		return

	if _should_use_locked_interaction_target(input_state):
		if _locked_interactable == null or not is_instance_valid(_locked_interactable):
			_clear_target()
			return
		current_interactable = _locked_interactable
		current_interaction_mode = _locked_interaction_mode
		if _is_world_mode(current_interaction_mode):
			_handle_world_interaction(delta, input_state)
			return
		_clear_target()
		return

	if not interaction_ray.is_colliding():
		_clear_target()
		return

	var collider: Node = interaction_ray.get_collider() as Node
	if collider == null:
		_clear_target()
		return

	var target_info: Dictionary = _resolve_interaction_target(collider, interaction_ray.get_collision_point())
	var next_interactable: Node = target_info.get("target", null) as Node
	var next_mode: StringName = StringName(target_info.get("mode", MODE_NONE))

	if next_interactable != current_interactable or next_mode != current_interaction_mode:
		_clear_target()
		current_interactable = next_interactable
		current_interaction_mode = next_mode
		if current_interactable != null:
			_focus_current_target()

	if current_interactable == null:
		return

	if _is_world_mode(current_interaction_mode):
		_handle_world_interaction(delta, input_state)
		var should_refresh_model: bool = true
		if is_interacting:
			var refreshing_option: WorldInteractionOption = _get_selected_world_option()
			if refreshing_option != null and refreshing_option.supports_hold():
				should_refresh_model = false
		if should_refresh_model:
			_world_panel_refresh_elapsed += delta
			if _world_panel_refresh_elapsed >= world_panel_refresh_interval_sec:
				_world_panel_refresh_elapsed = 0.0
				_refresh_world_panel()
		return

	_clear_target()

func _unhandled_input(event: InputEvent) -> void:
	if _external_ui_blocked:
		return
	if not _is_world_mode(current_interaction_mode) or current_interactable == null:
		return
	if _is_inventory_open():
		return
	if event is not InputEventMouseButton:
		return

	var mouse_event: InputEventMouseButton = event as InputEventMouseButton
	if not mouse_event.pressed:
		return

	var step: int = 0
	if mouse_event.button_index == MOUSE_BUTTON_WHEEL_UP:
		step = -1
	elif mouse_event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
		step = 1
	if step == 0:
		return

	_cycle_world_panel_selection(step)
	get_viewport().set_input_as_handled()

func _resolve_interaction_target(collider: Node, hit_position: Vector3) -> Dictionary:
	var xiaokong_target: Node = _resolve_xiaokong_interactable_target(collider)
	if xiaokong_target != null and not _is_target_held_object(xiaokong_target):
		return {"target": xiaokong_target, "mode": MODE_WORLD}

	var world_target: Node = _get_world_interactable(collider)
	if world_target != null and not _is_target_held_object(world_target):
		return {"target": world_target, "mode": MODE_WORLD}

	var legacy_target: Node = _get_legacy_interactable(collider)
	if legacy_target != null and not _is_target_held_object(legacy_target):
		return {"target": legacy_target, "mode": MODE_LEGACY_WORLD}

	if fallback_group_search_enabled:
		var fallback_info: Dictionary = _find_nearby_group_target(hit_position)
		var fallback_target: Node = fallback_info.get("target", null) as Node
		if fallback_target != null and _is_target_held_object(fallback_target):
			return {"target": null, "mode": MODE_NONE}
		return fallback_info

	return {"target": null, "mode": MODE_NONE}

func _resolve_xiaokong_interactable_target(collider: Node) -> Node:
	var xiaokong_root: Node = _find_xiaokong_root(collider)
	if xiaokong_root == null:
		xiaokong_root = _find_xiaokong_root_by_interactable_path(collider)
	if xiaokong_root == null:
		return null
	var interactable: Node = xiaokong_root.get_node_or_null(XIAOKONG_CHARACTER_INTERACTABLE_PATH)
	if _is_world_interactable_candidate(interactable):
		return interactable
	return _find_world_interactable_recursive(xiaokong_root, world_interactable_descendant_search_depth + 2)

func _find_xiaokong_root(from_node: Node) -> Node:
	var current: Node = from_node
	while current != null:
		if current.is_in_group(XIAOKONG_GROUP):
			return current
		current = current.get_parent()
	return null

func _find_xiaokong_root_by_interactable_path(from_node: Node) -> Node:
	var current: Node = from_node
	while current != null:
		var interactable: Node = current.get_node_or_null(XIAOKONG_CHARACTER_INTERACTABLE_PATH)
		if _is_world_interactable_candidate(interactable):
			return current
		current = current.get_parent()
	return null

func _get_legacy_interactable(node: Node) -> Node:
	var current: Node = node
	while current != null:
		if _is_interaction_enabled(current):
			var has_interact: bool = current.has_method("interact")
			var has_short: bool = current.has_method("short_interact")
			var has_timing: bool = current.has_method("get_interaction_time")
			if has_interact and (has_timing or has_short or _is_pickable_legacy_target(current)):
				return current
		current = current.get_parent()
	return null

func _get_world_interactable(node: Node) -> Node:
	if node == null or not is_instance_valid(node):
		return null

	var branch_candidate: Node = _find_world_interactable_recursive(node, world_interactable_descendant_search_depth)
	if branch_candidate != null:
		return branch_candidate

	var current: Node = node.get_parent()
	var source_branch: Node = node
	var depth: int = 0
	var sibling_max_distance_sq: float = world_interactable_sibling_scan_max_distance * world_interactable_sibling_scan_max_distance
	while current != null and depth <= world_interactable_parent_search_depth:
		if _is_world_interactable_candidate(current):
			return current

		if depth <= world_interactable_sibling_scan_parent_levels and current.get_child_count() <= world_interactable_sibling_scan_max_children:
			var sibling_candidate: Node = _find_world_interactable_sibling(current, source_branch, sibling_max_distance_sq)
			if sibling_candidate != null:
				return sibling_candidate

		source_branch = current
		current = current.get_parent()
		depth += 1
	return null

func _find_world_interactable_sibling(parent: Node, source_node: Node, max_distance_sq: float) -> Node:
	if parent == null or not is_instance_valid(parent):
		return null

	var source_anchor: Node3D = _get_nearest_node3d(source_node)
	for child in parent.get_children():
		var child_node: Node = child as Node
		if child_node == null or not is_instance_valid(child_node):
			continue
		if source_node != null and (child_node == source_node or child_node.is_ancestor_of(source_node)):
			continue

		var candidate: Node = _find_world_interactable_recursive(child_node, world_interactable_descendant_search_depth)
		if candidate == null:
			continue

		if source_anchor != null and max_distance_sq > 0.0:
			var candidate_anchor: Node3D = _get_nearest_node3d(candidate)
			if candidate_anchor != null:
				var dist_sq: float = source_anchor.global_position.distance_squared_to(candidate_anchor.global_position)
				if dist_sq > max_distance_sq:
					continue

		return candidate

	return null

func _get_nearest_node3d(node: Node) -> Node3D:
	var current: Node = node
	while current != null:
		if current is Node3D:
			return current as Node3D
		current = current.get_parent()
	return null

func _find_world_interactable_recursive(node: Node, remaining_depth: int) -> Node:
	if node == null or not is_instance_valid(node):
		return null
	if _is_world_interactable_candidate(node):
		return node
	if remaining_depth <= 0:
		return null
	for child in node.get_children():
		var child_node: Node = child as Node
		if child_node == null:
			continue
		var nested: Node = _find_world_interactable_recursive(child_node, remaining_depth - 1)
		if nested != null:
			return nested
	return null

func _find_nearby_group_target(hit_position: Vector3) -> Dictionary:
	var tree: SceneTree = get_tree()
	if tree == null:
		return {"target": null, "mode": MODE_NONE}

	var max_dist_sq: float = fallback_interactable_max_distance * fallback_interactable_max_distance
	var best_dist_sq: float = INF
	var best: Node = null
	var best_mode: StringName = MODE_NONE

	for group_name in fallback_interactable_groups:
		if String(group_name).strip_edges().is_empty():
			continue
		var nodes: Array = tree.get_nodes_in_group(group_name)
		for entry in nodes:
			var node3d: Node3D = entry as Node3D
			if node3d == null or not is_instance_valid(node3d):
				continue

			var candidate_info: Dictionary = _resolve_group_node_target(node3d)
			var candidate: Node = candidate_info.get("target", null) as Node
			if candidate == null:
				continue
			var candidate_mode: StringName = StringName(candidate_info.get("mode", MODE_NONE))
			if candidate_mode != MODE_WORLD:
				continue

			var dist_sq: float = node3d.global_position.distance_squared_to(hit_position)
			if dist_sq > max_dist_sq or dist_sq >= best_dist_sq:
				continue
			best_dist_sq = dist_sq
			best = candidate
			best_mode = candidate_mode

	return {"target": best, "mode": best_mode}

func _resolve_group_node_target(node: Node) -> Dictionary:
	var legacy_target: Node = _get_legacy_interactable(node)
	if _should_prefer_legacy_target(legacy_target):
		return {"target": legacy_target, "mode": MODE_LEGACY_WORLD}

	var world_target: Node = _get_world_interactable(node)
	if world_target != null:
		return {"target": world_target, "mode": MODE_WORLD}
	if legacy_target != null:
		return {"target": legacy_target, "mode": MODE_LEGACY_WORLD}
	return {"target": null, "mode": MODE_NONE}

func _focus_current_target() -> void:
	if current_interactable == null or not is_instance_valid(current_interactable):
		return
	if not _is_world_mode(current_interaction_mode):
		return

	is_interacting = false
	interact_timer = 0.0
	_world_panel_hold_executed = false
	_world_panel_refresh_elapsed = 0.0
	_world_panel_selected_option_id = ""
	_call_world_focus(true)
	_refresh_world_panel()

func _handle_world_interaction(delta: float, input_state: Dictionary) -> void:
	if current_interactable == null or not is_instance_valid(current_interactable):
		return
	if _world_panel_model == null:
		_refresh_world_panel()

	var is_pressing: bool = bool(input_state.get("pressed", false))
	var just_pressed: bool = bool(input_state.get("just_pressed", false))
	var option: WorldInteractionOption = _get_selected_world_option()
	if is_pressing:
		if not is_interacting:
			if not just_pressed:
				return
			is_interacting = true
			interact_timer = 0.0
			_world_panel_hold_executed = false
			_locked_interactable = current_interactable
			_locked_interaction_mode = current_interaction_mode
		interact_timer += delta

		if option != null and option.enabled and option.supports_hold():
			var hold_duration: float = option.get_safe_hold_duration(world_panel_default_hold_duration_sec)
			if _world_panel_model != null:
				_world_panel_model.hold_progress = clampf(interact_timer / hold_duration, 0.0, 1.0)
				_push_world_panel_model()
			if not _world_panel_hold_executed and interact_timer >= hold_duration:
				_world_panel_hold_executed = true
				_execute_world_panel_option(true, interact_timer)
			return

		if _world_panel_model != null and _world_panel_model.hold_progress > 0.0:
			_world_panel_model.hold_progress = 0.0
			_push_world_panel_model()
		return

	if not is_interacting:
		return

	var hold_time: float = interact_timer
	var should_execute_tap: bool = option != null and option.enabled and not _world_panel_hold_executed and option.supports_tap()
	is_interacting = false
	interact_timer = 0.0
	_world_panel_hold_executed = false

	if _world_panel_model != null and _world_panel_model.hold_progress > 0.0:
		_world_panel_model.hold_progress = 0.0
		_push_world_panel_model()

	if should_execute_tap:
		_execute_world_panel_option(false, hold_time)

func _clear_target() -> void:
	if current_interactable != null and is_instance_valid(current_interactable) and _is_world_mode(current_interaction_mode):
		_call_world_focus(false)
		_hide_world_panel()

	is_interacting = false
	interact_timer = 0.0
	_world_panel_hold_executed = false
	_world_panel_refresh_elapsed = 0.0
	_locked_interactable = null
	_locked_interaction_mode = MODE_NONE
	current_interactable = null
	current_interaction_mode = MODE_NONE


func _should_use_locked_interaction_target(input_state: Dictionary) -> bool:
	if not is_interacting:
		return false
	if _locked_interactable == null or not is_instance_valid(_locked_interactable):
		return false
	var pressed: bool = bool(input_state.get("pressed", false))
	var just_released: bool = bool(input_state.get("just_released", false))
	return pressed or just_released

func _refresh_world_panel() -> void:
	if not _is_world_mode(current_interaction_mode):
		return
	if current_interactable == null or not is_instance_valid(current_interactable):
		_hide_world_panel()
		return

	var model_variant: Variant = null
	if current_interactable.has_method(WorldPanelContract.METHOD_BUILD_MODEL):
		model_variant = current_interactable.call(
			WorldPanelContract.METHOD_BUILD_MODEL,
			self,
			_build_interaction_context()
		)
	elif current_interaction_mode == MODE_LEGACY_WORLD:
		model_variant = _build_legacy_world_panel_model(current_interactable)

	if model_variant is not WorldInteractionPanelModel:
		_hide_world_panel()
		return

	_world_panel_model = model_variant as WorldInteractionPanelModel
	_apply_world_panel_selection_memory(_world_panel_model)
	_push_world_panel_model()

func _push_world_panel_model() -> void:
	if _world_panel_model == null:
		return
	var panel: WorldInteractionPanelComponent = _resolve_world_panel()
	if panel == null:
		return
	panel.set_display_context(
		_resolve_world_panel_anchor(),
		_resolve_panel_camera(),
		world_panel_follow_camera_rotation,
		Vector3.ZERO
	)
	panel.show_model(_world_panel_model)

func _hide_world_panel() -> void:
	_world_panel_model = null
	var panel: WorldInteractionPanelComponent = _resolve_world_panel()
	if panel == null:
		return
	if panel.has_method("hide_panel"):
		panel.hide_panel()

func _resolve_world_panel() -> WorldInteractionPanelComponent:
	if _world_panel != null and is_instance_valid(_world_panel):
		return _world_panel
	_world_panel = get_node_or_null(world_panel_path) as WorldInteractionPanelComponent
	return _world_panel

func _resolve_world_panel_anchor() -> Node3D:
	if _world_panel_anchor != null and is_instance_valid(_world_panel_anchor):
		return _world_panel_anchor
	_world_panel_anchor = get_node_or_null(world_panel_anchor_path) as Node3D
	if _world_panel_anchor != null:
		return _world_panel_anchor
	var panel: WorldInteractionPanelComponent = _resolve_world_panel()
	if panel != null and panel.get_parent() is Node3D:
		return panel.get_parent() as Node3D
	return null

func _resolve_panel_camera() -> Camera3D:
	var viewport: Viewport = get_viewport()
	if viewport == null:
		return null
	return viewport.get_camera_3d()

func _cycle_world_panel_selection(step: int) -> void:
	if _world_panel_model == null or _world_panel_model.options.is_empty():
		_refresh_world_panel()
		if _world_panel_model == null or _world_panel_model.options.is_empty():
			return

	var option_count: int = _world_panel_model.options.size()
	var next_index: int = _world_panel_model.selected_index + step
	if world_panel_wrap_selection and option_count > 0:
		next_index = posmod(next_index, option_count)
	else:
		next_index = clampi(next_index, 0, option_count - 1)
	_world_panel_model.selected_index = next_index
	_world_panel_model.hold_progress = 0.0
	_world_panel_selected_option_id = _get_world_panel_option_id(_world_panel_model.get_selected_option())
	_push_world_panel_model()

func _get_selected_world_option() -> WorldInteractionOption:
	if _world_panel_model == null:
		return null
	return _world_panel_model.get_selected_option()

func _execute_world_panel_option(completed_by_hold: bool, hold_time: float) -> void:
	if _world_panel_model == null:
		return
	var option: WorldInteractionOption = _world_panel_model.get_selected_option()
	if option == null or not option.enabled:
		return
	if current_interactable == null or not is_instance_valid(current_interactable):
		return

	_world_panel_selected_option_id = _get_world_panel_option_id(option)
	if current_interactable.has_method(WorldPanelContract.METHOD_EXECUTE_OPTION):
		current_interactable.call(
			WorldPanelContract.METHOD_EXECUTE_OPTION,
			_world_panel_selected_option_id,
			self,
			_build_interaction_context(),
			completed_by_hold,
			hold_time
		)
	elif current_interaction_mode == MODE_LEGACY_WORLD:
		_execute_legacy_world_panel_option(
			current_interactable,
			_world_panel_selected_option_id,
			completed_by_hold,
			hold_time
		)
	else:
		return

	if _should_clear_world_target_after_execute():
		_clear_target()
		return

	_world_panel_refresh_elapsed = 0.0
	_refresh_world_panel()

func _should_clear_world_target_after_execute() -> bool:
	if current_interactable == null:
		return true
	if not is_instance_valid(current_interactable):
		return true
	if current_interactable.is_queued_for_deletion():
		return true
	var target_parent: Node = current_interactable.get_parent()
	if target_parent != null and is_instance_valid(target_parent) and target_parent.is_queued_for_deletion():
		return true
	return false

func _call_world_focus(focused: bool) -> void:
	if current_interactable == null or not is_instance_valid(current_interactable):
		return
	if current_interactable.has_method(WorldPanelContract.METHOD_SET_FOCUSED):
		current_interactable.call(WorldPanelContract.METHOD_SET_FOCUSED, focused)
	var callback: StringName = WorldPanelContract.METHOD_FOCUS_ENTER if focused else WorldPanelContract.METHOD_FOCUS_EXIT
	if current_interactable.has_method(callback):
		current_interactable.call(callback, self, _build_interaction_context())

func _build_legacy_world_panel_model(target: Node) -> WorldInteractionPanelModel:
	if target == null or not is_instance_valid(target):
		return null

	var model: WorldInteractionPanelModel = WorldInteractionPanelModel.new()
	model.title = _get_legacy_panel_title(target)

	var supports_pickup: bool = _legacy_supports_pickup_hand(target)
	var supports_stash: bool = _legacy_supports_stash_inventory(target)
	var hold_duration: float = _get_legacy_hold_duration(target)

	if supports_pickup and supports_stash:
		model.options.append(
			WorldInteractionOption.create(
				"legacy_pickup_or_stash",
				"拿起",
				"短按拿起，长按收纳。",
				WorldInteractionOption.TRIGGER_BOTH,
				hold_duration
			)
		)
		model.summary_lines = PackedStringArray([
			"短按：拿起",
			"长按：收纳",
		])
	elif supports_pickup:
		model.options.append(
			WorldInteractionOption.create(
				"legacy_pickup_only",
				"拿起",
				"短按拿起。",
				WorldInteractionOption.TRIGGER_TAP
			)
		)
		model.summary_lines = PackedStringArray([
			"短按：拿起",
		])
	elif supports_stash:
		var can_stash_now: bool = _legacy_can_stash_now(target)
		model.options.append(
			WorldInteractionOption.create(
				"legacy_stash_only",
				"收纳",
				"长按收纳。",
				WorldInteractionOption.TRIGGER_HOLD,
				hold_duration,
				can_stash_now,
				"" if can_stash_now else "背包空间不足"
			)
		)
		model.summary_lines = PackedStringArray([
			"长按：收纳",
		])
	else:
		model.options.append(
			WorldInteractionOption.create(
				"legacy_interact",
				"交互",
				"执行默认交互。",
				WorldInteractionOption.TRIGGER_TAP
			)
		)
		model.summary_lines = PackedStringArray([
			"按E交互",
		])

	return model

func _execute_legacy_world_panel_option(target: Node, option_id: String, completed_by_hold: bool, _hold_time: float) -> void:
	if target == null or not is_instance_valid(target):
		return
	if Global.player == null:
		return

	match option_id:
		"legacy_pickup_or_stash":
			if completed_by_hold:
				if target.has_method("interact"):
					target.call("interact", Global.player)
			elif target.has_method("short_interact"):
				target.call("short_interact", Global.player)
			elif target.has_method("interact"):
				target.call("interact", Global.player)
		"legacy_pickup_only":
			if target.has_method("short_interact"):
				target.call("short_interact", Global.player)
			elif target.has_method("interact"):
				target.call("interact", Global.player)
		"legacy_stash_only":
			if target.has_method("interact"):
				target.call("interact", Global.player)
		_:
			if target.has_method("interact"):
				target.call("interact", Global.player)

func _get_legacy_hold_duration(target: Node) -> float:
	if target == null or not is_instance_valid(target):
		return world_panel_default_hold_duration_sec
	if target.has_method("get_interaction_time"):
		var value: Variant = target.call("get_interaction_time")
		if value is int or value is float:
			return maxf(float(value), 0.05)
	return world_panel_default_hold_duration_sec

func _legacy_supports_pickup_hand(target: Node) -> bool:
	if target == null or not is_instance_valid(target):
		return false
	if not _is_pickable_legacy_target(target):
		return false
	if target.has_method("short_interact"):
		return true
	return target.has_method("interact") and not _legacy_supports_stash_inventory(target)

func _legacy_supports_stash_inventory(target: Node) -> bool:
	if target == null or not is_instance_valid(target):
		return false
	if not target.has_method("interact"):
		return false
	var item_data: ItemData = _extract_item_data_from_legacy_target(target)
	return item_data != null

func _legacy_can_stash_now(target: Node) -> bool:
	var item_data: ItemData = _extract_item_data_from_legacy_target(target)
	if item_data == null:
		return false
	if Global.player == null:
		return false

	var inventory_handler: Object = Global.player.get("inventory_handler") as Object
	if inventory_handler == null:
		return true
	if inventory_handler.has_method("CanPickupItem"):
		return bool(inventory_handler.call("CanPickupItem", item_data, 1))
	return true

func _extract_item_data_from_legacy_target(target: Node) -> ItemData:
	if target == null or not is_instance_valid(target):
		return null
	var item_data_value: Variant = target.get("item_data")
	if item_data_value is ItemData:
		return item_data_value as ItemData
	var parent: Node = target.get_parent()
	if parent == null or not is_instance_valid(parent):
		return null
	item_data_value = parent.get("item_data")
	if item_data_value is ItemData:
		return item_data_value as ItemData
	return null

func _get_legacy_panel_title(target: Node) -> String:
	var item_data: ItemData = _extract_item_data_from_legacy_target(target)
	if item_data != null:
		var item_name: String = String(item_data.ItemName).strip_edges()
		if not item_name.is_empty():
			return item_name

	if target != null and target.has_method("get_prompt_text"):
		var prompt_text: String = String(target.call("get_prompt_text")).strip_edges()
		if not prompt_text.is_empty():
			if prompt_text.begins_with("拾取:"):
				var pure_name_pickup: String = prompt_text.trim_prefix("拾取:").strip_edges()
				if not pure_name_pickup.is_empty():
					return pure_name_pickup
			if prompt_text.begins_with("交互:"):
				var pure_name_interact: String = prompt_text.trim_prefix("交互:").strip_edges()
				if not pure_name_interact.is_empty():
					return pure_name_interact
			return prompt_text
	return "物品"

func _apply_world_panel_selection_memory(model: WorldInteractionPanelModel) -> void:
	if model == null:
		return
	model.hold_progress = 0.0
	if model.options.is_empty():
		model.selected_index = 0
		_world_panel_selected_option_id = ""
		return
	if _world_panel_selected_option_id.is_empty():
		model.normalize_selection()
		_world_panel_selected_option_id = _get_world_panel_option_id(model.get_selected_option())
		return
	for index in range(model.options.size()):
		if _get_world_panel_option_id(model.options[index]) == _world_panel_selected_option_id:
			model.selected_index = index
			return
	model.normalize_selection()
	_world_panel_selected_option_id = _get_world_panel_option_id(model.get_selected_option())

func _get_world_panel_option_id(option: WorldInteractionOption) -> String:
	if option == null:
		return ""
	return String(option.id).strip_edges()

func _is_world_interactable_candidate(node: Node) -> bool:
	if node == null:
		return false
	if not _is_interaction_enabled(node):
		return false
	return WorldPanelContract.has_any_contract(node)

func _is_world_mode(mode: StringName) -> bool:
	return mode == MODE_WORLD or mode == MODE_LEGACY_WORLD

func _sync_held_object_exception() -> void:
	if interaction_ray == null:
		return
	var held_collision: CollisionObject3D = _get_held_collision_object()
	if held_collision == _ignored_held_collision:
		return
	if _ignored_held_collision != null and is_instance_valid(_ignored_held_collision):
		interaction_ray.remove_exception(_ignored_held_collision)
	_ignored_held_collision = held_collision
	if _ignored_held_collision != null and is_instance_valid(_ignored_held_collision):
		interaction_ray.add_exception(_ignored_held_collision)

func _get_held_collision_object() -> CollisionObject3D:
	if Global.player == null:
		return null
	var pickup_handler: Object = Global.player.get("pickup_handler") as Object
	if pickup_handler == null:
		return null

	var held_variant: Variant = null
	if pickup_handler.has_method("get_held_object"):
		held_variant = pickup_handler.call("get_held_object")
	else:
		held_variant = pickup_handler.get("held_object")
	if held_variant is not CollisionObject3D:
		return null

	var held_collision: CollisionObject3D = held_variant as CollisionObject3D
	if held_collision == null or not is_instance_valid(held_collision):
		return null
	return held_collision

func _is_target_held_object(target: Node) -> bool:
	if target == null or not is_instance_valid(target):
		return false
	var held_collision: CollisionObject3D = _get_held_collision_object()
	if held_collision == null:
		return false
	return (
		target == held_collision
		or held_collision.is_ancestor_of(target)
		or target.is_ancestor_of(held_collision)
	)

func _is_interaction_enabled(node: Node) -> bool:
	if node == null:
		return false
	if node.has_method("is_interaction_enabled"):
		return bool(node.call("is_interaction_enabled"))
	return true

func _should_prefer_legacy_target(node: Node) -> bool:
	if node == null or not is_instance_valid(node):
		return false
	return _is_pickable_legacy_target(node)

func _is_pickable_legacy_target(node: Node) -> bool:
	if node == null or not is_instance_valid(node):
		return false
	if _has_pickup_signature(node):
		return true
	var parent: Node = node.get_parent()
	if parent != null and is_instance_valid(parent):
		return _has_pickup_signature(parent)
	return false

func _has_pickup_signature(node: Node) -> bool:
	if node == null or not is_instance_valid(node):
		return false
	if node.has_method("set_held"):
		return true
	var item_data_value: Variant = node.get("item_data")
	if item_data_value != null:
		return true
	return node is RigidBody3D and node.has_method("short_interact")

func _poll_interact_input_state() -> Dictionary:
	var pressed: bool = false
	if InputMap.has_action("interact"):
		pressed = Input.is_action_pressed("interact")
	else:
		pressed = Input.is_key_pressed(interact_key)
	var just_pressed: bool = pressed and not _last_interact_pressed
	var just_released: bool = _last_interact_pressed and not pressed
	_last_interact_pressed = pressed
	return {
		"pressed": pressed,
		"just_pressed": just_pressed,
		"just_released": just_released,
	}

func set_external_ui_blocked(blocked: bool) -> void:
	if _external_ui_blocked == blocked:
		return
	_external_ui_blocked = blocked
	if _external_ui_blocked:
		_clear_target()

func is_external_ui_blocked() -> bool:
	return _external_ui_blocked

func _is_inventory_open() -> bool:
	if Global.player == null:
		return false
	var inventory: Object = Global.player.get("inventory_handler") as Object
	if inventory == null:
		return false
	return bool(inventory.get("inventory_visible"))

func _is_holding_object() -> bool:
	if Global.player == null:
		return false
	var pickup_handler: Object = Global.player.get("pickup_handler") as Object
	if pickup_handler == null:
		return false
	if pickup_handler.has_method("is_holding_object"):
		return bool(pickup_handler.call("is_holding_object"))
	return false

func _build_interaction_context() -> Dictionary:
	return FPSWorldPanelContext.build(
		Global.player,
		self,
		current_interactable,
		String(current_interaction_mode),
		interaction_ray
	)

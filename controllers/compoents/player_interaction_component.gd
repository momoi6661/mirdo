class_name PlayerInteractionComponent
extends Node

const WorldPanelContract := preload("res://controllers/interaction/world_panel_provider_contract.gd")

@export_category("References")
@export var interaction_ray: RayCast3D
@export var interaction_hud: Control

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

var current_interactable: Node = null
var current_interaction_mode: StringName = &""
var is_interacting: bool = false
var interact_timer: float = 0.0
var _last_interact_pressed: bool = false

var _world_panel: WorldInteractionPanelComponent
var _world_panel_anchor: Node3D
var _world_panel_model: WorldInteractionPanelModel
var _world_panel_refresh_elapsed: float = 0.0
var _world_panel_selected_option_id: String = ""
var _world_panel_hold_executed: bool = false

func _ready() -> void:
	set_process_unhandled_input(true)
	_world_panel = get_node_or_null(world_panel_path) as WorldInteractionPanelComponent
	_world_panel_anchor = get_node_or_null(world_panel_anchor_path) as Node3D

func _physics_process(delta: float) -> void:
	var input_state := _poll_interact_input_state()
	if not interaction_ray:
		return

	if _is_inventory_open():
		_clear_target()
		return

	if _is_holding_object() or not interaction_ray.is_colliding():
		_clear_target()
		return

	var collider := interaction_ray.get_collider() as Node
	if collider == null:
		_clear_target()
		return

	var target_info := _resolve_interaction_target(collider, interaction_ray.get_collision_point())
	var next_interactable: Node = target_info.get("target", null)
	var next_mode: StringName = target_info.get("mode", &"")

	if next_interactable != current_interactable or next_mode != current_interaction_mode:
		_clear_target()
		current_interactable = next_interactable
		current_interaction_mode = next_mode
		if current_interactable != null:
			_focus_current_target()

	if current_interactable == null:
		return

	if current_interaction_mode == &"world":
		_handle_world_interaction(delta, input_state)
		_world_panel_refresh_elapsed += delta
		if _world_panel_refresh_elapsed >= world_panel_refresh_interval_sec:
			_world_panel_refresh_elapsed = 0.0
			_refresh_world_panel()
		return

	_handle_legacy_interaction(delta, input_state)

func _unhandled_input(event: InputEvent) -> void:
	if current_interaction_mode != &"world" or current_interactable == null:
		return
	if _is_inventory_open() or _is_holding_object():
		return
	if event is not InputEventMouseButton:
		return

	var mouse_event := event as InputEventMouseButton
	if not mouse_event.pressed:
		return

	var step := 0
	if mouse_event.button_index == MOUSE_BUTTON_WHEEL_UP:
		step = -1
	elif mouse_event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
		step = 1
	if step == 0:
		return

	_cycle_world_panel_selection(step)
	get_viewport().set_input_as_handled()

func _resolve_interaction_target(collider: Node, hit_position: Vector3) -> Dictionary:
	var legacy_target: Node = _get_legacy_interactable(collider)
	if _should_prefer_legacy_target(legacy_target):
		return {"target": legacy_target, "mode": StringName(&"legacy")}

	var world_target: Node = _get_world_interactable(collider)
	if world_target != null:
		return {"target": world_target, "mode": StringName(&"world")}

	if legacy_target != null:
		return {"target": legacy_target, "mode": StringName(&"legacy")}

	if fallback_group_search_enabled:
		return _find_nearby_group_target(hit_position)

	return {"target": null, "mode": StringName(&"")}

func _get_legacy_interactable(node: Node) -> Node:
	var current: Node = node
	while current != null:
		if current.has_method("interact") and current.has_method("get_interaction_time"):
			if _is_interaction_enabled(current):
				return current
		for child in current.get_children():
			var child_node := child as Node
			if child_node == null:
				continue
			if child_node.has_method("interact") and child_node.has_method("get_interaction_time"):
				if _is_interaction_enabled(child_node):
					return child_node
		current = current.get_parent()
	return null

func _get_world_interactable(node: Node) -> Node:
	var current: Node = node
	var depth := 0
	while current != null and depth <= world_interactable_parent_search_depth:
		var candidate: Node = _find_world_interactable_recursive(current, world_interactable_descendant_search_depth)
		if candidate != null:
			return candidate
		current = current.get_parent()
		depth += 1
	return null

func _find_world_interactable_recursive(node: Node, remaining_depth: int) -> Node:
	if node == null or not is_instance_valid(node):
		return null
	if _is_world_interactable_candidate(node):
		return node
	if remaining_depth <= 0:
		return null
	for child in node.get_children():
		var child_node := child as Node
		if child_node == null:
			continue
		var nested: Node = _find_world_interactable_recursive(child_node, remaining_depth - 1)
		if nested != null:
			return nested
	return null

func _find_nearby_group_target(hit_position: Vector3) -> Dictionary:
	var tree: SceneTree = get_tree()
	if tree == null:
		return {"target": null, "mode": StringName(&"")}

	var max_dist_sq: float = fallback_interactable_max_distance * fallback_interactable_max_distance
	var best_dist_sq: float = INF
	var best: Node = null
	var best_mode: StringName = &""

	for group_name in fallback_interactable_groups:
		if String(group_name).strip_edges().is_empty():
			continue
		var nodes: Array = tree.get_nodes_in_group(group_name)
		for entry in nodes:
			var node3d := entry as Node3D
			if node3d == null or not is_instance_valid(node3d):
				continue

			var candidate_info := _resolve_group_node_target(node3d)
			var candidate: Node = candidate_info.get("target", null)
			if candidate == null:
				continue

			var dist_sq: float = node3d.global_position.distance_squared_to(hit_position)
			if dist_sq > max_dist_sq or dist_sq >= best_dist_sq:
				continue
			best_dist_sq = dist_sq
			best = candidate
			best_mode = candidate_info.get("mode", &"")

	return {"target": best, "mode": best_mode}

func _resolve_group_node_target(node: Node) -> Dictionary:
	var legacy_target: Node = _get_legacy_interactable(node)
	if _should_prefer_legacy_target(legacy_target):
		return {"target": legacy_target, "mode": StringName(&"legacy")}

	var world_target: Node = _get_world_interactable(node)
	if world_target != null:
		return {"target": world_target, "mode": StringName(&"world")}
	if legacy_target != null:
		return {"target": legacy_target, "mode": StringName(&"legacy")}
	return {"target": null, "mode": StringName(&"")}

func _focus_current_target() -> void:
	if current_interactable == null or not is_instance_valid(current_interactable):
		return
	if current_interaction_mode == &"world":
		if interaction_hud != null:
			if interaction_hud.has_method("hide_prompt"):
				interaction_hud.hide_prompt()
			if interaction_hud.has_method("update_progress"):
				interaction_hud.update_progress(0.0)
		is_interacting = false
		interact_timer = 0.0
		_world_panel_hold_executed = false
		_world_panel_refresh_elapsed = 0.0
		_call_world_focus(true)
		_refresh_world_panel()
		return

	_set_interactable_focus(current_interactable, true)
	var prompt_text := "交互"
	if current_interactable.has_method("get_prompt_text"):
		prompt_text = current_interactable.get_prompt_text()
	var trimmed_prompt: String = String(prompt_text).strip_edges()
	if trimmed_prompt.is_empty():
		trimmed_prompt = "交互"
	if interaction_hud != null and interaction_hud.has_method("show_prompt"):
		interaction_hud.show_prompt("[E] " + trimmed_prompt)

func _handle_world_interaction(delta: float, input_state: Dictionary) -> void:
	if current_interactable == null or not is_instance_valid(current_interactable):
		return
	if _world_panel_model == null:
		_refresh_world_panel()

	var is_pressing: bool = bool(input_state.get("pressed", false))
	var option := _get_selected_world_option()
	if is_pressing:
		if not is_interacting:
			is_interacting = true
			interact_timer = 0.0
			_world_panel_hold_executed = false
		interact_timer += delta

		if option != null and option.enabled and option.supports_hold():
			var hold_duration := option.get_safe_hold_duration(world_panel_default_hold_duration_sec)
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

	var hold_time := interact_timer
	var should_execute_tap := option != null and option.enabled and not _world_panel_hold_executed and option.supports_tap()
	is_interacting = false
	interact_timer = 0.0
	_world_panel_hold_executed = false

	if _world_panel_model != null and _world_panel_model.hold_progress > 0.0:
		_world_panel_model.hold_progress = 0.0
		_push_world_panel_model()

	if should_execute_tap:
		_execute_world_panel_option(false, hold_time)

func _handle_legacy_interaction(delta: float, input_state: Dictionary) -> void:
	var req_time := 0.0
	if current_interactable.has_method("get_interaction_time"):
		req_time = maxf(float(current_interactable.get_interaction_time()), 0.0)

	var is_pressing: bool = bool(input_state.get("pressed", false))
	if is_pressing:
		if not is_interacting:
			is_interacting = true
			interact_timer = 0.0
		interact_timer += delta
		if interaction_hud != null and interaction_hud.has_method("update_progress") and req_time > 0.0:
			interaction_hud.update_progress(interact_timer / req_time)
		if req_time > 0.0 and interact_timer >= req_time:
			if current_interactable.has_method("interact"):
				current_interactable.interact(Global.player)
			_clear_target()
		return

	if not is_interacting:
		return

	if interact_timer > 0.0 and interact_timer < req_time:
		if current_interactable.has_method("short_interact"):
			current_interactable.short_interact(Global.player)
	elif req_time <= 0.0:
		if current_interactable.has_method("interact"):
			current_interactable.interact(Global.player)

	is_interacting = false
	interact_timer = 0.0
	if interaction_hud != null and interaction_hud.has_method("update_progress"):
		interaction_hud.update_progress(0.0)

func _clear_target() -> void:
	if current_interactable != null and is_instance_valid(current_interactable):
		if current_interaction_mode == &"world":
			_call_world_focus(false)
			_hide_world_panel()
		else:
			_set_interactable_focus(current_interactable, false)
	is_interacting = false
	interact_timer = 0.0
	_world_panel_hold_executed = false
	_world_panel_refresh_elapsed = 0.0
	current_interactable = null
	current_interaction_mode = &""
	if interaction_hud != null:
		if interaction_hud.has_method("hide_prompt"):
			interaction_hud.hide_prompt()
		if interaction_hud.has_method("update_progress"):
			interaction_hud.update_progress(0.0)

func _set_interactable_focus(interactable: Node, focused: bool) -> void:
	if interactable == null:
		return
	if not interactable.has_method("set_interaction_focused"):
		return
	interactable.call("set_interaction_focused", focused)

func _refresh_world_panel() -> void:
	if current_interaction_mode != &"world":
		return
	if current_interactable == null or not is_instance_valid(current_interactable):
		_hide_world_panel()
		return
	if not current_interactable.has_method(WorldPanelContract.METHOD_BUILD_MODEL):
		_hide_world_panel()
		return

	var model_variant: Variant = current_interactable.call(
		WorldPanelContract.METHOD_BUILD_MODEL,
		self,
		_build_interaction_context()
	)
	if model_variant is not WorldInteractionPanelModel:
		_hide_world_panel()
		return

	_world_panel_model = model_variant as WorldInteractionPanelModel
	_apply_world_panel_selection_memory(_world_panel_model)
	_push_world_panel_model()

func _push_world_panel_model() -> void:
	if _world_panel_model == null:
		return
	var panel := _resolve_world_panel()
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
	var panel := _resolve_world_panel()
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
	var panel := _resolve_world_panel()
	if panel != null and panel.get_parent() is Node3D:
		return panel.get_parent() as Node3D
	return null

func _resolve_panel_camera() -> Camera3D:
	var viewport := get_viewport()
	if viewport == null:
		return null
	return viewport.get_camera_3d()

func _cycle_world_panel_selection(step: int) -> void:
	if _world_panel_model == null or _world_panel_model.options.is_empty():
		_refresh_world_panel()
		if _world_panel_model == null or _world_panel_model.options.is_empty():
			return

	var option_count := _world_panel_model.options.size()
	var next_index := _world_panel_model.selected_index + step
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
	var option := _world_panel_model.get_selected_option()
	if option == null or not option.enabled:
		return
	if current_interactable == null or not is_instance_valid(current_interactable):
		return
	if not current_interactable.has_method(WorldPanelContract.METHOD_EXECUTE_OPTION):
		return

	_world_panel_selected_option_id = _get_world_panel_option_id(option)
	current_interactable.call(
		WorldPanelContract.METHOD_EXECUTE_OPTION,
		_world_panel_selected_option_id,
		self,
		_build_interaction_context(),
		completed_by_hold,
		hold_time
	)
	_world_panel_refresh_elapsed = 0.0
	_refresh_world_panel()

func _call_world_focus(focused: bool) -> void:
	if current_interactable == null or not is_instance_valid(current_interactable):
		return
	if current_interactable.has_method(WorldPanelContract.METHOD_SET_FOCUSED):
		current_interactable.call(WorldPanelContract.METHOD_SET_FOCUSED, focused)
	var callback: StringName = WorldPanelContract.METHOD_FOCUS_ENTER if focused else WorldPanelContract.METHOD_FOCUS_EXIT
	if current_interactable.has_method(callback):
		current_interactable.call(callback, self, _build_interaction_context())

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
	var pressed := false
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

func _is_inventory_open() -> bool:
	var inventory = Global.player.get("inventory_handler") if Global.player else null
	return inventory != null and bool(inventory.inventory_visible)

func _is_holding_object() -> bool:
	if Global.player == null or Global.player.get("pickup_handler") == null:
		return false
	return bool(Global.player.pickup_handler.is_holding_object())

func _build_interaction_context() -> Dictionary:
	var context: Dictionary = {
		"player": Global.player,
		"source": self,
		"target": current_interactable,
		"mode": String(current_interaction_mode),
	}
	if interaction_ray != null and interaction_ray.is_colliding():
		context["collider"] = interaction_ray.get_collider()
		context["hit_position"] = interaction_ray.get_collision_point()
		context["hit_normal"] = interaction_ray.get_collision_normal()
	return context

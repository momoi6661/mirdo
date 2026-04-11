class_name PlayerInteractionComponent
extends Node

@export_category("References")
@export var interaction_ray: RayCast3D
@export var interaction_hud: Control

@export_category("Settings")
@export var interact_key: Key = KEY_E
@export var fallback_group_search_enabled: bool = true
@export var fallback_interactable_groups: PackedStringArray = PackedStringArray([&"xiaokong_interactable"])
@export_range(0.1, 3.0, 0.05) var fallback_interactable_max_distance: float = 0.6

var current_interactable: Node = null
var is_interacting: bool = false
var interact_timer: float = 0.0

func _physics_process(delta: float) -> void:
	if not interaction_ray or not interaction_hud:
		return
		
	# 【核心修复】：如果主背包是打开的，屏蔽一切交互！
	var inventory = Global.player.get("inventory_handler") if Global.player else null
	if inventory and inventory.inventory_visible:
		_clear_target()
		return
		
	# 如果手里已经拿着东西了，屏蔽一切准星交互

	var is_holding = false
	if Global.player and Global.player.get("pickup_handler"):
		is_holding = Global.player.pickup_handler.is_holding_object()
		
	if is_holding or not interaction_ray.is_colliding():
		_clear_target()
		return

		
	var collider = interaction_ray.get_collider()
	if not collider:
		_clear_target()
		return
		
	var interactable = _get_interactable(collider)
	if interactable == null and fallback_group_search_enabled:
		interactable = _find_nearby_group_interactable(interaction_ray.get_collision_point())
	
	if interactable != current_interactable:
		_clear_target()
		current_interactable = interactable
		if current_interactable:
			_set_interactable_focus(current_interactable, true)
			var prompt_text = "交互"
			if current_interactable.has_method("get_prompt_text"):
				prompt_text = current_interactable.get_prompt_text()
			var trimmed_prompt: String = String(prompt_text).strip_edges()
			if trimmed_prompt.is_empty():
				trimmed_prompt = "交互"
			interaction_hud.show_prompt("[E] " + trimmed_prompt)
			
	if current_interactable:
		_handle_interaction(delta)

func _get_interactable(node: Node) -> Node:
	var current: Node = node
	while current != null:
		if current.has_method("interact") and current.has_method("get_interaction_time"):
			if current.has_method("is_interaction_enabled") and not bool(current.call("is_interaction_enabled")):
				pass
			else:
				return current
		for child in current.get_children():
			if child.has_method("interact") and child.has_method("get_interaction_time"):
				if child.has_method("is_interaction_enabled") and not bool(child.call("is_interaction_enabled")):
					continue
				return child
		current = current.get_parent()
	return null

func _find_nearby_group_interactable(hit_position: Vector3) -> Node:
	var tree: SceneTree = get_tree()
	if tree == null:
		return null

	var max_dist_sq: float = fallback_interactable_max_distance * fallback_interactable_max_distance
	var best_dist_sq: float = INF
	var best: Node = null

	for group_name in fallback_interactable_groups:
		if String(group_name).strip_edges().is_empty():
			continue
		var nodes: Array = tree.get_nodes_in_group(group_name)
		for entry in nodes:
			var node3d := entry as Node3D
			if node3d == null or not is_instance_valid(node3d):
				continue

			var candidate: Node = _get_interactable(node3d)
			if candidate == null:
				continue

			var dist_sq: float = node3d.global_position.distance_squared_to(hit_position)
			if dist_sq > max_dist_sq or dist_sq >= best_dist_sq:
				continue
			best_dist_sq = dist_sq
			best = candidate

	return best

func _handle_interaction(delta: float) -> void:
	var req_time = 0.0
	if current_interactable.has_method("get_interaction_time"):
		req_time = current_interactable.get_interaction_time()
	
	# 检测按下状态
	var is_pressing = false
	var just_pressed = false
	var just_released = false
	
	if InputMap.has_action("interact"):
		is_pressing = Input.is_action_pressed("interact")
		just_pressed = Input.is_action_just_pressed("interact")
		just_released = Input.is_action_just_released("interact")
	else:
		is_pressing = Input.is_key_pressed(interact_key)
		# 因为在 process 里不好判断单帧，如果没有配置 action，这里会有一点点瑕疵，但依然能工作

	if is_pressing:
		is_interacting = true
		interact_timer += delta
		
		# 强制更新 HUD 读条
		if interaction_hud and interaction_hud.has_method("update_progress") and req_time > 0.0:
			interaction_hud.update_progress(interact_timer / req_time)
			
		# 【长按触发】：如果时间达到要求，且大于 0
		if req_time > 0.0 and interact_timer >= req_time:
			if current_interactable.has_method("interact"):
				current_interactable.interact(Global.player)
			_clear_target()
			
	elif just_released or (is_interacting and not is_pressing):
		# 【松手触发】：这是核心！如果没达到长按时间就松手了
		if is_interacting:
			if interact_timer > 0.0 and interact_timer < req_time:
				# 触发短按！
				if current_interactable.has_method("short_interact"):
					current_interactable.short_interact(Global.player)
			elif req_time <= 0.0:
				# 瞬间交互的物品
				if current_interactable.has_method("interact"):
					current_interactable.interact(Global.player)
					
			# 复位
			is_interacting = false
			interact_timer = 0.0
			if interaction_hud and interaction_hud.has_method("update_progress"):
				interaction_hud.update_progress(0.0)

func _clear_target() -> void:
	_set_interactable_focus(current_interactable, false)
	is_interacting = false
	interact_timer = 0.0
	current_interactable = null
	if interaction_hud:
		interaction_hud.hide_prompt()

func _set_interactable_focus(interactable: Node, focused: bool) -> void:
	if interactable == null:
		return
	if not interactable.has_method("set_interaction_focused"):
		return
	interactable.call("set_interaction_focused", focused)

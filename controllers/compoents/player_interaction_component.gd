class_name PlayerInteractionComponent
extends Node

@export_category("References")
@export var interaction_ray: RayCast3D
@export var interaction_hud: Control

@export_category("Settings")
@export var interact_key: Key = KEY_E

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
	
	if interactable != current_interactable:
		_clear_target()
		current_interactable = interactable
		if current_interactable:
			var prompt_text = "交互"
			if current_interactable.has_method("get_prompt_text"):
				prompt_text = current_interactable.get_prompt_text()
			interaction_hud.show_prompt("[E] " + prompt_text)
			
	if current_interactable:
		_handle_interaction(delta)

func _get_interactable(node: Node) -> Node:
	if node.has_method("interact") and node.has_method("get_interaction_time"):
		return node
	for child in node.get_children():
		if child.has_method("interact") and child.has_method("get_interaction_time"):
			return child
	return null

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
	is_interacting = false
	interact_timer = 0.0
	current_interactable = null
	if interaction_hud:
		interaction_hud.hide_prompt()

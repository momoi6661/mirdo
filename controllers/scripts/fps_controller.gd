class_name PlayerController
extends CharacterBody3D

@export var SPEED_DEFAULT : float = 3.0
@export var SPEED_CROUCH:float =2.0
@export var JUMP_VELOCITY : float = 4.5
@export var ACCEL:float=10.0
@export var MOUSE_SENSITIVITY : float = 0.5
@export var TILT_LOWER_LIMIT := deg_to_rad(-90.0)
@export var TILT_UPPER_LIMIT := deg_to_rad(90.0)
@export var CAMERA_CONTROLLER : Camera3D
@export_range(5,10,0.1) var CROUCH_SPEED:float=7.0
@export var step_handler:StepHandlerComponent
@export var pickup_handler:PickupHandlerComponent
@export var standing_collision:CollisionShape3D
@export var inventory_handler:InventoryDataService
@export var inventory_panel_3d: HoloInventoryPanel3D
@export var dual_inventory_panel: Node
@export var xiaokong_dialogue_panel: Node
@export var xiaokong_control_component_path: NodePath = NodePath("Components/XiaokongControlComponent")
@export var player_interaction_component_path: NodePath = NodePath("Components/PlayerInteractionComponent")
@export_range(0.5, 10.0, 0.1) var inventory_drop_distance: float = 2.5
@export var unique_id: String = "player_001"

@export_category("Footstep Audio")
@export var footstep_player_path: NodePath = NodePath("FootstepAudio3D")
@export var footstep_volume_db: float = -16.0
@export var footstep_min_speed: float = 0.9
@export var footstep_interval_walk: float = 0.45
@export var footstep_interval_sprint: float = 0.33
@export var footstep_pitch_min: float = 0.96
@export var footstep_pitch_max: float = 1.06
@export var footstep_clips: Array[AudioStream] = []
@export_dir var footstep_folder_path: String = "res://Audio/footsteps/concrete"

@export_category("Inventory UI Audio")
@export var inventory_ui_sfx_player_path: NodePath = NodePath("InventoryUISFXPlayer")
@export var inventory_open_sfx: AudioStream = preload("res://Audio/pausemenu/rollover1.ogg")
@export var inventory_close_sfx: AudioStream = preload("res://Audio/pausemenu/rollover2.ogg")
@export var inventory_ui_sfx_volume_db: float = -7.0

var interact_hold_timer:float=0.0
var is_interacting:bool=false
@export var long_press_time:float=0.50

@onready var marker_3d: Marker3D = $Marker3D
@onready var camera_offset: Node3D = $Marker3D/CameraOffset
@onready var animation_player: AnimationPlayer = $AnimationPlayer
@onready var shape_cast_3d: ShapeCast3D = $ShapeCast3D

var _speed:float
var _is_sprinting:bool=false
var _mouse_input : bool = false
var _rotation_input : float
var _tilt_input : float
var _time:float=0
var _bob_time:float=0.0 # 新增：专门用于记录晃动时间
var _head_bob_intensity:float=0
var _head_bob_target:float=0
var _was_on_floor:bool=true
var _jump_y_offset:float=0
var is_crouching:bool=false
var is_on_crouching:bool=false
var is_on_stand:bool=false
var _footstep_player: AudioStreamPlayer3D
var _footstep_elapsed: float = 0.0
var _inventory_ui_sfx_player: AudioStreamPlayer

var _mouse_rotation : Vector3
var _player_rotation : Vector3
var _camera_rotation : Vector3

var gravity = ProjectSettings.get_setting("physics/3d/default_gravity")

func _unhandled_input(event: InputEvent) -> void:
	if is_ui_text_input_focused():
		return
	_mouse_input = event is InputEventMouseMotion and Input.get_mouse_mode() == Input.MOUSE_MODE_CAPTURED
	if _mouse_input:
		_rotation_input = -event.relative.x * MOUSE_SENSITIVITY
		_tilt_input = -event.relative.y * MOUSE_SENSITIVITY

var _drop_timer: float = 0.0
var _is_holding_drop: bool = false
var _inventory_mouse_free_mode: bool = false
var _dialogue_mouse_free_mode: bool = false
var _xiaokong_control_component: Node = null
var _player_interaction_component: Node = null

func _input(event):
	if _is_custom_text_input_active():
		var key_event := event as InputEventKey
		var is_alt_toggle: bool = key_event != null and key_event.pressed and not key_event.echo and key_event.keycode == KEY_ALT
		if is_alt_toggle:
			if _is_dialogue_panel_open():
				_toggle_dialogue_mouse_mode()
			elif _is_inventory_panel_open():
				_toggle_inventory_mouse_mode()
			else:
				_toggle_mouse_capture_mode()
			var vp_alt := get_viewport()
			if vp_alt != null:
				vp_alt.set_input_as_handled()
			return
		else:
			if event.is_action_released("drop_item"):
				_is_holding_drop = false
				_drop_timer = 0.0
			return

	if event.is_action_pressed("inventory"):
		_toggle_inventory_panel()
		get_viewport().set_input_as_handled()
		return

	if is_ui_text_input_focused():
		if event.is_action_released("drop_item"):
			_is_holding_drop = false
			_drop_timer = 0.0
		return

	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_ALT:
		if _is_dialogue_panel_open():
			_toggle_dialogue_mouse_mode()
		elif _is_inventory_panel_open():
			_toggle_inventory_mouse_mode()
		else:
			_toggle_mouse_capture_mode()
		get_viewport().set_input_as_handled()
		return

	if event.is_action_pressed("sprint"):
		_is_sprinting = !_is_sprinting		
	
	# 处理长短按抛弃逻辑 (T 键)
	if event.is_action_pressed("drop_item"):
		if pickup_handler and pickup_handler.is_holding_object():
			_is_holding_drop = true
			_drop_timer = 0.0
	
	if event.is_action_released("drop_item"):
		if _is_holding_drop and pickup_handler:
			if _drop_timer < 0.3:
				pickup_handler.drop_object()  # 短按：轻轻放下
			else:
				pickup_handler.throw_object() # 长按：用力抛出
		_is_holding_drop = false
		_drop_timer = 0.0

func _toggle_mouse_capture_mode() -> void:
	if Input.get_mouse_mode() == Input.MOUSE_MODE_CAPTURED:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	else:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

func _toggle_inventory_mouse_mode() -> void:
	_inventory_mouse_free_mode = not _inventory_mouse_free_mode
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if _inventory_mouse_free_mode else Input.MOUSE_MODE_CAPTURED
	_update_inventory_alt_hint()

func _toggle_dialogue_mouse_mode() -> void:
	_dialogue_mouse_free_mode = not _dialogue_mouse_free_mode
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if _dialogue_mouse_free_mode else Input.MOUSE_MODE_CAPTURED


func _process(delta):
	# 只要按住 T 键，就累加时间
	if _is_holding_drop:
		_drop_timer += delta


func add_to_inventory(item: ItemData) -> bool:
	if not inventory_handler:
		print("错误: inventory_handler 未设置")
		return false

	return inventory_handler.PickupItem(item)


func _toggle_inventory_panel() -> void:
	if _is_dual_inventory_panel_open():
		_close_dual_inventory_panel()
		return
	_set_inventory_panel_open(not _is_inventory_panel_open())


func _set_inventory_panel_open(should_open: bool) -> void:
	var was_open: bool = _is_single_inventory_panel_open()
	if _is_dual_inventory_panel_open():
		if not should_open:
			_close_dual_inventory_panel()
		return

	if inventory_panel_3d and is_instance_valid(inventory_panel_3d):
		if should_open:
			inventory_panel_3d.show_panel()
		else:
			inventory_panel_3d.hide_panel()

	if inventory_handler and is_instance_valid(inventory_handler):
		inventory_handler.inventory_visible = should_open

	if should_open:
		_inventory_mouse_free_mode = false
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	else:
		_inventory_mouse_free_mode = false
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	_update_inventory_alt_hint()

	var now_open: bool = _is_single_inventory_panel_open()
	if was_open != now_open:
		_play_inventory_ui_sfx(now_open)


func _is_inventory_panel_open() -> bool:
	if _is_dual_inventory_panel_open():
		return true
	if inventory_panel_3d and is_instance_valid(inventory_panel_3d):
		return inventory_panel_3d.is_panel_open()
	if inventory_handler and is_instance_valid(inventory_handler):
		return inventory_handler.inventory_visible
	return false

func _is_single_inventory_panel_open() -> bool:
	if _is_dual_inventory_panel_open():
		return false
	if inventory_panel_3d and is_instance_valid(inventory_panel_3d):
		return inventory_panel_3d.is_panel_open()
	return false

func _update_inventory_alt_hint() -> void:
	var is_inventory_open: bool = _is_inventory_panel_open()
	var is_mouse_free_for_inventory: bool = _inventory_mouse_free_mode and is_inventory_open

	if inventory_panel_3d != null and is_instance_valid(inventory_panel_3d):
		if inventory_panel_3d.has_method("set_alt_hint_state"):
			inventory_panel_3d.call("set_alt_hint_state", is_mouse_free_for_inventory and _is_single_inventory_panel_open())

	if _has_dual_inventory_panel() and dual_inventory_panel.has_method("set_alt_hint_state"):
		dual_inventory_panel.call("set_alt_hint_state", is_mouse_free_for_inventory)


func open_loot_dual_panel(container: Node) -> void:
	if inventory_panel_3d and is_instance_valid(inventory_panel_3d) and inventory_panel_3d.is_panel_open():
		inventory_panel_3d.hide_panel()
	_inventory_mouse_free_mode = false
	_update_inventory_alt_hint()
	_open_dual_inventory_panel(container)
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _has_dual_inventory_panel() -> bool:
	return dual_inventory_panel != null and is_instance_valid(dual_inventory_panel)


func _is_dual_inventory_panel_open() -> bool:
	if not _has_dual_inventory_panel():
		return false
	if not dual_inventory_panel.has_method("is_dual_panel_open"):
		return false
	return bool(dual_inventory_panel.call("is_dual_panel_open"))


func _close_dual_inventory_panel() -> void:
	if not _has_dual_inventory_panel():
		return
	_inventory_mouse_free_mode = false
	if dual_inventory_panel.has_method("close_dual_panel"):
		dual_inventory_panel.call("close_dual_panel")
	_update_inventory_alt_hint()
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _open_dual_inventory_panel(container: Node) -> void:
	if not _has_dual_inventory_panel():
		return
	if dual_inventory_panel.has_method("open_for_container"):
		dual_inventory_panel.call("open_for_container", container)


func _on_loot_container_switch_requested(container: Node, player_node: Node) -> void:
	if player_node != self:
		return
	if not _is_dual_inventory_panel_open():
		return
	var target_container := container as LootContainerComponent
	if target_container == null:
		return
	if target_container.has_method("get_operate_range_area"):
		var area := target_container.call("get_operate_range_area") as Area3D
		if area == null or not area.overlaps_body(self):
			return
	if _has_dual_inventory_panel() and dual_inventory_panel.has_method("get_active_container"):
		var active_container := dual_inventory_panel.call("get_active_container") as LootContainerComponent
		if active_container == target_container:
			return
	_open_dual_inventory_panel(target_container)


func _on_inventory_drop_requested(item: ItemData, amount: int) -> void:
	_spawn_dropped_inventory_item(item, amount)


func _spawn_dropped_inventory_item(item: ItemData, amount: int) -> void:
	if item == null or amount <= 0:
		return

	var item_scene := item.get_scene()
	if item_scene == null:
		return

	var viewport := get_viewport()
	if viewport == null:
		return

	var camera := CAMERA_CONTROLLER
	if camera == null or not is_instance_valid(camera):
		camera = viewport.get_camera_3d()

	var spawn_pos := global_position + Vector3(0, 0.2, -1.0)
	if camera != null:
		var mouse_pos := viewport.get_mouse_position()
		var ray_from := camera.project_ray_origin(mouse_pos)
		var ray_to := ray_from + camera.project_ray_normal(mouse_pos) * inventory_drop_distance
		var world := viewport.get_world_3d()
		if world != null:
			var query := PhysicsRayQueryParameters3D.create(ray_from, ray_to, 1)
			query.exclude = [self]
			query.collision_mask = 3
			var result := world.direct_space_state.intersect_ray(query)
			if not result.is_empty():
				spawn_pos = result.position + result.normal * 0.08
			else:
				spawn_pos = ray_to
	else:
		var forward := -global_basis.z.normalized()
		spawn_pos = global_position + forward * 1.1
		spawn_pos.y = global_position.y + 0.2

	var spawn_parent := get_parent()
	if spawn_parent == null:
		return

	for i in range(amount):
		var dropped_item := item_scene.instantiate() as Node3D
		if dropped_item == null:
			continue
		spawn_parent.add_child(dropped_item)
		var spread_x := (float(i) - float(amount - 1) * 0.5) * 0.14
		var spread_z := float(i % 2) * 0.1
		dropped_item.global_position = spawn_pos + Vector3(spread_x, 0.0, spread_z)

func _update_camera(delta):
	_mouse_rotation.x += _tilt_input * delta
	_mouse_rotation.x = clamp(_mouse_rotation.x, TILT_LOWER_LIMIT, TILT_UPPER_LIMIT)
	_mouse_rotation.y += _rotation_input * delta
	
	_player_rotation = Vector3(0.0,_mouse_rotation.y,0.0)
	_camera_rotation = Vector3(_mouse_rotation.x,0.0,0.0)
	
	marker_3d.transform.basis = Basis.from_euler(_camera_rotation)
	global_transform.basis = Basis.from_euler(_player_rotation)
	
	_time+=delta
	
	_head_bob_intensity = lerpf(_head_bob_intensity, _head_bob_target, 10.0 * delta)
	
	# === 优化后的视角晃动逻辑 ===
	var head_bob = Vector3.ZERO
	# 获取玩家实际的水平移动速度
	var horizontal_vel = Vector2(velocity.x, velocity.z).length()
	var speed_ratio = clamp(horizontal_vel / SPEED_DEFAULT, 0.0, 2.0)
	
	# 只有在实际移动时，才推进晃动的时间
	if is_on_floor() and horizontal_vel > 0.1:
		_bob_time += delta * speed_ratio * 1.2
		# Y轴使用 sin，X轴使用 cos，形成更自然的 "∞" 字形晃动
		head_bob.y = sin(_bob_time * 8) * _head_bob_intensity * 0.04
		head_bob.x = cos(_bob_time * 4) * _head_bob_intensity * 0.02
	# ===========================
	
	if not is_on_floor():
		var jump_progress=clamp(velocity.y/JUMP_VELOCITY, -1.0, 1.0)
		_jump_y_offset=lerpf(_jump_y_offset,jump_progress*0.2,0.1)
	else:
		_jump_y_offset=lerpf(_jump_y_offset,0,0.2)
	_was_on_floor=is_on_floor()
	
	camera_offset.position=head_bob+Vector3(0,_jump_y_offset,0)
	
	CAMERA_CONTROLLER.global_transform=camera_offset.get_global_transform_interpolated()
	CAMERA_CONTROLLER.rotation.z = 0.0
	
	_rotation_input = 0.0
	_tilt_input = 0.0

func get_input_direction():
	if is_ui_text_input_focused() or _is_custom_text_input_active():
		return Vector3.ZERO
	var input_dir = Input.get_vector("move_left", "move_right", "move_forward", "move_backward")
	var direction = (transform.basis * Vector3(input_dir.x, 0, input_dir.y)).normalized()
	return direction

func is_ui_text_input_focused() -> bool:
	var viewport := get_viewport()
	if viewport == null:
		return false
	var focus_owner := viewport.gui_get_focus_owner()
	if focus_owner == null:
		return false
	var control := focus_owner as Control
	if control == null:
		return false
	return _is_text_input_control(control)

func _is_text_input_control(control: Control) -> bool:
	if control == null:
		return false
	if control is LineEdit:
		return true
	if control is TextEdit:
		return true
	if control is CodeEdit:
		return true
	return false

func _is_custom_text_input_active() -> bool:
	if xiaokong_dialogue_panel == null or not is_instance_valid(xiaokong_dialogue_panel):
		return false
	if xiaokong_dialogue_panel.has_method("is_text_input_active"):
		return bool(xiaokong_dialogue_panel.call("is_text_input_active"))
	return false

func _is_dialogue_panel_open() -> bool:
	if xiaokong_dialogue_panel == null or not is_instance_valid(xiaokong_dialogue_panel):
		return false
	if xiaokong_dialogue_panel.has_method("is_panel_open"):
		return bool(xiaokong_dialogue_panel.call("is_panel_open"))
	return false

func is_gameplay_input_blocked() -> bool:
	return _is_custom_text_input_active() or is_ui_text_input_focused()

func _resolve_xiaokong_control_component() -> Node:
	if _xiaokong_control_component != null and is_instance_valid(_xiaokong_control_component):
		return _xiaokong_control_component
	if xiaokong_control_component_path != NodePath():
		_xiaokong_control_component = get_node_or_null(xiaokong_control_component_path)
	if _xiaokong_control_component == null:
		_xiaokong_control_component = get_node_or_null("Components/XiaokongControlComponent")
	return _xiaokong_control_component

func _resolve_player_interaction_component() -> Node:
	if _player_interaction_component != null and is_instance_valid(_player_interaction_component):
		return _player_interaction_component
	if player_interaction_component_path != NodePath():
		_player_interaction_component = get_node_or_null(player_interaction_component_path)
	if _player_interaction_component == null:
		_player_interaction_component = get_node_or_null("Components/PlayerInteractionComponent")
	return _player_interaction_component

func _set_world_interaction_blocked(blocked: bool) -> void:
	var interaction_component := _resolve_player_interaction_component()
	if interaction_component == null or not is_instance_valid(interaction_component):
		return
	if interaction_component.has_method("set_external_ui_blocked"):
		interaction_component.call("set_external_ui_blocked", blocked)

func _find_dialogue_component_recursive(root_node: Node) -> Node:
	if root_node == null:
		return null
	if root_node.has_method("send_player_text"):
		return root_node
	for child in root_node.get_children():
		var child_node := child as Node
		if child_node == null:
			continue
		var nested := _find_dialogue_component_recursive(child_node)
		if nested != null:
			return nested
	return null

func _send_dialogue_to_xiaokong(text: String, payload: Dictionary) -> bool:
	var clean_text: String = text.strip_edges()
	if clean_text.is_empty():
		return false

	var xiaokong_path: String = String(payload.get("xiaokong_path", "")).strip_edges()
	var controller_node := _resolve_xiaokong_control_component()
	if controller_node != null and is_instance_valid(controller_node):
		if not xiaokong_path.is_empty() and controller_node.has_method("bind_target_by_path"):
			controller_node.call("bind_target_by_path", xiaokong_path)
		if controller_node.has_method("send_dialogue_text"):
			return bool(controller_node.call("send_dialogue_text", clean_text))

	if xiaokong_path.is_empty():
		return false
	var xiaokong_root: Node = get_node_or_null(NodePath(xiaokong_path))
	if xiaokong_root == null:
		return false
	var dialogue_component := _find_dialogue_component_recursive(xiaokong_root)
	if dialogue_component == null:
		return false
	var result: Variant = dialogue_component.call("send_player_text", clean_text)
	if result is Dictionary:
		return bool((result as Dictionary).get("ok", false))
	return bool(result)

func _on_global_xiaokong_dialogue_requested(payload: Dictionary) -> void:
	if xiaokong_dialogue_panel == null or not is_instance_valid(xiaokong_dialogue_panel):
		return
	_dialogue_mouse_free_mode = false
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	_set_world_interaction_blocked(true)
	if xiaokong_dialogue_panel.has_method("open_for_payload"):
		xiaokong_dialogue_panel.call("open_for_payload", payload)
	elif xiaokong_dialogue_panel.has_method("open_panel"):
		xiaokong_dialogue_panel.call("open_panel")

func _on_xiaokong_dialogue_panel_submit(text: String, payload: Dictionary) -> void:
	_send_dialogue_to_xiaokong(text, payload)

func _on_xiaokong_dialogue_panel_visibility_changed(is_open: bool) -> void:
	_set_world_interaction_blocked(is_open)
	if not is_open:
		_dialogue_mouse_free_mode = false
		if not _is_inventory_panel_open():
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

func apply_movement(allow_move: bool, stop_when_no_input: bool, head_bob_target: float, delta: float, direction: Vector3 = Vector3.ZERO):
	if direction == Vector3.ZERO:
		direction = get_input_direction()
	
	if allow_move and direction:
		velocity.x = lerp(velocity.x, direction.x * _speed, ACCEL * delta)
		velocity.z = lerp(velocity.z, direction.z * _speed, ACCEL * delta)
		_head_bob_target = head_bob_target
	elif stop_when_no_input:
		var stop_speed = _speed * ACCEL * delta
		velocity.x = move_toward(velocity.x, 0, stop_speed)
		velocity.z = move_toward(velocity.z, 0, stop_speed)
		_head_bob_target = head_bob_target
	else:
		_head_bob_target = head_bob_target
	
	var is_climbing = false
	if step_handler:
		is_climbing = step_handler.handle_step_climbing(delta)
	
	if !is_climbing:
		move_and_slide()
		
		handle_rigid_body_collisions()
		
		if step_handler:
			step_handler.handle_after_move_slide(delta)

	_update_footstep_audio(delta)

func _resolve_footstep_player() -> void:
	_footstep_player = get_node_or_null(footstep_player_path) as AudioStreamPlayer3D
	if _footstep_player == null:
		_footstep_player = get_node_or_null("FootstepAudio3D") as AudioStreamPlayer3D

func _autoload_footstep_clips() -> void:
	if not footstep_clips.is_empty():
		return
	if footstep_folder_path.is_empty():
		return

	var dir := DirAccess.open(footstep_folder_path)
	if dir == null:
		return

	var file_names: PackedStringArray = dir.get_files()
	file_names.sort()
	for file_name in file_names:
		var lower_name := file_name.to_lower()
		var is_audio_file := lower_name.ends_with(".ogg") or lower_name.ends_with(".wav") or lower_name.ends_with(".mp3")
		if not is_audio_file:
			continue
		var stream_path := footstep_folder_path.path_join(file_name)
		var clip := load(stream_path) as AudioStream
		if clip != null:
			footstep_clips.append(clip)

func _apply_footstep_volume() -> void:
	if _footstep_player == null:
		return
	_footstep_player.volume_db = footstep_volume_db

func _update_footstep_audio(delta: float) -> void:
	if _footstep_player == null:
		return
	var horizontal_speed: float = Vector2(velocity.x, velocity.z).length()
	var should_play_step := is_on_floor() and horizontal_speed >= footstep_min_speed
	if not should_play_step:
		_footstep_elapsed = 0.0
		return

	var base_interval: float = footstep_interval_sprint if _is_sprinting else footstep_interval_walk
	var speed_scale: float = clampf(horizontal_speed / maxf(0.01, SPEED_DEFAULT), 0.75, 2.0)
	var step_interval: float = maxf(0.08, base_interval / speed_scale)
	_footstep_elapsed += delta
	if _footstep_elapsed < step_interval:
		return
	_footstep_elapsed = 0.0
	_play_footstep_audio()

func _play_footstep_audio() -> void:
	if _footstep_player == null:
		return
	if not footstep_clips.is_empty():
		var clip_index: int = randi() % footstep_clips.size()
		var clip: AudioStream = footstep_clips[clip_index]
		if clip != null:
			_footstep_player.stream = clip
	if _footstep_player.stream == null:
		return
	_apply_footstep_volume()
	_footstep_player.pitch_scale = randf_range(footstep_pitch_min, footstep_pitch_max)
	_footstep_player.play()

func _resolve_inventory_ui_sfx_player() -> void:
	_inventory_ui_sfx_player = get_node_or_null(inventory_ui_sfx_player_path) as AudioStreamPlayer
	if _inventory_ui_sfx_player == null:
		_inventory_ui_sfx_player = get_node_or_null("InventoryUISFXPlayer") as AudioStreamPlayer
	if _inventory_ui_sfx_player == null:
		_inventory_ui_sfx_player = AudioStreamPlayer.new()
		_inventory_ui_sfx_player.name = "InventoryUISFXPlayer"
		add_child(_inventory_ui_sfx_player)
	_inventory_ui_sfx_player.bus = "UI" if AudioServer.get_bus_index("UI") != -1 else "Master"
	_inventory_ui_sfx_player.volume_db = inventory_ui_sfx_volume_db

func _play_inventory_ui_sfx(is_opening: bool) -> void:
	if _inventory_ui_sfx_player == null:
		return
	var stream: AudioStream = inventory_open_sfx if is_opening else inventory_close_sfx
	if stream == null:
		return
	_inventory_ui_sfx_player.stop()
	_inventory_ui_sfx_player.stream = stream
	_inventory_ui_sfx_player.play()
	
func handle_rigid_body_collisions():
	if not has_node("KickArea"):
		return
	
	var kick_area = $KickArea
	var bodies = kick_area.get_overlapping_bodies()
	
	var horizontal_velocity = Vector3(velocity.x, 0, velocity.z)
	var speed = horizontal_velocity.length()
	if speed < 0.1:
		return
		
	var delta = get_physics_process_delta_time()
		
	for body in bodies:
		if body is RigidBody3D:
			# 混合玩家移动方向和物体相对方向
			var to_body = (body.global_position - global_position)
			to_body.y = 0.0
			to_body = to_body.normalized()
			
			var move_dir = horizontal_velocity.normalized()
			
			# 将两个方向混合：60%向前推，40%往旁边挤开
			var push_direction = (move_dir * 0.6 + to_body * 0.4).normalized()
			
			# 修复：在物理帧连续执行时，必须根据 delta 缩小冲量，同时乘上物体质量，实现真实推力
			var force_magnitude = speed * body.mass * 8.0 * delta
			body.apply_central_impulse(push_direction * force_magnitude)

func push_rigid_body(rigid_body: RigidBody3D, collision: KinematicCollision3D):
	pass # 保留空函数防止有其他地方调用
	
func _ready():
	randomize()
	_speed=SPEED_DEFAULT
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	_resolve_footstep_player()
	_autoload_footstep_clips()
	_apply_footstep_volume()
	_resolve_inventory_ui_sfx_player()
	shape_cast_3d.add_exception($'.')
	add_to_group("player")
	if not is_in_group("Savable"):
		add_to_group("Savable")
	if not is_in_group("Player"):
		add_to_group("Player")
		
	shape_cast_3d.position.y=1.7
	Global.player=self
	if Global != null and Global.has_signal("loot_container_switch_requested"):
		var switch_callable := Callable(self, "_on_loot_container_switch_requested")
		if not Global.is_connected("loot_container_switch_requested", switch_callable):
			Global.connect("loot_container_switch_requested", switch_callable)
	if Global != null and Global.has_signal("xiaokong_dialogue_requested"):
		var xk_dialogue_callable := Callable(self, "_on_global_xiaokong_dialogue_requested")
		if not Global.is_connected("xiaokong_dialogue_requested", xk_dialogue_callable):
			Global.connect("xiaokong_dialogue_requested", xk_dialogue_callable)
	
	print("step_handler: ", step_handler)
	if !step_handler:
		if has_node("Components/StepHandler"):
			step_handler = $Components/StepHandler
	
	print("pickup_handler: ", pickup_handler)
	if !pickup_handler:
		if has_node("Components/PickupHandler"):
			pickup_handler = $Components/PickupHandler

	if inventory_panel_3d and is_instance_valid(inventory_panel_3d):
		if inventory_handler and is_instance_valid(inventory_handler):
			inventory_panel_3d.set_inventory_data(inventory_handler)
		inventory_panel_3d.hide_panel()
		_update_inventory_alt_hint()

	if _has_dual_inventory_panel():
		if inventory_handler and is_instance_valid(inventory_handler):
			if dual_inventory_panel.has_method("bind_player_inventory"):
				dual_inventory_panel.call("bind_player_inventory", inventory_handler)
		if dual_inventory_panel.has_signal("world_drop_requested"):
			var drop_callable := Callable(self, "_on_inventory_drop_requested")
			if not dual_inventory_panel.is_connected("world_drop_requested", drop_callable):
				dual_inventory_panel.connect("world_drop_requested", drop_callable)
	elif inventory_panel_3d and is_instance_valid(inventory_panel_3d):
		if not inventory_panel_3d.drop_requested.is_connected(_on_inventory_drop_requested):
			inventory_panel_3d.drop_requested.connect(_on_inventory_drop_requested)

	if inventory_handler and is_instance_valid(inventory_handler):
		inventory_handler.inventory_visible = false

	_resolve_xiaokong_control_component()
	_resolve_player_interaction_component()
	_set_world_interaction_blocked(false)
	if xiaokong_dialogue_panel != null and is_instance_valid(xiaokong_dialogue_panel):
		if xiaokong_dialogue_panel.has_method("hide_panel"):
			xiaokong_dialogue_panel.call("hide_panel")
		if xiaokong_dialogue_panel.has_signal("dialogue_submit_requested"):
			var submit_callable := Callable(self, "_on_xiaokong_dialogue_panel_submit")
			if not xiaokong_dialogue_panel.is_connected("dialogue_submit_requested", submit_callable):
				xiaokong_dialogue_panel.connect("dialogue_submit_requested", submit_callable)
		if xiaokong_dialogue_panel.has_signal("panel_visibility_changed"):
			var visibility_callable := Callable(self, "_on_xiaokong_dialogue_panel_visibility_changed")
			if not xiaokong_dialogue_panel.is_connected("panel_visibility_changed", visibility_callable):
				xiaokong_dialogue_panel.connect("panel_visibility_changed", visibility_callable)

# --- 存档系统自定义接口 ---

func _get_custom_save_data() -> Dictionary:
	var data = {
		"mouse_rotation": _mouse_rotation,
		"state": $StateMachine.CURRENT_STATE.name,
		"is_crouching": is_crouching,
		"is_sprinting": _is_sprinting
	}
	
	if inventory_handler:
		data["inventory"] = inventory_handler.get_inventory_data()
		
	return data

func _load_custom_save_data(data: Dictionary) -> void:
	# 1. 物理脱离：防止加载瞬间产生位移冲突
	set_physics_process(false) 
	
	# 2. 恢复旋转和视角
	_mouse_rotation = data.mouse_rotation
	_player_rotation = Vector3(0, _mouse_rotation.y, 0)
	_camera_rotation = Vector3(_mouse_rotation.x, 0, 0)
	global_transform.basis = Basis.from_euler(_player_rotation)
	marker_3d.transform.basis = Basis.from_euler(_camera_rotation)
	
	# 3. 恢复基础变量并压制状态机
	is_crouching = data.is_crouching
	_is_sprinting = data.is_sprinting
	velocity = Vector3.ZERO
	
	# 恢复背包数据
	if data.has("inventory") and inventory_handler:
		inventory_handler.load_inventory_data(data["inventory"])
	
	var sm = $StateMachine
	sm.is_locked = true
	sm._init_states()
	
	# 4. 恢复状态并强制同步变量（解决恢复到 Idle 的关键）
	var target_state = sm.states.get(data.state)
	if target_state:
		if sm.CURRENT_STATE:
			sm.CURRENT_STATE.exit()
		sm.CURRENT_STATE = target_state
		
		# 强制设置状态相关变量，不完全依赖 enter() 的自动处理
		if data.state == "CrouchState":
			_speed = SPEED_CROUCH
			is_crouching = true
			shape_cast_3d.position.y = 1.5
			animation_player.play("crouch")
			animation_player.advance(1.0)
		else:
			_speed = SPEED_DEFAULT
			is_crouching = false
			shape_cast_3d.position.y = 1.7
			animation_player.play("RESET")
			animation_player.advance(1.0)
		
		target_state.enter()
	
	# 5. 延迟解锁
	get_tree().create_timer(0.2).timeout.connect(func():
		print("\n--- [Player] 加载锁定解除 ---")
		set_physics_process(true)
		# 关键：强制刷新物理状态
		force_update_transform()
		move_and_slide() 
		
		# 再次确保碰撞盒高度正确
		if is_crouching: 
			shape_cast_3d.position.y = 1.5
			
		print("[Player] 解锁瞬间 is_on_floor: ", is_on_floor())
		sm.is_locked = false
	)

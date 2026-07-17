class_name PlayerController
extends CharacterBody3D

@export var SPEED_DEFAULT : float = 3.0
@export var SPEED_CROUCH:float =2.0
@export var JUMP_VELOCITY : float = 4.5
@export var ACCEL:float=10.0
# 鼠标事件已经是“本帧移动了多少像素”，这里直接换算成弧度。
# 旧实现又乘了一次 delta，导致帧率越高越慢；修复后使用小的“弧度/像素”值。
@export_range(0.0005, 0.02, 0.0005) var MOUSE_SENSITIVITY : float = 0.003
@export_range(8.0, 240.0, 1.0) var max_mouse_delta: float = 80.0
@export var recapture_mouse_on_focus: bool = true
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
@export var xiaokong_status_panel: Node
@export var player_status_screen: Node
@export var xiaokong_control_component_path: NodePath = NodePath("Components/XiaokongControlComponent")
@export var player_interaction_component_path: NodePath = NodePath("Components/PlayerInteractionComponent")
@export_range(0.5, 10.0, 0.1) var inventory_drop_distance: float = 2.5
@export var unique_id: String = "player_001"

@export_category("Footstep Audio")
@export var footstep_player_path: NodePath = NodePath("FootstepAudio3D")
@export var footstep_volume_db: float = -15.0
@export var footstep_min_speed: float = 0.65
@export var footstep_interval_walk: float = 0.58
@export var footstep_interval_sprint: float = 0.40
@export var footstep_pitch_min: float = 0.96
@export var footstep_pitch_max: float = 1.02
@export var footstep_volume_jitter_db: float = 0.9
@export var footstep_landing_min_fall_speed: float = 3.0
@export var footstep_landing_volume_boost_db: float = 2.0
@export var footstep_clips: Array[AudioStream] = []
@export_dir var footstep_folder_path: String = "res://Audio/footsteps/sneakers_soft"
@export_file("*.mp3", "*.ogg", "*.wav") var footstep_loop_stream_path: String = "res://Audio/footsteps/sneakers_soft/tennis_tile_medium_pace_170500.mp3"
@export_file("*.mp3", "*.ogg", "*.wav") var footstep_landing_stream_path: String = "res://Audio/footsteps/sneakers_soft/tennis_tile_scuffs_170499.mp3"
@export var footstep_bus_name: StringName = &"SFX"
@export var footstep_use_continuous_loop: bool = true
## 默认只使用玩家身上的 AudioStreamPlayer3D。
## 旧的 2D fallback 会把脚步声直接贴到耳机上，还可能和 3D 节点重复播放。
@export var footstep_use_2d_audible_fallback: bool = false
@export_range(0.0, 12.0, 0.1) var footstep_stop_fade_db_per_sec: float = 7.0
@export_range(-40.0, 6.0, 0.5) var footstep_landing_volume_db: float = -16.0
@export_range(0.5, 20.0, 0.1) var footstep_max_distance: float = 9.0
@export_range(0.1, 5.0, 0.1) var footstep_unit_size: float = 1.0
@export_range(0.0, 1.0, 0.05) var footstep_panning_strength: float = 0.55
@export_range(-24.0, 6.0, 0.5) var footstep_max_db: float = -5.0

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
var _footstep_landing_player: AudioStreamPlayer3D
var _footstep_audible_player: AudioStreamPlayer
var _footstep_landing_audible_player: AudioStreamPlayer
var _footstep_elapsed: float = 0.0
var _last_footstep_clip_index: int = -1
var _was_grounded_for_footsteps: bool = false
var _last_footstep_vertical_velocity: float = 0.0
var _footstep_loop_active: bool = false
var _footstep_loop_target_volume_db: float = -21.0
var _inventory_ui_sfx_player: AudioStreamPlayer
var _footstep_debug_elapsed: float = 0.0
var _footstep_was_moving: bool = false

var _mouse_rotation : Vector3
var _player_rotation : Vector3
var _camera_rotation : Vector3
var _window_has_focus: bool = true
var _mouse_mode_before_focus_out: int = Input.MOUSE_MODE_CAPTURED
var _mouse_sensitivity_scale: float = 1.0

var gravity = ProjectSettings.get_setting("physics/3d/default_gravity")

func _resolve_global_node() -> Node:
	return get_node_or_null(NodePath("/root/Global"))

func _unhandled_input(event: InputEvent) -> void:
	# 先在 _input 阶段处理鼠标，避免 3D 控件或对话面板提前吞掉鼠标事件。
	# 这里保留同一个处理函数作为未被 UI 消费时的兜底入口。
	if _handle_mouse_look_event(event):
		return
	if is_ui_text_input_focused() or _is_custom_text_input_active():
		if event is InputEventKey:
			var vp_text := get_viewport()
			if vp_text != null:
				vp_text.set_input_as_handled()
		return

func _handle_mouse_look_event(event: InputEvent) -> bool:
	if not event is InputEventMouseMotion:
		return false
	if is_ui_text_input_focused() or _is_custom_text_input_active():
		return false
	if not _window_has_focus or Input.get_mouse_mode() != Input.MOUSE_MODE_CAPTURED:
		return false

	_mouse_input = true
	# 累积事件而不是覆盖事件，避免高回报率鼠标丢帧；每帧上限避免窗口切回时突然甩视角。
	var motion := event as InputEventMouseMotion
	var relative := motion.relative.limit_length(max_mouse_delta)
	var sensitivity := MOUSE_SENSITIVITY * _mouse_sensitivity_scale
	_rotation_input = clampf(_rotation_input - relative.x * sensitivity, -0.35, 0.35)
	_tilt_input = clampf(_tilt_input - relative.y * sensitivity, -0.35, 0.35)
	get_viewport().set_input_as_handled()
	return true

func _notification(what: int) -> void:
	# 窗口失焦时释放鼠标和按键，避免点击到编辑器后角色继续移动或视角漂移。
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT:
		_window_has_focus = false
		_mouse_mode_before_focus_out = Input.mouse_mode
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		_release_ui_captured_movement_input()
	elif what == NOTIFICATION_APPLICATION_FOCUS_IN:
		_window_has_focus = true
		if recapture_mouse_on_focus and _should_capture_mouse_after_focus():
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

func _should_capture_mouse_after_focus() -> bool:
	if get_tree() == null or get_tree().paused:
		return false
	return not _is_dialogue_panel_open() and not _is_inventory_panel_open() and not _is_status_panel_open() and not is_ui_text_input_focused()

var _drop_timer: float = 0.0
var _is_holding_drop: bool = false
var _inventory_mouse_free_mode: bool = false
var _dialogue_mouse_free_mode: bool = false
var _xiaokong_control_component: Node = null
var _player_interaction_component: Node = null

func _input(event):
	# 在 GUI 处理前消费鼠标移动，避免界面控件吞掉第一人称视角输入。
	if _handle_mouse_look_event(event):
		return
	if _is_custom_text_input_active():
		var key_event := event as InputEventKey
		if key_event != null:
			if event.is_action_released("drop_item"):
				_is_holding_drop = false
				_drop_timer = 0.0
			var vp_text := get_viewport()
			if vp_text != null:
				vp_text.set_input_as_handled()
			return
		return

	if event.is_action_pressed("inventory"):
		_toggle_inventory_panel()
		get_viewport().set_input_as_handled()
		return

	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_H:
		_toggle_player_status_screen()
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
	# 摄像机属于玩家视觉层，直接由玩家节点驱动，不依赖 StateMachine 是否
	# 被 UI、存档或行为锁定。这样角色移动/状态切换时镜头始终保持跟随。
	_update_camera(delta)
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


func _set_inventory_panel_open(should_open: bool, preserve_use_context: bool = false) -> void:
	var was_open: bool = _is_single_inventory_panel_open()
	if _is_dual_inventory_panel_open():
		if not should_open:
			_close_dual_inventory_panel()
		return

	if inventory_panel_3d and is_instance_valid(inventory_panel_3d):
		if inventory_panel_3d.has_method("clear_use_target_context") and (not should_open or not preserve_use_context):
			inventory_panel_3d.call("clear_use_target_context")
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


func _on_global_character_inventory_use_requested(payload: Dictionary) -> void:
	var target_state := _resolve_inventory_use_target_consumer(payload)
	if target_state == null:
		target_state = _resolve_inventory_use_target_state(payload)
	if target_state == null:
		push_warning("找不到 Mirdo 状态组件，无法打开物品使用背包。")
		return
	if inventory_panel_3d == null or not is_instance_valid(inventory_panel_3d):
		push_warning("找不到玩家背包面板，无法给 Mirdo 使用物品。")
		return

	if _is_dual_inventory_panel_open():
		_close_dual_inventory_panel()

	var target_label := _resolve_inventory_use_target_label(payload, target_state)
	if inventory_panel_3d.has_method("set_use_target_context"):
		inventory_panel_3d.call("set_use_target_context", target_state, target_label)
	_set_inventory_panel_open(true, true)


func _resolve_inventory_use_target_consumer(payload: Dictionary) -> Node:
	var character := _resolve_inventory_use_character(payload)
	if character == null:
		return null
	var by_components := character.get_node_or_null("Components/ItemConsumer")
	if by_components != null and by_components.has_method("consume_item"):
		return by_components
	var by_root := character.get_node_or_null("ItemConsumer")
	if by_root != null and by_root.has_method("consume_item"):
		return by_root
	return null


func _resolve_inventory_use_target_state(payload: Dictionary) -> Node:
	var state_path := String(payload.get("state_component_path", "")).strip_edges()
	if not state_path.is_empty():
		var by_state_path := get_node_or_null(NodePath(state_path))
		if by_state_path != null and by_state_path.has_method("apply_item_effect"):
			return by_state_path

	var character := _resolve_inventory_use_character(payload)
	if character == null:
		return null
	var by_components := character.get_node_or_null("Components/StateComponent")
	if by_components != null and by_components.has_method("apply_item_effect"):
		return by_components
	var by_root := character.get_node_or_null("StateComponent")
	if by_root != null and by_root.has_method("apply_item_effect"):
		return by_root
	return null


func _resolve_inventory_use_character(payload: Dictionary) -> Node:
	var character_path := String(payload.get("character_path", payload.get("xiaokong_path", ""))).strip_edges()
	if character_path.is_empty():
		return null
	return get_node_or_null(NodePath(character_path))


func _resolve_inventory_use_target_label(payload: Dictionary, target_state: Node) -> String:
	var speaker_name := String(payload.get("speaker_name", "")).strip_edges()
	if not speaker_name.is_empty():
		return speaker_name
	var character := _resolve_inventory_use_character(payload)
	if character != null:
		var display_name := String(character.get("display_name")).strip_edges()
		if not display_name.is_empty() and display_name != "<null>":
			return display_name
		if not String(character.name).strip_edges().is_empty():
			return String(character.name).strip_edges()
	if target_state != null:
		var state_display_name := String(target_state.get("display_name")).strip_edges()
		if not state_display_name.is_empty() and state_display_name != "<null>":
			return state_display_name
	return "Mirdo"


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
	# _tilt_input/_rotation_input 已在输入阶段按像素换算，不再乘 delta。
	# 这样视角速度与渲染/物理帧率无关，也不会出现低帧时突然加速。
	_mouse_rotation.x += _tilt_input
	_mouse_rotation.x = clamp(_mouse_rotation.x, TILT_LOWER_LIMIT, TILT_UPPER_LIMIT)
	_mouse_rotation.y += _rotation_input

	# 使用“身体偏航 + 头部俯仰”的父子层级：身体负责角色方向，Marker3D
	# 负责上下看。不要直接重写 global_transform，否则存档/父节点变换会
	# 与摄像机方向脱节。
	_apply_view_rotation()
	
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

	# Camera3D 已经是 CameraOffset 的子节点，位置和方向会随父节点自动跟随。
	# 不要每帧覆盖 global_transform：这会绕过父子层级和插值，导致镜头
	# 偶尔停在旧位置，表现为摄像头不跟随角色或转向滞后。
	if CAMERA_CONTROLLER != null and is_instance_valid(CAMERA_CONTROLLER):
		# 只清除滚转，不改写由 Marker3D/CameraOffset 继承来的位置与方向。
		CAMERA_CONTROLLER.rotation.z = 0.0
	
	_rotation_input = 0.0
	_tilt_input = 0.0

func get_input_direction():
	if is_gameplay_input_blocked():
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

func _resolve_xiaokong_status_panel(payload: Dictionary = {}) -> Node:
	var character_path := String(payload.get("character_path", payload.get("xiaokong_path", ""))).strip_edges()
	if not character_path.is_empty():
		var character_root := get_node_or_null(NodePath(character_path))
		if character_root != null and is_instance_valid(character_root):
			var direct_panel := character_root.get_node_or_null("StatusPanel")
			if direct_panel != null and is_instance_valid(direct_panel):
				return direct_panel
	if not character_path.is_empty() and character_path != String(get_path()):
		return xiaokong_status_panel if xiaokong_status_panel != null and is_instance_valid(xiaokong_status_panel) else null
	if player_status_screen != null and is_instance_valid(player_status_screen):
		return player_status_screen
	player_status_screen = get_node_or_null("PlayerStatusScreen2D")
	if player_status_screen != null and is_instance_valid(player_status_screen):
		return player_status_screen
	return xiaokong_status_panel if xiaokong_status_panel != null and is_instance_valid(xiaokong_status_panel) else null

func _is_status_panel_open() -> bool:
	player_status_screen = get_node_or_null("PlayerStatusScreen2D")
	var status_panel := _resolve_xiaokong_status_panel()
	if status_panel == null or not is_instance_valid(status_panel):
		return false
	if status_panel.has_method("is_panel_open"):
		return bool(status_panel.call("is_panel_open"))
	return false

func is_gameplay_input_blocked() -> bool:
	return not _window_has_focus or (get_tree() != null and get_tree().paused) or _is_custom_text_input_active() or is_ui_text_input_focused()

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

	var xiaokong_path: String = String(payload.get("xiaokong_path", payload.get("character_path", ""))).strip_edges()
	var controller_node := _resolve_xiaokong_control_component()
	if controller_node != null and is_instance_valid(controller_node):
		var controller_bound := xiaokong_path.is_empty()
		if not xiaokong_path.is_empty() and controller_node.has_method("bind_target_by_path"):
			controller_bound = bool(controller_node.call("bind_target_by_path", xiaokong_path))
		if controller_bound and controller_node.has_method("send_dialogue_text"):
			return bool(controller_node.call("send_dialogue_text", clean_text))

	return _send_dialogue_direct_to_payload_target(clean_text, xiaokong_path)

func _notify_dialogue_input_draft_to_xiaokong(draft_text: String, payload: Dictionary) -> void:
	var xiaokong_path: String = String(payload.get("xiaokong_path", payload.get("character_path", ""))).strip_edges()
	var controller_node := _resolve_xiaokong_control_component()
	if controller_node != null and is_instance_valid(controller_node):
		if controller_node.has_method("notify_player_input_draft_changed"):
			controller_node.call("notify_player_input_draft_changed", draft_text)
			return
	var target_path := xiaokong_path.strip_edges()
	if target_path.is_empty():
		return
	var character_root: Node = get_node_or_null(NodePath(target_path))
	if character_root == null:
		return
	var dialogue_component := _find_dialogue_component_recursive(character_root)
	if dialogue_component != null and dialogue_component.has_method("notify_player_input_draft_changed"):
		dialogue_component.call("notify_player_input_draft_changed", draft_text)

func _send_dialogue_direct_to_payload_target(clean_text: String, character_path: String) -> bool:
	var target_path := character_path.strip_edges()
	if target_path.is_empty():
		return false
	var character_root: Node = get_node_or_null(NodePath(target_path))
	if character_root == null:
		return false
	var dialogue_component := _find_dialogue_component_recursive(character_root)
	if dialogue_component == null:
		return false
	var result: Variant = dialogue_component.call("send_player_text", clean_text)
	if result is Dictionary:
		return bool((result as Dictionary).get("ok", false))
	return bool(result)

func _on_global_xiaokong_dialogue_requested(payload: Dictionary) -> void:
	if xiaokong_dialogue_panel == null or not is_instance_valid(xiaokong_dialogue_panel):
		return
	var status_panel := _resolve_xiaokong_status_panel(payload)
	if _is_status_panel_open() and status_panel != null and is_instance_valid(status_panel):
		if status_panel.has_method("hide_panel"):
			status_panel.call("hide_panel")
	_dialogue_mouse_free_mode = false
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	_set_world_interaction_blocked(true)
	if xiaokong_dialogue_panel.has_method("open_for_payload"):
		xiaokong_dialogue_panel.call("open_for_payload", payload)
	elif xiaokong_dialogue_panel.has_method("open_panel"):
		xiaokong_dialogue_panel.call("open_panel")

func _on_xiaokong_dialogue_panel_submit(text: String, payload: Dictionary) -> void:
	_send_dialogue_to_xiaokong(text, payload)
	var controller_node := _resolve_xiaokong_control_component()
	if controller_node != null and is_instance_valid(controller_node) and controller_node.has_method("flush_pending_player_dialogue_now"):
		controller_node.call("flush_pending_player_dialogue_now")

func _on_xiaokong_dialogue_panel_input_draft_changed(draft_text: String, payload: Dictionary) -> void:
	_notify_dialogue_input_draft_to_xiaokong(draft_text, payload)

func _on_xiaokong_dialogue_panel_visibility_changed(is_open: bool) -> void:
	_set_world_interaction_blocked(is_open)
	if not is_open:
		_dialogue_mouse_free_mode = false
		_release_ui_captured_movement_input()
		if not _is_inventory_panel_open():
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

func _on_global_xiaokong_status_requested(payload: Dictionary) -> void:
	var status_panel := _resolve_xiaokong_status_panel(payload)
	if status_panel == null or not is_instance_valid(status_panel):
		return
	if _is_dialogue_panel_open() and xiaokong_dialogue_panel != null and is_instance_valid(xiaokong_dialogue_panel):
		if xiaokong_dialogue_panel.has_method("hide_panel"):
			xiaokong_dialogue_panel.call("hide_panel")
	_set_world_interaction_blocked(true)
	if status_panel.has_method("open_for_payload"):
		status_panel.call("open_for_payload", payload)
	elif status_panel.has_method("open_panel"):
		status_panel.call("open_panel")


func _toggle_player_status_screen() -> void:
	var status_panel := _resolve_xiaokong_status_panel({"character_path": String(get_path())})
	if status_panel == null or not is_instance_valid(status_panel):
		return
	if status_panel.has_method("is_panel_open") and bool(status_panel.call("is_panel_open")):
		if status_panel.has_method("hide_panel"):
			status_panel.call("hide_panel")
		return
	if status_panel.has_method("open_for_payload"):
		status_panel.call("open_for_payload", {"character_path": String(get_path())})
	elif status_panel.has_method("open_panel"):
		status_panel.call("open_panel")

func _on_xiaokong_status_panel_visibility_changed(is_open: bool) -> void:
	if is_open:
		_set_world_interaction_blocked(true)
		return
	if not _is_dialogue_panel_open():
		_set_world_interaction_blocked(false)
	if not _is_dialogue_panel_open() and not _is_inventory_panel_open():
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
	var vertical_velocity_before_slide := velocity.y
	if step_handler:
		is_climbing = step_handler.handle_step_climbing(delta)
	
	if !is_climbing:
		move_and_slide()
		handle_rigid_body_collisions()

	if step_handler:
		# 上台阶检测已经完成了本帧的受控位移；仍然执行收尾吸附，
		# 让下楼和相机状态不会因为跳过 move_and_slide 而断一帧。
		step_handler.handle_after_move_slide(delta)

	_update_footstep_audio(delta, vertical_velocity_before_slide)

func _release_ui_captured_movement_input() -> void:
	for action_name in [&"move_forward", &"move_backward", &"move_left", &"move_right", &"sprint", &"jump"]:
		if Input.is_action_pressed(action_name):
			Input.action_release(action_name)
	velocity.x = 0.0
	velocity.z = 0.0
	_rotation_input = 0.0
	_tilt_input = 0.0

func _apply_view_rotation() -> void:
	# 统一应用角色与镜头方向，加载存档和运行时输入都走同一条链路。
	_player_rotation = Vector3(0.0, _mouse_rotation.y, 0.0)
	_camera_rotation = Vector3(_mouse_rotation.x, 0.0, 0.0)
	rotation = _player_rotation
	marker_3d.rotation = _camera_rotation

func _resolve_footstep_player() -> void:
	_footstep_player = get_node_or_null(footstep_player_path) as AudioStreamPlayer3D
	if _footstep_player == null:
		_footstep_player = get_node_or_null("FootstepAudio3D") as AudioStreamPlayer3D
	_ensure_footstep_audible_player()
	if _footstep_landing_player == null or not is_instance_valid(_footstep_landing_player):
		_footstep_landing_player = get_node_or_null("FootstepLandingAudio3D") as AudioStreamPlayer3D
	if _footstep_landing_player == null:
		_footstep_landing_player = AudioStreamPlayer3D.new()
		_footstep_landing_player.name = "FootstepLandingAudio3D"
		add_child(_footstep_landing_player)
	_ensure_footstep_landing_audible_player()
	_configure_landing_player()

func _ensure_footstep_audible_player() -> void:
	if not footstep_use_2d_audible_fallback:
		return
	if _footstep_audible_player != null and is_instance_valid(_footstep_audible_player):
		return
	_footstep_audible_player = get_node_or_null("PlayerFootstepAudiblePlayer") as AudioStreamPlayer
	if _footstep_audible_player == null:
		_footstep_audible_player = AudioStreamPlayer.new()
		_footstep_audible_player.name = "PlayerFootstepAudiblePlayer"
		add_child(_footstep_audible_player)
	_configure_footstep_audible_player(_footstep_audible_player)

func _ensure_footstep_landing_audible_player() -> void:
	if not footstep_use_2d_audible_fallback:
		return
	if _footstep_landing_audible_player != null and is_instance_valid(_footstep_landing_audible_player):
		return
	_footstep_landing_audible_player = get_node_or_null("PlayerFootstepLandingAudiblePlayer") as AudioStreamPlayer
	if _footstep_landing_audible_player == null:
		_footstep_landing_audible_player = AudioStreamPlayer.new()
		_footstep_landing_audible_player.name = "PlayerFootstepLandingAudiblePlayer"
		add_child(_footstep_landing_audible_player)
	_configure_footstep_audible_player(_footstep_landing_audible_player)

func _get_primary_footstep_player():
	if footstep_use_2d_audible_fallback:
		_ensure_footstep_audible_player()
		if _footstep_audible_player != null:
			return _footstep_audible_player
	return _footstep_player

func _get_primary_landing_player():
	if footstep_use_2d_audible_fallback:
		_ensure_footstep_landing_audible_player()
		if _footstep_landing_audible_player != null:
			return _footstep_landing_audible_player
	return _footstep_landing_player

func _configure_footstep_audible_player(player: AudioStreamPlayer) -> void:
	if player == null:
		return
	if not String(footstep_bus_name).is_empty() and AudioServer.get_bus_index(String(footstep_bus_name)) != -1:
		player.bus = String(footstep_bus_name)
	player.volume_db = footstep_volume_db

func _configure_footstep_3d_player(player: AudioStreamPlayer3D, volume_db: float = INF) -> void:
	"""统一配置玩家脚步 3D 声源。

	主角的脚步声源在身体/脚边，监听器在相机上；用 3D 播放可以避免
	旧 AudioStreamPlayer fallback 那种“直接在耳机里播”的感觉。
	"""
	if player == null:
		return
	if not String(footstep_bus_name).is_empty() and AudioServer.get_bus_index(String(footstep_bus_name)) != -1:
		player.bus = String(footstep_bus_name)
	player.max_distance = footstep_max_distance
	player.unit_size = footstep_unit_size
	player.max_db = footstep_max_db
	player.panning_strength = footstep_panning_strength
	player.max_polyphony = 1
	player.area_mask = 1
	player.attenuation_model = AudioStreamPlayer3D.ATTENUATION_INVERSE_DISTANCE
	if is_finite(volume_db):
		player.volume_db = volume_db

func _autoload_footstep_clips() -> void:
	if not footstep_clips.is_empty():
		_configure_footstep_clips()
		return
	var preferred := load(footstep_loop_stream_path) as AudioStream if not footstep_loop_stream_path.is_empty() else null
	if preferred != null:
		footstep_clips.append(preferred)
		_configure_footstep_clips()
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
	_configure_footstep_clips()

func _apply_footstep_volume() -> void:
	var primary_player = _get_primary_footstep_player()
	if primary_player == null:
		return
	if not String(footstep_bus_name).is_empty() and AudioServer.get_bus_index(String(footstep_bus_name)) != -1:
		if _footstep_player != null:
			_footstep_player.bus = String(footstep_bus_name)
		primary_player.bus = String(footstep_bus_name)
	if _footstep_player != null:
		_configure_footstep_3d_player(_footstep_player, footstep_volume_db)
	_configure_footstep_audible_player(_footstep_audible_player)
	primary_player.volume_db = footstep_volume_db
	_configure_footstep_stream(primary_player.stream)
	if _footstep_player != null:
		_configure_footstep_stream(_footstep_player.stream)
	_configure_landing_player()

func _update_footstep_audio(delta: float, vertical_velocity_before_slide: float = INF) -> void:
	var primary_player = _get_primary_footstep_player()
	if primary_player == null:
		return
	var horizontal_speed: float = Vector2(velocity.x, velocity.z).length()
	var grounded := is_on_floor()
	var should_play_step := grounded and horizontal_speed >= footstep_min_speed
	_footstep_debug_elapsed += delta
	if _footstep_debug_elapsed >= 1.0:
		_footstep_debug_elapsed = 0.0
		if should_play_step or primary_player.playing:
			print("[Footstep] player ground=%s speed=%.2f should=%s playing=%s spatial=%s clips=%d stream=%s vol=%.1f bus=%s" % [str(grounded), horizontal_speed, str(should_play_step), str(primary_player.playing), str(primary_player is AudioStreamPlayer3D), footstep_clips.size(), primary_player.stream.resource_path if primary_player.stream != null else "", primary_player.volume_db, primary_player.bus])
	var vertical_sample := vertical_velocity_before_slide if is_finite(vertical_velocity_before_slide) else _last_footstep_vertical_velocity
	var landing_fall_speed: float = maxf(0.0, -vertical_sample)

	if grounded and not _was_grounded_for_footsteps and landing_fall_speed >= footstep_landing_min_fall_speed:
		_play_landing_footstep_audio(landing_fall_speed)
		_footstep_elapsed = -0.12

	_was_grounded_for_footsteps = grounded
	_last_footstep_vertical_velocity = velocity.y

	if footstep_use_continuous_loop:
		_update_footstep_loop(delta, should_play_step, horizontal_speed)
		return

	if not should_play_step:
		_footstep_was_moving = false
		if not grounded:
			_footstep_elapsed = 0.0
		return

	if not _footstep_was_moving:
		_footstep_was_moving = true
		_footstep_elapsed = 0.0
		_play_footstep_audio(false)
		return

	var base_interval: float = footstep_interval_sprint if _is_sprinting else footstep_interval_walk
	if is_crouching or is_on_crouching:
		base_interval *= 1.22
	var speed_scale: float = clampf(horizontal_speed / maxf(0.01, SPEED_DEFAULT), 0.85, 1.45)
	var step_interval: float = maxf(0.26, base_interval / speed_scale)
	_footstep_elapsed += delta
	if _footstep_elapsed < step_interval:
		return
	_footstep_elapsed = 0.0
	_play_footstep_audio(false)

func _play_footstep_audio(is_landing_step: bool = false) -> void:
	var primary_player = _get_primary_footstep_player()
	if primary_player == null:
		return
	if not footstep_clips.is_empty():
		var clip_index: int = randi() % footstep_clips.size()
		if footstep_clips.size() > 1:
			var guard := 0
			while clip_index == _last_footstep_clip_index and guard < 4:
				clip_index = randi() % footstep_clips.size()
				guard += 1
		_last_footstep_clip_index = clip_index
		var clip: AudioStream = footstep_clips[clip_index]
		if clip != null:
			primary_player.stream = clip
			if _footstep_player != null:
				_footstep_player.stream = clip
			_configure_footstep_stream(primary_player.stream)
	if primary_player.stream == null:
		return
	var horizontal_speed: float = Vector2(velocity.x, velocity.z).length()
	var speed_ratio: float = clampf(horizontal_speed / maxf(0.01, SPEED_DEFAULT), 0.0, 1.6)
	var speed_gain_db: float = lerpf(-2.2, 0.8, clampf(speed_ratio / 1.6, 0.0, 1.0))
	var crouch_gain_db: float = -4.0 if is_crouching or is_on_crouching else 0.0
	var landing_gain_db: float = footstep_landing_volume_boost_db if is_landing_step else 0.0
	primary_player.stop()
	primary_player.volume_db = footstep_volume_db + speed_gain_db + crouch_gain_db + landing_gain_db + randf_range(-footstep_volume_jitter_db, footstep_volume_jitter_db)
	primary_player.pitch_scale = randf_range(footstep_pitch_min, footstep_pitch_max)
	if primary_player is AudioStreamPlayer3D:
		_configure_footstep_3d_player(primary_player as AudioStreamPlayer3D, primary_player.volume_db)
	primary_player.play()
	print("[Footstep] play player spatial=%s stream=%s vol=%.1f pitch=%.2f bus=%s" % [str(primary_player is AudioStreamPlayer3D), primary_player.stream.resource_path if primary_player.stream != null else "", primary_player.volume_db, primary_player.pitch_scale, primary_player.bus])

func _play_landing_footstep_audio(fall_speed: float) -> void:
	var landing_player = _get_primary_landing_player()
	if landing_player == null:
		return
	if landing_player.stream == null:
		var landing_stream := load(footstep_landing_stream_path) as AudioStream if not footstep_landing_stream_path.is_empty() else null
		if landing_stream == null and not footstep_clips.is_empty():
			landing_stream = footstep_clips[0]
		landing_player.stream = landing_stream
		if _footstep_landing_player != null:
			_footstep_landing_player.stream = landing_stream
	_configure_landing_player()
	if landing_player.stream == null:
		return
	var strength := clampf((fall_speed - footstep_landing_min_fall_speed) / 5.0, 0.0, 1.0)
	landing_player.stop()
	landing_player.volume_db = footstep_landing_volume_db + footstep_landing_volume_boost_db * strength + randf_range(-0.6, 0.6)
	landing_player.pitch_scale = randf_range(0.96, 1.03)
	if landing_player is AudioStreamPlayer3D:
		_configure_footstep_3d_player(landing_player as AudioStreamPlayer3D, landing_player.volume_db)
	landing_player.play(0.0)
	print("[Footstep] landing player spatial=%s fall=%.2f stream=%s vol=%.1f bus=%s" % [str(landing_player is AudioStreamPlayer3D), fall_speed, landing_player.stream.resource_path if landing_player.stream != null else "", landing_player.volume_db, landing_player.bus])

func _update_footstep_loop(delta: float, should_play_step: bool, horizontal_speed: float) -> void:
	var primary_player = _get_primary_footstep_player()
	if primary_player == null:
		return
	if should_play_step:
		if primary_player.stream == null and not footstep_clips.is_empty():
			primary_player.stream = footstep_clips[0]
			if _footstep_player != null:
				_footstep_player.stream = footstep_clips[0]
			_configure_footstep_stream(primary_player.stream)
		if primary_player.stream == null:
			return
		var speed_ratio: float = clampf(horizontal_speed / maxf(0.01, SPEED_DEFAULT), 0.0, 1.6)
		var speed_gain_db: float = lerpf(-2.2, 0.8, clampf(speed_ratio / 1.6, 0.0, 1.0))
		var crouch_gain_db: float = -4.0 if is_crouching or is_on_crouching else 0.0
		_footstep_loop_target_volume_db = footstep_volume_db + speed_gain_db + crouch_gain_db
		primary_player.pitch_scale = clampf(remap(horizontal_speed, footstep_min_speed, SPEED_DEFAULT * 1.6, footstep_pitch_min, footstep_pitch_max), footstep_pitch_min, footstep_pitch_max)
		if primary_player is AudioStreamPlayer3D:
			_configure_footstep_3d_player(primary_player as AudioStreamPlayer3D, primary_player.volume_db)
		if not primary_player.playing:
			primary_player.volume_db = _footstep_loop_target_volume_db
			primary_player.play()
			print("[Footstep] START player spatial=%s stream=%s vol=%.1f bus=%s loop=%s pos=%.3f" % [str(primary_player is AudioStreamPlayer3D), primary_player.stream.resource_path if primary_player.stream != null else "", primary_player.volume_db, primary_player.bus, _stream_loop_debug(primary_player.stream), primary_player.get_playback_position()])
		else:
			primary_player.volume_db = lerpf(primary_player.volume_db, _footstep_loop_target_volume_db, clampf(delta * 8.0, 0.0, 1.0))
		_footstep_loop_active = true
		return
	if primary_player.playing and _footstep_loop_active:
		primary_player.volume_db = move_toward(primary_player.volume_db, -60.0, footstep_stop_fade_db_per_sec * delta)
		if primary_player.volume_db <= -55.0:
			primary_player.stop()
			primary_player.volume_db = footstep_volume_db
			_footstep_loop_active = false
	else:
		_footstep_loop_active = false

func _configure_footstep_clips() -> void:
	for clip in footstep_clips:
		_configure_footstep_stream(clip)

func _configure_footstep_stream(stream: AudioStream) -> void:
	if stream == null:
		return
	if stream is AudioStreamMP3:
		(stream as AudioStreamMP3).loop = footstep_use_continuous_loop
	elif stream is AudioStreamOggVorbis:
		(stream as AudioStreamOggVorbis).loop = footstep_use_continuous_loop
	elif stream is AudioStreamWAV:
		var wav := stream as AudioStreamWAV
		wav.loop_mode = AudioStreamWAV.LOOP_FORWARD if footstep_use_continuous_loop else AudioStreamWAV.LOOP_DISABLED
		if footstep_use_continuous_loop:
			wav.loop_begin = 0
			var sample_count := _footstep_wav_sample_count(wav)
			if sample_count > 0:
				wav.loop_end = sample_count

func _footstep_wav_sample_count(wav: AudioStreamWAV) -> int:
	if wav == null:
		return 0
	var channel_count := 2 if wav.stereo else 1
	var bytes_per_sample := 2
	match wav.format:
		AudioStreamWAV.FORMAT_8_BITS:
			bytes_per_sample = 1
		AudioStreamWAV.FORMAT_16_BITS:
			bytes_per_sample = 2
		_:
			return max(int(round(wav.get_length() * float(wav.mix_rate))), 0)
	var frame_size := bytes_per_sample * channel_count
	if frame_size <= 0:
		return 0
	return int(wav.data.size() / float(frame_size))

func _configure_landing_player() -> void:
	var landing_player = _get_primary_landing_player()
	if not String(footstep_bus_name).is_empty() and AudioServer.get_bus_index(String(footstep_bus_name)) != -1:
		if _footstep_landing_player != null:
			_footstep_landing_player.bus = String(footstep_bus_name)
		if landing_player != null:
			landing_player.bus = String(footstep_bus_name)
	if _footstep_landing_player != null:
		_configure_footstep_3d_player(_footstep_landing_player, footstep_landing_volume_db)
	if landing_player == null:
		return
	if landing_player.stream is AudioStreamMP3:
		(landing_player.stream as AudioStreamMP3).loop = false
	elif landing_player.stream is AudioStreamOggVorbis:
		(landing_player.stream as AudioStreamOggVorbis).loop = false
	elif landing_player.stream is AudioStreamWAV:
		(landing_player.stream as AudioStreamWAV).loop_mode = AudioStreamWAV.LOOP_DISABLED

func _stream_loop_debug(stream: AudioStream) -> String:
	if stream == null:
		return "none"
	if stream is AudioStreamMP3:
		return "mp3 loop=%s offset=%.3f len=%.3f" % [str((stream as AudioStreamMP3).loop), (stream as AudioStreamMP3).loop_offset, stream.get_length()]
	if stream is AudioStreamOggVorbis:
		return "ogg loop=%s offset=%.3f len=%.3f" % [str((stream as AudioStreamOggVorbis).loop), (stream as AudioStreamOggVorbis).loop_offset, stream.get_length()]
	if stream is AudioStreamWAV:
		var wav := stream as AudioStreamWAV
		return "wav mode=%d begin=%d end=%d len=%.3f" % [wav.loop_mode, wav.loop_begin, wav.loop_end, wav.get_length()]
	return stream.get_class()

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


func _load_mouse_sensitivity() -> void:
	var user_settings := get_node_or_null("/root/GameUserSettings")
	if user_settings == null:
		return
	_mouse_sensitivity_scale = clampf(float(user_settings.get("mouse_sensitivity")), 0.5, 2.0)
	if user_settings.has_signal("mouse_sensitivity_changed"):
		var callback := Callable(self, "_on_mouse_sensitivity_changed")
		if not user_settings.mouse_sensitivity_changed.is_connected(callback):
			user_settings.mouse_sensitivity_changed.connect(callback)


func _on_mouse_sensitivity_changed(value: float) -> void:
	_mouse_sensitivity_scale = clampf(value, 0.5, 2.0)
	
func _ready():
	randomize()
	# Keep the authored scene facing direction for a fresh scene. The movement
	# loop rebuilds the body/camera basis from _mouse_rotation every frame, so a
	# zero-initialized value silently overwrote the PlayerController transform
	# and made the render scene start by looking at the wall. Save loading still
	# replaces this value later when the slot contains a saved view.
	_mouse_rotation = Vector3(marker_3d.rotation.x, rotation.y, 0.0)
	_player_rotation = Vector3(0.0, _mouse_rotation.y, 0.0)
	_camera_rotation = Vector3(_mouse_rotation.x, 0.0, 0.0)
	_speed=SPEED_DEFAULT
	_load_mouse_sensitivity()
	if _window_has_focus:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	_resolve_footstep_player()
	_autoload_footstep_clips()
	_apply_footstep_volume()
	var footstep_ready_bus := ""
	if _footstep_player != null:
		footstep_ready_bus = _footstep_player.bus
	print("[Footstep] ready player=%s clips=%d folder=%s one_shot=%s volume=%.1f bus=%s" % [str(_footstep_player != null), footstep_clips.size(), footstep_folder_path, str(not footstep_use_continuous_loop), footstep_volume_db, footstep_ready_bus])
	_resolve_inventory_ui_sfx_player()
	shape_cast_3d.add_exception($'.')
	add_to_group("player")
	if not is_in_group("Savable"):
		add_to_group("Savable")
	if not is_in_group("Player"):
		add_to_group("Player")
		
	shape_cast_3d.position.y=1.7
	var global_node := _resolve_global_node()
	if global_node != null:
		global_node.set("player", self)
	if global_node != null and global_node.has_signal("loot_container_switch_requested"):
		var switch_callable := Callable(self, "_on_loot_container_switch_requested")
		if not global_node.is_connected("loot_container_switch_requested", switch_callable):
			global_node.connect("loot_container_switch_requested", switch_callable)
	if global_node != null and global_node.has_signal("xiaokong_dialogue_requested"):
		var xk_dialogue_callable := Callable(self, "_on_global_xiaokong_dialogue_requested")
		if not global_node.is_connected("xiaokong_dialogue_requested", xk_dialogue_callable):
			global_node.connect("xiaokong_dialogue_requested", xk_dialogue_callable)
	if global_node != null and global_node.has_signal("xiaokong_status_requested"):
		var xk_status_callable := Callable(self, "_on_global_xiaokong_status_requested")
		if not global_node.is_connected("xiaokong_status_requested", xk_status_callable):
			global_node.connect("xiaokong_status_requested", xk_status_callable)
	if global_node != null and global_node.has_signal("character_inventory_use_requested"):
		var character_inventory_use_callable := Callable(self, "_on_global_character_inventory_use_requested")
		if not global_node.is_connected("character_inventory_use_requested", character_inventory_use_callable):
			global_node.connect("character_inventory_use_requested", character_inventory_use_callable)
	
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
		if xiaokong_dialogue_panel.has_signal("input_draft_changed"):
			var draft_callable := Callable(self, "_on_xiaokong_dialogue_panel_input_draft_changed")
			if not xiaokong_dialogue_panel.is_connected("input_draft_changed", draft_callable):
				xiaokong_dialogue_panel.connect("input_draft_changed", draft_callable)
	var status_panel := _resolve_xiaokong_status_panel()
	if status_panel != null and is_instance_valid(status_panel):
		xiaokong_status_panel = status_panel
		if status_panel.has_method("hide_panel"):
			status_panel.call("hide_panel")
		if status_panel.has_signal("panel_visibility_changed"):
			var status_visibility_callable := Callable(self, "_on_xiaokong_status_panel_visibility_changed")
			if not status_panel.is_connected("panel_visibility_changed", status_visibility_callable):
				status_panel.connect("panel_visibility_changed", status_visibility_callable)

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
	_mouse_rotation = data.get("mouse_rotation", _mouse_rotation)
	_player_rotation = Vector3(0, _mouse_rotation.y, 0)
	_camera_rotation = Vector3(_mouse_rotation.x, 0, 0)
	_apply_view_rotation()
	
	# 3. 恢复基础变量并压制状态机
	is_crouching = bool(data.get("is_crouching", is_crouching))
	_is_sprinting = bool(data.get("is_sprinting", _is_sprinting))
	velocity = Vector3.ZERO
	
	# 恢复背包数据
	if data.has("inventory") and inventory_handler:
		inventory_handler.load_inventory_data(data["inventory"])
	
	var sm = $StateMachine
	sm.is_locked = true
	sm._init_states()
	
	# 4. 恢复状态并强制同步变量（解决恢复到 Idle 的关键）
	var state_name: StringName = data.get("state", &"IdleState")
	var target_state = sm.states.get(state_name)
	if target_state:
		if sm.CURRENT_STATE:
			sm.CURRENT_STATE.exit()
		sm.CURRENT_STATE = target_state
		
		# 强制设置状态相关变量，不完全依赖 enter() 的自动处理
		if state_name == &"CrouchState":
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

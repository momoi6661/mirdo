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
@export var inventory_handler:InventoryHandler
@export var unique_id: String = "player_001"

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

var _mouse_rotation : Vector3
var _player_rotation : Vector3
var _camera_rotation : Vector3

var gravity = ProjectSettings.get_setting("physics/3d/default_gravity")

func _unhandled_input(event: InputEvent) -> void:
	_mouse_input = event is InputEventMouseMotion and Input.get_mouse_mode() == Input.MOUSE_MODE_CAPTURED
	if _mouse_input:
		_rotation_input = -event.relative.x * MOUSE_SENSITIVITY
		_tilt_input = -event.relative.y * MOUSE_SENSITIVITY

var _drop_timer: float = 0.0
var _is_holding_drop: bool = false

func _input(event):
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

func _process(delta):
	# 只要按住 T 键，就累加时间
	if _is_holding_drop:
		_drop_timer += delta


func add_to_inventory(item: ItemData) -> bool:
	if not inventory_handler:
		print("错误: inventory_handler 未设置")
		return false
	
	return inventory_handler.PickupItem(item)

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
	var input_dir = Input.get_vector("move_left", "move_right", "move_forward", "move_backward")
	var direction = (transform.basis * Vector3(input_dir.x, 0, input_dir.y)).normalized()
	return direction
	
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
	_speed=SPEED_DEFAULT
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	shape_cast_3d.add_exception($'.')
	add_to_group("player")
	if not is_in_group("Savable"):
		add_to_group("Savable")
	if not is_in_group("Player"):
		add_to_group("Player")
		
	shape_cast_3d.position.y=2.0
	Global.player=self
	
	print("step_handler: ", step_handler)
	if !step_handler:
		if has_node("Components/StepHandler"):
			step_handler = $Components/StepHandler
	
	print("pickup_handler: ", pickup_handler)
	if !pickup_handler:
		if has_node("Components/PickupHandler"):
			pickup_handler = $Components/PickupHandler

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
			shape_cast_3d.position.y = 2.0
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

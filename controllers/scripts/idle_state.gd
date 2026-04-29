extends State

var player

func enter():
	if not player:
		player = Global.player
	if player:
		player._speed = player.SPEED_DEFAULT
		player._head_bob_target = 0.0
		player.is_on_stand = false

func update(delta: float):
	if not player:
		player = Global.player
	if not player:
		return
	if player.has_method("is_gameplay_input_blocked") and bool(player.call("is_gameplay_input_blocked")):
		player._update_camera(delta)
		return
	player._update_camera(delta)
	
	var input_dir = Input.get_vector("move_left", "move_right", "move_forward", "move_backward")
	var direction = (player.transform.basis * Vector3(input_dir.x, 0, input_dir.y)).normalized()
	if direction:
		if player._is_sprinting:
			transition.emit("SprintState")
		else:
			transition.emit("WalkState")
	
	if Input.is_action_just_pressed("jump") and player.is_on_floor():
		transition.emit("JumpState")
	
	if Input.is_action_just_pressed("crouch"):
		transition.emit("CrouchState")

func _input(event: InputEvent):
	pass

func physics_process(delta: float):
	if not player:
		return
	if not player.is_on_floor():
		player.velocity.y -= player.gravity * delta
		if player.velocity.y < -0.5:
			transition.emit("FallState")
	
# 楼梯处理将在玩家控制器中统一处理
	
	player.apply_movement(false, true, 0.0, delta)

extends State

var player

func enter():
	if not player:
		player = Global.player
	if player:
		player._speed = player.SPEED_CROUCH
		player.is_crouching = true
		player.is_on_crouching = true
		player.animation_player.play('crouch', -1, player.CROUCH_SPEED)
		player.shape_cast_3d.position.y = 1.5

func update(delta: float):
	if not player:
		player = Global.player
	if not player:
		return
	if player.has_method("is_gameplay_input_blocked") and bool(player.call("is_gameplay_input_blocked")):
		return
	
	if Input.is_action_just_pressed("jump") and player.is_on_floor():
		if not player.shape_cast_3d.is_colliding():
			if player._is_sprinting:
				transition.emit("SprintState")
			else:
				transition.emit("WalkState")
	
	if Input.is_action_just_pressed("crouch"):
		if not player.shape_cast_3d.is_colliding():
			var input_dir = Input.get_vector("move_left", "move_right", "move_forward", "move_backward")
			var direction = (player.transform.basis * Vector3(input_dir.x, 0, input_dir.y)).normalized()
			if direction and player._is_sprinting:
				transition.emit("SprintState")
			elif direction:
				transition.emit("WalkState")
			else:
				transition.emit("IdleState")

func handle_input(event: InputEvent):
	pass

func physics_process(delta: float):
	if not player:
		return
	if not player.is_on_floor():
		player.velocity.y -= player.gravity * delta
		if player.velocity.y < -0.5:
			transition.emit("FallState")
	
# 楼梯处理将在玩家控制器中统一处理
	
	var direction = player.get_input_direction()
	var head_bob_target = 0.5 if direction else 0.0
	player.apply_movement(true, true, head_bob_target, delta, direction)

func exit():
	player.is_crouching = false
	player.is_on_crouching = false
	player.is_on_stand = true
	player.animation_player.play('crouch', -1, -player.CROUCH_SPEED, true)

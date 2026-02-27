extends State

var player

func enter():
	if not player:
		player = Global.player
	if player:
		player._speed = 5.0
		player._head_bob_target = 1.5
		player.is_on_stand = false

func update(delta: float):
	if not player:
		player = Global.player
	if not player:
		return
	player._update_camera(delta)
	
	if not player._is_sprinting:
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
	
	player.apply_movement(true, true, 1.5, delta)
	
	if abs(player.velocity.x) < 0.1 and abs(player.velocity.z) < 0.1:
		transition.emit("IdleState")

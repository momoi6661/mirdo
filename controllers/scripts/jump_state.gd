extends State

var player
var has_jumped = false

func enter():
	if not player:
		player = Global.player
	has_jumped = false
	player._head_bob_target = 0.0
	player.is_on_stand = false
	
	var horizontal_speed = sqrt(player.velocity.x * player.velocity.x + player.velocity.z * player.velocity.z)
	if player._is_sprinting or horizontal_speed > 4.0:
		player._speed = 5.0
	else:
		player._speed = player.SPEED_DEFAULT

func update(delta: float):
	if not player:
		player = Global.player
	if not player:
		return
	if player.has_method("is_gameplay_input_blocked") and bool(player.call("is_gameplay_input_blocked")):
		player._update_camera(delta)
		return
	player._update_camera(delta)
	
	if Input.is_action_just_released("jump") and player.velocity.y > 0:
		player.velocity.y = player.velocity.y * 0.5

func handle_input(event: InputEvent):
	pass

func physics_process(delta: float):
	if not player:
		return
	if not has_jumped and player.is_on_floor():
		player.velocity.y = player.JUMP_VELOCITY
		has_jumped = true
	
	player.velocity.y -= player.gravity * delta
	
# 楼梯处理将在玩家控制器中统一处理
	
	player.apply_movement(true, false, 0.0, delta)
	
	if player.velocity.y < 0:
		transition.emit("FallState")

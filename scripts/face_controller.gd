@tool
extends Node

@export var blink_anim_player: AnimationPlayer
@export var mouth_anim_player: AnimationPlayer

@export_group("Editor Test Controls")
@export var test_talking: bool = false:
	set(value):
		test_talking = value
		if test_talking:
			start_talking()
			_auto_stop_test("talk", "test_talking")
		else:
			stop_talking()

@export var test_smiling: bool = false:
	set(value):
		test_smiling = value
		if test_smiling:
			start_smiling()
			_auto_stop_test("smile", "test_smiling")
		else:
			stop_smiling()

@export_group("Blink Settings")
@export var min_interval: float = 2.5
@export var max_interval: float = 5.5

var blink_timer: float = 0.0
var next_blink_time: float = 0.0
var is_talking: bool = false
var is_smiling: bool = false

func _ready():
	_set_next_blink_time()

func _process(delta):
	# 用 _process 替代 Timer 节点，这样在编辑器里也可以安全运行，不会产生垃圾节点
	blink_timer += delta
	if blink_timer >= next_blink_time:
		if blink_anim_player and blink_anim_player.has_animation("blink"):
			blink_anim_player.play("blink", 0.1)
		_set_next_blink_time()

func _set_next_blink_time():
	next_blink_time = randf_range(min_interval, max_interval)
	blink_timer = 0.0

# 自动在一个周期后关闭测试按钮
func _auto_stop_test(anim_name: String, property_name: String):
	# 确保节点在场景树中，避免加载场景时报错
	if not is_inside_tree():
		return
		
	if mouth_anim_player and mouth_anim_player.has_animation(anim_name):
		var anim = mouth_anim_player.get_animation(anim_name)
		# 按照动画的真实长度等待 (说话是 0.6 秒，微笑是 2.0 秒)
		await get_tree().create_timer(anim.length).timeout
		
		# 动画播放完一个周期后，如果按钮还是勾选状态，则自动取消勾选
		if get(property_name) == true:
			set(property_name, false)

# 可以通过代码调用的外部方法
func start_talking():
	is_talking = true
	if mouth_anim_player and mouth_anim_player.has_animation("talk"):
		mouth_anim_player.play("talk", 0.2)

func stop_talking():
	is_talking = false
	if mouth_anim_player:
		if is_smiling and mouth_anim_player.has_animation("smile"):
			mouth_anim_player.play("smile", 0.2)
		else:
			if mouth_anim_player.has_animation("RESET"):
				mouth_anim_player.play("RESET", 0.2)
			else:
				mouth_anim_player.stop()

func start_smiling():
	is_smiling = true
	if mouth_anim_player and not is_talking and mouth_anim_player.has_animation("smile"):
		mouth_anim_player.play("smile", 0.2)

func stop_smiling():
	is_smiling = false
	if mouth_anim_player and not is_talking:
		if mouth_anim_player.has_animation("RESET"):
			mouth_anim_player.play("RESET", 0.2)
		else:
			mouth_anim_player.stop()

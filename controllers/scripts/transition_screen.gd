extends CanvasLayer

## 最短过渡显示时间（秒）
const MIN_TIME = 1.0

@onready var animation_player: AnimationPlayer = %AnimationPlayer
@onready var status_label: Label = %StatusLabel
@onready var control: Control = $Control

var _start_time: float = 0.0
var _is_transitioning: bool = false

func _ready():
	visible = false
	control.modulate.a = 0.0

## 开启过渡界面
func start_transition(message: String = "DATA_RESTORATION // IN_PROGRESS", fade_in: bool = true):
	if _is_transitioning: return
	_is_transitioning = true
	
	_start_time = Time.get_ticks_msec() / 1000.0
	visible = true
	status_label.text = message
	
	if fade_in:
		animation_player.play("fade_in")
		animation_player.queue("idle_pulse")
	else:
		# 强制中断之前的动画并立即显示
		animation_player.stop()
		control.modulate.a = 1.0
		animation_player.play("idle_pulse")

## 进度条已废弃，保留函数签名以防外部报错
func update_progress(_value: float):
	pass

## 关闭过渡界面
func stop_transition():
	if !_is_transitioning: return
	
	# 确保达到最短显示时间，防止瞬间闪烁
	var elapsed = (Time.get_ticks_msec() / 1000.0) - _start_time
	if elapsed < MIN_TIME:
		await get_tree().create_timer(MIN_TIME - elapsed).timeout
	
	animation_player.play("fade_out")
	await animation_player.animation_finished
	
	visible = false
	control.modulate.a = 0.0
	_is_transitioning = false

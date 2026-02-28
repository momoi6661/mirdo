@tool
extends Node
# 暴露给属性面板，方便你直接把 FaceAnimationPlayer 拖进来
@export var face_anim_player: AnimationPlayer
@export var blink_anim_name: String = "blink"
# 眨眼间隔的时间范围
@export var min_interval: float = 1.5
@export var max_interval: float = 4.5
# 内部计时器
var _time_left: float = 0.0
func _ready() -> void:
	# 随机初始化第一次眨眼时间
	_reset_timer()
func _process(delta: float) -> void:
	# 如果没有在属性面板指定 AnimationPlayer，则不执行
	if not face_anim_player:
		return
		
	# 倒计时
	_time_left -= delta
	
	# 时间到了，执行眨眼
	if _time_left <= 0.0:
		if face_anim_player.has_animation(blink_anim_name):
			face_anim_player.play(blink_anim_name)
		else:
			push_warning("BlinkComponent: 在 AnimationPlayer 中找不到名为 '%s' 的动画！" % blink_anim_name)
			
		# 重置倒计时，准备下一次眨眼
		_reset_timer()
func _reset_timer() -> void:
	# 生成随机的下一次眨眼时间
	_time_left = randf_range(min_interval, max_interval)

extends CharacterBody3D
# ----------------- 节点引用 -----------------
# 极其重要：在 Godot 编辑器右侧的检查器中，把对应的节点拖入这些槽位！
@export var animation_player: AnimationPlayer
@export var navigation_agent: NavigationAgent3D
@export var look_at_modifier: SkeletonModifier3D # 将你设置好的 LookAtModifier3D 拖到这里！
@export var look_target_marker: Marker3D # 将你在 LookAtModifier3D 里设为 Target 的那个 Marker3D 拖到这里！

# ----------------- 参数设置 -----------------
@export var movement_speed: float = 1.5
@export var turn_speed: float = 6.0
# MMD 模型经常朝向不对。如果蕾塞走路时横着走或倒着走，把这个值改成 PI/2 (1.57) 或 -PI/2 (-1.57)
@export var model_forward_offset: float = 0.0 

# 控制待机动画播放的速度 (1.0是原速，0.5是慢放一倍，让动作更舒缓)
@export var idle_anim_speed: float = 0.5 

# ----------------- 注视玩家系统 -----------------
@export var auto_look_at_player: bool = true # 是否开启自动注视玩家
@export var look_at_distance: float = 5.0 # 在多远距离内会触发骨骼注视
@export var head_track_speed: float = 5.0 # 头部转动的平滑速度 (影响 target 移动速度)
@export var influence_speed: float = 2.0 # 权重过渡的平滑速度 (越小，头回正和开始看的过程越慢)
@export var max_view_angle: float = 120.0 # 最大可视角度（度数），超过这个角度就不看了

# ----------------- 状态机 -----------------
enum State { IDLE, WALKING }
var current_state: int = State.IDLE

# 用来缓存玩家的摄像机节点，这才是我们真正要注视的（你的眼睛所在的位置）
var player_camera: Camera3D = null

func _ready():
	if not animation_player:
		push_warning("蕾塞没有绑定 AnimationPlayer！请在右侧检查器中拖入！")
	
	if not look_at_modifier:
		push_warning("蕾塞没有绑定 LookAtModifier3D！如果需要头部注视，请在检查器中拖入！")
		
	if not look_target_marker:
		push_warning("蕾塞没有绑定 look_target_marker！请把 Modifier 追踪的那个 Marker3D 拖进来！")
		
	if not navigation_agent:
		push_warning("蕾塞没有绑定 NavigationAgent3D！请在右侧检查器中拖入！")
	else:
		# 配置导航精度
		navigation_agent.path_desired_distance = 0.5
		navigation_agent.target_desired_distance = 1.0
		
	# 启动时直接获取当前激活的 3D 摄像机（通常就是玩家视角的摄像机）
	player_camera = get_viewport().get_camera_3d()

	change_state(State.IDLE)

func _physics_process(delta):
	# 如果一开始没拿到摄像机（可能因为初始化顺序），在帧循环里补救一下
	if not player_camera:
		player_camera = get_viewport().get_camera_3d()
		
	# 处理骨骼注视玩家摄像头逻辑
	_handle_auto_look_at_player(delta)
	
	match current_state:
		State.IDLE:
			_process_idle(delta)
		State.WALKING:
			_process_walking(delta)
			
	# 应用重力
	if not is_on_floor():
		velocity.y -= 9.8 * delta
	
	move_and_slide()

# ==========================================
# 核心行为逻辑
# ==========================================

func _process_idle(delta):
	velocity.x = 0
	velocity.z = 0
	_safe_play_anim("idle")

func _process_walking(delta):
	if not navigation_agent: return
	
	if navigation_agent.is_navigation_finished():
		change_state(State.IDLE)
		return
		
	var current_agent_position: Vector3 = global_position
	var next_path_position: Vector3 = navigation_agent.get_next_path_position()

	var direction = current_agent_position.direction_to(next_path_position)
	direction.y = 0 
	direction = direction.normalized()

	velocity.x = direction.x * movement_speed
	velocity.z = direction.z * movement_speed
	
	# 走路时让整个身体平滑转身看路
	if direction.length_squared() > 0.01:
		var target_rotation_y = atan2(direction.x, direction.z) + model_forward_offset
		rotation.y = lerp_angle(rotation.y, target_rotation_y, turn_speed * delta)
		
	_safe_play_anim("walking")

# ==========================================
# 自动注视逻辑 (操控 Marker3D 跟踪摄像机)
# ==========================================

func _handle_auto_look_at_player(delta):
	if not look_at_modifier or not look_target_marker:
		return
		
	# 如果没开自动注视，或找不到玩家摄像机，或正在走路(专注看路)
	if not auto_look_at_player or not player_camera or current_state == State.WALKING:
		# 平滑关闭注视
		look_at_modifier.influence = lerpf(look_at_modifier.influence, 0.0, influence_speed * delta)
		return
		
	# 计算与玩家摄像机的距离
	var dist_to_player = global_position.distance_to(player_camera.global_position)
	
	# 【全新逻辑】：利用 Godot 的局部坐标系 (to_local) 判断玩家在前后
	# to_local 会把玩家的世界坐标转换成蕾塞的局部坐标
	# 在默认模型里，Z轴负方向(-Z)是前方。
	var player_local_pos = to_local(player_camera.global_position)
	
	# 如果你的模型是反的 (比如之前 offset 设的是 3.14)，你需要看情况修改下面这行的正负号
	# 正常情况下：player_local_pos.z < 0 表示在前方。如果发现反了，改成 > -0.2 即可！
	var is_in_front = player_local_pos.z > -0.2 # 给一点点容错余地
	
	# 只有在距离内，且在身前，才拉满权重
	if dist_to_player <= look_at_distance and is_in_front:
		# 1. 把 Marker3D 平滑地移动到玩家摄像机(也就是玩家的眼睛)的位置
		look_target_marker.global_position = look_target_marker.global_position.lerp(player_camera.global_position, head_track_speed * delta)
		# 2. 把骨骼影响权重平滑拉满
		look_at_modifier.influence = lerpf(look_at_modifier.influence, 1.0, influence_speed * delta)
	else:
		# 走远了，或者走到背后了，就平滑关闭注视 (这能完美防止 LookAtModifier 达到物理极限时的抽搐)
		look_at_modifier.influence = lerpf(look_at_modifier.influence, 0.0, influence_speed * delta)

# ==========================================
# 外部控制接口
# ==========================================
# 让蕾塞走到指定的 3D 坐标
func move_to_position(target_pos: Vector3):
	if navigation_agent:
		navigation_agent.target_position = target_pos
		change_state(State.WALKING)
# 切换状态
func change_state(new_state: int):
	current_state = new_state
# ==========================================
# 辅助表现逻辑
# ==========================================
# 安全播放动画
func _safe_play_anim(anim_name: String):
	if animation_player and animation_player.has_animation(anim_name):
		if animation_player.current_animation != anim_name:
			if anim_name == "idle":
				# 待机动画放慢
				animation_player.play(anim_name, 0.3, idle_anim_speed) 
			else:
				# 走路动画保持正常速度
				animation_player.play(anim_name, 0.3, 1.0) 

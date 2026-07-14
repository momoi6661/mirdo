class_name StepHandlerComponent
extends Node

@export_category("References")
@export var player: PlayerController
@export var collision_shape: CollisionShape3D

@export_category("Step Settings")
@export var MAX_STEP_HEIGHT: float = 0.3
@export var MAX_CROUCH_STEP_HEIGHT: float = 0.35
@export var camera_smooth_amount: float = 0.7
@export var SLOPE_LIMIT: float = 45.0
@export var camera_smooth_switch: bool = false
@export_range(0.0, 0.3, 0.01) var step_cooldown_sec: float = 0.08
@export_range(0.01, 1.0, 0.01) var min_step_speed: float = 0.08

var snap_stair_last_frame := false
var last_frame_on_floor = -INF
var camera_smooth_pos = null
var is_crouch_adjusted: bool = false
var _step_cooldown: float = 0.0

var stairs_below_ray: RayCast3D
var stairs_ahead_ray: RayCast3D
var _stairs_ahead_base_position: Vector3 = Vector3.ZERO
@export var camera_offset: Node3D
@export_flags_3d_physics var step_detection_mask: int = 1

func _ready():
	if player == null:
		player = get_parent().get_parent() as PlayerController
	if collision_shape == null and player != null:
		collision_shape = player.get_node_or_null("CollisionShape3D") as CollisionShape3D
	if camera_offset == null and player != null:
		camera_offset = player.get_node_or_null("Marker3D/CameraOffset") as Node3D
	if player != null:
		# 使用 CharacterBody3D 原生 floor snap 处理下楼，避免旧版
		# move_and_collide(velocity, true) 带来的重复碰撞测试和卡顿。
		player.floor_snap_length = maxf(player.floor_snap_length, MAX_STEP_HEIGHT * 1.5)
	call_deferred("setup_stair_rays")

func setup_stair_rays():
	if player == null:
		push_warning("StepHandlerComponent: player is null, skipping stair ray setup.")
		return

	# 创建向下检测楼梯的射线
	if !stairs_below_ray:
		stairs_below_ray = RayCast3D.new()
		stairs_below_ray.name = "StairsBelowRay"
		stairs_below_ray.target_position = Vector3(0, -1.5, 0)  # 向下检测1.5米
		stairs_below_ray.enabled = true
		# 重要：使用和玩家相同的碰撞掩码！
		# 原因：射线应该只检测玩家能碰撞的物体
		stairs_below_ray.collision_mask = _get_step_detection_mask()
		if stairs_below_ray.get_parent() == null:
			player.add_child(stairs_below_ray)
	
	# 创建向前检测楼梯的射线
	if !stairs_ahead_ray:
		stairs_ahead_ray = RayCast3D.new()
		stairs_ahead_ray.name = "StairsAHeadRay"
		# 设置射线起始位置在玩家前方偏上一点
		# 计算玩家碰撞体的半径作为前方距离
		var player_radius = 0.3
		if collision_shape and collision_shape.shape:
			if collision_shape.shape is CapsuleShape3D:
				player_radius = collision_shape.shape.radius
			elif collision_shape.shape is CylinderShape3D:
				player_radius = collision_shape.shape.radius
			elif collision_shape.shape is SphereShape3D:
				player_radius = collision_shape.shape.radius
			elif collision_shape.shape is BoxShape3D:
				player_radius = collision_shape.shape.size.x / 2.0
		
		stairs_ahead_ray.position = Vector3(0, 0.25, -player_radius)  # 射线起点位置
		_stairs_ahead_base_position = stairs_ahead_ray.position
		stairs_ahead_ray.target_position = Vector3(0, -0.25, 0)  # 从起点向下0.5米
		stairs_ahead_ray.enabled = true
		# 同样使用和玩家相同的碰撞掩码
		# 这样射线就能准确检测玩家可以站立或碰撞的表面
		stairs_ahead_ray.collision_mask = _get_step_detection_mask()
		if stairs_ahead_ray.get_parent() == null:
			player.add_child(stairs_ahead_ray)

func _get_step_detection_mask() -> int:
	if step_detection_mask > 0:
		return step_detection_mask
	if player:
		return player.collision_mask
	return 1

# 主函数：处理上楼梯逻辑，在move_and_slide之前调用
# 返回true表示正在上楼梯，应该跳过move_and_slide
#
# 重要：这个函数干预了正常的move_and_slide流程！
# 如果返回true，fps_controller会跳过move_and_slide()
# 因为我们已经手动移动玩家到台阶上了，不需要再move_and_slide
func handle_step_climbing(delta: float = 0.0) -> bool:
	if player == null or stairs_ahead_ray == null or stairs_below_ray == null:
		return false
	_step_cooldown = maxf(_step_cooldown - delta, 0.0)

	# 根据蹲伏状态调整射线位置
	adjust_rays_for_crouch()
	# 上一帧的预测会临时把射线移到台阶碰撞点；每帧恢复水平位置，
	# 避免射线残留导致角色在楼梯边缘反复检测同一个点。
	stairs_ahead_ray.position.x = _stairs_ahead_base_position.x
	stairs_ahead_ray.position.z = _stairs_ahead_base_position.z
	
	# 检查并执行上台阶动作
	if _step_cooldown <= 0.0 and check_and_climb_step(delta):
		# 如果成功上台阶，更新最后在地面上的帧数
		if player.is_on_floor():
			# Engine.get_physics_frames()返回当前物理帧的序号
			# 这是一个递增的数字，每物理帧增加1
			# 用于计算时间差，判断是否在特定时间范围内
			last_frame_on_floor = Engine.get_physics_frames()
		_step_cooldown = step_cooldown_sec
		return true  # 已经完成受控位移，本帧不再重复 move_and_slide
	
	return false  # 返回false → fps_controller会正常执行move_and_slide()

# 主函数：处理下楼梯逻辑，在move_and_slide之后调用
func handle_after_move_slide(delta: float):
	if player == null or stairs_below_ray == null:
		return

	# 检查是否需要吸附到楼梯
	check_snap_to_stairs()
	# 执行相机平滑
	if camera_smooth_switch:
		camera_smooth(delta)
	
	# 如果当前在地面，更新最后在地面上的帧数
	if player.is_on_floor():
		last_frame_on_floor = Engine.get_physics_frames()

# 根据玩家蹲伏状态调整检测射线的位置
func adjust_rays_for_crouch():
	var should_be_crouched = player.is_crouching or player.is_on_crouching
	
	# 当玩家蹲下时，提高射线位置以适应蹲伏状态
	if should_be_crouched and !is_crouch_adjusted:
		stairs_ahead_ray.position.y += 0.3  # 向上调整前方射线
		stairs_below_ray.position.y += 0.5  # 向上调整下方射线
		is_crouch_adjusted = true
	# 当玩家站起时，恢复射线原始位置
	elif !should_be_crouched and is_crouch_adjusted:
		stairs_ahead_ray.position.y -= 0.3
		stairs_below_ray.position.y -= 0.5
		is_crouch_adjusted = false

# 检查并处理下楼梯时的吸附效果
# 当玩家从楼梯边缘走下时，这个函数会让玩家平滑地下降到下一级台阶
func check_snap_to_stairs():
	# 检查下方是否有可行走的地面（不是太陡的斜坡）
	var floor_below = stairs_below_ray.is_colliding() and !is_too_steep(stairs_below_ray.get_collision_normal())
	# 判断上一帧是否在地面（通过帧数差值是否为1来判断）
	var was_on_floor_last_frame = Engine.get_physics_frames() - last_frame_on_floor == 1
	# 判断是否应该吸附到楼梯
	var should_snap = !player.is_on_floor() and player.velocity.y <= 0 and (was_on_floor_last_frame or snap_stair_last_frame)
	
	if should_snap and floor_below:
		# CharacterBody3D 会沿 floor_snap_length 向下吸附。
		# 这比手动修改 position.y 更稳定，不会和 move_and_slide 重复移动。
		player.apply_floor_snap()
		snap_stair_last_frame = true
		return
	
	snap_stair_last_frame = false

# 检查并执行上台阶动作的核心函数
# 上楼梯预测的核心思想：从高处向下"掉落"，检测能否站在台阶上
func check_and_climb_step(delta) -> bool:
	# 只有在地面或上一帧吸附到楼梯时才尝试上台阶
	if !player.is_on_floor() and !snap_stair_last_frame:
		return false
	
	# 步骤1: 计算预期的水平移动（忽略Y轴，因为上楼梯时我们不知道最终高度）
	# 注意这里！Vector3(1, 0, 1) 表示：
	# - X轴：保留原始移动（1 = 保留）
	# - Y轴：忽略原始移动（0 = 忽略）
	# - Z轴：保留原始移动（1 = 保留）
	# 
	# 示例计算：
	# 假设 player.velocity = (0, 0, 5) m/s（向前移动5米/秒）
	# delta = 0.016s（60fps，每帧16ms）
	# 
	# expected_motion = (0, 0, 5) * (1, 0, 1) * 0.016
	#                 = (0, 0, 5) * 0.016
	#                 = (0, 0, 0.08) m
	# 
	# 结果：这一帧玩家想要水平移动0.08米
	var expected_motion = player.velocity * Vector3(1, 0, 1) * delta
	if expected_motion.length_squared() < min_step_speed * min_step_speed * delta * delta:
		return false
	
	# 步骤2: 预测玩家的位置，向上抬高2倍台阶高度以确保能越过台阶
	# 为什么要抬高？因为台阶可能比玩家高，抬高是为了确保能"跳"过去
	#
	# 继续上面的示例：
	# MAX_STEP_HEIGHT = 0.3m
	# MAX_STEP_HEIGHT * 2 = 0.6m
	# 
	# step_test_pos = 当前位置 + (0, 0, 0.08) + (0, 0.6, 0)
	#                = 当前位置 + (0, 0.6, 0.08)
	# 
	# 结果：测试位置在"玩家前方0.08米、上方0.6米"的地方
	
	var step_test_pos = player.global_transform.translated(expected_motion + Vector3(0, MAX_STEP_HEIGHT * 2, 0))
	
	# 步骤3: 创建物理测试结果对象
	var result = PhysicsTestMotionResult3D.new()
	
	# 步骤4: 测试从预测位置向下移动是否会发生碰撞
	# 
	# 继续示例：
	# step_test_pos = (前方0.08米, 上方0.6米)
	# 测试向量 = Vector3(0, -MAX_STEP_HEIGHT * 2, 0) = (0, -0.6, 0)
	# 
	# 这相当于问：从测试位置向下掉0.6米，会掉到哪里？
	# 
	# 预期结果：
	# - 从高度0.6米向下掉落
	# - 碰到台阶顶面（高度0.2米）
	# - 实际移动距离：0.6 - 0.2 = 0.4米
	# - result.get_travel() = (0, -0.4, 0)
	
	if !body_test_motion_own(step_test_pos, Vector3(0, -MAX_STEP_HEIGHT * 2, 0), result):
		return false
	
	# 检查碰撞对象是否是有效的台阶
	if !is_valid_step_collider(result.get_collider()):
		return false
	
	# 步骤5: 计算台阶的实际高度
	# 
	# 公式解释：
	# - step_test_pos.origin: 测试位置 = (前方0.08米, 上方0.6米)
	# - result.get_travel(): 实际掉落距离 = (0, -0.4, 0)
	# - player.global_position: 玩家原始位置 = (0, 0, 0)
	# 
	# 计算：
	# step_test_pos.origin + result.get_travel() = (0, 0.6, 0.08) + (0, -0.4, 0)
	#                                            = (0, 0.2, 0.08)
	#                                            = 碰撞点位置
	# 
	# step_height = ((0, 0.2, 0.08) - (0, 0, 0)).y
	#             = 0.2米
	# 
	# 这就是台阶的高度！
	var step_height = ((step_test_pos.origin + result.get_travel()) - player.global_position).y
	var max_step = get_max_step_height()
	
	# 步骤6: 如果台阶太高或太低，则不上台阶
	# - 太高：超过最大可攀爬高度
	# - 太低：几乎水平移动，不需要上台阶
	if step_height > max_step or step_height <= 0.01:
		return false
	
	# 检查台阶上方是否有足够的空间
	# 将前方射线移动到台阶上方，检查是否有障碍
	stairs_ahead_ray.global_position = result.get_collision_point() + Vector3(0, MAX_STEP_HEIGHT, 0) + expected_motion.normalized() * 0.1
	stairs_ahead_ray.force_raycast_update()  # 强制立即更新射线检测结果
	
	if !stairs_ahead_ray.is_colliding() or is_too_steep(stairs_ahead_ray.get_collision_normal()):
		return false
	
	# 步骤7: 执行上台阶动作
	# 
	# 这里是关键！之前所有都是"模拟"，只有这里真的移动玩家
	# 
	# 计算：
	# - step_test_pos.origin: (前方0.08米, 上方0.6米)
	# - result.get_travel(): (0, -0.4, 0)
	# 
	# 玩家新位置 = (0, 0.6, 0.08) + (0, -0.4, 0)
	#           = (0, 0.2, 0.08)
	#           = (前方0.08米, 上方0.2米)
	# 
	# 结果：玩家现在站在台阶上了！
	save_camera_pos()  # 保存相机位置用于平滑过渡
	player.global_position = step_test_pos.origin + result.get_travel()
	
	# 执行相机平滑
	if camera_smooth_switch:
		camera_smooth(delta)
	
	# 确保玩家正确贴合台阶表面
	apply_floor_snap_own()
	snap_stair_last_frame = true
	return true

# 检查碰撞对象是否是有效的台阶
# 只允许在静态物体和CSG形状上攀爬，避免在动态物体上攀爬
func is_valid_step_collider(collider) -> bool:
	return collider.is_class("StaticBody3D") or collider.is_class("CSGShape3D")

# 根据玩家状态获取最大可攀爬的台阶高度
func get_max_step_height() -> float:
	if player.is_crouching or player.is_on_crouching:
		return MAX_CROUCH_STEP_HEIGHT  # 蹲伏时可以爬更高的台阶
	return MAX_STEP_HEIGHT

# 检查斜坡是否太陡，无法攀爬
func is_too_steep(normal: Vector3) -> bool:
	# 计算法线与垂直向上方向的夹角，如果超过SLOPE_LIMIT则认为太陡
	return normal.angle_to(Vector3.UP) > deg_to_rad(SLOPE_LIMIT)

# 保存当前相机位置，用于平滑过渡
func save_camera_pos():
	if camera_smooth_pos == null:
		camera_smooth_pos = camera_offset.global_position

# 相机平滑处理函数
# 当上下楼梯时，相机会有一个平滑的上下移动效果，避免突兀的跳跃
func camera_smooth(delta):
	if camera_smooth_pos == null:
		return
	
	# 保持相机在保存的高度位置
	camera_offset.global_position.y = camera_smooth_pos.y
	# 限制相机偏移在允许范围内
	camera_offset.position.y = clampf(camera_offset.position.y, -camera_smooth_amount, camera_smooth_amount)
	
	# 计算平滑移动的速度
	var move_amount = max(player.velocity.length() * delta, player._speed / 2 * delta)
	# 平滑地回到原始位置
	camera_offset.position.y = move_toward(camera_offset.position.y, 0.0, move_amount)
	camera_smooth_pos = camera_offset.global_position
	
	# 如果已经回到原位，清除平滑位置
	if camera_offset.position.y == 0:
		camera_smooth_pos = null

# 自定义地面吸附函数
# 确保玩家正确贴合地面，特别是在上下楼梯后
func apply_floor_snap_own():
	if player == null or player.is_on_floor():
		return
	player.apply_floor_snap()

# 自定义物理测试函数
# 这是对Godot物理系统的直接调用，用于在不实际移动物体的情况下测试碰撞
#
# 参数说明：
# - from: 测试起始的变换（位置+旋转）
# - motion: 要测试的移动向量
# - result: 存储测试结果的对象
#
# 返回：是否发生碰撞
func body_test_motion_own(from: Transform3D, motion: Vector3, result: PhysicsTestMotionResult3D) -> bool:
	# 创建物理测试参数
	var params = PhysicsTestMotionParameters3D.new()
	params.from = from  # 设置起始位置和姿态
	params.motion = motion  # 设置要测试的移动向量
	params.max_collisions = 4  # 最大检测碰撞次数
	params.recovery_as_collision = true  # 将恢复碰撞视为普通碰撞
	params.collide_separation_ray = true  # 启用分离射线碰撞检测
	
	# 使用物理服务器执行碰撞测试
	# PhysicsServer3D是Godot的物理引擎服务器，提供了底层物理功能
	# body_test_motion是一个强大的函数，可以在不实际移动物体的情况下测试碰撞
	#
	# 参数详解：
	# - player.get_rid(): 获取玩家对象的资源ID(RID)，物理系统通过RID识别对象
	# - params: 物理测试参数，包含起始位置、移动向量等
	# - result: 输出参数，函数会填充这个对象，包含碰撞点、法线、实际移动距离等信息
	#
	# 返回值：bool，表示是否发生碰撞
	return PhysicsServer3D.body_test_motion(player.get_rid(), params, result)

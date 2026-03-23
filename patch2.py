import re

with open("controllers/scripts/fps_controller.gd", "r") as f:
    content = f.read()

old_func = """func handle_rigid_body_collisions():
	if not has_node("KickArea"):
		return
	
	var kick_area = $KickArea
	var bodies = kick_area.get_overlapping_bodies()
	
	var horizontal_velocity = Vector3(velocity.x, 0, velocity.z)
	if horizontal_velocity.length() < 0.01:
		return
		
	for body in bodies:
		if body is RigidBody3D:
			var push_direction = (body.global_position - global_position).normalized()
			push_direction.y = 0.0
			if push_direction.length_squared() > 0:
				push_direction = push_direction.normalized()
			else:
				push_direction = horizontal_velocity.normalized()
			
			var impulse_magnitude = horizontal_velocity.length() * 0.3
			body.apply_central_impulse(push_direction * impulse_magnitude)"""

new_func = """func handle_rigid_body_collisions():
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
			# 混合玩家的移动方向和物体相对于玩家的方向
			var to_body = (body.global_position - global_position)
			to_body.y = 0.0
			to_body = to_body.normalized()
			
			var move_dir = horizontal_velocity.normalized()
			
			# 将两个方向混合，让受力更真实：既有玩家往前推的力，也有把物体往两边挤开的力
			var push_direction = (move_dir * 0.6 + to_body * 0.4).normalized()
			
			# 修复：因为是在物理帧(_physics_process)中连续执行，如果不乘以 delta，每秒会叠加120次巨大的瞬间冲量！
			# 根据玩家移动速度和物品质量施加推力，保证手感自然
			var impulse_magnitude = speed * body.mass * 8.0 * delta
			body.apply_central_impulse(push_direction * impulse_magnitude)"""

content = content.replace(old_func, new_func)

with open("controllers/scripts/fps_controller.gd", "w") as f:
    f.write(content)

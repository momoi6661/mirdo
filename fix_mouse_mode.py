import re

with open('controllers/scripts/pause_menu.gd', 'r', encoding='utf-8') as f:
    content = f.read()

# 1. 增加一个变量记录暂停前的鼠标状态
if "var pre_pause_mouse_mode: int" not in content:
    content = content.replace("var is_transitioning: bool = false", "var is_transitioning: bool = false\nvar pre_pause_mouse_mode: int = Input.MOUSE_MODE_CAPTURED")

# 2. 修改 show_menu() 记录状态
new_show = """func show_menu() -> void:
	if is_transitioning or visible: return
	is_transitioning = true
	
	# 记录打开 ESC 前的鼠标状态（比如是不是开着背包）
	pre_pause_mouse_mode = Input.mouse_mode
	
	show()
	if animation_player:
		animation_player.play("fade_in")
	
	_play_ui_sound("menu_open")
	
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	get_tree().paused = true
	
	if animation_player and animation_player.is_playing():
		await animation_player.animation_finished
	
	if visible and animation_player:
		animation_player.play("idle_pulse") # 开启呼吸动画
	
	is_transitioning = false"""

content = re.sub(r'func show_menu\(\) -> void:.*?is_transitioning = false', new_show, content, flags=re.DOTALL)

# 3. 修改 hide_menu() 恢复状态
new_hide = """func hide_menu() -> void:
	if is_transitioning or not visible: return
	is_transitioning = true
	
	_play_ui_sound("menu_close")
	
	if animation_player:
		animation_player.play("fade_out")
		await animation_player.animation_finished
	
	hide()
	
	# 恢复到打开 ESC 前的鼠标状态！如果之前开着背包，它依然是 VISIBLE
	Input.mouse_mode = pre_pause_mouse_mode
	get_tree().paused = false
	is_transitioning = false"""

content = re.sub(r'func hide_menu\(\) -> void:.*?is_transitioning = false', new_hide, content, flags=re.DOTALL)

with open('controllers/scripts/pause_menu.gd', 'w', encoding='utf-8') as f:
    f.write(content)

print("Mouse mode saving/restoring logic fixed!")

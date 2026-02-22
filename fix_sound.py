import re

with open('scripts/Inventory/InventoryHandler.gd', 'r', encoding='utf-8') as f:
    content = f.read()

# 修复 ui_sound_player 被错误移除或未正确初始化的 Bug
# 确保在 _ready 中正确添加并初始化 ui_sound_player
if "ui_sound_player = AudioStreamPlayer.new()" not in content:
    setup_sound = """func _ready() -> void:
	mouse_filter=Control.MOUSE_FILTER_STOP
	
	if not ui_sound_player:
		ui_sound_player = AudioStreamPlayer.new()
		ui_sound_player.bus = "UI"
		add_child(ui_sound_player)"""
    
    content = re.sub(r'func _ready\(\) -> void:\n\tmouse_filter=Control\.MOUSE_FILTER_STOP', setup_sound, content)

with open('scripts/Inventory/InventoryHandler.gd', 'w', encoding='utf-8') as f:
    f.write(content)

print("UI sound player re-initialized correctly.")

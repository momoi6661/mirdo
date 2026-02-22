import re

with open('scripts/Inventory/InventoryHandler.gd', 'r', encoding='utf-8') as f:
    content = f.read()

# 在开普通背包时，确保重置位置，防止它卡在上次箱子打开时的左边！
new_open = """func play_open_animation():
	self.visible = true
	_play_ui_sound("menu_open")
	
	# === 核心修复：单开背包时，必须确保主面板在正中心！ ===
	# 这是防止你开完箱子后，主面板一直被卡在左边的致命 Bug
	if PanelNode:
		PanelNode.position = Vector2(560, 290) # 这是你原本居中的坐标
	
	if has_node("UIAnimationPlayer"):
		var animator = $UIAnimationPlayer
		if animator.has_animation("inv_open"):
			animator.play("inv_open")
"""

content = re.sub(r'func play_open_animation\(\):.*?if animator\.has_animation\("inv_open"\):\n\t\t\tanimator\.play\("inv_open"\)\n', new_open, content, flags=re.DOTALL)

with open('scripts/Inventory/InventoryHandler.gd', 'w', encoding='utf-8') as f:
    f.write(content)

print("InventoryHandler open animation fixed with position reset.")

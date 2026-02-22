import re

with open('scripts/Inventory/InventoryHandler.gd', 'r', encoding='utf-8') as f:
    content = f.read()

# 在 _setup_ultimate_ui 中加入对 scale 的强制重置，防止因为上一次播放了 inv_close 导致 scale 停留在 (0.9, 0.9)
setup_fix = """func _setup_ultimate_ui():
	# 强制修正 UI 大小、锚点、中心坐标和缩放（防止被上一次动画缩放污染）
	if PanelNode:
		PanelNode.set_anchors_preset(Control.PRESET_CENTER)
		PanelNode.size = Vector2(800, 500)
		PanelNode.position = Vector2(560, 290)
		PanelNode.pivot_offset = Vector2(400, 250)
		PanelNode.scale = Vector2(1.0, 1.0) # 核心修复：防止上一次关背包把这玩意缩小到了0.9，导致和箱子产生大小差异！
	
	var loot_panel = get_node_or_null("LootPanel")
	if loot_panel:
		loot_panel.set_anchors_preset(Control.PRESET_CENTER)
		loot_panel.size = Vector2(350, 500)
		loot_panel.position = Vector2(785, 290) # 藏在背包背后中心点
		loot_panel.pivot_offset = Vector2(175, 250)
		loot_panel.scale = Vector2(1.0, 1.0) # 核心修复
		loot_panel.visible = false
		loot_panel.modulate.a = 0.0"""

content = re.sub(r'func _setup_ultimate_ui\(\):.*?loot_panel\.modulate\.a = 0\.0', setup_fix, content, flags=re.DOTALL)

with open('scripts/Inventory/InventoryHandler.gd', 'w', encoding='utf-8') as f:
    f.write(content)

print("Scale sync bug fixed in setup_ultimate_ui!")

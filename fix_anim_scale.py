import re

with open('scripts/Inventory/InventoryHandler.gd', 'r', encoding='utf-8') as f:
    content = f.read()

# 把强制重置 scale 的代码去掉，回归纯动画控制。
# 只保留大小尺寸和中心点保护，移除缩放强改。
clean_setup = """func _setup_ultimate_ui():
	# 强制修正 UI 大小、锚点和中心坐标（防止编辑器里被乱拖）
	if PanelNode:
		PanelNode.set_anchors_preset(Control.PRESET_CENTER)
		PanelNode.size = Vector2(800, 500)
		PanelNode.position = Vector2(560, 290)
		PanelNode.pivot_offset = Vector2(400, 250)
	
	var loot_panel = get_node_or_null("LootPanel")
	if loot_panel:
		loot_panel.set_anchors_preset(Control.PRESET_CENTER)
		loot_panel.size = Vector2(350, 500)
		loot_panel.position = Vector2(785, 290) # 藏在背包背后中心点
		loot_panel.pivot_offset = Vector2(175, 250)
		loot_panel.visible = false
		loot_panel.modulate.a = 0.0"""

content = re.sub(r'func _setup_ultimate_ui\(\):.*?loot_panel\.modulate\.a = 0\.0', clean_setup, content, flags=re.DOTALL)

# 现在修改我们在代码里动态生成的 _build_animations，为 loot_open 和 loot_close 强制注入 Scale(1,1)
# 这样动画在播放的每一帧都会自然地把缩放撑满。

new_loot_open_track = """	# 3. 开箱子（左右抽屉）
	var a_loot_open = Animation.new()
	a_loot_open.length = 0.35
	_add_track(a_loot_open, "MainPanel:position", 0.0, Vector2(560, 290), 0.35, Vector2(360, 290))
	_add_track(a_loot_open, "MainPanel:modulate", 0.0, Color(1,1,1,0), 0.25, Color(1,1,1,1))
	_add_track(a_loot_open, "MainPanel:scale", 0.0, Vector2(1,1), 0.35, Vector2(1,1)) # <== 注入的修复
	_add_track(a_loot_open, "LootPanel:position", 0.0, Vector2(785, 290), 0.35, Vector2(1180, 290))
	_add_track(a_loot_open, "LootPanel:modulate", 0.0, Color(1,1,1,0), 0.25, Color(1,1,1,1))
	_add_track(a_loot_open, "LootPanel:scale", 0.0, Vector2(1,1), 0.35, Vector2(1,1)) # <== 注入的修复
	lib.add_animation("loot_open", a_loot_open)
	
	# 4. 关箱子
	var a_loot_close = Animation.new()
	a_loot_close.length = 0.25
	_add_track(a_loot_close, "MainPanel:position", 0.0, Vector2(360, 290), 0.25, Vector2(560, 290))
	_add_track(a_loot_close, "MainPanel:modulate", 0.0, Color(1,1,1,1), 0.25, Color(1,1,1,0))
	_add_track(a_loot_close, "MainPanel:scale", 0.0, Vector2(1,1), 0.25, Vector2(1,1)) # <== 注入的修复
	_add_track(a_loot_close, "LootPanel:position", 0.0, Vector2(1180, 290), 0.25, Vector2(785, 290))
	_add_track(a_loot_close, "LootPanel:modulate", 0.0, Color(1,1,1,1), 0.25, Color(1,1,1,0))
	_add_track(a_loot_close, "LootPanel:scale", 0.0, Vector2(1,1), 0.25, Vector2(1,1)) # <== 注入的修复
	lib.add_animation("loot_close", a_loot_close)"""

content = re.sub(r'# 3\. 开箱子.*?lib\.add_animation\("loot_close", a_loot_close\)', new_loot_open_track, content, flags=re.DOTALL)

with open('scripts/Inventory/InventoryHandler.gd', 'w', encoding='utf-8') as f:
    f.write(content)

print("Scale fixes moved directly into Animation keyframes!")

import re

with open('controllers/scripts/loot_ui_handler.gd', 'r', encoding='utf-8') as f:
    content = f.read()

# 这次精确匹配到包含报错那一行的废弃代码块并删除
bad_block = """	if source_player_slot.parent_handler and source_player_slot.parent_handler.has_method("clear_info_display"):
		if source_player_slot.StackCount <= 0:
			source_player_slot.parent_handler.clear_info_display()
"""

# 我们用更安全的方式：找到 func _sync_loot_data() 之前所有带 source_player_slot 的错误悬空代码
content = re.sub(r'\tif source_player_slot\.parent_handler.*?clear_info_display\(\)\n\n\nfunc _sync_loot_data', 'func _sync_loot_data', content, flags=re.DOTALL)

with open('controllers/scripts/loot_ui_handler.gd', 'w', encoding='utf-8') as f:
    f.write(content)

print("Final ghost code eliminated!")

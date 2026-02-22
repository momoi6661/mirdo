import re

with open('controllers/scripts/loot_ui_handler.gd', 'r', encoding='utf-8') as f:
    loot_code = f.read()

# 1. 补上丢失的 close_loot_panel 和信号连接
if "Global.close_loot_ui.connect(close_loot_panel)" not in loot_code:
    loot_code = loot_code.replace("Global.open_loot_ui.connect(open_loot_panel)", "Global.open_loot_ui.connect(open_loot_panel)\n\tGlobal.close_loot_ui.connect(close_loot_panel)")

if "func close_loot_panel() -> void:" not in loot_code:
    close_func = """
func close_loot_panel() -> void:
	current_container = null
	_clear_slots()
"""
    loot_code += close_func

with open('controllers/scripts/loot_ui_handler.gd', 'w', encoding='utf-8') as f:
    f.write(loot_code)

print("LootUIHandler cleanup logic added.")

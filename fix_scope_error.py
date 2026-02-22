import re

with open('controllers/scripts/loot_ui_handler.gd', 'r', encoding='utf-8') as f:
    content = f.read()

# 移除 _drop_data 后面错误复制的 clear_info_display 残留代码
content = re.sub(r'\tfor slot in active_slots:\n\t\tif not slot\.SlotFilled:\n\t\t\ttransfer_item_from_player\(source_slot, slot, amount\)\n\t\t\treturn\n\n\tif source_player_slot\.parent_handler and source_player_slot\.parent_handler\.has_method\("clear_info_display"\):\n\t\tif source_player_slot\.StackCount <= 0:\n\t\t\tsource_player_slot\.parent_handler\.clear_info_display\(\)\n', '\tfor slot in active_slots:\n\t\tif not slot.SlotFilled:\n\t\t\ttransfer_item_from_player(source_slot, slot, amount)\n\t\t\treturn\n', content, flags=re.DOTALL)


with open('controllers/scripts/loot_ui_handler.gd', 'w', encoding='utf-8') as f:
    f.write(content)

print("Scope error fixed!")

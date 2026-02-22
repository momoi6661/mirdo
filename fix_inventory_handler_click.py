import re

with open('scripts/Inventory/InventoryHandler.gd', 'r', encoding='utf-8') as f:
    content = f.read()

# 修复 _on_slot_item_clicked 中的变量引用错误。
# 函数签名接收的是 slot_id: int，但是内部尝试直接当成 slot 对象来用 (比如 != slot, slot.set_pressed_no_signal)
new_click_func = """func _on_slot_item_clicked(item_data: ItemData, slot_id: int):
	var slot = InventorySlots[slot_id]
	if current_selected_slot and current_selected_slot != slot:
		current_selected_slot.set_pressed_no_signal(false)
	
	current_selected_slot = slot
	if slot:
		slot.set_pressed_no_signal(true)
		_play_ui_sound("button_click")
	
	if item_data:"""

content = re.sub(r'func _on_slot_item_clicked\(item_data: ItemData, slot_id: int\):\n\tif current_selected_slot and current_selected_slot != slot:\n\t\tcurrent_selected_slot\.set_pressed_no_signal\(false\)\n\t\n\tcurrent_selected_slot = slot\n\tif slot:\n\t\tslot\.set_pressed_no_signal\(true\)\n\t\t_play_ui_sound\("button_click"\)\n\t\n\tif item_data:', new_click_func, content, flags=re.DOTALL)

with open('scripts/Inventory/InventoryHandler.gd', 'w', encoding='utf-8') as f:
    f.write(content)

print("InventoryHandler _on_slot_item_clicked fixed!")

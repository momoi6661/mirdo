import re

with open('scripts/Inventory/InventoryHandler.gd', 'r', encoding='utf-8') as f:
    content = f.read()

# 修复 bind() 传递了错误的参数类型 (slot 对象而不是 slot_id)
content = re.sub(r'slot\.item_clicked\.connect\(_on_slot_item_clicked\.bind\(slot\)\)', r'slot.item_clicked.connect(_on_slot_item_clicked)', content)

# 修复 259 行手动调用时，传递了错误的参数类型 (slot 对象而不是 slot_id)
content = re.sub(r'_on_slot_item_clicked\(current_selected_slot\.SlotData, current_selected_slot\)', r'_on_slot_item_clicked(current_selected_slot.SlotData, current_selected_slot.InventorySlotId)', content)

with open('scripts/Inventory/InventoryHandler.gd', 'w', encoding='utf-8') as f:
    f.write(content)

print("Invalid arguments fixed!")

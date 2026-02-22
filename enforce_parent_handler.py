import re

with open('scripts/Inventory/InventoryHandler.gd', 'r', encoding='utf-8') as f:
    content = f.read()

# 确保在 _ready 生成格子时，强行加上 slot.parent_handler = self
# 在两个地方：existing_slots 和 new slots
new_existing = """			slot.InventorySlotId = i
			slot.slot_owner = slot.SlotOwner.PLAYER
			slot.parent_handler = self
			slot.is_selectable = true
			slot.amount_selector = AmountSelector"""

content = re.sub(r'slot\.InventorySlotId = i\n\t\t\tslot\.amount_selector = AmountSelector', new_existing, content)

new_spawned = """				slot.InventorySlotId=i
				slot.slot_owner = slot.SlotOwner.PLAYER
				slot.parent_handler = self
				slot.is_selectable = true
				slot.amount_selector=AmountSelector"""

content = re.sub(r'slot\.InventorySlotId=i\n\t\t\t\tslot\.amount_selector=AmountSelector', new_spawned, content)

with open('scripts/Inventory/InventoryHandler.gd', 'w', encoding='utf-8') as f:
    f.write(content)

print("Parent handler strongly enforced for player slots.")

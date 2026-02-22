import re

with open('scripts/Inventory/InventoryHandler.gd', 'r', encoding='utf-8') as f:
    content = f.read()

# 在 existing_slots 和 new slot 生成的地方，补上极其重要的 parent_handler = self
new_existing = """			if slot:
				slot.InventorySlotId = i
				slot.slot_owner = slot.SlotOwner.PLAYER # 标记为玩家格子
				slot.parent_handler = self # 核心修复！告诉格子它的主人是谁！
				slot.amount_selector = AmountSelector"""

new_spawned = """				var slot=slot_node.get_node("Button") as InventorySlot
				if slot:
					slot.InventorySlotId=i
					slot.slot_owner = slot.SlotOwner.PLAYER # 标记为玩家格子
					slot.parent_handler = self # 核心修复！
					slot.amount_selector=AmountSelector"""

content = re.sub(r'\t\t\tif slot:\n\t\t\t\tslot\.InventorySlotId = i\n\t\t\t\tslot\.amount_selector = AmountSelector', new_existing, content)

content = re.sub(r'\t\t\t\tvar slot=slot_node\.get_node\("Button"\) as InventorySlot\n\t\t\t\tif slot:\n\t\t\t\t\tslot\.InventorySlotId=i\n\t\t\t\t\tslot\.amount_selector=AmountSelector', new_spawned, content)


with open('scripts/Inventory/InventoryHandler.gd', 'w', encoding='utf-8') as f:
    f.write(content)

print("parent_handler linkage restored in InventoryHandler!")

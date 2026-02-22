import re

with open('scripts/Inventory/InventoryHandler.gd', 'r', encoding='utf-8') as f:
    content = f.read()

# 核心修复点：将 transfer_item_from_loot 移动到 InventoryHandler，但是要确保 slot.parent_handler 绑定的就是自己！
# 我发现之前的修复虽然绑定了，但是 _ready 里的代码可能有遗漏。

ensure_handler_binding = """			slot.InventorySlotId = i
			slot.slot_owner = slot.SlotOwner.PLAYER # 标记为玩家格子
			slot.parent_handler = self # 告诉格子它的主人是谁！"""

if "slot.slot_owner = slot.SlotOwner.PLAYER" not in content:
    content = re.sub(r'slot\.InventorySlotId = i\n\t\t\tslot\.amount_selector', ensure_handler_binding + '\n\t\t\tslot.amount_selector', content)

if "slot.slot_owner = slot.SlotOwner.PLAYER" not in content:
    content = re.sub(r'slot\.InventorySlotId=i\n\t\t\t\tslot\.amount_selector', ensure_handler_binding + '\n\t\t\t\tslot.amount_selector', content)

with open('scripts/Inventory/InventoryHandler.gd', 'w', encoding='utf-8') as f:
    f.write(content)

print("Double checked the Player's parent_handler binding!")

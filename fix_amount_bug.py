import re

# 1. 修复 inventory_slot.gd 中字典键值的回退问题
with open('scripts/Inventory/inventory_slot.gd', 'r', encoding='utf-8') as f:
    slot_code = f.read()

# 为了绝对的兼容性，让它同时去取 "amount" 或者 "Amount"（因为有些跨文件的地方可能用了大写）
drop_data_fix = """func _drop_data(at_position: Vector2, data: Variant) -> void:
	var amount = 1
	if data.has("amount"):
		amount = data.get("amount")
	elif data.has("Amount"):
		amount = data.get("Amount")
		
	var source_slot = data.get("source_slot")"""

slot_code = re.sub(r'func _drop_data\(at_position: Vector2, data: Variant\) -> void:\n\tvar amount = data\.get\("amount"\) # 注意这里是 "amount"，不是 "Amount"\n\tvar source_slot = data\.get\("source_slot"\)', drop_data_fix, slot_code)

with open('scripts/Inventory/inventory_slot.gd', 'w', encoding='utf-8') as f:
    f.write(slot_code)


# 2. 修复 InventoryHandler.gd 中由于 .bind() 带来的空参数覆盖问题
with open('scripts/Inventory/InventoryHandler.gd', 'r', encoding='utf-8') as f:
    inv_code = f.read()

# 移除 OnItemDropped.connect(ItemDroppedOnSlot.bind()) 中的 .bind()，这会强制用空参数覆盖原本发出的三个参数！
inv_code = inv_code.replace("slot.OnItemDropped.connect(ItemDroppedOnSlot.bind())", "slot.OnItemDropped.connect(ItemDroppedOnSlot)")

with open('scripts/Inventory/InventoryHandler.gd', 'w', encoding='utf-8') as f:
    f.write(inv_code)

print("Amount drop bug and bind() override fixed!")

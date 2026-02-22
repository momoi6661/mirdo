import re

with open('controllers/scripts/loot_ui_handler.gd', 'r', encoding='utf-8') as f:
    content = f.read()

# 移除循环内部重复声明的 main_inventory，只保留顶部的那个，并复用它
content = content.replace('\t\tvar main_inventory = get_parent()\n\t\tvar raw_node = inventory_slot_prefab.instantiate()', '\t\tvar raw_node = inventory_slot_prefab.instantiate()')

# 移除循环后面重复声明的 main_inventory，因为我们在最上面已经获取过了
content = content.replace('\tvar main_inventory = get_parent()\n\tif main_inventory and main_inventory.has_method("play_loot_open_animation"):', '\tif main_inventory and main_inventory.has_method("play_loot_open_animation"):')

with open('controllers/scripts/loot_ui_handler.gd', 'w', encoding='utf-8') as f:
    f.write(content)

print("Duplicate variables eliminated!")

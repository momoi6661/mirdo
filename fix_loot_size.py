import re

with open('controllers/ui/InventoryUI.tscn', 'r', encoding='utf-8') as f:
    content = f.read()

# 主背包 MainPanel 的尺寸是 offset_left = -400, offset_right = 400 （宽度 800）
# 箱子面板我们给它一半的宽度（宽度 400），高度保持一致（从 -250 到 250，高度 500）
new_loot_node = """[node name="LootPanel" parent="." unique_id=1279546275 instance=ExtResource("loot_scene_123")]
visible = false
layout_mode = 1
anchors_preset = 8
anchor_left = 0.5
anchor_top = 0.5
anchor_right = 0.5
anchor_bottom = 0.5
offset_left = -200.0
offset_top = -250.0
offset_right = 200.0
offset_bottom = 250.0
grow_horizontal = 2
grow_vertical = 2"""

content = re.sub(r'\[node name="LootPanel".*?grow_vertical = 2', new_loot_node, content, flags=re.DOTALL)

with open('controllers/ui/InventoryUI.tscn', 'w', encoding='utf-8') as f:
    f.write(content)

print("LootPanel size fixed to match MainPanel height and have proper width!")

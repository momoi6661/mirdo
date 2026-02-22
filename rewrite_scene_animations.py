import re

with open('controllers/ui/InventoryUI.tscn', 'r', encoding='utf-8') as f:
    content = f.read()

# 1. 修复 LootPanel 的静态位置和锚点，使其大小正常，并且居中停放等待动画
new_loot_node = """[node name="LootPanel" parent="." unique_id=1279546275 instance=ExtResource("loot_scene_123")]
visible = false
modulate = Color(1, 1, 1, 0)
layout_mode = 1
anchors_preset = 8
anchor_left = 0.5
anchor_top = 0.5
anchor_right = 0.5
anchor_bottom = 0.5
offset_left = -175.0
offset_top = -250.0
offset_right = 175.0
offset_bottom = 250.0
grow_horizontal = 2
grow_vertical = 2"""

content = re.sub(r'\[node name="LootPanel".*?grow_vertical = 2', new_loot_node, content, flags=re.DOTALL)


# 2. 彻底重写 AnimationPlayer 里的滑开和合拢逻辑。
# 基于 1920x1080，MainPanel 中心是 560, LootPanel 中心是 785
# 展开时：MainPanel 往左退到 340, LootPanel 往右推到 960 (彻底露出)
new_anim_library = """[sub_resource type="Animation" id="Animation_inv_open"]
resource_name = "inv_open"
length = 0.25
tracks/0/type = "value"
tracks/0/imported = false
tracks/0/enabled = true
tracks/0/path = NodePath("MainPanel:scale")
tracks/0/interp = 2
tracks/0/loop_wrap = true
tracks/0/keys = {
"times": PackedFloat32Array(0, 0.25),
"transitions": PackedFloat32Array(0.5, 1),
"update": 0,
"values": [Vector2(0.9, 0.9), Vector2(1, 1)]
}
tracks/1/type = "value"
tracks/1/imported = false
tracks/1/enabled = true
tracks/1/path = NodePath("MainPanel:modulate")
tracks/1/interp = 2
tracks/1/loop_wrap = true
tracks/1/keys = {
"times": PackedFloat32Array(0, 0.2),
"transitions": PackedFloat32Array(1, 1),
"update": 0,
"values": [Color(1, 1, 1, 0), Color(1, 1, 1, 1)]
}
tracks/2/type = "value"
tracks/2/imported = false
tracks/2/enabled = true
tracks/2/path = NodePath("MainPanel:position")
tracks/2/interp = 1
tracks/2/loop_wrap = true
tracks/2/keys = {
"times": PackedFloat32Array(0),
"transitions": PackedFloat32Array(1),
"update": 0,
"values": [Vector2(560, 290)]
}

[sub_resource type="Animation" id="Animation_inv_close"]
resource_name = "inv_close"
length = 0.15
tracks/0/type = "value"
tracks/0/imported = false
tracks/0/enabled = true
tracks/0/path = NodePath("MainPanel:scale")
tracks/0/interp = 2
tracks/0/loop_wrap = true
tracks/0/keys = {
"times": PackedFloat32Array(0, 0.15),
"transitions": PackedFloat32Array(2, 1),
"update": 0,
"values": [Vector2(1, 1), Vector2(0.9, 0.9)]
}
tracks/1/type = "value"
tracks/1/imported = false
tracks/1/enabled = true
tracks/1/path = NodePath("MainPanel:modulate")
tracks/1/interp = 2
tracks/1/loop_wrap = true
tracks/1/keys = {
"times": PackedFloat32Array(0, 0.15),
"transitions": PackedFloat32Array(2, 1),
"update": 0,
"values": [Color(1, 1, 1, 1), Color(1, 1, 1, 0)]
}

[sub_resource type="Animation" id="Animation_loot_open"]
resource_name = "loot_open"
length = 0.35
tracks/0/type = "value"
tracks/0/imported = false
tracks/0/enabled = true
tracks/0/path = NodePath("MainPanel:position")
tracks/0/interp = 2
tracks/0/loop_wrap = true
tracks/0/keys = {
"times": PackedFloat32Array(0, 0.35),
"transitions": PackedFloat32Array(0.3, 1),
"update": 0,
"values": [Vector2(560, 290), Vector2(160, 290)]
}
tracks/1/type = "value"
tracks/1/imported = false
tracks/1/enabled = true
tracks/1/path = NodePath("LootPanel:position")
tracks/1/interp = 2
tracks/1/loop_wrap = true
tracks/1/keys = {
"times": PackedFloat32Array(0, 0.35),
"transitions": PackedFloat32Array(0.3, 1),
"update": 0,
"values": [Vector2(785, 290), Vector2(985, 290)]
}
tracks/2/type = "value"
tracks/2/imported = false
tracks/2/enabled = true
tracks/2/path = NodePath("LootPanel:modulate")
tracks/2/interp = 2
tracks/2/loop_wrap = true
tracks/2/keys = {
"times": PackedFloat32Array(0, 0.25),
"transitions": PackedFloat32Array(1, 1),
"update": 0,
"values": [Color(1, 1, 1, 0), Color(1, 1, 1, 1)]
}
tracks/3/type = "value"
tracks/3/imported = false
tracks/3/enabled = true
tracks/3/path = NodePath("MainPanel:modulate")
tracks/3/interp = 2
tracks/3/loop_wrap = true
tracks/3/keys = {
"times": PackedFloat32Array(0, 0.25),
"transitions": PackedFloat32Array(1, 1),
"update": 0,
"values": [Color(1, 1, 1, 0), Color(1, 1, 1, 1)]
}
tracks/4/type = "value"
tracks/4/imported = false
tracks/4/enabled = true
tracks/4/path = NodePath("LootPanel:visible")
tracks/4/interp = 1
tracks/4/loop_wrap = true
tracks/4/keys = {
"times": PackedFloat32Array(0),
"transitions": PackedFloat32Array(1),
"update": 1,
"values": [true]
}

[sub_resource type="Animation" id="Animation_loot_close"]
resource_name = "loot_close"
length = 0.25
tracks/0/type = "value"
tracks/0/imported = false
tracks/0/enabled = true
tracks/0/path = NodePath("MainPanel:position")
tracks/0/interp = 2
tracks/0/loop_wrap = true
tracks/0/keys = {
"times": PackedFloat32Array(0, 0.25),
"transitions": PackedFloat32Array(2, 1),
"update": 0,
"values": [Vector2(160, 290), Vector2(560, 290)]
}
tracks/1/type = "value"
tracks/1/imported = false
tracks/1/enabled = true
tracks/1/path = NodePath("LootPanel:position")
tracks/1/interp = 2
tracks/1/loop_wrap = true
tracks/1/keys = {
"times": PackedFloat32Array(0, 0.25),
"transitions": PackedFloat32Array(2, 1),
"update": 0,
"values": [Vector2(985, 290), Vector2(785, 290)]
}
tracks/2/type = "value"
tracks/2/imported = false
tracks/2/enabled = true
tracks/2/path = NodePath("LootPanel:modulate")
tracks/2/interp = 2
tracks/2/loop_wrap = true
tracks/2/keys = {
"times": PackedFloat32Array(0, 0.25),
"transitions": PackedFloat32Array(1, 1),
"update": 0,
"values": [Color(1, 1, 1, 1), Color(1, 1, 1, 0)]
}
tracks/3/type = "value"
tracks/3/imported = false
tracks/3/enabled = true
tracks/3/path = NodePath("MainPanel:modulate")
tracks/3/interp = 2
tracks/3/loop_wrap = true
tracks/3/keys = {
"times": PackedFloat32Array(0, 0.25),
"transitions": PackedFloat32Array(1, 1),
"update": 0,
"values": [Color(1, 1, 1, 1), Color(1, 1, 1, 0)]
}
tracks/4/type = "value"
tracks/4/imported = false
tracks/4/enabled = true
tracks/4/path = NodePath("LootPanel:visible")
tracks/4/interp = 1
tracks/4/loop_wrap = true
tracks/4/keys = {
"times": PackedFloat32Array(0.25),
"transitions": PackedFloat32Array(1),
"update": 1,
"values": [false]
}

[sub_resource type="Animation" id="Animation_close_all"]
resource_name = "close_all"
length = 0.15
tracks/0/type = "value"
tracks/0/imported = false
tracks/0/enabled = true
tracks/0/path = NodePath("MainPanel:modulate")
tracks/0/interp = 2
tracks/0/loop_wrap = true
tracks/0/keys = {
"times": PackedFloat32Array(0, 0.15),
"transitions": PackedFloat32Array(2, 1),
"update": 0,
"values": [Color(1, 1, 1, 1), Color(1, 1, 1, 0)]
}

[sub_resource type="AnimationLibrary" id="AnimationLibrary_ui"]
_data = {
&"close_all": SubResource("Animation_close_all"),
&"inv_close": SubResource("Animation_inv_close"),
&"inv_open": SubResource("Animation_inv_open"),
&"loot_close": SubResource("Animation_loot_close"),
&"loot_open": SubResource("Animation_loot_open")
}"""

content = re.sub(r'\[sub_resource type="Animation".*?\}\n\n\[node name="InventoryUi"', new_anim_library + '\n\n[node name="InventoryUi"', content, flags=re.DOTALL)

with open('controllers/ui/InventoryUI.tscn', 'w', encoding='utf-8') as f:
    f.write(content)

print("Scene safely overwritten with perfectly centered and sliding animations!")

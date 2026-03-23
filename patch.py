import re

with open("controllers/fps_controller.tscn", "r") as f:
    content = f.read()

# Add KickArea Area3D and its CollisionShape3D
# Find the end of the file or a good place to insert.
# Let's insert it under the root node.

kick_area = """
[node name="KickArea" type="Area3D" parent="."]
collision_layer = 0
collision_mask = 2

[node name="CollisionShape3D" type="CollisionShape3D" parent="KickArea"]
transform = Transform3D(1, 0, 0, 0, 1, 0, 0, 0, 1, 0, 0.5, 0)
shape = SubResource("CylinderShape3D_kick")
"""

# We also need to add the SubResource for CylinderShape3D_kick
sub_resource = """
[sub_resource type="CylinderShape3D" id="CylinderShape3D_kick"]
radius = 0.6
height = 1.0
"""

# Insert sub_resource before the first [node name=
node_idx = content.find('\n[node name=')
content = content[:node_idx] + sub_resource + content[node_idx:]

# Insert kick_area at the end of the file
content += kick_area

# Update Player's collision layer and mask to avoid hard collisions
# Find [node name="PlayerController" type="CharacterBody3D"
player_node_idx = content.find('[node name="PlayerController" type="CharacterBody3D"')
# Find the next [node
next_node_idx = content.find('[node', player_node_idx + 1)

player_section = content[player_node_idx:next_node_idx]
if "collision_layer" not in player_section:
    player_section = player_section.replace('\nscript =', '\ncollision_layer = 4\ncollision_mask = 1\nscript =')
else:
    # Modify existing
    player_section = re.sub(r'collision_layer = .*', 'collision_layer = 4', player_section)
    player_section = re.sub(r'collision_mask = .*', 'collision_mask = 1', player_section)

content = content[:player_node_idx] + player_section + content[next_node_idx:]

with open("controllers/fps_controller.tscn", "w") as f:
    f.write(content)

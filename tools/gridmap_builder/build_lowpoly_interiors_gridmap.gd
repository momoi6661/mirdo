extends SceneTree

const SOURCE_SCENE := "res://3DModel/lowpoly_interior_kit/lowpoly_interiors.tscn"
const OUT_ROOT := "res://levels/interiors/lowpoly_interiors"
const GRIDMAP_DIR := OUT_ROOT + "/gridmap"
const PROPS_DIR := OUT_ROOT + "/props"
const MESH_LIBRARY_PATH := GRIDMAP_DIR + "/lowpoly_interiors_building_mesh_library.tres"
const TOON_MATERIAL_PATH := OUT_ROOT + "/materials/lowpoly_interior_toon_material.tres"
const PLAIN_MATERIAL_PATH := "res://3DModel/lowpoly_interior_kit/materials/mat_default.tres"
const TEST_SCENE_PATH := OUT_ROOT + "/interior_gridmap_test.tscn"
const WORLD_TEST_SCENE_PATH := "res://levels/lowpoly_interiors_world_test.tscn"
const GRID_CELL_SIZE := Vector3(2.0, 3.0, 2.0)

const BUILDING_NAMES := [
	"M_wall_1",
	"M_wall_2",
	"M_wall_3",
	"M_wall_doors_empty_1",
	"M_wall_doors_empty_2",
	"M_wall_doors_empty_3",
	"M_floor_0",
	"M_floor_1",
	"M_floor_3",
	"M_ceiling",
]

const PROP_CATEGORIES := {
	"school": [
		"M_SchoolTable",
		"M_SchoolChair",
		"M_SchoolTeacherTable",
		"M_BlackBoard",
		"M_Corc_Board",
	],
	"bedroom": [
		"M_Bed",
		"M_shelf_small",
		"M_room_desk",
		"M_Bookshelf",
		"M_Wardrobe",
		"M_retroTV",
	],
	"books": [
		"M_BookClosed_1",
		"M_BookOpen_1",
		"M_BookClosed_2",
		"M_BookOpen_2",
		"M_BookClosed_3",
		"M_BookOpen_3",
		"M_BookClosed_4",
		"M_HopsonBook_Closed",
		"M_HopsonBook_Open",
	],
	"lighting": [
		"M_Ceiling_Lamp",
		"M_LampSmall",
	],
	"decor": [
		"M_scienctific_poster_1",
	],
	"doors": [
		"M_doors",
	],
	"windows": [
		"M_Window_1",
		"M_Window_2",
	],
}

var _building_id_by_name: Dictionary = {}
var _prop_instance_counts: Dictionary = {}

func _init() -> void:
	print("Building Lowpoly Interiors GridMap assets...")
	_ensure_dirs()
	var root := _load_source()
	if root == null:
		return
	_build_mesh_library(root)
	_build_prop_scenes(root)
	_build_test_scene()
	_build_world_test_scene()
	root.free()
	print("Done: %s" % OUT_ROOT)
	quit()

func _ensure_dirs() -> void:
	_make_dir_recursive(GRIDMAP_DIR)
	_make_dir_recursive(PROPS_DIR)
	for category in PROP_CATEGORIES.keys():
		_make_dir_recursive(PROPS_DIR + "/" + str(category))

func _make_dir_recursive(path: String) -> void:
	var dir := DirAccess.open("res://")
	var rel := path.trim_prefix("res://")
	if dir != null:
		dir.make_dir_recursive(rel)

func _load_source() -> Node3D:
	var packed := load(SOURCE_SCENE) as PackedScene
	if packed == null:
		push_error("Cannot load source scene: %s" % SOURCE_SCENE)
		return null
	return packed.instantiate() as Node3D

func _find_mesh(root: Node, node_name: String) -> MeshInstance3D:
	if root.name == node_name and root is MeshInstance3D:
		return root as MeshInstance3D
	for child in root.get_children():
		var result := _find_mesh(child, node_name)
		if result != null:
			return result
	return null

func _get_grid_item_transform(mesh_name: String, mesh: Mesh) -> Transform3D:
	var aabb := mesh.get_aabb()
	var offset := Vector3.ZERO
	# Source sizes:
	# floor/ceiling local x/z = -1..1, wall local x = -1..1 and z = 0..0.2.
	# GridMap uses corner alignment (cell_center false), so convert local bounds to cell coordinates.
	if mesh_name.begins_with("M_floor"):
		# floor spans x/z 0..2, top at y=0
		offset = Vector3(-aabb.position.x, -(aabb.position.y + aabb.size.y), -aabb.position.z)
	elif mesh_name == "M_ceiling":
		# ceiling spans x/z 0..2, bottom at CeilingGridMap y=3
		offset = Vector3(-aabb.position.x, -aabb.position.y, -aabb.position.z)
	elif mesh_name.begins_with("M_wall"):
		# wall spans x 0..2, y 0..3, thickness starts at z=0 boundary line.
		offset = Vector3(-aabb.position.x, -aabb.position.y, -aabb.position.z)
	else:
		offset = Vector3(-aabb.position.x, -aabb.position.y, -aabb.position.z)
	return Transform3D(Basis.IDENTITY, offset)

func _get_toon_material() -> Material:
	# Temporarily use the original palette material. The generated map should be easy to inspect
	# before re-enabling anime toon/outline rendering.
	var material := load(PLAIN_MATERIAL_PATH) as Material
	if material == null:
		push_warning("Missing plain lowpoly material: %s" % PLAIN_MATERIAL_PATH)
	return material

func _apply_toon_material_to_mesh(mesh: Mesh) -> void:
	if mesh == null:
		return
	var material := _get_toon_material()
	if material == null:
		return
	for surface_index in range(mesh.get_surface_count()):
		mesh.surface_set_material(surface_index, material)

func _build_mesh_library(root: Node3D) -> void:
	var library := MeshLibrary.new()
	_building_id_by_name.clear()
	var item_id := 0
	for mesh_name in BUILDING_NAMES:
		var source := _find_mesh(root, mesh_name)
		if source == null or source.mesh == null:
			push_warning("Missing building mesh: %s" % mesh_name)
			continue
		var mesh := source.mesh.duplicate(true) as Mesh
		_apply_toon_material_to_mesh(mesh)
		library.create_item(item_id)
		library.set_item_name(item_id, _display_name(mesh_name))
		var item_transform := _get_grid_item_transform(mesh_name, mesh)
		library.set_item_mesh(item_id, mesh)
		library.set_item_mesh_transform(item_id, item_transform)
		var shape := mesh.create_trimesh_shape()
		if shape != null:
			library.set_item_shapes(item_id, [shape, item_transform])
		_building_id_by_name[mesh_name] = item_id
		item_id += 1
	var err := ResourceSaver.save(library, MESH_LIBRARY_PATH)
	if err != OK:
		push_error("Failed to save MeshLibrary %s: %s" % [MESH_LIBRARY_PATH, error_string(err)])
	else:
		print("Saved MeshLibrary: %s (%d items)" % [MESH_LIBRARY_PATH, item_id])

func _build_prop_scenes(root: Node3D) -> void:
	for category in PROP_CATEGORIES.keys():
		for mesh_name in PROP_CATEGORIES[category]:
			var source := _find_mesh(root, mesh_name)
			if source == null or source.mesh == null:
				push_warning("Missing prop mesh: %s" % mesh_name)
				continue
			_save_prop_scene(source, str(category))

func _save_prop_scene(source: MeshInstance3D, category: String) -> void:
	var scene_root := Node3D.new()
	scene_root.name = _display_name(source.name)
	var mesh_instance := MeshInstance3D.new()
	mesh_instance.name = "Mesh"
	mesh_instance.mesh = source.mesh.duplicate(true)
	_apply_toon_material_to_mesh(mesh_instance.mesh)
	mesh_instance.transform = Transform3D.IDENTITY
	scene_root.add_child(mesh_instance)
	mesh_instance.owner = scene_root
	var collision := StaticBody3D.new()
	collision.name = "StaticBody3D"
	scene_root.add_child(collision)
	collision.owner = scene_root
	var shape_node := CollisionShape3D.new()
	shape_node.name = "CollisionShape3D"
	var aabb := mesh_instance.mesh.get_aabb()
	var box := BoxShape3D.new()
	box.size = aabb.size
	shape_node.shape = box
	shape_node.position = aabb.position + aabb.size * 0.5
	collision.add_child(shape_node)
	shape_node.owner = scene_root
	var packed := PackedScene.new()
	var pack_err := packed.pack(scene_root)
	if pack_err != OK:
		push_error("Cannot pack prop %s: %s" % [source.name, error_string(pack_err)])
		scene_root.free()
		return
	var path := "%s/%s/%s.tscn" % [PROPS_DIR, category, _safe_file_name(source.name)]
	var save_err := ResourceSaver.save(packed, path)
	if save_err != OK:
		push_error("Cannot save prop %s: %s" % [path, error_string(save_err)])
	scene_root.free()

func _build_test_scene() -> void:
	var root := Node3D.new()
	root.name = "LowpolyInteriorGridmapTest"
	var env := WorldEnvironment.new()
	env.name = "WorldEnvironment"
	root.add_child(env)
	env.owner = root
	var sun := DirectionalLight3D.new()
	sun.name = "DirectionalLight3D"
	sun.rotation_degrees = Vector3(-55.0, -35.0, 0.0)
	sun.light_energy = 1.25
	root.add_child(sun)
	sun.owner = root
	var fill := OmniLight3D.new()
	fill.name = "SoftInteriorFillLight"
	fill.position = Vector3(12.0, 4.0, 8.0)
	fill.light_energy = 2.2
	fill.omni_range = 20.0
	root.add_child(fill)
	fill.owner = root
	var layers := Node3D.new()
	layers.name = "GridMapLayers"
	root.add_child(layers)
	layers.owner = root
	var floor_grid := _create_gridmap_layer(layers, "FloorGridMap")
	var wall_x_grid := _create_gridmap_layer(layers, "WallXGridMap")
	var wall_z_grid := _create_gridmap_layer(layers, "WallZGridMap")
	var ceiling_grid := _create_gridmap_layer(layers, "CeilingGridMap")
	ceiling_grid.position.y = GRID_CELL_SIZE.y
	_paint_compact_room_layout(floor_grid, wall_x_grid, wall_z_grid, ceiling_grid)
	var props := Node3D.new()
	props.name = "Props"
	root.add_child(props)
	props.owner = root
	_prop_instance_counts.clear()
	_place_props(props)
	var markers := Node3D.new()
	markers.name = "Markers"
	root.add_child(markers)
	markers.owner = root
	_add_marker(markers, "MirdoSpawn", Vector3(7.5, 0.0, 6.0))
	_add_marker(markers, "Entrance", Vector3(7.0, 0.0, 0.5))
	_add_marker(markers, "BedroomDoor", Vector3(6.0, 0.0, 2.0))
	_add_marker(markers, "ResourceRoomDoor", Vector3(10.0, 0.0, 2.0))
	var packed := PackedScene.new()
	var pack_err := packed.pack(root)
	if pack_err != OK:
		push_error("Cannot pack test scene: %s" % error_string(pack_err))
		root.free()
		return
	var save_err := ResourceSaver.save(packed, TEST_SCENE_PATH)
	if save_err != OK:
		push_error("Cannot save test scene %s: %s" % [TEST_SCENE_PATH, error_string(save_err)])
	else:
		print("Saved test scene: %s" % TEST_SCENE_PATH)
	root.free()

func _create_gridmap_layer(parent: Node3D, layer_name: String) -> GridMap:
	var grid := GridMap.new()
	grid.name = layer_name
	grid.cell_size = GRID_CELL_SIZE
	grid.cell_center_x = false
	grid.cell_center_y = false
	grid.cell_center_z = false
	grid.mesh_library = load(MESH_LIBRARY_PATH) as MeshLibrary
	parent.add_child(grid)
	grid.owner = parent.owner
	return grid



func _paint_compact_room_layout(floor_grid: GridMap, wall_x_grid: GridMap, wall_z_grid: GridMap, ceiling_grid: GridMap) -> void:
	var floor_id := _id("M_floor_0")
	var floor_alt_id := _id("M_floor_1")
	var ceiling_id := _id("M_ceiling")
	var wall_id := _id("M_wall_1")
	var wall_alt_id := _id("M_wall_2")
	var door_wall_id := _id("M_wall_doors_empty_1")
	if floor_id < 0 or ceiling_id < 0 or wall_id < 0 or door_wall_id < 0:
		return
	# Model-measured grid:
	# floor/ceiling = 2m x 2m, wall/door-wall = 2m wide x 3m high.
	# Compact complete map, 8 x 6 cells = 16m x 12m.
	for x in range(0, 8):
		for z in range(0, 6):
			floor_grid.set_cell_item(Vector3i(x, 0, z), floor_id)
			ceiling_grid.set_cell_item(Vector3i(x, 0, z), ceiling_id)
	# Outer shell: all solid wall modules. No door-wall modules on exterior, so no accidental open leaks.
	for x in range(0, 8):
		_set_wall_x(wall_x_grid, x, 0, wall_id)
		_set_wall_x(wall_x_grid, x, 6, wall_id)
	for z in range(0, 6):
		_set_wall_z(wall_z_grid, 0, z, wall_id)
		_set_wall_z(wall_z_grid, 8, z, wall_id)
	# Corridor separators x=3 and x=5. Only these four cells are door openings.
	for z in range(0, 6):
		_set_wall_z(wall_z_grid, 3, z, wall_alt_id if wall_alt_id >= 0 else wall_id)
		_set_wall_z(wall_z_grid, 5, z, wall_alt_id if wall_alt_id >= 0 else wall_id)
	_set_wall_z(wall_z_grid, 3, 1, door_wall_id) # bedroom -> corridor
	_set_wall_z(wall_z_grid, 3, 4, door_wall_id) # work room -> corridor
	_set_wall_z(wall_z_grid, 5, 1, door_wall_id) # resource room -> corridor
	_set_wall_z(wall_z_grid, 5, 4, door_wall_id) # rest room -> corridor
	# Split upper/lower rooms. Corridor cells x=3..4 are left open as hallway.
	for x in range(0, 3):
		_set_wall_x(wall_x_grid, x, 3, wall_id)
	for x in range(5, 8):
		_set_wall_x(wall_x_grid, x, 3, wall_id)



func _create_clean_terrain(parent: Node3D) -> void:
	var material := _get_toon_material()
	# Final terrain footprint: 30m x 18m. Split into four room floor/ceiling plates.
	_add_room_surface_pair(parent, "LivingRoom", Vector3(0.0, 0.0, 0.0), Vector2(10.0, 10.0), material)
	_add_room_surface_pair(parent, "CorridorRoom", Vector3(10.0, 0.0, 0.0), Vector2(8.0, 10.0), material)
	_add_room_surface_pair(parent, "Bedroom", Vector3(18.0, 0.0, 0.0), Vector2(12.0, 10.0), material)
	_add_room_surface_pair(parent, "StudyRoom", Vector3(0.0, 0.0, 10.0), Vector2(30.0, 8.0), material)
	# Outer shell. Doors/openings are made by splitting a wall into multiple wall segments.
	_add_wall_segment_x(parent, "Outer_North_A", 0.0, 0.0, 14.0, material)
	_add_wall_segment_x(parent, "Outer_North_Door", 14.0, 0.0, 2.0, material) # currently closed; replace with auto door later.
	_add_wall_segment_x(parent, "Outer_North_B", 16.0, 0.0, 14.0, material)
	_add_wall_segment_x(parent, "Outer_South", 0.0, 18.0, 30.0, material)
	_add_wall_segment_z(parent, "Outer_West", 0.0, 0.0, 18.0, material)
	_add_wall_segment_z(parent, "Outer_East", 30.0, 0.0, 18.0, material)
	# Interior vertical partitions x=10 and x=18. Leave 3m door openings at z=4..7.
	_add_wall_segment_z(parent, "Partition_X10_A", 10.0, 0.0, 4.0, material)
	_add_wall_segment_z(parent, "Partition_X10_B", 10.0, 7.0, 11.0, material)
	_add_wall_segment_z(parent, "Partition_X18_A", 18.0, 0.0, 4.0, material)
	_add_wall_segment_z(parent, "Partition_X18_B", 18.0, 7.0, 11.0, material)
	# Back/study partition z=10. Leave openings around x=5..7, 14..16, 23..25.
	_add_wall_segment_x(parent, "Partition_Z10_A", 0.0, 10.0, 5.0, material)
	_add_wall_segment_x(parent, "Partition_Z10_B", 7.0, 10.0, 7.0, material)
	_add_wall_segment_x(parent, "Partition_Z10_C", 16.0, 10.0, 7.0, material)
	_add_wall_segment_x(parent, "Partition_Z10_D", 25.0, 10.0, 5.0, material)

func _add_wall_segment_x(parent: Node3D, node_name: String, x: float, z: float, length: float, material: Material) -> void:
	_add_box_surface(parent, node_name, Vector3(x + length * 0.5, GRID_CELL_SIZE.y * 0.5, z), Vector3(length, GRID_CELL_SIZE.y, 0.20), material, true)

func _add_wall_segment_z(parent: Node3D, node_name: String, x: float, z: float, length: float, material: Material) -> void:
	_add_box_surface(parent, node_name, Vector3(x, GRID_CELL_SIZE.y * 0.5, z + length * 0.5), Vector3(0.20, GRID_CELL_SIZE.y, length), material, true)

func _add_room_surface_pair(parent: Node3D, room_name: String, origin: Vector3, size: Vector2, material: Material) -> void:
	_add_box_surface(parent, room_name + "_Floor", origin + Vector3(size.x * 0.5, -0.04, size.y * 0.5), Vector3(size.x, 0.08, size.y), material, true)
	_add_box_surface(parent, room_name + "_Ceiling", origin + Vector3(size.x * 0.5, GRID_CELL_SIZE.y + 0.04, size.y * 0.5), Vector3(size.x, 0.08, size.y), material, false)

func _add_box_surface(parent: Node3D, node_name: String, pos: Vector3, size: Vector3, material: Material, with_collision: bool = false) -> void:
	var mesh_instance := MeshInstance3D.new()
	mesh_instance.name = node_name
	var box := BoxMesh.new()
	box.size = size
	if material != null:
		box.material = material
	mesh_instance.mesh = box
	mesh_instance.position = pos
	parent.add_child(mesh_instance)
	mesh_instance.owner = parent.owner
	if with_collision:
		var body := StaticBody3D.new()
		body.name = node_name + "_StaticBody3D"
		parent.add_child(body)
		body.owner = parent.owner
		var shape_node := CollisionShape3D.new()
		shape_node.name = node_name + "_CollisionShape3D"
		var shape := BoxShape3D.new()
		shape.size = size
		shape_node.shape = shape
		shape_node.position = pos
		body.add_child(shape_node)
		shape_node.owner = parent.owner


func _set_wall_x(grid: GridMap, x: int, z: int, item_id: int) -> void:
	grid.set_cell_item(Vector3i(x, 0, z), item_id, 0)

func _set_wall_z(grid: GridMap, x: int, z: int, item_id: int) -> void:
	# Orthogonal index 22 is +90 degrees around Y for this wall mesh.
	grid.set_cell_item(Vector3i(x, 0, z), item_id, 22)

func _place_props(parent: Node3D) -> void:
	# Bedroom: left upper room.
	_instance_prop(parent, "res://levels/interiors/lowpoly_interiors/props/bedroom/m_bed.tscn", Vector3(2.0, 0.0, 2.0), Vector3(0, 90, 0))
	_instance_prop(parent, "res://levels/interiors/lowpoly_interiors/props/bedroom/m_shelf_small.tscn", Vector3(4.2, 0.0, 4.4), Vector3.ZERO)
	_instance_prop(parent, "res://levels/interiors/lowpoly_interiors/props/lighting/m_lamp_small.tscn", Vector3(1.2, 0.0, 4.4), Vector3.ZERO)
	# Resource room: right upper room.
	_instance_prop(parent, "res://levels/interiors/lowpoly_interiors/props/bedroom/m_bookshelf.tscn", Vector3(12.0, 0.0, 1.1), Vector3(0, 180, 0))
	_instance_prop(parent, "res://levels/interiors/lowpoly_interiors/props/bedroom/m_wardrobe.tscn", Vector3(14.2, 0.0, 4.4), Vector3(0, 180, 0))
	_instance_prop(parent, "res://levels/interiors/lowpoly_interiors/props/books/m_book_closed_1.tscn", Vector3(11.2, 1.0, 3.0), Vector3.ZERO)
	# Work/study room: left lower room.
	_instance_prop(parent, "res://levels/interiors/lowpoly_interiors/props/school/m_school_table.tscn", Vector3(2.0, 0.0, 8.4), Vector3.ZERO)
	_instance_prop(parent, "res://levels/interiors/lowpoly_interiors/props/school/m_school_chair.tscn", Vector3(2.0, 0.0, 7.2), Vector3.ZERO)
	_instance_prop(parent, "res://levels/interiors/lowpoly_interiors/props/school/m_black_board.tscn", Vector3(1.2, 1.0, 11.85), Vector3.ZERO)
	# Rest/common room: right lower room.
	_instance_prop(parent, "res://levels/interiors/lowpoly_interiors/props/bedroom/m_retro_tv.tscn", Vector3(12.0, 0.0, 11.0), Vector3.ZERO)
	_instance_prop(parent, "res://levels/interiors/lowpoly_interiors/props/bedroom/m_room_desk.tscn", Vector3(14.0, 0.0, 8.5), Vector3(0, 180, 0))
	# Corridor lighting and wall detail.
	_instance_prop(parent, "res://levels/interiors/lowpoly_interiors/props/lighting/m_ceiling_lamp.tscn", Vector3(8.0, 2.9, 6.0), Vector3.ZERO)
	_instance_prop(parent, "res://levels/interiors/lowpoly_interiors/props/decor/m_scienctific_poster_1.tscn", Vector3(6.1, 1.4, 9.0), Vector3(0, 90, 0))
	# Window props are separate from wall GridMap cells so they do not steal wall positions.
	_instance_prop(parent, "res://levels/interiors/lowpoly_interiors/props/windows/m_window_1.tscn", Vector3(2.0, 0.0, -0.21), Vector3.ZERO)
	_instance_prop(parent, "res://levels/interiors/lowpoly_interiors/props/windows/m_window_1.tscn", Vector3(12.0, 0.0, -0.21), Vector3.ZERO)
	_instance_prop(parent, "res://levels/interiors/lowpoly_interiors/props/windows/m_window_1.tscn", Vector3(16.21, 0.0, 8.0), Vector3(0, 90, 0))


func _instance_source_mesh_prop(parent: Node3D, source_name: String, node_name: String, pos: Vector3, rot_degrees: Vector3) -> void:
	var source_scene := load(SOURCE_SCENE) as PackedScene
	if source_scene == null:
		return
	var source_root := source_scene.instantiate()
	var source := source_root.find_child(source_name, true, false) as MeshInstance3D
	if source == null or source.mesh == null:
		source_root.free()
		return
	var mesh_instance := MeshInstance3D.new()
	mesh_instance.name = node_name
	mesh_instance.mesh = source.mesh.duplicate(true)
	_apply_toon_material_to_mesh(mesh_instance.mesh)
	mesh_instance.position = pos
	mesh_instance.rotation_degrees = rot_degrees
	parent.add_child(mesh_instance)
	mesh_instance.owner = parent.owner
	source_root.free()

func _instance_prop(parent: Node3D, path: String, pos: Vector3, rot_degrees: Vector3) -> void:
	var packed := load(path) as PackedScene
	if packed == null:
		push_warning("Missing prop scene: %s" % path)
		return
	var inst := packed.instantiate() as Node3D
	if inst == null:
		return
	var base_name := _display_name(inst.name)
	inst.name = _unique_prop_name(base_name)
	inst.position = pos
	inst.rotation_degrees = rot_degrees
	parent.add_child(inst)
	# Only the nested instance root belongs to this scene. Do not recursively set owner on
	# Mesh/StaticBody/CollisionShape children from the prop scene, or Godot will report
	# same-name nested-instance collisions when several props share child names.
	inst.owner = parent.owner

func _unique_prop_name(base_name: String) -> String:
	var clean := base_name.strip_edges()
	if clean.is_empty():
		clean = "Prop"
	var count := int(_prop_instance_counts.get(clean, 0)) + 1
	_prop_instance_counts[clean] = count
	return "%s_%02d" % [clean, count]

func _add_marker(parent: Node3D, marker_name: String, pos: Vector3) -> void:
	var marker := Marker3D.new()
	marker.name = marker_name
	marker.position = pos
	parent.add_child(marker)
	marker.owner = parent.owner


func _build_world_test_scene() -> void:
	var root := Node3D.new()
	root.name = "LowpolyInteriorsWorldTest"
	var env := WorldEnvironment.new()
	env.name = "WorldEnvironment"
	root.add_child(env)
	env.owner = root
	var sun := DirectionalLight3D.new()
	sun.name = "SunLight"
	sun.rotation_degrees = Vector3(-50.0, -35.0, 0.0)
	sun.light_energy = 1.2
	root.add_child(sun)
	sun.owner = root
	var map_scene := load(TEST_SCENE_PATH) as PackedScene
	if map_scene != null:
		var map := map_scene.instantiate() as Node3D
		map.name = "LowpolyInteriorMap"
		root.add_child(map)
		map.owner = root
	var camera := Camera3D.new()
	camera.name = "PreviewCamera"
	camera.position = Vector3(15.0, 12.0, 22.0)
	camera.rotation_degrees = Vector3(-35.0, 35.0, 0.0)
	camera.current = true
	root.add_child(camera)
	camera.owner = root
	var packed := PackedScene.new()
	var pack_err := packed.pack(root)
	if pack_err != OK:
		push_error("Cannot pack world test scene: %s" % error_string(pack_err))
		root.free()
		return
	var save_err := ResourceSaver.save(packed, WORLD_TEST_SCENE_PATH)
	if save_err != OK:
		push_error("Cannot save world test scene %s: %s" % [WORLD_TEST_SCENE_PATH, error_string(save_err)])
	else:
		print("Saved world test scene: %s" % WORLD_TEST_SCENE_PATH)
	root.free()

func _id(mesh_name: String) -> int:
	return int(_building_id_by_name.get(mesh_name, -1))

func _display_name(raw_name: String) -> String:
	return raw_name.trim_prefix("M_")

func _safe_file_name(raw_name: String) -> String:
	return raw_name.to_snake_case().to_lower()

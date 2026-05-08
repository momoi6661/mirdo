@tool
extends SceneTree

const AUTO_GENERATOR_CLASS := "AutoModelCollisionGenerator3D"

var _failures: Array[String] = []


func _init() -> void:
	var scene_paths := _get_scene_paths()
	if scene_paths.is_empty():
		scene_paths = [
			"res://levels/props/medical_cabinet_container.tscn",
			"res://levels/props/weapon_equipment_cabinet_container.tscn",
			"res://levels/props/rack_storage_container_001.tscn",
		]

	for scene_path in scene_paths:
		_bake_scene(scene_path)

	if _failures.is_empty():
		print("[PASS] baked model collisions for ", scene_paths.size(), " scene(s)")
		quit(0)
	else:
		for failure in _failures:
			push_error(failure)
		quit(1)


func _get_scene_paths() -> Array[String]:
	var args := OS.get_cmdline_user_args()
	var paths: Array[String] = []
	for arg in args:
		var text := String(arg).strip_edges()
		if text.ends_with(".tscn"):
			paths.append(text)
	return paths


func _bake_scene(scene_path: String) -> void:
	var packed := load(scene_path) as PackedScene
	if packed == null:
		_failures.append("LOAD_FAILED: " + scene_path)
		return

	var root := packed.instantiate()
	if root == null:
		_failures.append("INSTANTIATE_FAILED: " + scene_path)
		return
	root.owner = root

	var generators: Array[Node] = []
	_collect_generators(root, generators)
	if generators.is_empty():
		_failures.append("NO_GENERATOR_FOUND: " + scene_path)
		root.queue_free()
		return

	var generated_total := 0
	for generator in generators:
		if not generator.has_method("regenerate_collision"):
			continue
		var generated := int(generator.call("regenerate_collision"))
		generated_total += generated
		var parent := generator.get_parent()
		if parent != null:
			parent.remove_child(generator)
		generator.free()

	if generated_total <= 0:
		_failures.append("NO_COLLISION_GENERATED: " + scene_path)
		root.queue_free()
		return

	_assign_owner_recursive(root, root)
	var saved := PackedScene.new()
	var pack_result := saved.pack(root)
	if pack_result != OK:
		_failures.append("PACK_FAILED: %s code=%d" % [scene_path, pack_result])
		root.queue_free()
		return

	var save_result := ResourceSaver.save(saved, scene_path)
	if save_result != OK:
		_failures.append("SAVE_FAILED: %s code=%d" % [scene_path, save_result])
		root.queue_free()
		return

	print("[BakeCollision] ", scene_path, " shapes=", generated_total)
	root.queue_free()


func _collect_generators(node: Node, out_generators: Array[Node]) -> void:
	if node.get_class() == AUTO_GENERATOR_CLASS or node.has_method("regenerate_collision"):
		if node.get_script() != null and String(node.get_script().resource_path).ends_with("auto_model_collision_generator_3d.gd"):
			out_generators.append(node)
	for child in node.get_children():
		_collect_generators(child, out_generators)


func _assign_owner_recursive(node: Node, owner_node: Node) -> void:
	if node != owner_node:
		node.owner = owner_node
	for child in node.get_children():
		_assign_owner_recursive(child, owner_node)

extends SceneTree

const MIRDO_SCENE := preload("res://characters/mirdo/mirdo_character.tscn")
const ITEM_SCENES := [
	"res://resources/items/models/physical/medkit_item.tscn",
	"res://resources/items/models/physical/painkiller_item.tscn",
]

var _failures: Array[String] = []

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	var mirdo := MIRDO_SCENE.instantiate() as Node3D
	root.add_child(mirdo)
	await process_frame
	await process_frame
	for path in ITEM_SCENES:
		var item := load(path).instantiate() as Node3D
		root.add_child(item)
		await process_frame
		var pickable := item.get_node_or_null("CharacterPickableItem")
		_expect(pickable != null and pickable.attach_visual_to(mirdo), "%s should attach to Mirdo's hand" % path.get_file())
		await process_frame
		var held := mirdo.find_child("HeldItemVisual", true, false) as Node3D
		var size := _max_mesh_dimension(held)
		_expect(size >= 0.25 and size <= 0.32, "%s held size %.3fm should match the other consumables" % [path.get_file(), size])
		if held != null:
			held.queue_free()
		item.queue_free()
		await process_frame
	mirdo.queue_free()
	await process_frame
	_finish()

func _max_mesh_dimension(root_node: Node3D) -> float:
	var bounds := AABB()
	var found := false
	for mesh in _find_meshes(root_node):
		var aabb := mesh.get_aabb()
		for x in [aabb.position.x, aabb.end.x]:
			for y in [aabb.position.y, aabb.end.y]:
				for z in [aabb.position.z, aabb.end.z]:
					var point := mesh.global_transform * Vector3(x, y, z)
					bounds = bounds.expand(point) if found else AABB(point, Vector3.ZERO)
					found = true
	return maxf(bounds.size.x, maxf(bounds.size.y, bounds.size.z))

func _find_meshes(node: Node) -> Array[MeshInstance3D]:
	var meshes: Array[MeshInstance3D] = []
	if node is MeshInstance3D:
		meshes.append(node as MeshInstance3D)
	for child in node.get_children():
		meshes.append_array(_find_meshes(child))
	return meshes

func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)

func _finish() -> void:
	if _failures.is_empty():
		print("[PASS] Mirdo held item scale")
		quit(0)
		return
	for failure in _failures:
		push_error(failure)
	quit(1)

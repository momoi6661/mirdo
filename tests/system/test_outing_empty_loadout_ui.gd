extends SceneTree

var _failures: Array[String] = []

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	var scene := load("res://levels/outing/OutingMap.tscn") as PackedScene
	_expect(scene != null, "OutingMap scene should load")
	if scene == null:
		_finish()
		return
	var map := scene.instantiate()
	root.add_child(map)
	await process_frame
	await process_frame
	var first_non_bunker := _select_first_non_bunker_location(map)
	_expect(not first_non_bunker.is_empty(), "OutingMap should have a selectable non-bunker location")
	if not first_non_bunker.is_empty():
		map.set("_selected_location_id", first_non_bunker)
		map.call("_open_prepare_panel")
		await process_frame
		var confirm := map.get_node_or_null("%PrepareConfirmButton") as Button
		var capacity := map.get_node_or_null("%CapacityLabel") as Label
		_expect(confirm != null, "PrepareConfirmButton should exist")
		if confirm != null:
			_expect(not confirm.disabled, "Expedition confirm should allow empty loadout")
			_expect(confirm.text == "轻装探索", "Empty loadout confirm text should be light exploration")
		if capacity != null:
			_expect(capacity.text.contains("轻装探索"), "Capacity label should show light exploration mode")
	map.queue_free()
	_finish()

func _select_first_non_bunker_location(map: Node) -> String:
	var count := int(map.call("get_location_count"))
	for rule in map.get("_rules"):
		var id := String(rule.get("location_id"))
		if id != "bunker" and bool(map.call("_is_location_unlocked", id)):
			return id
	return ""

func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)

func _finish() -> void:
	if _failures.is_empty():
		print("[PASS] outing empty loadout ui")
		quit(0)
	else:
		for failure in _failures:
			push_error(failure)
		quit(1)

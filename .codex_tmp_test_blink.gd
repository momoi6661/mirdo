extends SceneTree
func _init():
	var scene = load("res://characters/mirdo/mirdo_character.tscn")
	var root = scene.instantiate()
	get_root().add_child(root)
	await process_frame
	var face = root.get_node("Components/FaceComponent")
	var tree = root.get_node("FaceAnimationTree")
	face.call("set_expression", &"fun")
	face.call("_process", 20.0)
	print("fun blink=", tree.get("parameters/BlinkBlend/add_amount"))
	face.call("set_expression", &"neutral")
	face.set("blink_interval_min", 0.01)
	face.set("blink_interval_max", 0.01)
	face.call("_schedule_next_blink")
	face.call("_process", 0.02)
	print("neutral blink=", tree.get("parameters/BlinkBlend/add_amount"))
	root.queue_free()
	quit(0)

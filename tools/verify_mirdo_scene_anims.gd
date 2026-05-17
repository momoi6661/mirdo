extends SceneTree

func _initialize() -> void:
	var scene := ResourceLoader.load("res://characters/mirdo/mirdo_character.tscn") as PackedScene
	if scene == null:
		push_error("failed to load scene")
		quit(1)
		return
	var root := scene.instantiate()
	var ap := root.get_node_or_null("AnimationPlayer") as AnimationPlayer
	if ap == null:
		push_error("missing AnimationPlayer")
		quit(1)
		return
	for name in [&"stand_to_walk", &"walk_forward_loop", &"walk_to_stop", &"walk"]:
		var a := ap.get_animation(name)
		print(name, " exists=", a != null, " length=", a.length if a != null else -1, " loop=", a.loop_mode if a != null else -1)
	root.free()
	quit(0)

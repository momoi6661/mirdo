extends SceneTree

const SCENE_PATH := "res://characters/mirdo/mirdo_character.tscn"

func _init():
	var scene: PackedScene = ResourceLoader.load(SCENE_PATH)
	if scene == null:
		print("LOAD_FAILED scene")
		quit(1); return
	var root := scene.instantiate()
	var players := []
	_find_players(root, players)
	print("scene=", SCENE_PATH, " players=", players.size())
	for p in players:
		var ap: AnimationPlayer = p
		print("\nAnimationPlayer ", ap.get_path())
		var list := ap.get_animation_list()
		list.sort()
		for name in list:
			var a: Animation = ap.get_animation(name)
			if a == null: continue
			var is_loop := a.loop_mode != Animation.LOOP_NONE or String(name).to_lower().contains("loop") or String(name).to_lower().contains("idle")
			if is_loop:
				print("anim=", name, " length=", a.length, " loop=", a.loop_mode, " tracks=", a.get_track_count(), " resource=", a.resource_path)
	root.free()
	quit()

func _find_players(n: Node, out: Array) -> void:
	if n is AnimationPlayer:
		out.append(n)
	for c in n.get_children():
		_find_players(c, out)

extends SceneTree

var _failures: Array[String] = []

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	await _test_face_fun_alias_disables_blink()
	await _test_face_fun_animation_uses_full_weight()
	_finish()

func _test_face_fun_alias_disables_blink() -> void:
	var script := load("res://features/character_face/blend_shape_face_component.gd") as Script
	_expect(script != null, "BlendShapeFaceComponent script should load")
	if script == null:
		return
	var face := Node.new()
	face.set_script(script)
	root.add_child(face)
	await process_frame
	var normalized: StringName = face.call("_normalize_expression_name", &"face_fun")
	_expect(normalized == &"fun", "face_fun should normalize to fun so auto blink is disabled")
	face.set("_current_expression", &"face_fun")
	var disabled: bool = bool(face.call("_should_disable_blink_now"))
	_expect(disabled, "current face_fun expression should disable blink")
	face.queue_free()
	await process_frame

func _test_face_fun_animation_uses_full_weight() -> void:
	var animation := load("res://features/character_face/animations/face_fun.tres") as Animation
	_expect(animation != null, "face_fun animation should load")
	if animation == null:
		return
	var fun_track := -1
	for track_index in range(animation.get_track_count()):
		if String(animation.track_get_path(track_index)).ends_with(":Fun"):
			fun_track = track_index
			break
	_expect(fun_track >= 0, "face_fun animation should contain Fun blendshape track")
	if fun_track < 0:
		return
	for key_index in range(animation.track_get_key_count(fun_track)):
		var value := float(animation.track_get_key_value(fun_track, key_index))
		_expect(is_equal_approx(value, 1.0), "face_fun Fun blendshape key should be 1.0, got %.3f" % value)

func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)

func _finish() -> void:
	if _failures.is_empty():
		print("[PASS] character face fun blink")
		quit(0)
	else:
		for failure in _failures:
			push_error(failure)
		quit(1)

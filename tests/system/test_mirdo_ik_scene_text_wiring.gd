extends SceneTree
var _failures: Array[String] = []
func _init() -> void:
	call_deferred("_run")
func _run() -> void:
	var script := load("res://scripts/mirdo/mirdo_ik_controller.gd")
	_expect(script != null, "controller script loads")
	var file := FileAccess.open("res://characters/mirdo/mirdo_character.tscn", FileAccess.READ)
	_expect(file != null, "mirdo scene text opens")
	var text := file.get_as_text() if file != null else ""
	for needle in [
		"[node name=\"MirdoIK\" type=\"Node3D\" parent=\"VisualRoot/Model/Armature\"]",
		"[node name=\"AuthorTargets\" type=\"Node3D\" parent=\"VisualRoot/Model/Armature/MirdoIK\"]",
		"[node name=\"RightHandBase\" type=\"Node3D\" parent=\"VisualRoot/Model/Armature/MirdoIK/AuthorTargets\"]",
		"[node name=\"RightHand\" type=\"Marker3D\" parent=\"VisualRoot/Model/Armature/MirdoIK/AuthorTargets/RightHandBase\"]",
		"[node name=\"RuntimeTargets\" type=\"Node3D\" parent=\"VisualRoot/Model/Armature/MirdoIK\"]",
		"[node name=\"FinalTargets\" type=\"Node3D\" parent=\"VisualRoot/Model/Armature/MirdoIK\"]",
		"[node name=\"MirdoIKController\" type=\"Node\" parent=\"VisualRoot/Model/Armature/MirdoIK\"]",
		"script = ExtResource(\"84_mirdo_ik_controller\")",
		"skeleton_path = NodePath(\"../../GeneralSkeleton\")",
		"settings/0/target_node = NodePath(\"../../MirdoIK/FinalTargets/LeftHand\")",
		"settings/0/target_node = NodePath(\"../../MirdoIK/FinalTargets/RightHand\")",
		"settings/0/target_node = NodePath(\"../../MirdoIK/FinalTargets/LeftFoot\")",
		"settings/0/target_node = NodePath(\"../../MirdoIK/FinalTargets/RightFoot\")",
	]:
		_expect(text.contains(needle), "scene should contain " + needle)
	for modifier in ["LeftArmIK", "RightArmIK", "LeftLegIK", "RightLegIK"]:
		var marker: String = "[node name=\"" + String(modifier) + "\" type=\"TwoBoneIK3D\""
		var idx := text.find(marker)
		_expect(idx >= 0, String(modifier) + " node exists")
		if idx >= 0:
			var chunk := text.substr(idx, 500)
			_expect(chunk.contains("influence = 0.0"), String(modifier) + " influence defaults to zero")
	var runtime_idx := text.find("[node name=\"RuntimeTargets\" type=\"Node3D\" parent=\"VisualRoot/Model/Armature/MirdoIK\"]")
	_expect(runtime_idx >= 0, "RuntimeTargets node exists")
	if runtime_idx >= 0:
		var runtime_chunk := text.substr(runtime_idx, 160)
		_expect(runtime_chunk.contains("visible = false"), "RuntimeTargets hidden in editor")
	_finish()
func _expect(ok: bool, msg: String) -> void:
	if not ok:
		_failures.append(msg)
func _finish() -> void:
	if _failures.is_empty():
		print("[PASS] mirdo ik scene text wiring")
		quit(0)
	else:
		for f in _failures:
			push_error(f)
		quit(1)

extends SceneTree

const EXTEND_TIME := 1.0 / 30.0
const BODY_LOOP_PATHS := [
	"res://resources/animate/Kimodo/kimodo_idle_alert_loop.res",
	"res://resources/animate/Kimodo/kimodo_idle_fidget.res",
	"res://resources/animate/Kimodo/idle_normal_loop.res",
	"res://resources/animate/Kimodo/Kimodo_idle_relaxed_loop.res",
	"res://resources/animate/Kimodo/kimodo_idle_sleepy.res",
	"res://resources/animate/Kimodo/kimodo_listen.res",
	"res://resources/animate/Kimodo/kimodo_look_around.res",
	"res://resources/animate/Kimodo/run_forward_loop_short.res",
	"res://resources/animate/Kimodo/walk_forward_loop_v2.res",
]

func track_name(anim: Animation, i: int) -> String:
	var p := str(anim.track_get_path(i))
	var idx := p.rfind(":")
	return p.substr(idx + 1) if idx >= 0 else p

func get_root_z_delta(anim: Animation) -> float:
	for i in range(anim.get_track_count()):
		if anim.track_get_type(i) == Animation.TYPE_POSITION_3D and track_name(anim, i) == "Root":
			var kc := anim.track_get_key_count(i)
			if kc >= 2:
				var first: Vector3 = anim.track_get_key_value(i, 0)
				var last: Vector3 = anim.track_get_key_value(i, kc - 1)
				return last.z - first.z
	return 0.0

func extend_loop(path: String) -> void:
	var anim: Animation = ResourceLoader.load(path, "Animation", ResourceLoader.CACHE_MODE_IGNORE)
	if anim == null:
		print("LOAD_FAILED ", path)
		return

	var old_len: float = anim.length
	var key_last := 0.0
	for i in range(anim.get_track_count()):
		var kc := anim.track_get_key_count(i)
		if kc > 0:
			key_last = max(key_last, anim.track_get_key_time(i, kc - 1))

	var root_delta_z := get_root_z_delta(anim)
	var has_root_motion: bool = abs(root_delta_z) > 0.1
	var base_len: float = max(old_len, key_last)
	var new_len: float = base_len + EXTEND_TIME
	anim.length = new_len
	anim.loop_mode = Animation.LOOP_LINEAR

	for i in range(anim.get_track_count()):
		var typ := anim.track_get_type(i)
		var name := track_name(anim, i)
		# For root-motion clips, do not force Root to interpolate backward during the extra wrap window.
		if has_root_motion and typ == Animation.TYPE_POSITION_3D and name == "Root":
			anim.track_set_interpolation_loop_wrap(i, false)
		else:
			anim.track_set_interpolation_loop_wrap(i, true)

	var err := ResourceSaver.save(anim, path)
	print("SAVE err=", err, " path=", path, " old_len=", old_len, " key_last=", key_last, " new_len=", new_len, " rootZ=", root_delta_z, " root_motion=", has_root_motion)

func _init():
	for path in BODY_LOOP_PATHS:
		extend_loop(path)
	quit()


extends SceneTree

const PATH := "res://resources/animate/Kimodo/check_lower.res"
const BASE_LEN := 5.0
const FINAL_LEN := 5.03333333333333
const BODY_STEP := 0.10
const ARM_STEP := 0.45
const EPS := 0.00001
const ARM_NAMES := ["LeftUpperArm", "LeftLowerArm", "LeftHand", "RightUpperArm", "RightLowerArm", "RightHand"]

func track_name(anim: Animation, i: int) -> String:
	var p := str(anim.track_get_path(i))
	var idx := p.rfind(":")
	return p.substr(idx + 1) if idx >= 0 else p

func is_arm(name: String) -> bool:
	return ARM_NAMES.has(name)

func sample_value(anim: Animation, track: int, t: float):
	var typ := anim.track_get_type(track)
	if typ == Animation.TYPE_POSITION_3D:
		return anim.position_track_interpolate(track, t)
	if typ == Animation.TYPE_ROTATION_3D:
		return anim.rotation_track_interpolate(track, t)
	if typ == Animation.TYPE_SCALE_3D:
		return anim.scale_track_interpolate(track, t)
	var best := 0
	for k in range(anim.track_get_key_count(track)):
		if anim.track_get_key_time(track, k) <= t:
			best = k
		else:
			break
	return anim.track_get_key_value(track, best)

func _init():
	var src: Animation = ResourceLoader.load(PATH, "Animation", ResourceLoader.CACHE_MODE_IGNORE)
	if src == null:
		print("LOAD_FAILED ", PATH)
		quit(1); return

	var out := Animation.new()
	out.length = FINAL_LEN
	out.loop_mode = Animation.LOOP_LINEAR
	out.step = src.step
	var old_keys := 0
	var new_keys := 0

	for i in range(src.get_track_count()):
		var typ := src.track_get_type(i)
		var name := track_name(src, i)
		var dst := out.add_track(typ)
		out.track_set_path(dst, src.track_get_path(i))
		out.track_set_interpolation_type(dst, Animation.INTERPOLATION_CUBIC if (typ == Animation.TYPE_ROTATION_3D or typ == Animation.TYPE_POSITION_3D or typ == Animation.TYPE_SCALE_3D) else src.track_get_interpolation_type(i))
		out.track_set_interpolation_loop_wrap(dst, true)
		out.track_set_enabled(dst, src.track_is_enabled(i))
		old_keys += src.track_get_key_count(i)

		var freeze_root := typ == Animation.TYPE_POSITION_3D and name == "Root"
		if typ == Animation.TYPE_ROTATION_3D or typ == Animation.TYPE_POSITION_3D or typ == Animation.TYPE_SCALE_3D:
			var step := ARM_STEP if (typ == Animation.TYPE_ROTATION_3D and is_arm(name)) else BODY_STEP
			var t := 0.0
			while t <= BASE_LEN + EPS:
				var val = sample_value(src, i, min(t, src.length))
				if freeze_root:
					val = Vector3.ZERO
				out.track_insert_key(dst, t, val)
				t += step
		else:
			for k in range(src.track_get_key_count(i)):
				var kt := src.track_get_key_time(i, k)
				if kt <= BASE_LEN + EPS:
					out.track_insert_key(dst, kt, src.track_get_key_value(i, k), src.track_get_key_transition(i, k))
		new_keys += out.track_get_key_count(dst)

	var err := ResourceSaver.save(out, PATH)
	print("SAVE err=", err, " path=", PATH)
	print("length=", out.length, " old_keys=", old_keys, " new_keys=", new_keys, " body_step=", BODY_STEP, " arm_step=", ARM_STEP)
	quit(err)

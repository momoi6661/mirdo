extends SceneTree

const SRC_PATH := "res://resources/animate/Kimodo/check_lower.res"
const OUT_PATH := "res://resources/animate/Kimodo/check_lower.res"
const CUT_START := 2.4
const CUT_END := 7.4
const EXTEND_TIME := 1.0 / 30.0
const ARM_SAMPLE_STEP := 0.35
const NORMAL_SAMPLE_STEP := 1.0 / 30.0
const EPS := 0.00001

const ARM_NAMES := ["LeftUpperArm", "LeftLowerArm", "LeftHand", "RightUpperArm", "RightLowerArm", "RightHand"]
const OPEN_LEFT_DEG := -7.5
const OPEN_RIGHT_DEG := 7.5

func track_name(anim: Animation, i: int) -> String:
	var p := str(anim.track_get_path(i))
	var idx := p.rfind(":")
	return p.substr(idx + 1) if idx >= 0 else p

func sample_value(anim: Animation, track: int, t: float):
	var typ := anim.track_get_type(track)
	if typ == Animation.TYPE_POSITION_3D:
		return anim.position_track_interpolate(track, t)
	if typ == Animation.TYPE_ROTATION_3D:
		return anim.rotation_track_interpolate(track, t)
	if typ == Animation.TYPE_SCALE_3D:
		return anim.scale_track_interpolate(track, t)
	# fallback nearest previous key
	var best := 0
	for k in range(anim.track_get_key_count(track)):
		if anim.track_get_key_time(track, k) <= t:
			best = k
		else:
			break
	return anim.track_get_key_value(track, best)

func arm_open_correction(name: String) -> Quaternion:
	# Small local roll correction; only on upper arms so lower arms/hands follow naturally.
	if name == "LeftUpperArm":
		return Quaternion(Vector3(0, 0, 1), deg_to_rad(OPEN_LEFT_DEG))
	if name == "RightUpperArm":
		return Quaternion(Vector3(0, 0, 1), deg_to_rad(OPEN_RIGHT_DEG))
	return Quaternion.IDENTITY

func corrected_value(typ: int, name: String, val):
	if typ == Animation.TYPE_ROTATION_3D:
		var q: Quaternion = val
		var c := arm_open_correction(name)
		if c != Quaternion.IDENTITY:
			return (q * c).normalized()
	return val

func is_arm(name: String) -> bool:
	return ARM_NAMES.has(name)

func insert_key(anim: Animation, track: int, time: float, value) -> void:
	anim.track_insert_key(track, time, value)

func _init():
	var src: Animation = ResourceLoader.load(SRC_PATH, "Animation", ResourceLoader.CACHE_MODE_IGNORE)
	if src == null:
		print("LOAD_FAILED ", SRC_PATH)
		quit(1); return

	var base_len: float = CUT_END - CUT_START
	var out := Animation.new()
	out.length = base_len + EXTEND_TIME
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
		var step := ARM_SAMPLE_STEP if (typ == Animation.TYPE_ROTATION_3D and is_arm(name)) else NORMAL_SAMPLE_STEP

		if typ == Animation.TYPE_ROTATION_3D or typ == Animation.TYPE_POSITION_3D or typ == Animation.TYPE_SCALE_3D:
			var t := 0.0
			while t <= base_len + EPS:
				var src_t: float = min(CUT_START + t, CUT_END)
				var val = sample_value(src, i, src_t)
				if freeze_root:
					val = Vector3.ZERO
				else:
					val = corrected_value(typ, name, val)
				insert_key(out, dst, t, val)
				t += step
			# Do not insert duplicate key at extended end; length extension gives natural wrap slack.
		else:
			for k in range(src.track_get_key_count(i)):
				var kt := src.track_get_key_time(i, k)
				if kt < CUT_START - EPS or kt > CUT_END + EPS:
					continue
				insert_key(out, dst, kt - CUT_START, src.track_get_key_value(i, k))
		new_keys += out.track_get_key_count(dst)

	var err := ResourceSaver.save(out, OUT_PATH)
	print("SAVE err=", err, " path=", OUT_PATH)
	print("cut=", CUT_START, "..", CUT_END, " base_len=", base_len, " final_len=", out.length)
	print("arm_sample_step=", ARM_SAMPLE_STEP, " old_keys=", old_keys, " new_keys=", new_keys, " upper_arm_open_deg=", OPEN_LEFT_DEG, "/", OPEN_RIGHT_DEG)
	quit(err)

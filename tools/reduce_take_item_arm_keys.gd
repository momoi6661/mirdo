extends SceneTree

const PATH := "res://resources/animate/Kimodo/take_item.res"
const ARM_STEP := 0.18
const HAND_STEP := 0.22
const EPS := 0.00001
const ARM_NAMES := ["LeftUpperArm", "LeftLowerArm", "RightUpperArm", "RightLowerArm"]
const HAND_NAMES := ["LeftHand", "RightHand", "LeftHandThumbEnd", "RightHandThumbEnd", "LeftHandMiddleEnd", "RightHandMiddleEnd"]

func track_name(anim: Animation, i: int) -> String:
	var p := str(anim.track_get_path(i))
	var idx := p.rfind(":")
	return p.substr(idx + 1) if idx >= 0 else p

func is_target(name: String) -> bool:
	if ARM_NAMES.has(name) or HAND_NAMES.has(name):
		return true
	# Also catch finger end tracks with many keys.
	return name.contains("Hand") and (name.contains("End") or name.contains("Thumb") or name.contains("Index") or name.contains("Middle") or name.contains("Ring") or name.contains("Pinky"))

func step_for(name: String) -> float:
	return HAND_STEP if HAND_NAMES.has(name) or name.contains("Hand") else ARM_STEP

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
	out.length = src.length
	out.loop_mode = src.loop_mode
	out.step = src.step
	var old_keys := 0
	var new_keys := 0
	var changed_tracks := 0

	for i in range(src.get_track_count()):
		var typ := src.track_get_type(i)
		var name := track_name(src, i)
		var dst := out.add_track(typ)
		out.track_set_path(dst, src.track_get_path(i))
		out.track_set_interpolation_type(dst, src.track_get_interpolation_type(i))
		out.track_set_interpolation_loop_wrap(dst, src.track_get_interpolation_loop_wrap(i))
		out.track_set_enabled(dst, src.track_is_enabled(i))
		old_keys += src.track_get_key_count(i)

		if typ == Animation.TYPE_ROTATION_3D and is_target(name) and src.track_get_key_count(i) > 6:
			changed_tracks += 1
			var st := step_for(name)
			var t := 0.0
			while t < src.length - EPS:
				out.track_insert_key(dst, t, sample_value(src, i, t))
				t += st
			out.track_insert_key(dst, src.length, sample_value(src, i, src.length))
			out.track_set_interpolation_type(dst, Animation.INTERPOLATION_CUBIC)
		else:
			for k in range(src.track_get_key_count(i)):
				out.track_insert_key(dst, src.track_get_key_time(i, k), src.track_get_key_value(i, k), src.track_get_key_transition(i, k))
		new_keys += out.track_get_key_count(dst)

	var err := ResourceSaver.save(out, PATH)
	print("SAVE err=", err, " path=", PATH, " length=", out.length)
	print("changed_tracks=", changed_tracks, " old_keys=", old_keys, " new_keys=", new_keys, " arm_step=", ARM_STEP, " hand_step=", HAND_STEP)
	quit(err)

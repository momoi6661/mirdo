extends SceneTree

const PATH := "res://resources/animate/Kimodo/walk_forward_loop_v2.res"
const OUT_PATH := "res://resources/animate/Kimodo/walk_forward_loop_v2.res"
const BLEND_TIME := 0.30
const EPS := 0.00001

func track_name(anim: Animation, i: int) -> String:
	var p := str(anim.track_get_path(i))
	var idx := p.rfind(":")
	return p.substr(idx + 1) if idx >= 0 else p

func ease01(x: float) -> float:
	x = clamp(x, 0.0, 1.0)
	return x * x * (3.0 - 2.0 * x)

func blend_value(typ: int, a, b, t: float):
	if typ == Animation.TYPE_ROTATION_3D:
		var qa: Quaternion = a
		var qb: Quaternion = b
		return qa.slerp(qb, t).normalized()
	if typ == Animation.TYPE_POSITION_3D or typ == Animation.TYPE_SCALE_3D:
		var va: Vector3 = a
		var vb: Vector3 = b
		return va.lerp(vb, t)
	return b if t >= 1.0 else a

func _init():
	var anim: Animation = ResourceLoader.load(PATH, "Animation", ResourceLoader.CACHE_MODE_IGNORE)
	if anim == null:
		print("LOAD_FAILED ", PATH)
		quit(1)
		return

	var length: float = anim.length
	var blend_start: float = max(0.0, length - BLEND_TIME)
	var changed := 0
	anim.loop_mode = Animation.LOOP_LINEAR

	for i in range(anim.get_track_count()):
		var typ := anim.track_get_type(i)
		var name := track_name(anim, i)
		var key_count := anim.track_get_key_count(i)
		if key_count <= 0:
			continue
		anim.track_set_interpolation_loop_wrap(i, true)

		# Root position keeps real RootMotion displacement. Do not pull it back to first frame.
		if typ == Animation.TYPE_POSITION_3D and name == "Root":
			continue

		if typ != Animation.TYPE_ROTATION_3D and typ != Animation.TYPE_POSITION_3D and typ != Animation.TYPE_SCALE_3D:
			continue

		var first_value = anim.track_get_key_value(i, 0)
		for k in range(key_count):
			var kt := anim.track_get_key_time(i, k)
			if kt < blend_start - EPS:
				continue
			var w: float = ease01((kt - blend_start) / max(BLEND_TIME, EPS))
			var old_value = anim.track_get_key_value(i, k)
			var new_value = blend_value(typ, old_value, first_value, w)
			anim.track_set_key_value(i, k, new_value)
			changed += 1

		# Ensure exact closing key at animation length.
		var last_idx := anim.track_get_key_count(i) - 1
		var last_time := anim.track_get_key_time(i, last_idx)
		if abs(last_time - length) <= EPS:
			anim.track_set_key_value(i, last_idx, first_value)
		else:
			anim.track_insert_key(i, length, first_value)
		changed += 1

	var err := ResourceSaver.save(anim, OUT_PATH)
	print("SAVE err=", err, " path=", OUT_PATH, " length=", anim.length, " blend_time=", BLEND_TIME, " changed_keys=", changed)
	quit(err)


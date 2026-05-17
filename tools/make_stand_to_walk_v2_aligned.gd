extends SceneTree

const SRC_STAND_PATH := "res://resources/animate/Kimodo/mirdo_stand_to_walk_fast.res"
const TARGET_WALK_PATH := "res://resources/animate/Kimodo/walk_forward_loop_v2.res"
const OUT_PATH := "res://resources/animate/Kimodo/stand_to_walk_v2.res"
const ALIGN_BLEND_TIME := 0.22
const EPS := 0.00001

func track_name(anim: Animation, i: int) -> String:
	var p := str(anim.track_get_path(i))
	var idx := p.rfind(":")
	return p.substr(idx + 1) if idx >= 0 else p

func find_track(anim: Animation, name: String, typ: int) -> int:
	for i in range(anim.get_track_count()):
		if anim.track_get_type(i) == typ and track_name(anim, i) == name:
			return i
	return -1

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

func normalized_root_target(src: Animation, walk: Animation, src_track: int, walk_track: int) -> Vector3:
	# stand_to_walk_v2 root starts at zero and keeps its own final forward displacement,
	# only lateral/vertical are aligned to walk start to avoid a visible offset pop.
	var src_start: Vector3 = src.track_get_key_value(src_track, 0)
	var src_end: Vector3 = src.position_track_interpolate(src_track, src.length) - src_start
	var walk_start: Vector3 = walk.track_get_key_value(walk_track, 0)
	return Vector3(walk_start.x, walk_start.y, src_end.z)

func _init():
	var src: Animation = ResourceLoader.load(SRC_STAND_PATH, "Animation", ResourceLoader.CACHE_MODE_IGNORE)
	var walk: Animation = ResourceLoader.load(TARGET_WALK_PATH, "Animation", ResourceLoader.CACHE_MODE_IGNORE)
	if src == null or walk == null:
		print("LOAD_FAILED src=", src != null, " walk=", walk != null)
		quit(1)
		return

	var out := Animation.new()
	out.length = src.length
	out.loop_mode = Animation.LOOP_NONE
	out.step = src.step
	var blend_start: float = max(0.0, src.length - ALIGN_BLEND_TIME)
	var changed := 0
	var missing := 0

	for i in range(src.get_track_count()):
		var typ := src.track_get_type(i)
		var name := track_name(src, i)
		var dst := out.add_track(typ)
		out.track_set_path(dst, src.track_get_path(i))
		out.track_set_interpolation_type(dst, src.track_get_interpolation_type(i))
		out.track_set_interpolation_loop_wrap(dst, false)
		out.track_set_enabled(dst, src.track_is_enabled(i))

		var target_track := find_track(walk, name, typ)
		var has_target := target_track >= 0
		if not has_target:
			missing += 1

		var src_root_offset = null
		if typ == Animation.TYPE_POSITION_3D and name == "Root":
			src_root_offset = src.track_get_key_value(i, 0)

		var target_value = null
		if has_target:
			if typ == Animation.TYPE_POSITION_3D and name == "Root":
				target_value = normalized_root_target(src, walk, i, target_track)
			else:
				target_value = walk.track_get_key_value(target_track, 0)

		for k in range(src.track_get_key_count(i)):
			var kt := src.track_get_key_time(i, k)
			var val = src.track_get_key_value(i, k)
			if src_root_offset != null:
				val = val - src_root_offset
			if has_target and (typ == Animation.TYPE_ROTATION_3D or typ == Animation.TYPE_POSITION_3D or typ == Animation.TYPE_SCALE_3D):
				if kt >= blend_start - EPS:
					var w: float = ease01((kt - blend_start) / max(ALIGN_BLEND_TIME, EPS))
					val = blend_value(typ, val, target_value, w)
					changed += 1
			out.track_insert_key(dst, kt, val, src.track_get_key_transition(i, k))

		# Force exact final aligned key, otherwise some tracks may have last key before src.length.
		if has_target and (typ == Animation.TYPE_ROTATION_3D or typ == Animation.TYPE_POSITION_3D or typ == Animation.TYPE_SCALE_3D):
			var last_idx := out.track_get_key_count(dst) - 1
			if last_idx >= 0 and abs(out.track_get_key_time(dst, last_idx) - src.length) <= EPS:
				out.track_set_key_value(dst, last_idx, target_value)
			else:
				out.track_insert_key(dst, src.length, target_value)
			changed += 1

	var err := ResourceSaver.save(out, OUT_PATH)
	print("SAVE err=", err, " path=", OUT_PATH)
	print("source=", SRC_STAND_PATH, " target=", TARGET_WALK_PATH)
	print("length=", out.length, " align_blend=", ALIGN_BLEND_TIME, " changed=", changed, " missing_target_tracks=", missing)
	quit(err)

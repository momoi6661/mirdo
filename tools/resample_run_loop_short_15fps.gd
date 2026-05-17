extends SceneTree

const PATH := "res://resources/animate/Kimodo/run_forward_loop_short.res"
const SAMPLE_FPS := 15.0
const EPS := 0.00001

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

func _init():
	var src: Animation = ResourceLoader.load(PATH, "Animation", ResourceLoader.CACHE_MODE_IGNORE)
	if src == null:
		print("LOAD_FAILED ", PATH)
		quit(1)
		return

	var out := Animation.new()
	out.length = src.length
	out.loop_mode = Animation.LOOP_LINEAR
	out.step = 1.0 / SAMPLE_FPS
	var old_keys := 0
	var new_keys := 0

	for i in range(src.get_track_count()):
		var typ := src.track_get_type(i)
		var name := track_name(src, i)
		var dst := out.add_track(typ)
		out.track_set_path(dst, src.track_get_path(i))
		out.track_set_interpolation_type(dst, src.track_get_interpolation_type(i))
		out.track_set_interpolation_loop_wrap(dst, true)
		out.track_set_enabled(dst, src.track_is_enabled(i))
		old_keys += src.track_get_key_count(i)

		# Root position: keep original detail, because root motion timing matters.
		if typ == Animation.TYPE_POSITION_3D and name == "Root":
			for k in range(src.track_get_key_count(i)):
				out.track_insert_key(dst, src.track_get_key_time(i, k), src.track_get_key_value(i, k), src.track_get_key_transition(i, k))
			new_keys += out.track_get_key_count(dst)
			continue

		if typ == Animation.TYPE_ROTATION_3D or typ == Animation.TYPE_POSITION_3D or typ == Animation.TYPE_SCALE_3D:
			var sample_count := int(floor(src.length * SAMPLE_FPS))
			for s in range(sample_count + 1):
				var t: float = min(float(s) / SAMPLE_FPS, src.length)
				# Skip exact duplicate endpoint for non-root to avoid repeated first-frame pause.
				if t >= src.length - EPS:
					continue
				out.track_insert_key(dst, t, sample_value(src, i, t))
		else:
			for k in range(src.track_get_key_count(i)):
				out.track_insert_key(dst, src.track_get_key_time(i, k), src.track_get_key_value(i, k), src.track_get_key_transition(i, k))
		new_keys += out.track_get_key_count(dst)

	var err := ResourceSaver.save(out, PATH)
	print("SAVE err=", err, " path=", PATH)
	print("sample_fps=", SAMPLE_FPS, " length=", out.length, " old_keys=", old_keys, " new_keys=", new_keys)
	quit(err)

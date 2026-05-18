extends SceneTree

const SRC_PATH := "res://resources/animate/Kimodo/seated_sleepy.res"
const OUT_PATH := "res://resources/animate/Kimodo/seated_sleepy_loop.res"
const CUT_START := 2.6
const CUT_END := 12.7916669845581
const EXTEND_TIME := 1.0 / 30.0
const EPS := 0.00001

func track_name(anim: Animation, i: int) -> String:
	var p := str(anim.track_get_path(i))
	var idx := p.rfind(":")
	return p.substr(idx + 1) if idx >= 0 else p

func key_range(anim: Animation, track: int, t: float) -> Array:
	var n := anim.track_get_key_count(track)
	if n <= 0: return [0, 0, 0.0]
	if t <= anim.track_get_key_time(track, 0): return [0, 0, 0.0]
	if t >= anim.track_get_key_time(track, n - 1): return [n - 1, n - 1, 0.0]
	var lo := 0
	var hi := n - 1
	while hi - lo > 1:
		var mid := int((lo + hi) / 2)
		if anim.track_get_key_time(track, mid) <= t:
			lo = mid
		else:
			hi = mid
	var t0 := anim.track_get_key_time(track, lo)
	var t1 := anim.track_get_key_time(track, hi)
	var a: float = 0.0 if abs(t1 - t0) < EPS else (t - t0) / (t1 - t0)
	return [lo, hi, clamp(a, 0.0, 1.0)]

func sample_value(anim: Animation, track: int, t: float):
	var typ := anim.track_get_type(track)
	if typ == Animation.TYPE_POSITION_3D: return anim.position_track_interpolate(track, t)
	if typ == Animation.TYPE_ROTATION_3D: return anim.rotation_track_interpolate(track, t)
	if typ == Animation.TYPE_SCALE_3D: return anim.scale_track_interpolate(track, t)
	var r := key_range(anim, track, t)
	return anim.track_get_key_value(track, int(r[0]))

func insert_unique_key(anim: Animation, track: int, time: float, value, transition: float = 1.0) -> void:
	for k in range(anim.track_get_key_count(track)):
		if abs(anim.track_get_key_time(track, k) - time) < EPS:
			anim.track_set_key_value(track, k, value)
			return
	anim.track_insert_key(track, time, value, transition)

func _init():
	var src: Animation = ResourceLoader.load(SRC_PATH)
	if src == null:
		print("LOAD_FAILED ", SRC_PATH)
		quit(1); return
	var base_dur: float = CUT_END - CUT_START
	var out := Animation.new()
	out.length = base_dur + EXTEND_TIME
	out.loop_mode = Animation.LOOP_LINEAR
	out.step = src.step

	for i in range(src.get_track_count()):
		var typ := src.track_get_type(i)
		var dst := out.add_track(typ)
		out.track_set_path(dst, src.track_get_path(i))
		out.track_set_interpolation_type(dst, src.track_get_interpolation_type(i))
		out.track_set_interpolation_loop_wrap(dst, true)
		out.track_set_enabled(dst, src.track_is_enabled(i))
		var name := track_name(src, i)
		var root_offset = null
		var freeze_root := typ == Animation.TYPE_POSITION_3D and name == "Root"
		if freeze_root:
			root_offset = sample_value(src, i, CUT_START)
		var v0 = sample_value(src, i, CUT_START)
		var v1 = sample_value(src, i, CUT_END)
		if freeze_root:
			v0 = Vector3.ZERO
			v1 = Vector3.ZERO
		insert_unique_key(out, dst, 0.0, v0)
		for k in range(src.track_get_key_count(i)):
			var kt := src.track_get_key_time(i, k)
			if kt <= CUT_START + EPS or kt >= CUT_END - EPS: continue
			var val = src.track_get_key_value(i, k)
			if freeze_root:
				val = Vector3.ZERO
			insert_unique_key(out, dst, kt - CUT_START, val, src.track_get_key_transition(i, k))
		insert_unique_key(out, dst, base_dur, v1)
		# No extra duplicate pose key at extended end; just extend animation length slightly.
	var err := ResourceSaver.save(out, OUT_PATH)
	print("SAVE err=", err, " path=", OUT_PATH, " cut=", CUT_START, "..", CUT_END, " length=", out.length, " base_dur=", base_dur, " loop=", out.loop_mode)
	quit(err)

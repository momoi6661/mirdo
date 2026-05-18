extends SceneTree

const SRC_PATH := "res://resources/animate/Kimodo/sit_and_stand.res"
const EPS := 0.00001

var jobs := [
	{"out":"res://resources/animate/Kimodo/sit_down.res", "s":0.0, "e":2.6, "loop":false, "freeze_root":false},
	{"out":"res://resources/animate/Kimodo/seated_idle_loop.res", "s":2.6, "e":11.2, "loop":true, "freeze_root":true},
	{"out":"res://resources/animate/Kimodo/stand_up.res", "s":11.2, "e":14.5, "loop":false, "freeze_root":false},
]

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

func slice_anim(src: Animation, out_path: String, cut_start: float, cut_end: float, looped: bool, freeze_root: bool) -> Error:
	var dur: float = cut_end - cut_start
	var out := Animation.new()
	out.length = dur
	out.loop_mode = Animation.LOOP_LINEAR if looped else Animation.LOOP_NONE
	out.step = src.step

	for i in range(src.get_track_count()):
		var typ := src.track_get_type(i)
		var dst := out.add_track(typ)
		out.track_set_path(dst, src.track_get_path(i))
		out.track_set_interpolation_type(dst, src.track_get_interpolation_type(i))
		out.track_set_interpolation_loop_wrap(dst, looped)
		out.track_set_enabled(dst, src.track_is_enabled(i))

		var name := track_name(src, i)
		var root_offset = null
		var root_base = null
		if typ == Animation.TYPE_POSITION_3D and name == "Root":
			root_offset = sample_value(src, i, cut_start)
			root_base = Vector3.ZERO

		var v0 = sample_value(src, i, cut_start)
		var v1 = sample_value(src, i, cut_end)
		if root_offset != null:
			v0 = v0 - root_offset
			v1 = v1 - root_offset
			if freeze_root:
				v0 = root_base
				v1 = root_base
		insert_unique_key(out, dst, 0.0, v0)

		for k in range(src.track_get_key_count(i)):
			var kt := src.track_get_key_time(i, k)
			if kt <= cut_start + EPS or kt >= cut_end - EPS: continue
			var val = src.track_get_key_value(i, k)
			if root_offset != null:
				val = val - root_offset
				if freeze_root:
					val = root_base
			insert_unique_key(out, dst, kt - cut_start, val, src.track_get_key_transition(i, k))

		insert_unique_key(out, dst, dur, v1)
	return ResourceSaver.save(out, out_path)

func _init():
	var src: Animation = ResourceLoader.load(SRC_PATH)
	if src == null:
		print("LOAD_FAILED ", SRC_PATH)
		quit(1); return
	var final_err := OK
	for job in jobs:
		var err := slice_anim(src, String(job.out), float(job.s), float(job.e), bool(job.loop), bool(job.freeze_root))
		print("SAVE err=", err, " path=", job.out, " cut=", "%0.3f" % float(job.s), "..", "%0.3f" % float(job.e), " length=", "%0.3f" % (float(job.e)-float(job.s)), " loop=", job.loop, " freeze_root=", job.freeze_root)
		if err != OK: final_err = err
	quit(final_err)

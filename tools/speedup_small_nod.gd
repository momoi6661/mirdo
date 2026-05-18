extends SceneTree

const PATH := "res://resources/animate/Kimodo/small_nod.res"
const SPEEDUP := 1.35
const EPS := 0.00001

func _init():
	var src: Animation = ResourceLoader.load(PATH, "Animation", ResourceLoader.CACHE_MODE_IGNORE)
	if src == null:
		print("LOAD_FAILED ", PATH)
		quit(1); return
	var old_len: float = src.length
	var new_len: float = old_len / SPEEDUP
	var scale: float = new_len / old_len
	var out := Animation.new()
	out.length = new_len
	out.loop_mode = src.loop_mode
	out.step = src.step * scale
	var old_keys := 0
	var new_keys := 0
	for i in range(src.get_track_count()):
		var typ := src.track_get_type(i)
		var dst := out.add_track(typ)
		out.track_set_path(dst, src.track_get_path(i))
		out.track_set_interpolation_type(dst, src.track_get_interpolation_type(i))
		out.track_set_interpolation_loop_wrap(dst, src.track_get_interpolation_loop_wrap(i))
		out.track_set_enabled(dst, src.track_is_enabled(i))
		old_keys += src.track_get_key_count(i)
		for k in range(src.track_get_key_count(i)):
			var old_t := src.track_get_key_time(i, k)
			var new_t: float = old_t * scale
			if abs(old_t - old_len) < EPS:
				new_t = new_len
			out.track_insert_key(dst, new_t, src.track_get_key_value(i, k), src.track_get_key_transition(i, k))
		new_keys += out.track_get_key_count(dst)
	var err := ResourceSaver.save(out, PATH)
	print("SAVE err=", err, " path=", PATH)
	print("old_len=", old_len, " new_len=", new_len, " speedup=", SPEEDUP, " old_keys=", old_keys, " new_keys=", new_keys)
	quit(err)

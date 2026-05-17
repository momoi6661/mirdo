extends SceneTree

const SRC_PATH := "res://resources/animate/Kimodo/run_to_stop_short.res"
const OUT_PATH := "res://resources/animate/Kimodo/run_to_stop_fast.res"
const TARGET_LENGTH := 1.45
const EPS := 0.00001

func _init():
	var src: Animation = ResourceLoader.load(SRC_PATH, "Animation", ResourceLoader.CACHE_MODE_IGNORE)
	if src == null:
		print("LOAD_FAILED ", SRC_PATH)
		quit(1)
		return
	var scale: float = TARGET_LENGTH / src.length
	var out := Animation.new()
	out.length = TARGET_LENGTH
	out.loop_mode = Animation.LOOP_NONE
	out.step = src.step * scale
	for i in range(src.get_track_count()):
		var typ := src.track_get_type(i)
		var dst := out.add_track(typ)
		out.track_set_path(dst, src.track_get_path(i))
		out.track_set_interpolation_type(dst, src.track_get_interpolation_type(i))
		out.track_set_interpolation_loop_wrap(dst, false)
		out.track_set_enabled(dst, src.track_is_enabled(i))
		for k in range(src.track_get_key_count(i)):
			var old_t := src.track_get_key_time(i, k)
			var new_t: float = old_t * scale
			if abs(old_t - src.length) < EPS:
				new_t = TARGET_LENGTH
			out.track_insert_key(dst, new_t, src.track_get_key_value(i, k), src.track_get_key_transition(i, k))
	var err := ResourceSaver.save(out, OUT_PATH)
	print("SAVE err=", err, " path=", OUT_PATH)
	print("source_length=", src.length, " target_length=", out.length, " speedup=", src.length / out.length, " tracks=", out.get_track_count())
	var check: Animation = ResourceLoader.load(OUT_PATH, "Animation", ResourceLoader.CACHE_MODE_IGNORE)
	if check:
		print("CHECK length=", check.length, " loop=", check.loop_mode, " tracks=", check.get_track_count())
		for i in range(min(3, check.get_track_count())):
			print("track", i, " keys=", check.track_get_key_count(i), " first=", check.track_get_key_time(i,0), " last=", check.track_get_key_time(i, check.track_get_key_count(i)-1))
	quit(err)

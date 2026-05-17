extends SceneTree
func _init():
	for path in ["res://resources/animate/Kimodo/stand_to_run.res", "res://resources/animate/Kimodo/run_forward_loop_short.res"]:
		var a: Animation = ResourceLoader.load(path, "Animation", ResourceLoader.CACHE_MODE_IGNORE)
		print(path, " length=", a.length, " loop=", a.loop_mode, " tracks=", a.get_track_count())
		for i in range(min(2, a.get_track_count())):
			print("  track", i, " keys=", a.track_get_key_count(i), " first=", a.track_get_key_time(i,0), " last=", a.track_get_key_time(i,a.track_get_key_count(i)-1))
	quit()

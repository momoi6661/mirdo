extends SceneTree
const PATHS := [
	"res://resources/animate/Kimodo/sit_down.res",
	"res://resources/animate/Kimodo/seated_idle_loop.res",
	"res://resources/animate/Kimodo/stand_up.res",
]
func _init():
	for path in PATHS:
		var a: Animation = ResourceLoader.load(path, "Animation", ResourceLoader.CACHE_MODE_IGNORE)
		if a == null:
			print("LOAD_FAILED ", path)
			continue
		var key_last := 0.0
		var key_min_last := INF
		for i in range(a.get_track_count()):
			var kc := a.track_get_key_count(i)
			if kc > 0:
				var lt := a.track_get_key_time(i, kc - 1)
				key_last = max(key_last, lt)
				key_min_last = min(key_min_last, lt)
		print(path, " length=", a.length, " loop=", a.loop_mode, " tracks=", a.get_track_count(), " key_last=", key_last, " min_last=", key_min_last)
	quit()

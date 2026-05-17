extends SceneTree

const BODY_LOOP_PATHS := [
	"res://resources/animate/Kimodo/kimodo_idle_alert_loop.res",
	"res://resources/animate/Kimodo/kimodo_idle_fidget.res",
	"res://resources/animate/Kimodo/idle_normal_loop.res",
	"res://resources/animate/Kimodo/Kimodo_idle_relaxed_loop.res",
	"res://resources/animate/Kimodo/kimodo_idle_sleepy.res",
	"res://resources/animate/Kimodo/kimodo_listen.res",
	"res://resources/animate/Kimodo/kimodo_look_around.res",
	"res://resources/animate/Kimodo/run_forward_loop_short.res",
	"res://resources/animate/Kimodo/walk_forward_loop_v2.res",
]

func _init():
	for path in BODY_LOOP_PATHS:
		var a: Animation = ResourceLoader.load(path, "Animation", ResourceLoader.CACHE_MODE_IGNORE)
		if a == null:
			print("LOAD_FAILED ", path)
			continue
		var key_last := 0.0
		var min_last := INF
		for i in range(a.get_track_count()):
			var kc := a.track_get_key_count(i)
			if kc > 0:
				var lt := a.track_get_key_time(i, kc - 1)
				key_last = max(key_last, lt)
				min_last = min(min_last, lt)
		print(path, " length=", a.length, " loop=", a.loop_mode, " key_last=", key_last, " min_last=", min_last, " tracks=", a.get_track_count())
	quit()

extends SceneTree

const SOURCE := "res://resources/animate/Kimodo/walk.res"
const FILES := [
	"res://resources/animate/Kimodo/mirdo_stand_to_walk.res",
	"res://resources/animate/Kimodo/mirdo_walk_forward_loop.res",
	"res://resources/animate/Kimodo/mirdo_walk_to_stop.res",
]

func _initialize() -> void:
	var src := ResourceLoader.load(SOURCE) as Animation
	var uncovered := 0
	for ti in range(src.get_track_count()):
		for ki in range(src.track_get_key_count(ti)):
			var t := src.track_get_key_time(ti, ki)
			var covered := (t >= 0.0 and t < 2.0) or (t >= 2.0 and t < 8.5) or (t >= 8.5 and t <= src.length + 0.0001)
			if not covered:
				uncovered += 1
	print("source_length=", src.length, " uncovered_keys=", uncovered)
	for f in FILES:
		var a := ResourceLoader.load(f) as Animation
		var root_info := ""
		for i in range(a.get_track_count()):
			var p := str(a.track_get_path(i))
			if p.find("GeneralSkeleton:Root") >= 0:
				root_info = "root_track=%d keys=%d first=%s last=%s" % [i, a.track_get_key_count(i), a.track_get_key_time(i, 0), a.track_get_key_time(i, a.track_get_key_count(i)-1)]
		print(f, " length=", a.length, " loop=", a.loop_mode, " tracks=", a.get_track_count(), " ", root_info)
	quit(0)

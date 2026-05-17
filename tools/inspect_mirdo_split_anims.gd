extends SceneTree

const FILES := [
	"res://resources/animate/Kimodo/mirdo_stand_to_walk.res",
	"res://resources/animate/Kimodo/mirdo_walk_forward_loop.res",
	"res://resources/animate/Kimodo/mirdo_walk_to_stop.res",
]

func _initialize() -> void:
	for f in FILES:
		var a := ResourceLoader.load(f) as Animation
		if a == null:
			print("missing ", f)
			continue
		var root_tracks := []
		for i in range(a.get_track_count()):
			var p := str(a.track_get_path(i))
			if p.find("GeneralSkeleton:Root") >= 0:
				root_tracks.append("%s:%s keys=%s" % [i, p, a.track_get_key_count(i)])
		print(f, " length=", a.length, " loop=", a.loop_mode, " tracks=", a.get_track_count(), " root_tracks=", root_tracks)
	quit(0)

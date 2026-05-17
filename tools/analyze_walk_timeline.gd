extends SceneTree

const SOURCE := "res://resources/animate/Kimodo/walk.res"

func _initialize() -> void:
	var a := ResourceLoader.load(SOURCE) as Animation
	if a == null:
		push_error("missing animation")
		quit(1)
		return
	print("length=", a.length, " tracks=", a.get_track_count())
	for i in range(a.get_track_count()):
		var p := str(a.track_get_path(i))
		if p.find("GeneralSkeleton:Root") >= 0 or p.find("GeneralSkeleton:Hips") >= 0:
			print("track ", i, " type=", a.track_get_type(i), " path=", p, " keys=", a.track_get_key_count(i))
			_dump_track_samples(a, i)
	quit(0)

func _dump_track_samples(a: Animation, ti: int) -> void:
	var kc := a.track_get_key_count(ti)
	if kc <= 0:
		return
	print("  first=", a.track_get_key_time(ti, 0), " last=", a.track_get_key_time(ti, kc - 1))
	var prev_t := -1.0
	var prev_v = null
	for ki in range(kc):
		var t := a.track_get_key_time(ti, ki)
		if ki == 0 or ki == kc - 1 or absf(fmod(t, 0.5)) < 0.017:
			var v = a.track_get_key_value(ti, ki)
			var speed := 0.0
			if prev_v != null and v is Vector3 and prev_v is Vector3:
				var dt := maxf(0.0001, t - prev_t)
				speed = (v - prev_v).length() / dt
			print("  k=", ki, " t=", t, " v=", v, " approx_speed=", speed)
		prev_t = t
		prev_v = a.track_get_key_value(ti, ki)

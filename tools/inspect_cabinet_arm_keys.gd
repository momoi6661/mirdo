extends SceneTree

const PATH := "res://resources/animate/Kimodo/inspect_cabinet.res"
const START := 3.2
const END := 3.7

func bone_name(anim: Animation, i: int) -> String:
	var p := str(anim.track_get_path(i))
	var idx := p.rfind(":")
	return p.substr(idx + 1) if idx >= 0 else p

func quat_deg(a: Quaternion, b: Quaternion) -> float:
	var d: float = abs(a.dot(b))
	d = clamp(d, -1.0, 1.0)
	return rad_to_deg(2.0 * acos(d))

func _init():
	var anim: Animation = ResourceLoader.load(PATH, "Animation", ResourceLoader.CACHE_MODE_IGNORE)
	if anim == null:
		print("LOAD_FAILED")
		quit(1); return
	print("ANIM length=", anim.length, " loop=", anim.loop_mode, " tracks=", anim.get_track_count())
	for i in range(anim.get_track_count()):
		var name := bone_name(anim, i)
		if name.contains("Right") and (name.contains("Arm") or name.contains("Hand")):
			print("track=", i, " type=", anim.track_get_type(i), " name=", name, " keys=", anim.track_get_key_count(i), " path=", anim.track_get_path(i))
			var prev_q: Quaternion
			var prev_t := -1.0
			for k in range(anim.track_get_key_count(i)):
				var t := anim.track_get_key_time(i, k)
				if t < START - 0.2 or t > END + 0.2: continue
				if anim.track_get_type(i) == Animation.TYPE_ROTATION_3D:
					var q: Quaternion = anim.track_get_key_value(i, k)
					var deg := 0.0 if prev_t < 0.0 else quat_deg(prev_q, q)
					print("  k=", k, " t=", "%0.4f" % t, " delta=", "%0.2f" % deg)
					prev_q = q; prev_t = t
	quit()

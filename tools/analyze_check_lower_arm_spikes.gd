extends SceneTree

const PATH := "res://resources/animate/Kimodo/check_lower.res"
const FPS := 30.0
const ARM_NAMES := ["LeftUpperArm", "LeftLowerArm", "LeftHand", "RightUpperArm", "RightLowerArm", "RightHand"]

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
	print("ANIM=", PATH, " length=", anim.length, " loop=", anim.loop_mode, " tracks=", anim.get_track_count())
	for i in range(anim.get_track_count()):
		var name := bone_name(anim, i)
		if not ARM_NAMES.has(name): continue
		if anim.track_get_type(i) != Animation.TYPE_ROTATION_3D: continue
		print("\ntrack=", i, " name=", name, " keys=", anim.track_get_key_count(i))
		var spikes := []
		var prev_q: Quaternion
		var prev_t := -1.0
		for k in range(anim.track_get_key_count(i)):
			var t := anim.track_get_key_time(i, k)
			var q: Quaternion = anim.track_get_key_value(i, k)
			if prev_t >= 0.0:
				var deg := quat_deg(prev_q, q)
				if deg >= 1.2:
					spikes.append({"k": k, "t": t, "deg": deg, "dt": t - prev_t})
			prev_q = q; prev_t = t
		spikes.sort_custom(func(a,b): return a.deg > b.deg)
		for s in range(min(12, spikes.size())):
			var d = spikes[s]
			print(" spike k=", d.k, " t=", "%0.4f" % d.t, " deg=", "%0.2f" % d.deg, " dt=", "%0.4f" % d.dt)
	quit()

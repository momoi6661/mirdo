extends SceneTree

const PATH := "res://resources/animate/Kimodo/check_lower.res"
const ARM_NAMES := ["LeftUpperArm", "LeftLowerArm", "LeftHand", "RightUpperArm", "RightLowerArm", "RightHand"]
const WINDOWS := [
	{"s": 1.20, "e": 2.25, "step": 0.175},
	{"s": 7.35, "e": 7.50, "step": 0.075},
]
const EPS := 0.00001

func bone_name(anim: Animation, i: int) -> String:
	var p := str(anim.track_get_path(i))
	var idx := p.rfind(":")
	return p.substr(idx + 1) if idx >= 0 else p

func find_arm_tracks(anim: Animation) -> Array[int]:
	var result: Array[int] = []
	for i in range(anim.get_track_count()):
		if anim.track_get_type(i) != Animation.TYPE_ROTATION_3D:
			continue
		if ARM_NAMES.has(bone_name(anim, i)):
			result.append(i)
	return result

func quat_deg(a: Quaternion, b: Quaternion) -> float:
	var d: float = abs(a.dot(b))
	d = clamp(d, -1.0, 1.0)
	return rad_to_deg(2.0 * acos(d))

func make_times(start: float, end: float, step: float) -> Array[float]:
	var times: Array[float] = []
	times.append(start)
	var t := start + step
	while t < end - EPS:
		times.append(t)
		t += step
	times.append(end)
	return times

func _init():
	var anim: Animation = ResourceLoader.load(PATH, "Animation", ResourceLoader.CACHE_MODE_IGNORE)
	if anim == null:
		print("LOAD_FAILED ", PATH)
		quit(1); return

	var tracks := find_arm_tracks(anim)
	var total_removed := 0
	var total_inserted := 0
	var report := []

	# Collect samples before mutating.
	var samples := {}
	for track in tracks:
		samples[track] = []
		for w in WINDOWS:
			var ts := make_times(float(w.s), float(w.e), float(w.step))
			var vals := []
			for t in ts:
				vals.append({"t": t, "v": anim.rotation_track_interpolate(track, t)})
			samples[track].append({"s": float(w.s), "e": float(w.e), "vals": vals})

	for track in tracks:
		var before := anim.track_get_key_count(track)
		var removed := 0
		for w in WINDOWS:
			var s := float(w.s)
			var e := float(w.e)
			for k in range(anim.track_get_key_count(track) - 1, -1, -1):
				var kt := anim.track_get_key_time(track, k)
				if kt >= s - EPS and kt <= e + EPS:
					anim.track_remove_key(track, k)
					removed += 1
		var inserted := 0
		for pack in samples[track]:
			for item in pack.vals:
				anim.track_insert_key(track, float(item.t), item.v)
				inserted += 1
		anim.track_set_interpolation_type(track, Animation.INTERPOLATION_CUBIC)
		total_removed += removed
		total_inserted += inserted
		report.append({"name": bone_name(anim, track), "track": track, "before": before, "removed": removed, "inserted": inserted, "after": anim.track_get_key_count(track)})

	var err := ResourceSaver.save(anim, PATH)
	print("SAVE err=", err, " path=", PATH)
	print("arm_tracks=", tracks.size(), " total_removed=", total_removed, " total_inserted=", total_inserted)
	for r in report:
		print(r.name, " track=", r.track, " keys ", r.before, " -> ", r.after, " removed=", r.removed, " inserted=", r.inserted)
	quit(err)

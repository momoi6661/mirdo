extends SceneTree

const SOURCE := "res://resources/animate/Kimodo/walk.res"
const SEARCH_START := 2.0
const SEARCH_END := 8.5
const MIN_DUR := 1.0
const MAX_DUR := 2.2
const STEP := 1.0 / 30.0

func _initialize() -> void:
	var a := ResourceLoader.load(SOURCE) as Animation
	if a == null:
		push_error("missing " + SOURCE)
		quit(1)
		return
	print("source_length=", a.length, " tracks=", a.get_track_count())
	var candidates := []
	var d := MIN_DUR
	while d <= MAX_DUR + 0.0001:
		var t := SEARCH_START
		while t + d <= SEARCH_END + 0.0001:
			var score := pose_score(a, t, t + d)
			candidates.append({"start": t, "end": t + d, "dur": d, "score": score})
			t += STEP
		d += STEP
	candidates.sort_custom(func(x, y): return x.score < y.score)
	print("best candidates ignoring root forward displacement:")
	for i in range(min(20, candidates.size())):
		var c = candidates[i]
		print("#", i + 1, " start=", snapped(c.start, 0.001), " end=", snapped(c.end, 0.001), " dur=", snapped(c.dur, 0.001), " score=", snapped(c.score, 0.00001), " root_delta=", root_delta(a, c.start, c.end))
	quit(0)

func pose_score(a: Animation, t0: float, t1: float) -> float:
	var score := 0.0
	var count := 0
	for ti in range(a.get_track_count()):
		if not a.track_is_enabled(ti):
			continue
		var path := str(a.track_get_path(ti))
		var typ := a.track_get_type(ti)
		# Ignore Root translation because root motion is supposed to advance.
		if path.find("GeneralSkeleton:Root") >= 0 and typ == Animation.TYPE_POSITION_3D:
			continue
		var v0 = nearest_value(a, ti, t0)
		var v1 = nearest_value(a, ti, t1)
		if v0 == null or v1 == null:
			continue
		if typ == Animation.TYPE_ROTATION_3D and v0 is Quaternion and v1 is Quaternion:
			var dot = absf(v0.normalized().dot(v1.normalized()))
			score += 1.0 - clampf(dot, 0.0, 1.0)
			count += 1
		elif typ == Animation.TYPE_POSITION_3D and v0 is Vector3 and v1 is Vector3:
			# Most non-root position tracks are small; compare directly.
			score += (v0 - v1).length() * 0.25
			count += 1
		elif typ == Animation.TYPE_SCALE_3D and v0 is Vector3 and v1 is Vector3:
			score += (v0 - v1).length() * 0.05
			count += 1
	return score / max(1, count)

func nearest_value(a: Animation, ti: int, time: float):
	var kc := a.track_get_key_count(ti)
	if kc <= 0:
		return null
	var best := 0
	var best_dist := INF
	for ki in range(kc):
		var d := absf(a.track_get_key_time(ti, ki) - time)
		if d < best_dist:
			best_dist = d
			best = ki
	return a.track_get_key_value(ti, best)

func root_delta(a: Animation, t0: float, t1: float) -> Vector3:
	for ti in range(a.get_track_count()):
		if str(a.track_get_path(ti)).find("GeneralSkeleton:Root") >= 0 and a.track_get_type(ti) == Animation.TYPE_POSITION_3D:
			var v0 = nearest_value(a, ti, t0)
			var v1 = nearest_value(a, ti, t1)
			if v0 is Vector3 and v1 is Vector3:
				return v1 - v0
	return Vector3.ZERO

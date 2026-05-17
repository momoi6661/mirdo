extends SceneTree

const ANIM_PATH := "res://resources/animate/Kimodo/run_forward_loop.res"
const FPS := 30.0
const EPS := 0.00001

var important := {
	"Hips": 3.0,"Spine": 1.5,"Chest": 1.5,"UpperChest": 1.2,"Neck": 0.8,"Head": 1.0,
	"LeftUpperArm": 1.2,"LeftLowerArm": 1.2,"LeftHand": 0.8,
	"RightUpperArm": 1.2,"RightLowerArm": 1.2,"RightHand": 0.8,
	"LeftUpperLeg": 3.0,"LeftLowerLeg": 3.0,"LeftFoot": 2.5,"LeftToeBase": 1.2,
	"RightUpperLeg": 3.0,"RightLowerLeg": 3.0,"RightFoot": 2.5,"RightToeBase": 1.2,
}

func bone_name(anim: Animation, i: int) -> String:
	var p := str(anim.track_get_path(i))
	var idx := p.rfind(":")
	return p.substr(idx + 1) if idx >= 0 else p

func key_range(anim: Animation, track: int, t: float) -> Array:
	var n := anim.track_get_key_count(track)
	if n <= 0:
		return [0, 0, 0.0]
	if t <= anim.track_get_key_time(track, 0):
		return [0, 0, 0.0]
	if t >= anim.track_get_key_time(track, n - 1):
		return [n - 1, n - 1, 0.0]
	var lo := 0
	var hi := n - 1
	while hi - lo > 1:
		var mid := int((lo + hi) / 2)
		if anim.track_get_key_time(track, mid) <= t:
			lo = mid
		else:
			hi = mid
	var t0 := anim.track_get_key_time(track, lo)
	var t1 := anim.track_get_key_time(track, hi)
	var f: float = 0.0 if abs(t1 - t0) < EPS else (t - t0) / (t1 - t0)
	return [lo, hi, clamp(f, 0.0, 1.0)]

func raw_pos(anim: Animation, track: int, t: float) -> Vector3:
	var r := key_range(anim, track, t)
	var a: int = r[0]
	var b: int = r[1]
	var f: float = r[2]
	var va: Vector3 = anim.track_get_key_value(track, a)
	var vb: Vector3 = anim.track_get_key_value(track, b)
	return va.lerp(vb, f)

func raw_rot(anim: Animation, track: int, t: float) -> Quaternion:
	var r := key_range(anim, track, t)
	var a: int = r[0]
	var b: int = r[1]
	var f: float = r[2]
	var qa: Quaternion = anim.track_get_key_value(track, a)
	var qb: Quaternion = anim.track_get_key_value(track, b)
	return qa.slerp(qb, f).normalized()

func quat_deg(a: Quaternion, b: Quaternion) -> float:
	var d: float = abs(a.dot(b))
	d = clamp(d, -1.0, 1.0)
	return rad_to_deg(2.0 * acos(d))

func score_segment(anim: Animation, t0: float, dur: float) -> Dictionary:
	var t1: float = t0 + dur
	var rot_sum := 0.0
	var w_sum := 0.0
	var max_rot := 0.0
	var max_name := ""
	var hip_y_cm := 0.0
	var root_delta := Vector3.ZERO
	for i in range(anim.get_track_count()):
		var typ := anim.track_get_type(i)
		var name := bone_name(anim, i)
		if typ == Animation.TYPE_ROTATION_3D and important.has(name):
			var deg := quat_deg(raw_rot(anim, i, t0), raw_rot(anim, i, t1))
			var w: float = float(important[name])
			rot_sum += deg * w
			w_sum += w
			if deg > max_rot:
				max_rot = deg
				max_name = name
		elif typ == Animation.TYPE_POSITION_3D:
			var pd := raw_pos(anim, i, t1) - raw_pos(anim, i, t0)
			if name == "Root":
				root_delta = pd
			elif name == "Hips":
				hip_y_cm = abs(pd.y) * 100.0
	var rot_avg: float = rot_sum / max(w_sum, 0.0001)
	var speed: float = root_delta.z / dur
	var score: float = rot_avg + hip_y_cm * 0.25 + abs(root_delta.x) * 100.0 + abs(root_delta.y) * 100.0
	return {"t0": t0, "t1": t1, "dur": dur, "score": score, "rot": rot_avg, "max": max_rot, "max_name": max_name, "hip": hip_y_cm, "root": root_delta, "speed": speed}

func print_seg(prefix: String, d: Dictionary) -> void:
	var r: Vector3 = d.root
	print(prefix,
		" start=", "%0.4f" % d.t0,
		" end=", "%0.4f" % d.t1,
		" dur=", "%0.4f" % d.dur,
		" score=", "%0.4f" % d.score,
		" rot=", "%0.3f" % d.rot,
		" max=", "%0.2f" % d.max, "@", d.max_name,
		" hipYcm=", "%0.3f" % d.hip,
		" root=(", "%0.4f" % r.x, ",", "%0.4f" % r.y, ",", "%0.4f" % r.z, ")",
		" speed=", "%0.4f" % d.speed)

func scan_window(anim: Animation, last: float, min_d: float, max_d: float, label: String) -> Array:
	var cands := []
	for sf in range(0, int(floor((last - min_d) * FPS)) + 1):
		var t0: float = sf / FPS
		for df in range(int(round(min_d * FPS)), int(round(max_d * FPS)) + 1):
			var dur: float = df / FPS
			if t0 + dur > last + EPS:
				continue
			var d := score_segment(anim, t0, dur)
			# 只排除明显非跑步/速度异常的片段，保留更多候选。
			if d.speed < 1.0 or d.speed > 5.0:
				continue
			cands.append(d)
	cands.sort_custom(func(a, b): return a.score < b.score)
	print("\n", label, " ", min_d, "..", max_d)
	for i in range(min(12, cands.size())):
		print_seg("#" + str(i + 1), cands[i])
	return cands

func _init():
	var anim: Animation = ResourceLoader.load(ANIM_PATH)
	if anim == null:
		print("LOAD_FAILED ", ANIM_PATH)
		quit(1)
		return
	var last := 0.0
	for i in range(anim.get_track_count()):
		var n := anim.track_get_key_count(i)
		if n > 0:
			last = max(last, anim.track_get_key_time(i, n - 1))
	print("ANIM=", ANIM_PATH, " anim_length=", anim.length, " key_last=", last, " loop=", anim.loop_mode, " tracks=", anim.get_track_count())
	var short := scan_window(anim, last, 0.50, 1.20, "RUN_ONE_CYCLE")
	var mid := scan_window(anim, last, 1.20, 2.20, "RUN_TWO_CYCLE")
	var rec = short[0] if short.size() > 0 else null
	var rec2 = mid[0] if mid.size() > 0 else null
	print("\nRECOMMEND")
	if rec != null:
		print_seg("one_cycle", rec)
	if rec2 != null:
		print_seg("two_cycle", rec2)
	quit()

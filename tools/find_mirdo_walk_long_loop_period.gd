extends SceneTree

const ANIM_PATH := "res://resources/animate/Kimodo/mirdo_walk_forward_loop.res"
const FPS := 30.0

var important := {
	"Hips": 3.0,"Spine": 1.5,"Chest": 1.5,"UpperChest": 1.2,"Head": 1.0,
	"LeftUpperArm": 1.1,"LeftLowerArm": 1.1,"LeftHand": 0.8,
	"RightUpperArm": 1.1,"RightLowerArm": 1.1,"RightHand": 0.8,
	"LeftUpperLeg": 2.5,"LeftLowerLeg": 2.5,"LeftFoot": 2.2,"LeftToeBase": 1.2,
	"RightUpperLeg": 2.5,"RightLowerLeg": 2.5,"RightFoot": 2.2,"RightToeBase": 1.2,
}
func bone_name(anim: Animation, i: int) -> String:
	var p := str(anim.track_get_path(i)); var idx := p.rfind(":"); return p.substr(idx + 1) if idx >= 0 else p
func key_range(anim: Animation, track: int, t: float) -> Array:
	var n := anim.track_get_key_count(track)
	if t <= anim.track_get_key_time(track, 0): return [0,0,0.0]
	if t >= anim.track_get_key_time(track, n - 1): return [n-1,n-1,0.0]
	var lo := 0; var hi := n - 1
	while hi - lo > 1:
		var mid := int((lo + hi) / 2)
		if anim.track_get_key_time(track, mid) <= t: lo = mid
		else: hi = mid
	var t0 := anim.track_get_key_time(track, lo); var t1 := anim.track_get_key_time(track, hi)
	var f := 0.0 if abs(t1 - t0) < 0.000001 else (t - t0) / (t1 - t0)
	return [lo,hi,clamp(f,0.0,1.0)]
func raw_pos(anim: Animation, track: int, t: float) -> Vector3:
	var r := key_range(anim, track, t); var a: int = r[0]; var b: int = r[1]; var f: float = r[2]
	var va: Vector3 = anim.track_get_key_value(track, a); var vb: Vector3 = anim.track_get_key_value(track, b)
	return va.lerp(vb, f)
func raw_rot(anim: Animation, track: int, t: float) -> Quaternion:
	var r := key_range(anim, track, t); var a: int = r[0]; var b: int = r[1]; var f: float = r[2]
	var qa: Quaternion = anim.track_get_key_value(track, a); var qb: Quaternion = anim.track_get_key_value(track, b)
	return qa.slerp(qb, f).normalized()
func quat_deg(a: Quaternion, b: Quaternion) -> float:
	var d: float = abs(a.dot(b)); d = clamp(d, -1.0, 1.0); return rad_to_deg(2.0 * acos(d))
func score_segment(anim: Animation, t0: float, dur: float) -> Dictionary:
	var t1: float = t0 + dur; var rot_sum := 0.0; var w_sum := 0.0; var max_rot := 0.0; var max_name := ""; var hip_y_cm := 0.0; var root_delta := Vector3.ZERO
	for i in range(anim.get_track_count()):
		var type := anim.track_get_type(i); var name := bone_name(anim, i)
		if type == Animation.TYPE_ROTATION_3D and important.has(name):
			var deg := quat_deg(raw_rot(anim, i, t0), raw_rot(anim, i, t1)); var w: float = float(important[name])
			rot_sum += deg * w; w_sum += w
			if deg > max_rot: max_rot = deg; max_name = name
		elif type == Animation.TYPE_POSITION_3D:
			var d := raw_pos(anim, i, t1) - raw_pos(anim, i, t0)
			if name == "Root": root_delta = d
			elif name == "Hips": hip_y_cm = abs(d.y) * 100.0
	var rot_avg: float = rot_sum / max(w_sum, 0.0001); var speed := root_delta.z / dur
	var score: float = rot_avg + hip_y_cm * 0.25 + abs(root_delta.x) * 100.0 + abs(root_delta.y) * 100.0
	return {"t0":t0,"t1":t1,"dur":dur,"score":score,"rot":rot_avg,"max":max_rot,"max_name":max_name,"hip":hip_y_cm,"rootZ":root_delta.z,"speed":speed}
func print_seg(prefix: String, d: Dictionary) -> void:
	print(prefix," start=","%0.4f"%d.t0," end=","%0.4f"%d.t1," dur=","%0.4f"%d.dur," score=","%0.4f"%d.score," rot=","%0.3f"%d.rot," max=","%0.2f"%d.max,"@",d.max_name," hipYcm=","%0.3f"%d.hip," rootZ=","%0.4f"%d.rootZ," speed=","%0.4f"%d.speed)
func _init():
	var anim: Animation = ResourceLoader.load(ANIM_PATH)
	var last := 0.0
	for i in range(anim.get_track_count()):
		var n := anim.track_get_key_count(i)
		if n > 0: last = max(last, anim.track_get_key_time(i, n-1))
	print("ANIM raw_key_last=", last, " anim.length=", anim.length)
	for window in [[2.20,2.70,"TWO_STEP"],[3.40,4.00,"THREE_STEP"],[1.80,3.40,"MID_LONG"]]:
		var cands := []
		for sf in range(0, int(floor((last - float(window[0])) * FPS)) + 1):
			var t0 := sf / FPS
			for df in range(int(round(float(window[0]) * FPS)), int(round(float(window[1]) * FPS)) + 1):
				var dur := df / FPS
				if t0 + dur > last + 0.0001: continue
				var d := score_segment(anim, t0, dur)
				if d.speed < 0.65 or d.speed > 1.35: continue
				cands.append(d)
		cands.sort_custom(func(a,b): return a.score < b.score)
		print("\n", window[2], " ", window[0], "..", window[1])
		for i in range(min(10, cands.size())): print_seg("#"+str(i+1), cands[i])
	quit()

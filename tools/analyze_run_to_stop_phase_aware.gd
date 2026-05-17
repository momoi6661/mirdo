extends SceneTree

const STOP_PATH := "res://resources/animate/Kimodo/run_to_stop.res"
const LOOP_PATH := "res://resources/animate/Kimodo/run_forward_loop_short.res"
const FPS := 30.0

var important := {
	"Hips": 3.0,"Spine": 1.5,"Chest": 1.5,"UpperChest": 1.2,"Neck": 0.8,"Head": 1.0,
	"LeftUpperArm": 1.2,"LeftLowerArm": 1.2,"LeftHand": 0.8,
	"RightUpperArm": 1.2,"RightLowerArm": 1.2,"RightHand": 0.8,
	"LeftUpperLeg": 3.0,"LeftLowerLeg": 3.0,"LeftFoot": 2.5,"LeftToeBase": 1.2,
	"RightUpperLeg": 3.0,"RightLowerLeg": 3.0,"RightFoot": 2.5,"RightToeBase": 1.2,
}
func bone_name(anim: Animation, i: int) -> String:
	var p := str(anim.track_get_path(i)); var idx := p.rfind(":"); return p.substr(idx + 1) if idx >= 0 else p
func quat_deg(a: Quaternion, b: Quaternion) -> float:
	var d: float = abs(a.dot(b)); d = clamp(d, -1.0, 1.0); return rad_to_deg(2.0 * acos(d))
func find_track(anim: Animation, name: String, typ: int) -> int:
	for i in range(anim.get_track_count()):
		if anim.track_get_type(i) == typ and bone_name(anim, i) == name: return i
	return -1
func pose_score(a: Animation, ta: float, b: Animation, tb: float) -> Dictionary:
	var sum := 0.0; var ws := 0.0; var maxd := 0.0; var maxn := ""
	for ia in range(a.get_track_count()):
		if a.track_get_type(ia) != Animation.TYPE_ROTATION_3D: continue
		var name := bone_name(a, ia)
		if not important.has(name): continue
		var ib := find_track(b, name, Animation.TYPE_ROTATION_3D)
		if ib < 0: continue
		var deg := quat_deg(a.rotation_track_interpolate(ia, ta), b.rotation_track_interpolate(ib, tb))
		var w: float = float(important[name])
		sum += deg * w; ws += w
		if deg > maxd: maxd = deg; maxn = name
	return {"score":sum/max(ws,0.0001),"max":maxd,"max_name":maxn}
func best_loop_phase(stop: Animation, loop: Animation, stop_t: float) -> Dictionary:
	var best := {"phase":0.0,"score":9999.0,"max":0.0,"max_name":""}
	for f in range(0, int(round(loop.length * FPS)) + 1):
		var lt: float = min(float(f) / FPS, loop.length)
		var ps := pose_score(stop, stop_t, loop, lt)
		if ps.score < best.score:
			best = {"phase":lt,"score":ps.score,"max":ps.max,"max_name":ps.max_name}
	return best
func root_z(anim: Animation, t: float) -> float:
	var rt := find_track(anim, "Root", Animation.TYPE_POSITION_3D)
	return 0.0 if rt < 0 else anim.position_track_interpolate(rt, t).z
func motion_at(anim: Animation, t: float) -> float:
	var dt := 1.0/FPS
	var a: float = max(0.0, t - dt); var b: float = min(anim.length, t + dt)
	return 0.0 if b <= a else (root_z(anim,b)-root_z(anim,a))/(b-a)
func print_c(label: String, d: Dictionary) -> void:
	print(label," start=","%0.4f"%d.start," end=","%0.4f"%d.end," dur=","%0.4f"%d.dur," phase=","%0.4f"%d.phase," entry=","%0.3f"%d.entry," endMotion=","%0.3f"%d.end_motion," rootZ=","%0.4f"%d.rootZ," score=","%0.3f"%d.score," max=","%0.2f"%d.max,"@",d.max_name)
func _init():
	var stop: Animation = ResourceLoader.load(STOP_PATH)
	var loop: Animation = ResourceLoader.load(LOOP_PATH)
	print("STOP length=", stop.length, " LOOP length=", loop.length)
	var cands := []
	for sf in range(0, int(round((stop.length - 0.4) * FPS)) + 1):
		var s: float = float(sf)/FPS
		var bp := best_loop_phase(stop, loop, s)
		for ef in range(sf + int(round(0.6*FPS)), int(round(stop.length*FPS)) + 1):
			var e: float = min(float(ef)/FPS, stop.length)
			var dur: float = e - s
			if dur < 0.6 or dur > 2.2: continue
			var end_m: float = abs(motion_at(stop, e))
			var rz: float = root_z(stop,e)-root_z(stop,s)
			# 入口相位匹配 + 结尾停止 + 不太短；最终结尾 2.5 有加分。
			var final_bonus := 0.0 if abs(e - stop.length) < 0.001 else 0.25
			var score: float = bp.score + end_m * 2.5 + final_bonus
			cands.append({"start":s,"end":e,"dur":dur,"phase":bp.phase,"entry":bp.score,"end_motion":end_m,"rootZ":rz,"score":score,"max":bp.max,"max_name":bp.max_name})
	cands.sort_custom(func(a,b): return a.score < b.score)
	print("\nBEST phase-aware candidates")
	for i in range(min(25, cands.size())): print_c("#"+str(i+1), cands[i])
	quit()

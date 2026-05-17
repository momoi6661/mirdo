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
func root_z(anim: Animation, t: float) -> float:
	var rt := find_track(anim, "Root", Animation.TYPE_POSITION_3D)
	return 0.0 if rt < 0 else anim.position_track_interpolate(rt, t).z
func motion_at(anim: Animation, t: float) -> float:
	var dt := 1.0 / FPS
	var a: float = max(0.0, t - dt)
	var b: float = min(anim.length, t + dt)
	if b <= a: return 0.0
	return (root_z(anim, b) - root_z(anim, a)) / (b - a)
func print_c(label: String, d: Dictionary) -> void:
	print(label," start=","%0.4f"%d.start," end=","%0.4f"%d.end," dur=","%0.4f"%d.dur," entry=","%0.3f"%d.entry," endMotion=","%0.3f"%d.end_motion," rootZ=","%0.4f"%d.rootZ," score=","%0.3f"%d.score," max=","%0.2f"%d.max,"@",d.max_name)
func _init():
	var stop: Animation = ResourceLoader.load(STOP_PATH)
	var loop: Animation = ResourceLoader.load(LOOP_PATH)
	if stop == null or loop == null:
		print("LOAD_FAILED"); quit(1); return
	print("STOP length=", stop.length, " loop length=", loop.length)
	var candidates := []
	# loop 的 0 和末尾姿态已闭合；停止动画入口应接 loop 的当前相位，默认比对 loop 0。
	for sf in range(0, int(round(stop.length * FPS)) + 1):
		var s: float = float(sf) / FPS
		if s >= stop.length - 0.20: continue
		for ef in range(sf + int(round(0.35 * FPS)), int(round(stop.length * FPS)) + 1):
			var e: float = min(float(ef) / FPS, stop.length)
			var dur: float = e - s
			if dur < 0.35 or dur > 1.80: continue
			var ps: Dictionary = pose_score(stop, s, loop, 0.0)
			var end_m: float = abs(motion_at(stop, e))
			var rz: float = root_z(stop, e) - root_z(stop, s)
			# 入口姿态优先，结尾速度低优先，长度不要太短。
			var score: float = ps.score + end_m * 3.0 + (0.8 if dur < 0.55 else 0.0)
			candidates.append({"start":s,"end":e,"dur":dur,"entry":ps.score,"end_motion":end_m,"rootZ":rz,"score":score,"max":ps.max,"max_name":ps.max_name})
	candidates.sort_custom(func(a,b): return a.score < b.score)
	print("\nBEST candidates")
	for i in range(min(20, candidates.size())): print_c("#"+str(i+1), candidates[i])
	print("\nTimeline root speed")
	for f in range(0, int(round(stop.length * FPS)) + 1):
		var t: float = min(float(f)/FPS, stop.length)
		if f % 2 == 0 or f == int(round(stop.length*FPS)):
			print("t=","%0.3f"%t," rootZ=","%0.4f"%root_z(stop,t)," speed=","%0.3f"%motion_at(stop,t))
	quit()


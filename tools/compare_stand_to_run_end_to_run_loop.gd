extends SceneTree

const SRC_PATH := "res://resources/animate/Kimodo/run_forward_loop.res"
const LOOP_POSE_TIME := 2.03333333333333 # run_forward_loop_short start/end pose in source
const FIRST_STAND_START := 0.33333333333333
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
func pose_score(anim: Animation, t: float, target: float) -> Dictionary:
	var sum := 0.0; var ws := 0.0; var maxd := 0.0; var maxn := ""
	for i in range(anim.get_track_count()):
		if anim.track_get_type(i) != Animation.TYPE_ROTATION_3D: continue
		var name := bone_name(anim, i)
		if not important.has(name): continue
		var deg := quat_deg(anim.rotation_track_interpolate(i, t), anim.rotation_track_interpolate(i, target))
		var w: float = float(important[name])
		sum += deg * w; ws += w
		if deg > maxd: maxd = deg; maxn = name
	return {"time":t,"local":t-FIRST_STAND_START,"score":sum/max(ws,0.0001),"max":maxd,"max_name":maxn}
func print_d(label: String, d: Dictionary) -> void:
	print(label," source=","%0.4f"%d.time," local=","%0.4f"%d.local," score=","%0.3f"%d.score," max=","%0.2f"%d.max,"@",d.max_name)
func _init():
	var anim: Animation = ResourceLoader.load(SRC_PATH)
	print("Compare candidate end pose to run_forward_loop_short source pose at ", LOOP_POSE_TIME)
	print("First stand_to_run local time = source - ", FIRST_STAND_START)
	var cands := []
	# 只在第一次 stand_to_run 的前半段附近找：local 0.45..1.10，即 source 0.783..1.433。
	for f in range(int(round((FIRST_STAND_START + 0.45) * FPS)), int(round((FIRST_STAND_START + 1.10) * FPS)) + 1):
		var t: float = float(f) / FPS
		cands.append(pose_score(anim, t, LOOP_POSE_TIME))
	cands.sort_custom(func(a,b): return a.score < b.score)
	print("\nBEST around local 0.45..1.10")
	for i in range(min(15, cands.size())): print_d("#"+str(i+1), cands[i])
	print("\nSELECTED fixed checks")
	for local in [0.55,0.58,0.60,0.61,0.633333,0.666667,0.70,0.733333,0.80,0.90,1.0,1.10,1.20,1.333333,1.5,1.7]:
		var t2: float = FIRST_STAND_START + local
		print_d("local_"+str(local), pose_score(anim, t2, LOOP_POSE_TIME))
	quit()

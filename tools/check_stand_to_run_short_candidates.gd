extends SceneTree

const ANIM_PATH := "res://resources/animate/Kimodo/run_forward_loop.res"
const RUN_LOOP_START := 2.03333333333333
const FPS := 30.0

var important := {
	"Hips": 3.0,"Spine": 1.5,"Chest": 1.5,"UpperChest": 1.2,
	"LeftUpperArm": 1.2,"LeftLowerArm": 1.2,"RightUpperArm": 1.2,"RightLowerArm": 1.2,
	"LeftUpperLeg": 3.0,"LeftLowerLeg": 3.0,"LeftFoot": 2.5,
	"RightUpperLeg": 3.0,"RightLowerLeg": 3.0,"RightFoot": 2.5,
}
func bone_name(anim: Animation, i: int) -> String:
	var p := str(anim.track_get_path(i)); var idx := p.rfind(":"); return p.substr(idx + 1) if idx >= 0 else p
func quat_deg(a: Quaternion, b: Quaternion) -> float:
	var d: float = abs(a.dot(b)); d = clamp(d, -1.0, 1.0); return rad_to_deg(2.0 * acos(d))
func score_pose_delta(anim: Animation, t0: float, t1: float) -> float:
	var sum := 0.0; var ws := 0.0
	for i in range(anim.get_track_count()):
		if anim.track_get_type(i) != Animation.TYPE_ROTATION_3D: continue
		var name := bone_name(anim, i)
		if not important.has(name): continue
		var w: float = float(important[name])
		sum += quat_deg(anim.rotation_track_interpolate(i, t0), anim.rotation_track_interpolate(i, t1)) * w
		ws += w
	return sum / max(ws, 0.0001)
func _init():
	var anim: Animation = ResourceLoader.load(ANIM_PATH)
	var root_track := -1
	for i in range(anim.get_track_count()):
		if anim.track_get_type(i) == Animation.TYPE_POSITION_3D and bone_name(anim, i) == "Root": root_track = i
	print("stand_to_run candidates ending at run loop start=", RUN_LOOP_START)
	for dur in [0.533333, 0.566667, 0.600000, 0.633333, 0.666667, 0.700000, 0.733333]:
		var s: float = RUN_LOOP_START - dur
		var root0: Vector3 = anim.position_track_interpolate(root_track, s)
		var root1: Vector3 = anim.position_track_interpolate(root_track, RUN_LOOP_START)
		var dz: float = root1.z - root0.z
		var pose: float = score_pose_delta(anim, s, RUN_LOOP_START)
		print("dur=", "%0.4f" % dur, " start=", "%0.4f" % s, " end=", "%0.4f" % RUN_LOOP_START, " rootZ=", "%0.4f" % dz, " speed=", "%0.4f" % (dz/dur), " poseDelta=", "%0.3f" % pose)
	quit()

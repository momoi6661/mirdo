extends SceneTree

const ANIM_PATH := "res://resources/animate/Kimodo/run_forward_loop.res"
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
func _init():
	var anim: Animation = ResourceLoader.load(ANIM_PATH)
	if anim == null:
		print("LOAD_FAILED"); quit(1); return
	var root_track := -1
	for i in range(anim.get_track_count()):
		if anim.track_get_type(i) == Animation.TYPE_POSITION_3D and bone_name(anim, i) == "Root": root_track = i
	print("ANIM=", ANIM_PATH, " length=", anim.length, " root_track=", root_track)
	print("time rootZ dz poseDelta")
	var prev_root := Vector3.ZERO
	var prev_valid := false
	for f in range(0, int(ceil(2.20 * FPS)) + 1):
		var t: float = min(float(f) / FPS, anim.length)
		var root := Vector3.ZERO
		if root_track >= 0: root = anim.position_track_interpolate(root_track, t)
		var dz: float = 0.0 if not prev_valid else root.z - prev_root.z
		var pose := 0.0; var ws := 0.0
		if f > 0:
			var pt: float = max(0.0, t - 1.0/FPS)
			for i in range(anim.get_track_count()):
				if anim.track_get_type(i) != Animation.TYPE_ROTATION_3D: continue
				var name := bone_name(anim, i)
				if not important.has(name): continue
				var w: float = float(important[name])
				pose += quat_deg(anim.rotation_track_interpolate(i, pt), anim.rotation_track_interpolate(i, t)) * w
				ws += w
			pose = pose / max(ws, 0.0001)
		print("t=", "%0.3f" % t, " rootZ=", "%0.4f" % root.z, " dz=", "%0.4f" % dz, " pose=", "%0.3f" % pose)
		prev_root = root; prev_valid = true
	quit()

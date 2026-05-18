extends SceneTree

const ANIM_PATH := "res://resources/animate/Kimodo/sit_and_stand.res"
const FPS := 30.0

var important := {
	"Hips": 3.0,"Spine": 1.5,"Chest": 1.5,"UpperChest": 1.2,"Head": 1.0,
	"LeftUpperLeg": 2.5,"LeftLowerLeg": 2.5,"LeftFoot": 2.0,
	"RightUpperLeg": 2.5,"RightLowerLeg": 2.5,"RightFoot": 2.0,
	"LeftUpperArm": 1.0,"LeftLowerArm": 1.0,"RightUpperArm": 1.0,"RightLowerArm": 1.0,
}

func bone_name(anim: Animation, i: int) -> String:
	var p := str(anim.track_get_path(i))
	var idx := p.rfind(":")
	return p.substr(idx + 1) if idx >= 0 else p

func find_track(anim: Animation, name: String, typ: int) -> int:
	for i in range(anim.get_track_count()):
		if anim.track_get_type(i) == typ and bone_name(anim, i) == name:
			return i
	return -1

func quat_deg(a: Quaternion, b: Quaternion) -> float:
	var d: float = abs(a.dot(b))
	d = clamp(d, -1.0, 1.0)
	return rad_to_deg(2.0 * acos(d))

func pose_delta(anim: Animation, a: float, b: float) -> float:
	var sum := 0.0
	var ws := 0.0
	for i in range(anim.get_track_count()):
		if anim.track_get_type(i) != Animation.TYPE_ROTATION_3D:
			continue
		var n := bone_name(anim, i)
		if not important.has(n):
			continue
		var w: float = float(important[n])
		sum += quat_deg(anim.rotation_track_interpolate(i, a), anim.rotation_track_interpolate(i, b)) * w
		ws += w
	return sum / max(ws, 0.0001)

func pos(anim: Animation, track: int, t: float) -> Vector3:
	return Vector3.ZERO if track < 0 else anim.position_track_interpolate(track, t)

func _init():
	var anim: Animation = ResourceLoader.load(ANIM_PATH)
	if anim == null:
		print("LOAD_FAILED ", ANIM_PATH)
		quit(1); return
	var root_t := find_track(anim, "Root", Animation.TYPE_POSITION_3D)
	var hips_t := find_track(anim, "Hips", Animation.TYPE_POSITION_3D)
	print("ANIM=", ANIM_PATH, " length=", anim.length, " loop=", anim.loop_mode, " tracks=", anim.get_track_count(), " root_t=", root_t, " hips_t=", hips_t)
	print("time rootY rootZ hipsY poseDelta speedZ")
	var prev_root := pos(anim, root_t, 0.0)
	for f in range(0, int(ceil(anim.length * FPS)) + 1):
		var t: float = min(float(f) / FPS, anim.length)
		if f % 3 != 0 and f != int(ceil(anim.length * FPS)):
			continue
		var dt: float = 1.0 / FPS
		var p_root := pos(anim, root_t, t)
		var p_hips := pos(anim, hips_t, t)
		var a: float = max(0.0, t - dt)
		var pd: float = 0.0 if t <= 0.0 else pose_delta(anim, a, t)
		var rz_speed: float = 0.0 if t <= 0.0 else (p_root.z - pos(anim, root_t, a).z) / max(t - a, 0.0001)
		print("t=", "%0.3f" % t, " rootY=", "%0.4f" % p_root.y, " rootZ=", "%0.4f" % p_root.z, " hipsY=", "%0.4f" % p_hips.y, " pose=", "%0.3f" % pd, " speedZ=", "%0.3f" % rz_speed)
	quit()


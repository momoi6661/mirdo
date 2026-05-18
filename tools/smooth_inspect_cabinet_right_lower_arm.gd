extends SceneTree

const PATH := "res://resources/animate/Kimodo/inspect_cabinet.res"
const START := 3.2
const MID := 3.45
const END := 3.7
const EPS := 0.00001

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

func _init():
	var anim: Animation = ResourceLoader.load(PATH, "Animation", ResourceLoader.CACHE_MODE_IGNORE)
	if anim == null:
		print("LOAD_FAILED ", PATH)
		quit(1); return
	var track := find_track(anim, "RightLowerArm", Animation.TYPE_ROTATION_3D)
	if track < 0:
		print("TRACK_NOT_FOUND RightLowerArm")
		quit(1); return

	var q_start: Quaternion = anim.rotation_track_interpolate(track, START)
	var q_end: Quaternion = anim.rotation_track_interpolate(track, END)
	var q_mid: Quaternion = q_start.slerp(q_end, 0.5).normalized()
	var before_keys := anim.track_get_key_count(track)
	var removed := 0

	# Remove keys inside (START, END), keep boundary outside intact.
	for k in range(anim.track_get_key_count(track) - 1, -1, -1):
		var t := anim.track_get_key_time(track, k)
		if t > START + EPS and t < END - EPS:
			anim.track_remove_key(track, k)
			removed += 1

	# Ensure smooth sparse keys.
	anim.track_insert_key(track, START, q_start)
	anim.track_insert_key(track, MID, q_mid)
	anim.track_insert_key(track, END, q_end)
	anim.track_set_interpolation_type(track, Animation.INTERPOLATION_CUBIC)

	var err := ResourceSaver.save(anim, PATH)
	print("SAVE err=", err, " path=", PATH)
	print("track=", track, " RightLowerArm before_keys=", before_keys, " removed=", removed, " after_keys=", anim.track_get_key_count(track))
	print("start_to_mid=", "%0.3f" % quat_deg(q_start, q_mid), " mid_to_end=", "%0.3f" % quat_deg(q_mid, q_end), " start_to_end=", "%0.3f" % quat_deg(q_start, q_end))
	quit(err)

extends SceneTree

const PATH := "res://resources/animate/Kimodo/run_forward_loop_short.res"
const EPS := 0.0005

func track_name(anim: Animation, i: int) -> String:
	var p := str(anim.track_get_path(i))
	var idx := p.rfind(":")
	return p.substr(idx + 1) if idx >= 0 else p

func quat_gap(a: Quaternion, b: Quaternion) -> float:
	var d: float = abs(a.dot(b))
	d = clamp(d, -1.0, 1.0)
	return 2.0 * acos(d)

func values_close(typ: int, a, b) -> bool:
	if typ == Animation.TYPE_ROTATION_3D:
		return quat_gap(a, b) < deg_to_rad(0.25)
	if typ == Animation.TYPE_POSITION_3D or typ == Animation.TYPE_SCALE_3D:
		var va: Vector3 = a
		var vb: Vector3 = b
		return va.distance_to(vb) < EPS
	return a == b

func _init():
	var anim: Animation = ResourceLoader.load(PATH, "Animation", ResourceLoader.CACHE_MODE_IGNORE)
	if anim == null:
		print("LOAD_FAILED ", PATH)
		quit(1)
		return

	anim.loop_mode = Animation.LOOP_LINEAR
	var removed := 0
	var kept_root := 0
	var checked := 0

	for i in range(anim.get_track_count()):
		var kc := anim.track_get_key_count(i)
		if kc < 2:
			continue
		var typ := anim.track_get_type(i)
		var name := track_name(anim, i)
		anim.track_set_interpolation_loop_wrap(i, true)

		# Root position needs the final forward displacement for root motion.
		if typ == Animation.TYPE_POSITION_3D and name == "Root":
			kept_root += 1
			continue

		var last_idx := kc - 1
		var last_time := anim.track_get_key_time(i, last_idx)
		if abs(last_time - anim.length) > 0.002:
			continue

		checked += 1
		var first_val = anim.track_get_key_value(i, 0)
		var last_val = anim.track_get_key_value(i, last_idx)
		# If the endpoint is an explicit duplicate/near-duplicate of first frame, remove it.
		if values_close(typ, first_val, last_val):
			anim.track_remove_key(i, last_idx)
			removed += 1

	var err := ResourceSaver.save(anim, PATH)
	print("SAVE err=", err, " path=", PATH)
	print("length=", anim.length, " checked_endpoint_tracks=", checked, " removed_duplicate_end_keys=", removed, " kept_root_tracks=", kept_root)
	quit(err)

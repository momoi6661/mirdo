extends SceneTree

const LOOP_PATHS := [
	"res://resources/animate/Kimodo/walk_forward_loop_v2.res",
	"res://resources/animate/Kimodo/run_forward_loop_v2.res",
]
const EPS := 0.00001

func track_name(anim: Animation, i: int) -> String:
	var p := str(anim.track_get_path(i))
	var idx := p.rfind(":")
	return p.substr(idx + 1) if idx >= 0 else p

func force_close_loop(path: String) -> Error:
	var anim: Animation = ResourceLoader.load(path, "Animation", ResourceLoader.CACHE_MODE_IGNORE)
	if anim == null:
		print("LOAD_FAILED ", path)
		return ERR_CANT_OPEN
	anim.loop_mode = Animation.LOOP_LINEAR
	for i in range(anim.get_track_count()):
		var key_count := anim.track_get_key_count(i)
		if key_count <= 0:
			continue
		var typ := anim.track_get_type(i)
		var name := track_name(anim, i)
		# Root position must keep forward displacement for RootMotion.
		if typ == Animation.TYPE_POSITION_3D and name == "Root":
			continue
		var first_value = anim.track_get_key_value(i, 0)
		var last_idx := key_count - 1
		var last_time := anim.track_get_key_time(i, last_idx)
		if abs(last_time - anim.length) > EPS:
			anim.track_insert_key(i, anim.length, first_value)
		else:
			anim.track_set_key_value(i, last_idx, first_value)
		anim.track_set_interpolation_loop_wrap(i, true)
	var err := ResourceSaver.save(anim, path)
	print("FORCE_CLOSE err=", err, " path=", path, " length=", anim.length, " tracks=", anim.get_track_count())
	return err

func _init():
	var final_err := OK
	for path in LOOP_PATHS:
		var err := force_close_loop(path)
		if err != OK:
			final_err = err
	quit(final_err)

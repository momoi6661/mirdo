extends SceneTree

const SRC_PATH := "res://resources/animate/Kimodo/run_forward_loop.res"
const OUT_PATH := "res://resources/animate/Kimodo/run_forward_loop_short.res"
const BACKUP_PATH := "res://resources/animate/Kimodo/run_forward_loop_short_before_natural_smooth.res"
const CUT_START := 2.06666666666667
const CUT_END := 2.9
const EPS := 0.00001

func track_name(anim: Animation, i: int) -> String:
	var p := str(anim.track_get_path(i))
	var idx := p.rfind(":")
	return p.substr(idx + 1) if idx >= 0 else p
func key_range(anim: Animation, track: int, t: float) -> Array:
	var n := anim.track_get_key_count(track)
	if n <= 0: return [0,0,0.0]
	if t <= anim.track_get_key_time(track,0): return [0,0,0.0]
	if t >= anim.track_get_key_time(track,n-1): return [n-1,n-1,0.0]
	var lo := 0; var hi := n - 1
	while hi - lo > 1:
		var mid := int((lo + hi) / 2)
		if anim.track_get_key_time(track, mid) <= t: lo = mid
		else: hi = mid
	var t0 := anim.track_get_key_time(track, lo); var t1 := anim.track_get_key_time(track, hi)
	var a: float = 0.0 if abs(t1-t0)<EPS else (t-t0)/(t1-t0)
	return [lo,hi,clamp(a,0.0,1.0)]
func sample_value(anim: Animation, track: int, t: float):
	var typ := anim.track_get_type(track)
	if typ == Animation.TYPE_POSITION_3D: return anim.position_track_interpolate(track,t)
	if typ == Animation.TYPE_ROTATION_3D: return anim.rotation_track_interpolate(track,t)
	if typ == Animation.TYPE_SCALE_3D: return anim.scale_track_interpolate(track,t)
	var r := key_range(anim,track,t)
	return anim.track_get_key_value(track,int(r[0]))
func insert_unique_key(anim: Animation, track: int, time: float, value, transition: float = 1.0) -> void:
	for k in range(anim.track_get_key_count(track)):
		if abs(anim.track_get_key_time(track,k)-time)<EPS: return
	anim.track_insert_key(track,time,value,transition)
func _init():
	var old: Animation = ResourceLoader.load(OUT_PATH,"Animation",ResourceLoader.CACHE_MODE_IGNORE)
	if old != null: ResourceSaver.save(old,BACKUP_PATH)
	var src: Animation = ResourceLoader.load(SRC_PATH)
	if src == null:
		print("LOAD_FAILED ", SRC_PATH); quit(1); return
	var dur: float = CUT_END - CUT_START
	var out := Animation.new()
	out.length = dur
	out.loop_mode = Animation.LOOP_LINEAR
	out.step = src.step
	for i in range(src.get_track_count()):
		var typ := src.track_get_type(i)
		var dst := out.add_track(typ)
		out.track_set_path(dst, src.track_get_path(i))
		out.track_set_interpolation_type(dst, src.track_get_interpolation_type(i))
		out.track_set_interpolation_loop_wrap(dst, true)
		out.track_set_enabled(dst, src.track_is_enabled(i))
		var name := track_name(src,i)
		var root_offset = null
		if typ == Animation.TYPE_POSITION_3D and name == "Root": root_offset = sample_value(src,i,CUT_START)
		var v0 = sample_value(src,i,CUT_START)
		var v1 = sample_value(src,i,CUT_END)
		if root_offset != null:
			v0 = v0 - root_offset
			v1 = v1 - root_offset
		# Natural boundaries: do not force last pose to first pose.
		insert_unique_key(out,dst,0.0,v0)
		for k in range(src.track_get_key_count(i)):
			var kt := src.track_get_key_time(i,k)
			if kt <= CUT_START + EPS or kt >= CUT_END - EPS: continue
			var val = src.track_get_key_value(i,k)
			if root_offset != null: val = val - root_offset
			insert_unique_key(out,dst,kt-CUT_START,val,src.track_get_key_transition(i,k))
		insert_unique_key(out,dst,dur,v1)
	var err := ResourceSaver.save(out,OUT_PATH)
	print("SAVE err=",err," path=",OUT_PATH," cut=",CUT_START,"..",CUT_END," length=",dur," backup=",BACKUP_PATH)
	quit(err)

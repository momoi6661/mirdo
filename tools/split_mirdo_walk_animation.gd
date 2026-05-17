extends SceneTree

const SOURCE := "res://resources/animate/Kimodo/walk.res"
const OUT_STAND_TO_WALK := "res://resources/animate/Kimodo/mirdo_stand_to_walk.res"
const OUT_WALK_FORWARD := "res://resources/animate/Kimodo/mirdo_walk_forward_loop.res"
const OUT_WALK_TO_STOP := "res://resources/animate/Kimodo/mirdo_walk_to_stop.res"

# Re-split by the actual 10.041667s timeline.
# Root motion is almost still until ~2.0s, steady walk until ~8.5s, then decelerates to stop.
const STAND_TO_WALK_START := 0.0
const STAND_TO_WALK_END := 2.0
const WALK_FORWARD_START := 2.0
const WALK_FORWARD_END := 8.5
const WALK_TO_STOP_START := 8.5
const WALK_TO_STOP_END := -1.0 # use exact animation length

# Only transitions are shortened.
const STAND_TO_WALK_TARGET := 1.5
const WALK_TO_STOP_TARGET := 1.5

func _initialize() -> void:
	var src := ResourceLoader.load(SOURCE)
	if src == null or not (src is Animation):
		push_error("Failed to load Animation: " + SOURCE)
		quit(1)
		return
	var anim := src as Animation
	var stop_end := anim.length if WALK_TO_STOP_END < 0.0 else WALK_TO_STOP_END
	var walk_target := WALK_FORWARD_END - WALK_FORWARD_START
	print("Source: ", SOURCE, " length=", anim.length, " tracks=", anim.get_track_count())
	print("Segments cover: ", STAND_TO_WALK_START, "-", STAND_TO_WALK_END, ", ", WALK_FORWARD_START, "-", WALK_FORWARD_END, ", ", WALK_TO_STOP_START, "-", stop_end)

	_save_slice(anim, STAND_TO_WALK_START, STAND_TO_WALK_END, STAND_TO_WALK_TARGET, OUT_STAND_TO_WALK, "stand_to_walk", false)
	_save_slice(anim, WALK_FORWARD_START, WALK_FORWARD_END, walk_target, OUT_WALK_FORWARD, "walk_forward_loop", true)
	_save_slice(anim, WALK_TO_STOP_START, stop_end, WALK_TO_STOP_TARGET, OUT_WALK_TO_STOP, "walk_to_stop", false)

	print("Done.")
	quit(0)

func _save_slice(src: Animation, start_time: float, end_time: float, target_length: float, out_path: String, anim_name: String, looped: bool) -> void:
	var dst := Animation.new()
	dst.resource_name = anim_name
	dst.length = target_length
	dst.loop_mode = Animation.LOOP_LINEAR if looped else Animation.LOOP_NONE

	var src_span := maxf(0.001, end_time - start_time)
	var scale := target_length / src_span
	var copied_keys := 0

	for ti in range(src.get_track_count()):
		var ttype := src.track_get_type(ti)
		var nti := dst.add_track(ttype)
		dst.track_set_path(nti, src.track_get_path(ti))
		dst.track_set_enabled(nti, src.track_is_enabled(ti))
		dst.track_set_interpolation_type(nti, src.track_get_interpolation_type(ti))
		dst.track_set_interpolation_loop_wrap(nti, src.track_get_interpolation_loop_wrap(ti))

		var key_count := src.track_get_key_count(ti)
		for ki in range(key_count):
			var kt := src.track_get_key_time(ti, ki)
			# Inclusive start, exclusive end except for the final segment.
			var is_final_end := is_equal_approx(end_time, src.length)
			var in_range := kt >= start_time and (kt < end_time or (is_final_end and kt <= end_time))
			if not in_range:
				continue
			var nt := (kt - start_time) * scale
			var val = src.track_get_key_value(ti, ki)
			var trans := src.track_get_key_transition(ti, ki)
			dst.track_insert_key(nti, nt, val, trans)
			copied_keys += 1

		# If a track had no exact key at the segment boundary, add nearest boundary keys
		# so the sliced animation starts and ends cleanly.
		_ensure_boundary_key(src, dst, ti, nti, start_time, 0.0)
		_ensure_boundary_key(src, dst, ti, nti, end_time, target_length)

	var err := ResourceSaver.save(dst, out_path)
	if err != OK:
		push_error("Failed to save " + out_path + ": " + str(err))
	else:
		print("Saved: ", out_path, " length=", target_length, " source=", start_time, "-", end_time, " copied_keys=", copied_keys)

func _ensure_boundary_key(src: Animation, dst: Animation, src_track: int, dst_track: int, source_time: float, target_time: float) -> void:
	if dst.track_get_key_count(dst_track) <= 0:
		_insert_nearest_key(src, dst, src_track, dst_track, source_time, target_time)
		return

	for ki in range(dst.track_get_key_count(dst_track)):
		if absf(dst.track_get_key_time(dst_track, ki) - target_time) < 0.0001:
			return
	_insert_nearest_key(src, dst, src_track, dst_track, source_time, target_time)

func _insert_nearest_key(src: Animation, dst: Animation, src_track: int, dst_track: int, source_time: float, target_time: float) -> void:
	var key_count := src.track_get_key_count(src_track)
	if key_count <= 0:
		return
	var best := 0
	var best_dist := INF
	for ki in range(key_count):
		var d := absf(src.track_get_key_time(src_track, ki) - source_time)
		if d < best_dist:
			best_dist = d
			best = ki
	var val = src.track_get_key_value(src_track, best)
	var trans := src.track_get_key_transition(src_track, best)
	dst.track_insert_key(dst_track, target_time, val, trans)

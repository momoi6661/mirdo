extends SceneTree

const PATH := "res://resources/animate/Kimodo/mirdo_walk_forward_loop.res"
const NEW_LENGTH := 4.0

func _initialize() -> void:
	var anim := ResourceLoader.load(PATH) as Animation
	if anim == null:
		push_error("Failed to load: " + PATH)
		quit(1)
		return

	var before_length := anim.length
	var before_counts := []
	for i in range(anim.get_track_count()):
		before_counts.append(anim.track_get_key_count(i))

	# Only shorten playback length. Do not move, delete, or retime keys.
	anim.length = NEW_LENGTH
	anim.loop_mode = Animation.LOOP_LINEAR

	var err := ResourceSaver.save(anim, PATH)
	if err != OK:
		push_error("Failed to save: " + str(err))
		quit(1)
		return

	var reloaded := ResourceLoader.load(PATH) as Animation
	var after_counts := []
	for i in range(reloaded.get_track_count()):
		after_counts.append(reloaded.track_get_key_count(i))

	var changed_counts := 0
	for i in range(before_counts.size()):
		if before_counts[i] != after_counts[i]:
			changed_counts += 1

	print("Updated ", PATH)
	print("length: ", before_length, " -> ", reloaded.length)
	print("tracks: ", reloaded.get_track_count())
	print("tracks_with_changed_key_count: ", changed_counts)
	for i in range(reloaded.get_track_count()):
		var p := str(reloaded.track_get_path(i))
		if p.find("GeneralSkeleton:Root") >= 0:
			print("root_track=", i, " keys=", reloaded.track_get_key_count(i), " first=", reloaded.track_get_key_time(i, 0), " last=", reloaded.track_get_key_time(i, reloaded.track_get_key_count(i)-1))
	quit(0)

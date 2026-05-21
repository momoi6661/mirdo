extends SceneTree

var failures: Array[String] = []

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	var audio_manager_script := load("res://scripts/audio/audio_manager.gd") as Script
	if audio_manager_script == null:
		failures.append("AudioManager script should exist and compile")
	else:
		var manager := audio_manager_script.new() as Node
		if manager == null:
			failures.append("AudioManager should instantiate as Node")
		else:
			if not manager.has_method("play_menu_music"):
				failures.append("AudioManager should expose play_menu_music")
			if not manager.has_method("play_game_music"):
				failures.append("AudioManager should expose play_game_music")
			if not manager.has_method("stop_music"):
				failures.append("AudioManager should expose stop_music")
			if not manager.has_method("sync_music_pause_with_tree"):
				failures.append("AudioManager should expose sync_music_pause_with_tree")
			if float(manager.get("menu_music_volume_db")) > -6.0:
				failures.append("Menu music default volume should be quieter than -6 dB")
			if float(manager.get("game_music_volume_db")) > -6.0:
				failures.append("Game music default volume should be quieter than -6 dB")
			manager.queue_free()

	var audio_manager_scene := load("res://scripts/audio/AudioManager.tscn") as PackedScene
	if audio_manager_scene == null:
		failures.append("AudioManager scene should load")
	else:
		var scene_manager := audio_manager_scene.instantiate() as Node
		root.add_child(scene_manager)
		await process_frame
		var player := scene_manager.get_node_or_null("BGMPlayer") as AudioStreamPlayer
		if player == null:
			failures.append("AudioManager scene should contain BGMPlayer")
		elif scene_manager.has_method("sync_music_pause_with_tree"):
			paused = true
			scene_manager.call("sync_music_pause_with_tree")
			if not player.stream_paused:
				failures.append("BGMPlayer should pause when SceneTree is paused")
			paused = false
			scene_manager.call("sync_music_pause_with_tree")
			if player.stream_paused:
				failures.append("BGMPlayer should resume when SceneTree is unpaused")
		scene_manager.queue_free()

	if not ResourceLoader.exists("res://Audio/music/menu_mita_dream_loop.wav"):
		failures.append("Menu music resource should exist")
	if not ResourceLoader.exists("res://Audio/music/game_mita_room_loop.wav"):
		failures.append("Game music resource should exist")

	var menu_stream := load("res://Audio/music/menu_mita_dream_loop.wav") as AudioStream
	if menu_stream == null:
		failures.append("Menu music should load as AudioStream")
	elif menu_stream is AudioStreamWAV and (menu_stream as AudioStreamWAV).loop_mode != AudioStreamWAV.LOOP_FORWARD:
		failures.append("Menu music should be configured to loop forward")

	var game_stream := load("res://Audio/music/game_mita_room_loop.wav") as AudioStream
	if game_stream == null:
		failures.append("Game music should load as AudioStream")
	elif game_stream is AudioStreamWAV and (game_stream as AudioStreamWAV).loop_mode != AudioStreamWAV.LOOP_FORWARD:
		failures.append("Game music should be configured to loop forward")

	var project_config := FileAccess.get_file_as_string("res://project.godot")
	if project_config.find("AudioManager") == -1:
		failures.append("AudioManager should be registered as an autoload")

	if failures.is_empty():
		print("[PASS] audio manager music resources")
		quit(0)
	else:
		for failure in failures:
			push_error(failure)
		quit(1)

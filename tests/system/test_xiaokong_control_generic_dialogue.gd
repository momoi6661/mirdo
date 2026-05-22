extends SceneTree

var _failures: Array[String] = []

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	await _test_control_component_binds_generic_mirdo_dialogue_component()
	await _test_control_component_auto_binds_mirdo_group_dialogue_component()
	_finish()

func _test_control_component_binds_generic_mirdo_dialogue_component() -> void:
	var script: Script = load("res://controllers/compoents/xiaokong_control_component.gd") as Script
	_expect(script != null, "XiaokongControlComponent script should load")
	if script == null:
		return
	var host := Node.new()
	root.add_child(host)
	var control := Node.new()
	control.set_script(script)
	host.add_child(control)
	var target := Node.new()
	target.name = "MirdoCharacter"
	host.add_child(target)
	var components := Node.new()
	components.name = "Components"
	target.add_child(components)
	var dialogue := _GenericMirdoDialogue.new()
	dialogue.name = "AIDialogueComponent"
	components.add_child(dialogue)
	control.set("_target", target)
	control.call("_bind_dialogue_component_from_target")
	var bound: Variant = control.get("_dialogue_component")
	_expect(bound == dialogue, "control component should bind generic Mirdo dialogue component, not only Xiaokong dialogue")
	var ok: bool = control.call("send_dialogue_text", "老师测试一句")
	_expect(ok, "control component should send text through generic Mirdo dialogue component")
	_expect(dialogue.sent_texts.size() == 1, "generic dialogue should receive one player text")
	if dialogue.sent_texts.size() > 0:
		_expect(String(dialogue.sent_texts[0]) == "老师测试一句", "sent text should be forwarded unchanged")
	host.queue_free()
	await process_frame

func _test_control_component_auto_binds_mirdo_group_dialogue_component() -> void:
	var script: Script = load("res://controllers/compoents/xiaokong_control_component.gd") as Script
	_expect(script != null, "XiaokongControlComponent script should load for Mirdo auto-bind")
	if script == null:
		return
	var host := Node.new()
	root.add_child(host)
	var control := Node.new()
	control.set_script(script)
	host.add_child(control)
	var target := Node.new()
	target.name = "MirdoCharacter"
	target.add_to_group(&"Mirdo")
	host.add_child(target)
	var components := Node.new()
	components.name = "Components"
	target.add_child(components)
	var dialogue := _GenericMirdoDialogue.new()
	dialogue.name = "AIDialogueComponent"
	components.add_child(dialogue)
	var bound_ok: bool = control.call("_deferred_bind_target")
	_expect(bound_ok, "control component should auto-bind Mirdo group target")
	_expect(control.get("_target") == target, "auto-bound target should be MirdoCharacter")
	_expect(control.get("_dialogue_component") == dialogue, "auto-bind should bind Mirdo dialogue component")
	host.queue_free()
	await process_frame

func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)

func _finish() -> void:
	if _failures.is_empty():
		print("[PASS] xiaokong control generic dialogue")
		quit(0)
	else:
		for failure in _failures:
			push_error(failure)
		quit(1)

class _GenericMirdoDialogue:
	extends Node
	signal dialogue_requested(payload: Dictionary)
	signal dialogue_chunk_received(chunk: String)
	signal dialogue_stream_finished(dialogue_text: String)
	signal dialogue_completed(report: Dictionary)
	signal dialogue_failed(error_text: String)
	var sent_texts: Array[String] = []
	func send_player_text(text: String, _given_item: String = "") -> Dictionary:
		sent_texts.append(text)
		var payload := {"player_text": text, "context": {"request_source": "player"}}
		dialogue_requested.emit(payload.duplicate(true))
		return {"ok": true, "payload": payload}

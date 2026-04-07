extends Control

@onready var status_label: Label = $VBoxContainer/StatusLabel
@onready var dialogue_box: RichTextLabel = $VBoxContainer/DialogueBox
@onready var input_edit: LineEdit = $VBoxContainer/HBoxContainer/InputEdit
@onready var send_button: Button = $VBoxContainer/HBoxContainer/SendButton
@export var action_router_path: NodePath
@onready var action_router: Node = get_node_or_null(action_router_path)
@export var state_component_path: NodePath
@onready var state_component: Node = get_node_or_null(state_component_path)

var ai_manager: AIManager

func _ready() -> void:
	ai_manager = AIManager.new()
	add_child(ai_manager)

	send_button.pressed.connect(_on_send_pressed)
	input_edit.text_submitted.connect(_on_send_submitted)

	ai_manager.on_ai_stream_chunk_received.connect(_on_ai_stream_chunk)
	ai_manager.on_ai_response_completed.connect(_on_ai_response_completed)
	ai_manager.on_ai_request_error.connect(_on_ai_request_error)


func _on_send_submitted(_new_text: String) -> void:
	_on_send_pressed()


func _on_send_pressed() -> void:
	var text := input_edit.text.strip_edges()
	if text.is_empty():
		return

	input_edit.text = ""
	input_edit.editable = false
	send_button.disabled = true

	status_label.text = "状态: 请求中..."
	dialogue_box.text += "\n\n[玩家]: " + text + "\n[小空]: "

	if text.begins_with("/debug"):
		var debug_text := text.substr(6).strip_edges()
		if debug_text.is_empty():
			debug_text = "Subtitle debug test"
		ai_manager.send_subtitle_test_stream(debug_text, "ai_test_ui")
		return

	var hunger := 50
	var thirst := 50
	var mood := 50
	var favor := 20
	if state_component != null and state_component.has_method("build_ai_stats"):
		var stats_value: Variant = state_component.call("build_ai_stats")
		if stats_value is Dictionary:
			var stats := stats_value as Dictionary
			hunger = int(stats.get("hunger", hunger))
			thirst = int(stats.get("thirst", thirst))
			mood = int(stats.get("mood", mood))
			favor = int(stats.get("favor", favor))

	ai_manager.send_interaction_stream(1, 480, hunger, thirst, mood, favor, text)


func _on_ai_stream_chunk(chunk: String) -> void:
	status_label.text = "状态: 流式返回中..."
	dialogue_box.text += chunk
	var scrollbar := dialogue_box.get_v_scroll_bar()
	if scrollbar != null:
		scrollbar.value = scrollbar.max_value


func _on_ai_response_completed(final_data: Dictionary) -> void:
	status_label.text = "状态: 完成"
	input_edit.editable = true
	send_button.disabled = false
	input_edit.grab_focus()

	print("===============================")
	print("收到完整 AI 数据: ", final_data)
	if final_data.has("emotion"):
		print("emotion: ", final_data["emotion"])
	if final_data.has("action"):
		print("action: ", final_data["action"])
	if action_router != null and action_router.has_method("apply_ai_response"):
		var route_summary = action_router.call("apply_ai_response", final_data)
		print("route summary: ", route_summary)
	print("===============================")


func _on_ai_request_error(error_msg: String) -> void:
	status_label.text = "状态: 错误"
	dialogue_box.text += "\n[系统提示: " + error_msg + "]"
	input_edit.editable = true
	send_button.disabled = false

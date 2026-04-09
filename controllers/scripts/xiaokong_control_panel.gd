extends PanelContainer

const ACTIONS: PackedStringArray = [
	"Idle",
	"StandingGreeting",
	"Drinking",
	"Salute",
	"Kiss",
	"SittingIdle",
	"Laying",
	"LeftTurn",
	"RightTurn",
]

@onready var target_path_input: LineEdit = $Margin/VBox/TargetRow/TargetPathInput
@onready var bind_target_button: Button = $Margin/VBox/TargetRow/BindTargetButton
@onready var target_label: Label = $Margin/VBox/TargetRow/TargetLabel
@onready var pos_x: SpinBox = $Margin/VBox/PositionRow/PosX
@onready var pos_y: SpinBox = $Margin/VBox/PositionRow/PosY
@onready var pos_z: SpinBox = $Margin/VBox/PositionRow/PosZ
@onready var go_position_button: Button = $Margin/VBox/PositionRow/GoPositionButton
@onready var action_option: OptionButton = $Margin/VBox/ActionRow/ActionOption
@onready var play_action_button: Button = $Margin/VBox/ActionRow/PlayActionButton
@onready var pick_nav_button: CheckButton = $Margin/VBox/PickRow/PickNavButton
@onready var stop_nav_button: Button = $Margin/VBox/PickRow/StopNavButton
@onready var dialogue_input: LineEdit = $Margin/VBox/DialogueRow/DialogueInput
@onready var send_dialogue_button: Button = $Margin/VBox/DialogueRow/SendDialogueButton
@onready var subtitle_queue_input: LineEdit = get_node_or_null("Margin/VBox/SubtitleQueueRow/SubtitleQueueInput") as LineEdit
@onready var queue_subtitle_button: Button = get_node_or_null("Margin/VBox/SubtitleQueueRow/QueueSubtitleButton") as Button
@onready var clear_subtitle_queue_button: Button = get_node_or_null("Margin/VBox/SubtitleQueueRow/ClearSubtitleQueueButton") as Button
@onready var dialogue_reply_label: Label = $Margin/VBox/DialogueReplyLabel
@onready var status_label: Label = $Margin/VBox/StatusLabel
@onready var probe_model_button: Button = get_node_or_null("Margin/VBox/AIDebugRow/ProbeModelButton") as Button
@onready var clear_debug_button: Button = get_node_or_null("Margin/VBox/AIDebugRow/ClearDebugButton") as Button
@onready var probe_status_label: Label = get_node_or_null("Margin/VBox/ProbeStatusLabel") as Label
@onready var request_payload_text: TextEdit = get_node_or_null("Margin/VBox/RequestPayloadText") as TextEdit
@onready var response_payload_text: TextEdit = get_node_or_null("Margin/VBox/ResponsePayloadText") as TextEdit

var _controller: Node

func _ready() -> void:
	_populate_actions()
	_ensure_subtitle_queue_controls()
	_ensure_debug_controls()
	_bind_signals()
	if target_path_input != null:
		target_path_input.editable = false
	if target_label != null:
		target_label.text = "Target (auto)"
	if bind_target_button != null:
		bind_target_button.visible = false

func _ensure_subtitle_queue_controls() -> void:
	if subtitle_queue_input != null and queue_subtitle_button != null and clear_subtitle_queue_button != null:
		return

	var vbox := get_node_or_null("Margin/VBox") as VBoxContainer
	if vbox == null:
		return

	var row := get_node_or_null("Margin/VBox/SubtitleQueueRow") as HBoxContainer
	if row == null:
		row = HBoxContainer.new()
		row.name = "SubtitleQueueRow"
		row.add_theme_constant_override("separation", 6)
		vbox.add_child(row)
		if dialogue_reply_label != null:
			vbox.move_child(row, dialogue_reply_label.get_index())

	if subtitle_queue_input == null:
		subtitle_queue_input = get_node_or_null("Margin/VBox/SubtitleQueueRow/SubtitleQueueInput") as LineEdit
	if subtitle_queue_input == null:
		subtitle_queue_input = LineEdit.new()
		subtitle_queue_input.name = "SubtitleQueueInput"
		subtitle_queue_input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		subtitle_queue_input.placeholder_text = "Queue world subtitle text..."
		row.add_child(subtitle_queue_input)

	if queue_subtitle_button == null:
		queue_subtitle_button = get_node_or_null("Margin/VBox/SubtitleQueueRow/QueueSubtitleButton") as Button
	if queue_subtitle_button == null:
		queue_subtitle_button = Button.new()
		queue_subtitle_button.name = "QueueSubtitleButton"
		queue_subtitle_button.text = "Queue"
		row.add_child(queue_subtitle_button)

	if clear_subtitle_queue_button == null:
		clear_subtitle_queue_button = get_node_or_null("Margin/VBox/SubtitleQueueRow/ClearSubtitleQueueButton") as Button
	if clear_subtitle_queue_button == null:
		clear_subtitle_queue_button = Button.new()
		clear_subtitle_queue_button.name = "ClearSubtitleQueueButton"
		clear_subtitle_queue_button.text = "Clear"
		row.add_child(clear_subtitle_queue_button)

func _ensure_debug_controls() -> void:
	var vbox := get_node_or_null("Margin/VBox") as VBoxContainer
	if vbox == null:
		return

	var debug_row := get_node_or_null("Margin/VBox/AIDebugRow") as HBoxContainer
	if debug_row == null:
		debug_row = HBoxContainer.new()
		debug_row.name = "AIDebugRow"
		debug_row.add_theme_constant_override("separation", 6)
		vbox.add_child(debug_row)

	if probe_model_button == null:
		probe_model_button = get_node_or_null("Margin/VBox/AIDebugRow/ProbeModelButton") as Button
	if probe_model_button == null:
		probe_model_button = Button.new()
		probe_model_button.name = "ProbeModelButton"
		probe_model_button.text = "Probe Model"
		debug_row.add_child(probe_model_button)

	if clear_debug_button == null:
		clear_debug_button = get_node_or_null("Margin/VBox/AIDebugRow/ClearDebugButton") as Button
	if clear_debug_button == null:
		clear_debug_button = Button.new()
		clear_debug_button.name = "ClearDebugButton"
		clear_debug_button.text = "Clear Debug"
		debug_row.add_child(clear_debug_button)

	if probe_status_label == null:
		probe_status_label = get_node_or_null("Margin/VBox/ProbeStatusLabel") as Label
	if probe_status_label == null:
		probe_status_label = Label.new()
		probe_status_label.name = "ProbeStatusLabel"
		probe_status_label.text = "Probe: idle"
		vbox.add_child(probe_status_label)

	var request_title := get_node_or_null("Margin/VBox/RequestPayloadTitle") as Label
	if request_title == null:
		request_title = Label.new()
		request_title.name = "RequestPayloadTitle"
		request_title.text = "Request Payload (Transparent)"
		vbox.add_child(request_title)

	if request_payload_text == null:
		request_payload_text = get_node_or_null("Margin/VBox/RequestPayloadText") as TextEdit
	if request_payload_text == null:
		request_payload_text = TextEdit.new()
		request_payload_text.name = "RequestPayloadText"
		request_payload_text.custom_minimum_size = Vector2(0.0, 110.0)
		request_payload_text.size_flags_vertical = Control.SIZE_EXPAND_FILL
		request_payload_text.editable = false
		request_payload_text.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
		request_payload_text.text = "{}"
		vbox.add_child(request_payload_text)

	var response_title := get_node_or_null("Margin/VBox/ResponsePayloadTitle") as Label
	if response_title == null:
		response_title = Label.new()
		response_title.name = "ResponsePayloadTitle"
		response_title.text = "Response Payload"
		vbox.add_child(response_title)

	if response_payload_text == null:
		response_payload_text = get_node_or_null("Margin/VBox/ResponsePayloadText") as TextEdit
	if response_payload_text == null:
		response_payload_text = TextEdit.new()
		response_payload_text.name = "ResponsePayloadText"
		response_payload_text.custom_minimum_size = Vector2(0.0, 120.0)
		response_payload_text.size_flags_vertical = Control.SIZE_EXPAND_FILL
		response_payload_text.editable = false
		response_payload_text.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
		response_payload_text.text = "{}"
		vbox.add_child(response_payload_text)

func setup(controller: Node) -> void:
	_controller = controller

func refresh_target_path(path_text: String) -> void:
	if target_path_input != null:
		if path_text.is_empty():
			target_path_input.text = "(auto group: Xiaokong)"
		else:
			target_path_input.text = path_text

func sync_pick_mode(enabled: bool) -> void:
	if pick_nav_button != null:
		pick_nav_button.button_pressed = enabled

func set_status(text: String) -> void:
	if status_label != null:
		status_label.text = text

func _populate_actions() -> void:
	action_option.clear()
	for action_name in ACTIONS:
		action_option.add_item(action_name)
	action_option.select(0)

func _bind_signals() -> void:
	if bind_target_button != null:
		bind_target_button.pressed.connect(_on_bind_target_pressed)
	if go_position_button != null:
		go_position_button.pressed.connect(_on_go_position_pressed)
	if play_action_button != null:
		play_action_button.pressed.connect(_on_play_action_pressed)
	if pick_nav_button != null:
		pick_nav_button.toggled.connect(_on_pick_nav_toggled)
	if stop_nav_button != null:
		stop_nav_button.pressed.connect(_on_stop_nav_pressed)
	if send_dialogue_button != null:
		send_dialogue_button.pressed.connect(_on_send_dialogue_pressed)
	if dialogue_input != null:
		dialogue_input.text_submitted.connect(_on_dialogue_submitted)
	if queue_subtitle_button != null and not queue_subtitle_button.pressed.is_connected(_on_queue_subtitle_pressed):
		queue_subtitle_button.pressed.connect(_on_queue_subtitle_pressed)
	if clear_subtitle_queue_button != null and not clear_subtitle_queue_button.pressed.is_connected(_on_clear_subtitle_queue_pressed):
		clear_subtitle_queue_button.pressed.connect(_on_clear_subtitle_queue_pressed)
	if subtitle_queue_input != null and not subtitle_queue_input.text_submitted.is_connected(_on_subtitle_queue_submitted):
		subtitle_queue_input.text_submitted.connect(_on_subtitle_queue_submitted)
	if probe_model_button != null and not probe_model_button.pressed.is_connected(_on_probe_model_pressed):
		probe_model_button.pressed.connect(_on_probe_model_pressed)
	if clear_debug_button != null and not clear_debug_button.pressed.is_connected(_on_clear_debug_pressed):
		clear_debug_button.pressed.connect(_on_clear_debug_pressed)

func _on_bind_target_pressed() -> void:
	if _controller == null:
		return
	if _controller.has_method("bind_target_by_path"):
		_controller.call("bind_target_by_path", target_path_input.text)

func _on_go_position_pressed() -> void:
	if _controller == null:
		return
	var world_position := Vector3(pos_x.value, pos_y.value, pos_z.value)
	if _controller.has_method("navigate_to_position"):
		_controller.call("navigate_to_position", world_position)

func _on_play_action_pressed() -> void:
	if _controller == null:
		return
	var idx := action_option.selected
	if idx < 0 or idx >= ACTIONS.size():
		return
	if _controller.has_method("play_action"):
		_controller.call("play_action", StringName(ACTIONS[idx]))

func _on_pick_nav_toggled(toggled_on: bool) -> void:
	if _controller == null:
		return
	if _controller.has_method("set_pick_navigation_enabled"):
		_controller.call("set_pick_navigation_enabled", toggled_on)

func _on_stop_nav_pressed() -> void:
	if _controller == null:
		return
	if _controller.has_method("stop_navigation"):
		_controller.call("stop_navigation")

func _on_dialogue_submitted(_new_text: String) -> void:
	_on_send_dialogue_pressed()

func _on_send_dialogue_pressed() -> void:
	if _controller == null:
		return

	var text := dialogue_input.text.strip_edges()
	if text.is_empty():
		return

	if _controller.has_method("send_dialogue_text"):
		_controller.call("send_dialogue_text", text)
		dialogue_input.text = ""

func _on_subtitle_queue_submitted(_new_text: String) -> void:
	_on_queue_subtitle_pressed()

func _on_queue_subtitle_pressed() -> void:
	if _controller == null:
		return
	if subtitle_queue_input == null:
		return

	var text := subtitle_queue_input.text.strip_edges()
	if text.is_empty():
		return

	if _controller.has_method("enqueue_subtitle_text"):
		_controller.call("enqueue_subtitle_text", text)
		subtitle_queue_input.text = ""

func _on_clear_subtitle_queue_pressed() -> void:
	if _controller == null:
		return
	if _controller.has_method("clear_subtitle_queue"):
		_controller.call("clear_subtitle_queue", true)

func _on_probe_model_pressed() -> void:
	if _controller == null:
		return
	if _controller.has_method("probe_model_status"):
		_controller.call("probe_model_status")

func _on_clear_debug_pressed() -> void:
	if request_payload_text != null:
		request_payload_text.text = "{}"
	if response_payload_text != null:
		response_payload_text.text = "{}"
	if probe_status_label != null:
		probe_status_label.text = "Probe: idle"

func set_dialogue_reply(text: String) -> void:
	if dialogue_reply_label != null:
		var trimmed = text.strip_edges()
		dialogue_reply_label.text = "AI: %s" % (trimmed if not trimmed.is_empty() else "(empty)")

func set_request_payload(payload: Dictionary) -> void:
	if request_payload_text != null:
		request_payload_text.text = _pretty_json(payload)

func set_response_payload(payload: Dictionary) -> void:
	if response_payload_text != null:
		response_payload_text.text = _pretty_json(payload)

func set_probe_status(text: String) -> void:
	if probe_status_label != null:
		probe_status_label.text = "Probe: %s" % text

func focus_dialogue_input() -> void:
	if dialogue_input == null:
		return
	dialogue_input.grab_focus()
	dialogue_input.caret_column = dialogue_input.text.length()

func _pretty_json(value: Variant) -> String:
	return JSON.stringify(value, "\t", false)

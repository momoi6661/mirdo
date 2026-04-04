extends Control

@onready var status_label = $VBoxContainer/StatusLabel
@onready var dialogue_box = $VBoxContainer/DialogueBox
@onready var input_edit = $VBoxContainer/HBoxContainer/InputEdit
@onready var send_button = $VBoxContainer/HBoxContainer/SendButton
@export var action_router_path: NodePath
@onready var action_router: Node = get_node_or_null(action_router_path)

var ai_manager: AIManager

func _ready():
	# 初始化 AIManager 并添加到场景树
	ai_manager = AIManager.new()
	add_child(ai_manager)
	
	# 连接 UI 信号
	send_button.pressed.connect(_on_send_pressed)
	input_edit.text_submitted.connect(_on_send_submitted)
	
	# 连接 AI 接口发出的信号
	ai_manager.on_ai_stream_chunk_received.connect(_on_ai_stream_chunk)
	ai_manager.on_ai_response_completed.connect(_on_ai_response_completed)
	ai_manager.on_ai_request_error.connect(_on_ai_request_error)

func _on_send_submitted(new_text: String):
	_on_send_pressed()

func _on_send_pressed():
	var text = input_edit.text.strip_edges()
	if text.is_empty():
		return
		
	# 锁定 UI
	input_edit.text = ""
	input_edit.editable = false
	send_button.disabled = true
	
	status_label.text = "状态: AI 正在思考..."
	dialogue_box.text += "\n\n[机器人]: " + text + "\n[小雅]: "
	
	# 模拟发送数据给后端 (第1天, 早上8点, 饱食度50, 心情50)
	ai_manager.send_interaction_stream(1, 480, 50, 50, text)

# ==========================================
# 接收 AI 信号的回调函数
# ==========================================

# 1. 流式接收文字（实现打字机效果）
func _on_ai_stream_chunk(chunk: String):
	status_label.text = "状态: 小雅正在回复..."
	dialogue_box.text += chunk # 把收到的字直接拼在后面
	
	# 滚动条自动滚到底部
	var scrollbar = dialogue_box.get_v_scroll_bar()
	if scrollbar:
		scrollbar.value = scrollbar.max_value

# 2. 接收完整结果（用于更新游戏状态）
func _on_ai_response_completed(final_data: Dictionary):
	status_label.text = "状态: 回复完成"
	input_edit.editable = true
	send_button.disabled = false
	input_edit.grab_focus()
	
	print("===============================")
	print("收到完整的 AI 决策数据: ", final_data)
	if final_data.has("emotion"):
		print("小雅当前的表情是: ", final_data["emotion"])
	if final_data.has("action"):
		print("小雅决定去: ", final_data["action"])
	if action_router != null and action_router.has_method("apply_ai_response"):
		var route_summary = action_router.call("apply_ai_response", final_data)
		print("动作路由执行结果: ", route_summary)
	print("===============================")

# 3. 接收网络错误
func _on_ai_request_error(error_msg: String):
	status_label.text = "状态: 错误!"
	dialogue_box.text += "\n[系统提示: " + error_msg + "]"
	
	input_edit.editable = true
	send_button.disabled = false

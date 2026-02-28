extends Node
class_name AIManager

# Python 后端流式接口地址
const SERVER_URL = "http://127.0.0.1:8000/chat_stream"

var http_client: HTTPClient
var connection_thread: Thread
var is_requesting: bool = false
var response_buffer: PackedByteArray = PackedByteArray()

# 信号：流式接收到新字符时触发（用于打字机效果）
signal on_ai_stream_chunk_received(chunk: String)
# 信号：流式接收完毕，返回完整的 JSON 数据（用于更新状态和动画）
signal on_ai_response_completed(final_data: Dictionary)
# 信号：请求出错
signal on_ai_request_error(error_msg: String)

func _ready():
	http_client = HTTPClient.new()
	connection_thread = Thread.new()

# ==========================================
# 核心调用函数：发送状态和文本，开始流式接收
# ==========================================
func send_interaction_stream(day: int, time: int, hunger: int, mood: int, text: String, item: String = ""):
	if is_requesting:
		print("AIManager: 上一个请求尚未完成，忽略本次请求。")
		return
		
	is_requesting = true
	response_buffer.clear()
	
	var request_data = {
		"day": day,
		"time": time,
		"ai_hunger": hunger,
		"ai_mood": mood,
		"player_text": text,
		"given_item": item
	}
	
	# 在新线程中启动 HTTPClient 以处理流式数据，防止阻塞主线程卡顿
	if connection_thread.is_alive():
		connection_thread.wait_to_finish()
	connection_thread.start(_process_stream_request.bind(request_data))

# ==========================================
# 线程函数：处理底层的 HTTP 流式连接
# ==========================================
func _process_stream_request(request_data: Dictionary):
	var err = http_client.connect_to_host("127.0.0.1", 8000)
	if err != OK:
		call_deferred("_emit_error", "无法连接到 AI 服务器: " + str(err))
		return
		
	# 等待连接成功
	while http_client.get_status() == HTTPClient.STATUS_CONNECTING or http_client.get_status() == HTTPClient.STATUS_RESOLVING:
		http_client.poll()
		OS.delay_msec(10)

	if http_client.get_status() != HTTPClient.STATUS_CONNECTED:
		call_deferred("_emit_error", "连接服务器失败，状态: " + str(http_client.get_status()))
		return
		
	var json_string = JSON.stringify(request_data)
	var headers = [
		"Content-Type: application/json",
		"Accept: text/event-stream" # 告诉后端我们要接收流数据 (SSE)
	]
	
	err = http_client.request(HTTPClient.METHOD_POST, "/chat_stream", headers, json_string)
	if err != OK:
		call_deferred("_emit_error", "发送请求失败: " + str(err))
		return
		
	# 等待服务器响应头
	while http_client.get_status() == HTTPClient.STATUS_REQUESTING:
		http_client.poll()
		OS.delay_msec(10)
		
	if http_client.get_status() != HTTPClient.STATUS_BODY and http_client.get_status() != HTTPClient.STATUS_CONNECTED:
		call_deferred("_emit_error", "服务器未返回预期响应，状态: " + str(http_client.get_status()))
		return
		
	if not http_client.has_response():
		call_deferred("_emit_error", "服务器没有返回 Response")
		return
		
	var response_code = http_client.get_response_code()
	if response_code != 200:
		call_deferred("_emit_error", "服务器返回错误状态码: " + str(response_code))
		return

	# ==========================================
	# 核心流式读取循环
	# ==========================================
	var full_json_string = ""
	
	while http_client.get_status() == HTTPClient.STATUS_BODY:
		http_client.poll()
		var chunk = http_client.read_response_body_chunk()
		
		if chunk.size() > 0:
			response_buffer.append_array(chunk)
			var current_text = response_buffer.get_string_from_utf8()
			
			# 处理 Server-Sent Events (SSE) 格式的数据
			# 数据格式通常是: data: {"chunk": "你", "is_done": false}\n\n
			var lines = current_text.split("\n")
			
			# 保留最后可能不完整的一行
			var incomplete_data = lines[lines.size() - 1]
			response_buffer = incomplete_data.to_utf8_buffer()
			
			for i in range(lines.size() - 1):
				var line = lines[i].strip_edges()
				if line.begins_with("data:"):
					var json_content = line.substr(5).strip_edges()
					if json_content == "[DONE]":
						continue
						
					var json = JSON.new()
					var parse_err = json.parse(json_content)
					
					if parse_err == OK:
						var data = json.get_data()
						
						# 1. 提取并发送增量的文本块 (用于打字机)
						if data.has("dialogue_chunk") and data["dialogue_chunk"] != "":
							call_deferred("_emit_chunk", data["dialogue_chunk"])
							
						# 2. 累加完整的 JSON 字符串
						if data.has("full_json_so_far"):
							full_json_string = data["full_json_so_far"]
							
						# 3. 如果流结束，解析最终结果
						if data.has("is_done") and data["is_done"]:
							var final_json = JSON.new()
							if final_json.parse(full_json_string) == OK:
								call_deferred("_emit_completed", final_json.get_data())
							else:
								call_deferred("_emit_error", "最终 JSON 解析失败: " + full_json_string)
							http_client.close()
							return
							
		OS.delay_msec(10) # 避免 CPU 占用过高

	http_client.close()
	call_deferred("_finish_request")

# ==========================================
# 辅助函数：跨线程抛出信号
# ==========================================
func _emit_chunk(chunk: String):
	on_ai_stream_chunk_received.emit(chunk)

func _emit_completed(final_data: Dictionary):
	is_requesting = false
	on_ai_response_completed.emit(final_data)

func _emit_error(msg: String):
	is_requesting = false
	on_ai_request_error.emit(msg)

func _finish_request():
	is_requesting = false

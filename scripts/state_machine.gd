class_name StateMachine extends Node

@export var CURRENT_STATE:State

var states:Dictionary={}
var is_locked: bool = false # 加载锁

func _ready() -> void:
	_init_states()
	if CURRENT_STATE:
		CURRENT_STATE.enter()

func _init_states():
	if not states.is_empty(): return
	for child in get_children():
		if child is State:
			states[child.name]=child
			if not child.transition.is_connected(_on_child_transition):
				child.transition.connect(_on_child_transition)
		else:
			push_warning("something wrong in statemachine setting")

func _process(delta: float) -> void:
	if is_locked or not CURRENT_STATE: return
	CURRENT_STATE.update(delta)

func _physics_process(delta: float):
	if is_locked or not CURRENT_STATE: return
	CURRENT_STATE.physics_process(delta)



func _on_child_transition(new_state_name:StringName):
	if is_locked: return
	change_state(new_state_name)


func change_state(new_state_name: StringName):
	if is_locked: 
		#print("[StateMachine] 锁定中，拦截切换请求: ", new_state_name)
		return
	
	# 拦截错误的 FallState 请求：如果玩家实际在地上，忽略来自其它状态的掉落请求
	if new_state_name == "FallState":
		var parent = get_parent()
		if parent and parent.has_method("is_on_floor") and parent.is_on_floor():
			#print("[StateMachine] 拦截虚假的 FallState 请求（玩家当前在地面）")
			return
	
	var new_state=states.get(new_state_name)
	if new_state!=null and new_state != CURRENT_STATE:
		var old_name = CURRENT_STATE.name if CURRENT_STATE else "None"
		#print("[StateMachine] 状态切换: ", old_name, " -> ", new_state_name)
		
		if CURRENT_STATE:
			CURRENT_STATE.exit()
		new_state.enter()
		CURRENT_STATE=new_state
	elif new_state == null:
		push_warning("StateMachine: State " + new_state_name + " not found.")

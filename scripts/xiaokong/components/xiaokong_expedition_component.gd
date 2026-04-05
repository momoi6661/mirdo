extends Node
class_name XiaokongExpeditionComponent

signal expedition_requested(payload: Dictionary)
signal expedition_completed(report: Dictionary)
signal expedition_failed(error_text: String)
signal stay_home_processed(report: Dictionary)

@export var stock_component_path: NodePath
@export var state_component_path: NodePath
@export var ai_action_router_path: NodePath
@export var direct_action_controller_path: NodePath = NodePath("..")

@export var base_expedition_cost: Dictionary = {
	"water": 1,
	"food": 1,
}

@export var stay_home_consumption: Dictionary = {
	"water": -1,
	"food": -1,
}

@export var stay_home_chat_bonus: Dictionary = {
	"mood": 2,
	"favor": 1,
}

@export_range(1, 3, 1) var max_risk_level: int = 3

var current_day: int = 1
var expeditions_done_today: int = 0
var pending_payload: Dictionary = {}

var _rng = RandomNumberGenerator.new()
var _stock_component: ShelterStockComponent
var _state_component: XiaokongStateComponent
var _ai_action_router: Node
var _direct_action_controller: Node

func _ready() -> void:
	_rng.randomize()
	_refresh_refs()

func start_new_day(day_index: int) -> void:
	current_day = max(day_index, 1)
	expeditions_done_today = 0
	pending_payload.clear()
	if _stock_component != null:
		_stock_component.apply_daily_upkeep(1)

func stay_home_and_chat(hours: float = 3.0) -> Dictionary:
	_refresh_refs()

	var report = {
		"ok": true,
		"type": "stay_home",
		"hours": hours,
		"stock_delta": {},
		"stat_delta": {},
	}

	if _stock_component != null:
		report["stock_delta"] = _stock_component.apply_delta(stay_home_consumption, "stay_home_consumption")
	if _state_component != null:
		var decay_delta = _state_component.tick_hours(hours)
		var chat_delta = _state_component.apply_delta(stay_home_chat_bonus, "stay_home_chat")
		report["stat_delta"] = _merge_delta(decay_delta, chat_delta)

	stay_home_processed.emit(report)
	return report

func begin_expedition(player_prompt: String, risk_level: int = 1, consume_cost: bool = true) -> Dictionary:
	_refresh_refs()

	var clamped_risk = clampi(risk_level, 1, max_risk_level)
	var cost = _compute_expedition_cost(clamped_risk)

	if consume_cost and _stock_component != null and not _stock_component.spend(cost, "expedition_cost"):
		var error_text = "not_enough_stock_for_expedition"
		expedition_failed.emit(error_text)
		return {"ok": false, "error": error_text, "required_cost": cost}

	pending_payload = {
		"day": current_day,
		"risk_level": clamped_risk,
		"expedition_index": expeditions_done_today + 1,
		"prompt": player_prompt.strip_edges(),
		"stock_snapshot": _stock_component.get_snapshot() if _stock_component != null else {},
		"npc_stats": _state_component.build_ai_stats() if _state_component != null else {},
		"required_cost": cost,
	}

	expedition_requested.emit(pending_payload.duplicate(true))
	return {"ok": true, "payload": pending_payload.duplicate(true)}

func resolve_pending_expedition(ai_result: Dictionary) -> Dictionary:
	if pending_payload.is_empty():
		var error_text = "no_pending_expedition"
		expedition_failed.emit(error_text)
		return {"ok": false, "error": error_text}

	var report = _apply_expedition_result(ai_result, "ai")
	pending_payload.clear()
	return report

func run_expedition_with_fallback(player_prompt: String, risk_level: int = 1) -> Dictionary:
	var begin_result = begin_expedition(player_prompt, risk_level, true)
	if not bool(begin_result.get("ok", false)):
		return begin_result

	var fallback_result = _roll_fallback_result(clampi(risk_level, 1, max_risk_level))
	return resolve_pending_expedition(fallback_result)

func _apply_expedition_result(result_payload: Dictionary, source: String) -> Dictionary:
	_refresh_refs()

	var stock_delta = _normalize_stock_delta(result_payload.get("stock_delta", {}))
	var stat_delta = _normalize_stat_delta(result_payload.get("stat_change", {}))
	var action_name = String(result_payload.get("action", "")).strip_edges()

	var applied_stock = {}
	if _stock_component != null and not stock_delta.is_empty():
		applied_stock = _stock_component.apply_delta(stock_delta, "expedition_%s_stock" % source)

	var applied_stats = {}
	if _state_component != null and not stat_delta.is_empty():
		applied_stats = _state_component.apply_delta(stat_delta, "expedition_%s_stat" % source)

	if not action_name.is_empty():
		_apply_action(action_name, result_payload)

	expeditions_done_today += 1

	var report = {
		"ok": true,
		"type": "expedition",
		"source": source,
		"summary": String(result_payload.get("summary", "")),
		"tags": result_payload.get("tags", []),
		"stock_delta": applied_stock,
		"stat_delta": applied_stats,
		"action": action_name,
		"risk_level": int(pending_payload.get("risk_level", 1)),
		"expedition_index": expeditions_done_today,
	}

	expedition_completed.emit(report)
	return report

func _apply_action(action_name: String, result_payload: Dictionary) -> void:
	if _ai_action_router != null and _ai_action_router.has_method("apply_ai_response"):
		var action_payload = {
			"action": action_name,
			"move_target": result_payload.get("move_target", null),
			"stat_change": {},
		}
		_ai_action_router.call("apply_ai_response", action_payload)
		return

	if _direct_action_controller != null and _direct_action_controller.has_method("trigger_action"):
		_direct_action_controller.call("trigger_action", StringName(action_name))

func _compute_expedition_cost(risk_level: int) -> Dictionary:
	var scaled = {}
	for key in base_expedition_cost.keys():
		var base_cost = int(round(float(base_expedition_cost[key])))
		scaled[key] = maxi(0, base_cost + max(risk_level - 1, 0))
	return scaled

func _roll_fallback_result(risk_level: int) -> Dictionary:
	var roll = _rng.randf()

	match risk_level:
		1:
			if roll < 0.45:
				return {
					"summary": "你找到一小批净水和可食用补给。",
					"stock_delta": {"water": 2, "food": 1},
					"stat_change": {"mood": 3},
					"action": "StandingGreeting",
					"tags": ["lucky_find"],
				}
			if roll < 0.80:
				return {
					"summary": "这次收获平平，只带回少量材料。",
					"stock_delta": {"parts": 1},
					"stat_change": {"mood": 1},
					"action": "Idle",
					"tags": ["normal_return"],
				}
			return {
				"summary": "遭遇危险，被迫空手撤回。",
				"stock_delta": {},
				"stat_change": {"mood": -5, "favor": -1},
				"action": "Laying",
				"tags": ["retreat"],
			}
		2:
			if roll < 0.35:
				return {
					"summary": "深入区域找到更多物资。",
					"stock_delta": {"water": 2, "food": 2, "parts": 1},
					"stat_change": {"mood": 4, "favor": 1},
					"action": "Salute",
					"tags": ["high_reward"],
				}
			if roll < 0.65:
				return {
					"summary": "遭遇阻碍，但还是带回了一些补给。",
					"stock_delta": {"food": 1},
					"stat_change": {"mood": -1},
					"action": "Idle",
					"tags": ["scrappy_success"],
				}
			return {
				"summary": "你在外部受了轻伤，补给损失。",
				"stock_delta": {"medicine": -1},
				"stat_change": {"mood": -6, "favor": -1},
				"action": "SittingIdle",
				"tags": ["minor_injury"],
			}
		_:
			if roll < 0.28:
				return {
					"summary": "高风险区爆出大量稀有物资。",
					"stock_delta": {"water": 3, "food": 3, "medicine": 1, "parts": 2},
					"stat_change": {"mood": 6, "favor": 2},
					"action": "Kiss",
					"tags": ["jackpot"],
				}
			if roll < 0.55:
				return {
					"summary": "勉强全身而退，收益一般。",
					"stock_delta": {"parts": 1, "food": 1},
					"stat_change": {"mood": -2},
					"action": "Idle",
					"tags": ["barely_safe"],
				}
			return {
				"summary": "遭遇严重危机，士气重挫。",
				"stock_delta": {"water": -1, "food": -1, "medicine": -1},
				"stat_change": {"mood": -10, "favor": -3},
				"action": "Laying",
				"tags": ["major_failure"],
			}

func _normalize_stock_delta(raw: Variant) -> Dictionary:
	if raw is not Dictionary:
		return {}
	var normalized = {}
	for key in (raw as Dictionary).keys():
		normalized[key] = int(round(float(raw[key])))
	return normalized

func _normalize_stat_delta(raw: Variant) -> Dictionary:
	if raw is not Dictionary:
		return {}
	var normalized = {}
	for key in ["hunger", "thirst", "mood", "favor"]:
		if (raw as Dictionary).has(key):
			normalized[key] = float((raw as Dictionary)[key])
	return normalized

func _merge_delta(first: Dictionary, second: Dictionary) -> Dictionary:
	var merged = first.duplicate(true)
	for key in second.keys():
		merged[key] = float(merged.get(key, 0.0)) + float(second[key])
	return merged

func _refresh_refs() -> void:
	_stock_component = get_node_or_null(stock_component_path) as ShelterStockComponent
	if _stock_component == null:
		_stock_component = _find_stock_component()

	_state_component = get_node_or_null(state_component_path) as XiaokongStateComponent
	if _state_component == null:
		_state_component = _find_state_component()

	_ai_action_router = get_node_or_null(ai_action_router_path)
	_direct_action_controller = get_node_or_null(direct_action_controller_path)

func _find_stock_component() -> ShelterStockComponent:
	var parent_node = get_parent()
	if parent_node == null:
		return null
	for child in parent_node.get_children():
		var stock_component = child as ShelterStockComponent
		if stock_component != null:
			return stock_component
	return null

func _find_state_component() -> XiaokongStateComponent:
	var parent_node = get_parent()
	if parent_node == null:
		return null
	for child in parent_node.get_children():
		var state_component = child as XiaokongStateComponent
		if state_component != null:
			return state_component
	return null

extends RefCounted
class_name WorldInteractionOption

const TRIGGER_TAP := "tap"
const TRIGGER_HOLD := "hold"
const TRIGGER_BOTH := "both"

var id: String = ""
var label: String = ""
var description: String = ""
var enabled: bool = true
var disabled_reason: String = ""
var trigger_mode: String = TRIGGER_TAP
var hold_duration: float = 0.35
var style: String = ""

static func create(
	option_id: String,
	option_label: String,
	option_description: String = "",
	option_trigger_mode: String = TRIGGER_TAP,
	option_hold_duration: float = 0.35,
	option_enabled: bool = true,
	option_disabled_reason: String = "",
	option_style: String = ""
) -> WorldInteractionOption:
	var option := WorldInteractionOption.new()
	option.id = option_id
	option.label = option_label
	option.description = option_description
	option.trigger_mode = option_trigger_mode
	option.hold_duration = maxf(option_hold_duration, 0.0)
	option.enabled = option_enabled
	option.disabled_reason = option_disabled_reason
	option.style = option_style
	return option

func supports_tap() -> bool:
	return trigger_mode == TRIGGER_TAP or trigger_mode == TRIGGER_BOTH

func supports_hold() -> bool:
	return trigger_mode == TRIGGER_HOLD or trigger_mode == TRIGGER_BOTH

func get_safe_hold_duration(default_duration: float = 0.35) -> float:
	if hold_duration > 0.0:
		return hold_duration
	return maxf(default_duration, 0.05)

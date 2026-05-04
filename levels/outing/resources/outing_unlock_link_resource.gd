@tool
extends Resource
class_name OutingUnlockLinkResource

@export var from_location_id: StringName
@export var to_location_id: StringName
@export var unlock_key: StringName
@export var required_success_count: int = 1
@export_multiline var discovery_text: String = ""
@export_multiline var ai_discovery_rule: String = ""

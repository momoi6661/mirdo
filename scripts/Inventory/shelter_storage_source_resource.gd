extends Resource
class_name ShelterStorageSourceResource

@export var source_id: StringName
@export var display_name: String = "储物点"
@export_enum("food", "medical", "material", "equipment", "temporary", "special") var source_kind: String = "material"
@export var storage: InventoryStorageResource
@export var include_in_outing_pool: bool = true
@export_multiline var notes: String = ""


func is_valid_source() -> bool:
	return not String(source_id).is_empty() and storage != null


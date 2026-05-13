extends Resource
class_name CharacterAIProfileResource

@export var character_id: StringName
@export var display_name: String = ""
@export var state_component_path: NodePath
@export var navigation_component_path: NodePath
@export var action_controller_path: NodePath
@export var face_component_path: NodePath
@export var subtitle_component_path: NodePath
@export var perception_origin_path: NodePath
@export var player_target_path: NodePath
@export var supported_intents: PackedStringArray = PackedStringArray()
@export var expression_map: Dictionary = {}

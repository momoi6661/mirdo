@tool
extends "res://components/xiaokong_character_interactable_component.gd"
class_name CharacterInteractableComponent

## Generic semantic wrapper for NPC world-panel interaction.
##
## The base component still contains legacy Xiaokong signal names so existing
## controller/UI wiring continues to work. New characters should attach this
## script to avoid character-specific class names in scenes.

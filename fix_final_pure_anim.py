import re

with open('scripts/Inventory/InventoryHandler.gd', 'r', encoding='utf-8') as f:
    content = f.read()

new_animations = """func play_open_animation():
	self.visible = true
	_play_ui_sound("menu_open")
	if has_node("UIAnimationPlayer"):
		var animator = $UIAnimationPlayer
		if animator.has_animation("inv_open"):
			animator.play("inv_open")

func play_loot_open_animation():
	self.visible = true
	_play_ui_sound("menu_open")
	
	var loot_panel = get_node_or_null("LootPanel")
	if loot_panel:
		loot_panel.visible = true
		
	if has_node("UIAnimationPlayer"):
		var animator = $UIAnimationPlayer
		if animator.has_animation("loot_open"):
			animator.play("loot_open")

func play_close_animation():
	_play_ui_sound("menu_close")
	
	if has_node("UIAnimationPlayer"):
		var animator = $UIAnimationPlayer
		
		var loot_panel = get_node_or_null("LootPanel")
		if loot_panel and loot_panel.visible:
			if animator.has_animation("loot_close"):
				animator.play("loot_close")
			else:
				animator.play("close_all")
		else:
			if animator.has_animation("inv_close"):
				animator.play("inv_close")
			else:
				if animator.has_animation("close_all"):
					animator.play("close_all")
				
		await animator.animation_finished
	
	self.visible = false
	var loot_panel = get_node_or_null("LootPanel")
	if loot_panel:
		loot_panel.visible = false
		
	Global.close_loot_ui.emit()"""

content = re.sub(r'func play_open_animation\(\):.*?(?=func ItemDroppedOnSlot|func _on_slot_item_clicked)', new_animations + '\n\n', content, flags=re.DOTALL)

with open('scripts/Inventory/InventoryHandler.gd', 'w', encoding='utf-8') as f:
    f.write(content)

print("InventoryHandler pure AnimationPlayer patch applied!")

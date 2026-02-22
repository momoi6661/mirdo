import re

# 修复 inventory_slot.gd 中对 button_pressed 和 focus 的控制，从根本上杀掉高亮
with open('scripts/Inventory/inventory_slot.gd', 'r', encoding='utf-8') as f:
    content = f.read()

# 升级 _ready 函数
new_ready = """func _ready():
	# 确保不被意外拉取焦点导致的高亮
	focus_mode = Control.FOCUS_NONE
	
	if is_selectable:
		self.toggled.connect(_on_toggled)
	else:
		toggle_mode = false
		button_mask = MOUSE_BUTTON_MASK_LEFT | MOUSE_BUTTON_MASK_RIGHT # 允许拖拽
		# 强制把所有会导致高亮的皮肤和效果清空或者锁定
		action_mode = BaseButton.ACTION_MODE_BUTTON_PRESS"""

content = re.sub(r'func _ready\(\):.*?(?=func _on_toggled)', new_ready + '\n\n', content, flags=re.DOTALL)

# 升级 _gui_input 函数，屏蔽无效右键点击导致的高亮
new_gui_input = """func _gui_input(event: InputEvent):
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
			if is_selectable and not self.button_pressed:
				self.button_pressed = true"""

content = re.sub(r'func _gui_input\(event: InputEvent\):.*?(?=func FillSlot)', new_gui_input + '\n\n', content, flags=re.DOTALL)

with open('scripts/Inventory/inventory_slot.gd', 'w', encoding='utf-8') as f:
    f.write(content)

print("Slot highlight completely disabled for LootPanel!")

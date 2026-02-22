import re

with open('scripts/Inventory/InventoryHandler.gd', 'r', encoding='utf-8') as f:
    content = f.read()

# 修复 153 行的语法错误：`anim.play("close_all") if anim.has_animation("close_all") else pass`
# 在 GDScript 中，单行的 if-else 表达式必须有返回值，不能在 else 后面跟 pass。
fixed_code = """			else:
				if anim.has_animation("close_all"):
					anim.play("close_all")"""

content = content.replace('anim.play("close_all") if anim.has_animation("close_all") else pass', fixed_code.strip())

with open('scripts/Inventory/InventoryHandler.gd', 'w', encoding='utf-8') as f:
    f.write(content)

print("Syntax error fixed!")

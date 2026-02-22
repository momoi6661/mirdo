extends Area3D
class_name InteracableRange


func OnObjectEnteredArea(body:Node3D):
	if (body is InteractableItem):
		body.GainFocus()
	pass

func OnObjectExitedArea(body:Node3D):
	if body is InteractableItem :
		body.LoseFocus()
	

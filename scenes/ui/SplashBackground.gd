extends Control

func _input(event):
	if event is InputEventMouseButton and event.pressed:
		get_parent().move_child(self, 0)
		mouse_filter = Control.MOUSE_FILTER_IGNORE

extends TextureButton

@onready var label: Label = $Label

func _ready() -> void:
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.label_settings = label.label_settings.duplicate()
	mouse_entered.connect(_on_mouse_entered)
	mouse_exited.connect(_on_mouse_exited)

func _on_mouse_entered() -> void:
	if disabled:
		return
	label.label_settings.font_color = Color("#ffffff78")

func _on_mouse_exited() -> void:
	if disabled:
		return
	label.label_settings.font_color = Color("#ffffff")

func set_disabled_state(value: bool) -> void:
	disabled = value
	label.label_settings.font_color = Color("#ffffff78") if value else Color("#ffffff")

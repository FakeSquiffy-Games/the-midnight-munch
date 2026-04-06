extends CanvasLayer

func show_toast(text_str: String, color: Color = Color.WHITE) -> void:
	var label := Label.new()
	label.text = text_str
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	
	var settings := LabelSettings.new()
	settings.font_size = 24
	settings.outline_size = 6
	settings.outline_color = Color.BLACK
	settings.font_color = color
	label.label_settings = settings
	
	## Center at the top of the screen
	label.set_anchors_preset(Control.PRESET_TOP_WIDE)
	label.position.y = 50.0
	label.modulate.a = 0.0
	add_child(label)
	
	var tween := create_tween()
	tween.tween_property(label, "modulate:a", 1.0, 0.3)
	tween.tween_interval(2.5) # Hold for 2.5 seconds
	tween.tween_property(label, "modulate:a", 0.0, 0.5)
	tween.tween_callback(label.queue_free)

## FloatingText.gd
class_name FloatingText
extends Label

## Creates a floating text label dynamically. 
## parent: The node to attach to (usually the World so it doesn't move with the fish)
static func spawn(parent: Node, start_pos: Vector2, text_str: String, color: Color) -> void:
	var label := FloatingText.new()
	label.text = text_str
	label.modulate = color
	
	## NEW: Random spread to prevent overlapping texts
	var random_offset := Vector2(randf_range(-40.0, 40.0), randf_range(-20.0, 20.0))
	label.global_position = start_pos + random_offset
	label.z_index = 100
	
	## Center the text on the spawn point
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.position -= Vector2(100, 15) # Assuming width 200, height 30
	label.size = Vector2(200, 30)
	
	## Code-driven styling (Black outline for readability)
	var settings := LabelSettings.new()
	settings.font_size = 20
	settings.outline_size = 4
	settings.outline_color = Color.BLACK
	settings.font_color = Color.WHITE
	label.label_settings = settings
	
	parent.add_child(label)
	
	## Tween upward and fade out simultaneously
	var tween := label.create_tween().set_parallel(true)
	tween.tween_property(label, "global_position:y", start_pos.y - 60.0, 1.0).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)
	tween.tween_property(label, "modulate:a", 0.0, 1.0).set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_EXPO)
	
	## Delete the label when the tween finishes
	tween.chain().tween_callback(label.queue_free)

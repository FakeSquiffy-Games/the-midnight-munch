class_name BodyArea
extends Area2D


# =========================================================
# LIFECYCLE
# =========================================================

func _ready() -> void:
	# Set built-in Area2D properties
	monitoring = false
	monitorable = true
	collision_layer = 2
	collision_mask = 0

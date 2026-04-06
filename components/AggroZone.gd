extends Area2D

## The detection radius for this specific enemy type.
@export var aggro_radius: float = 300.0

@onready var collision_shape: CollisionShape2D = $CollisionShape2D

func _ready() -> void:
	# Duplicate the shape resource so changing one enemy 
	# doesn't change the radius for EVERY enemy.
	if collision_shape.shape is CircleShape2D:
		collision_shape.shape = collision_shape.shape.duplicate()
		
		# Apply the exported value
		collision_shape.shape.radius = aggro_radius
	else:
		push_error("AggroZone: Please assign a CircleShape2D to the CollisionShape2D node.")

## Call this function if you need to change the radius mid-game (e.g., Enraged mode)
func update_radius(new_size: float) -> void:
	aggro_radius = new_size
	collision_shape.shape.radius = aggro_radius

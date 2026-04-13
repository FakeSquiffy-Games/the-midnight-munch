class_name FloaterBehavior
extends Node

@export var float_speed_multiplier: float = 1.0
@export var ceiling_y_level: float = -1100.0

var _entity: CharacterBody2D
var _stat_manager: StatManager

func _ready() -> void:
	_entity = owner as CharacterBody2D
	_stat_manager = _entity.get_node("StatManager")
	_entity.add_to_group("npc_invisible") # Flag to ignore NPC aggro
	
	## FIX: Disable collision with World Boundaries (Mask 1) 
	## so the item can float seamlessly up and out of the arena.
	_entity.set_collision_layer_value(2, false)
	_entity.set_collision_mask_value(1, false)

func _physics_process(_delta: float) -> void:
	if not multiplayer.is_server(): return
	if not is_instance_valid(_entity): return
	
	_entity.velocity = Vector2.UP * (_stat_manager.speed * float_speed_multiplier)
	_entity.move_and_slide()
	
	# Despawn if it floats entirely out of the world bounds
	if _entity.global_position.y < ceiling_y_level:
		_entity.queue_free()

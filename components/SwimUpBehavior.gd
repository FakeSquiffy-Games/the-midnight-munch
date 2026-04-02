class_name SwimUpBehavior
extends Node

@export var float_speed: float = 75.0
var _entity: CharacterBody2D

func _ready() -> void:
	_entity = owner as CharacterBody2D
	_entity.add_to_group("npc_inedible") # Flag to ignore NPC aggro

func _physics_process(_delta: float) -> void:
	if not multiplayer.is_server(): return
	if not is_instance_valid(_entity): return
	
	_entity.velocity = Vector2.UP * float_speed
	_entity.move_and_slide()
	
	# Despawn if it floats entirely out of the world bounds
	if _entity.global_position.y < -1100.0:
		_entity.queue_free()

class_name NPCBehavior
extends Node

@export var is_inedible: bool = false
@export var wander_speed: float = 50.0

var _entity: CharacterBody2D

func _ready() -> void:
	_entity = owner as CharacterBody2D
	if is_inedible:
		_entity.add_to_group("npc_inedible")
	
	# Basic horizontal wander for special fish
	if multiplayer.is_server():
		var direction := 1.0 if _entity.global_position.x < 0 else -1.0
		_entity.velocity = Vector2.RIGHT * direction * wander_speed
		_entity.sync_flip_h = (direction < 0) # Assumes sync_flip_h is on the NPC root

func _physics_process(_delta: float) -> void:
	if not multiplayer.is_server(): return
	if not is_instance_valid(_entity): return
	
	_entity.move_and_slide()
	
	if abs(_entity.global_position.x) > 1900.0:
		_entity.queue_free()

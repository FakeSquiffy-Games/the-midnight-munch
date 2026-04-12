class_name ScuttlerBehavior
extends Node

@export var patrol_speed_multiplier: float = 0.3
@export var floor_y_level: float = 900.0 ## The Y-coordinate to cling to

var _entity: CharacterBody2D
var _stat_manager: StatManager
var move_direction: Vector2 = Vector2.RIGHT

func _ready() -> void:
	_entity = owner as CharacterBody2D
	_stat_manager = _entity.get_node("StatManager")
	
	if multiplayer.is_server():
		move_direction = Vector2.RIGHT if randf() > 0.5 else Vector2.LEFT

func trigger_cooldown(duration: float = 2.0) -> void:
	move_direction.x *= -1 # Just turn around if bitten

func _physics_process(delta: float) -> void:
	if not multiplayer.is_server() or not is_instance_valid(_entity): return

	if _entity.is_on_wall():
		move_direction.x *= -1
		
	var target_velocity = move_direction * (_stat_manager.speed * patrol_speed_multiplier)
	
	## Force the Y velocity downward if they are above the floor line
	if _entity.global_position.y < floor_y_level:
		target_velocity.y = 150.0 
	else:
		target_velocity.y = 0.0

	_entity.velocity = target_velocity
	_entity.move_and_slide()
	_entity.update_facing(_entity.velocity)

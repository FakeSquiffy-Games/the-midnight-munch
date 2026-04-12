class_name WandererBehavior
extends Node

enum State { WANDER, FLEE }

@export var wander_speed_multiplier: float = 0.4
@export var flee_speed_multiplier: float = 1.0

var _entity: CharacterBody2D
var _stat_manager: StatManager

var current_state: State = State.WANDER
var move_direction: Vector2 = Vector2.RIGHT
var state_timer: float = 0.0

func _ready() -> void:
	_entity = owner as CharacterBody2D
	_stat_manager = _entity.get_node("StatManager")
	
	if multiplayer.is_server():
		var dir_to_center := _entity.global_position.direction_to(Vector2.ZERO)
		move_direction = dir_to_center.rotated(randf_range(-0.5, 0.5)).normalized()
		state_timer = randf_range(2.0, 5.0)

## Called by CombatResolver when this entity bites or gets bitten
func trigger_cooldown(duration: float = 2.0) -> void:
	current_state = State.FLEE
	state_timer = duration
	
	## Reverse current direction with a little bit of noise to simulate panic
	move_direction = move_direction.rotated(PI + randf_range(-0.3, 0.3)).normalized()

func _physics_process(delta: float) -> void:
	if not multiplayer.is_server() or not is_instance_valid(_entity): return

	state_timer -= delta

	match current_state:
		State.WANDER:
			_process_wander()
		State.FLEE:
			_process_flee()
			
	_entity.move_and_slide()
	_entity.update_facing(_entity.velocity)

func _process_wander() -> void:
	## Wall Bounce Mechanic
	if _entity.is_on_wall():
		var normal := _entity.get_wall_normal()
		move_direction = normal.rotated(randf_range(-0.5, 0.5)).normalized()
		state_timer = randf_range(2.0, 4.0)
	elif state_timer <= 0.0:
		_pick_new_wander_direction()
		
	_entity.velocity = move_direction * (_stat_manager.speed * wander_speed_multiplier)

func _process_flee() -> void:
	## Still respect walls while panicking
	if _entity.is_on_wall():
		var normal := _entity.get_wall_normal()
		move_direction = normal.rotated(randf_range(-0.5, 0.5)).normalized()
	
	if state_timer <= 0.0:
		current_state = State.WANDER
		_pick_new_wander_direction()
		
	_entity.velocity = move_direction * (_stat_manager.speed * flee_speed_multiplier)

func _pick_new_wander_direction() -> void:
	move_direction = Vector2(randf_range(-1, 1), randf_range(-1, 1)).normalized()
	state_timer = randf_range(2.0, 5.0)

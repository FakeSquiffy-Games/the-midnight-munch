class_name ScuttlerBehavior
extends Node

@export var patrol_speed_multiplier: float = 0.3
@export var floor_y_level: float = 900.0 ## The Y-coordinate to cling to
@export var stop_chance: float = 0.25

var _entity: CharacterBody2D
var _stat_manager: StatManager
var move_direction: Vector2 = Vector2.RIGHT
var state_timer: float = 0.0

func _ready() -> void:
	_entity = owner as CharacterBody2D
	_stat_manager = _entity.get_node("StatManager")
	
	if multiplayer.is_server():
		_pick_new_direction()

func trigger_cooldown(_duration: float = 2.0) -> void:
	## If bitten, immediately panic and run the opposite way
	if move_direction.x == 0.0:
		move_direction.x = 1.0 if randf() > 0.5 else -1.0
	else:
		move_direction.x *= -1.0
	state_timer = randf_range(2.0, 4.0)

func _physics_process(delta: float) -> void:
	if not multiplayer.is_server() or not is_instance_valid(_entity): return

	## 1. Organic Randomness (Timers)
	state_timer -= delta
	if state_timer <= 0.0:
		_pick_new_direction()

	## 2. Smart Wall Bounce (Override Timer if we hit a wall)
	if _entity.is_on_wall():
		var wall_normal_x := _entity.get_wall_normal().x
		if abs(wall_normal_x) > 0.5:
			move_direction.x = sign(wall_normal_x)
			state_timer = randf_range(3.0, 6.0) # Reset timer so it doesn't instantly turn back
			
	## 3. Hard Bounds Fallback (Prevents getting stuck on corners)
	if _entity.global_position.x > 1700.0:
		move_direction.x = -1.0
		state_timer = randf_range(3.0, 6.0)
	elif _entity.global_position.x < -1700.0:
		move_direction.x = 1.0
		state_timer = randf_range(3.0, 6.0)
		
	var target_velocity = move_direction * (_stat_manager.speed * patrol_speed_multiplier)
	
	## 4. Floor Clinging Logic
	if _entity.global_position.y < floor_y_level:
		target_velocity.y = 150.0 
	else:
		target_velocity.y = 0.0

	_entity.velocity = target_velocity
	_entity.move_and_slide()
	
	## Only update facing if they are actually moving (don't flip while stopped)
	if abs(target_velocity.x) > 0.01:
		_entity.update_facing(target_velocity)

func _pick_new_direction() -> void:
	## 25% chance to stop and "forage" on the ocean floor
	if randf() <= stop_chance:
		move_direction.x = 0.0
		state_timer = randf_range(1.5, 3.0)
	## 75% chance to pick a random direction and scuttle
	else:
		move_direction.x = 1.0 if randf() < 0.5 else -1.0
		state_timer = randf_range(4.0, 8.0)

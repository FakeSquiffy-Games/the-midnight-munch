class_name ChaserBehavior
extends Node

enum State { WANDER, CHASE, FLEE }

@export var wander_speed_multiplier: float = 1.0
@export var chase_speed_multiplier: float = 1.5
@export var flee_speed_multiplier: float = 1.5
@export var chase_chance: float = 0.6
@export var flee_chance: float = 0.4
@export var max_chase_distance: float = 500.0

var _entity: CharacterBody2D
var _stat_manager: StatManager
var _aggro_zone: Area2D

var current_state: State = State.WANDER
var target: CharacterBody2D = null
var wander_direction: Vector2 = Vector2.RIGHT

var state_timer: float = 0.0
var aggro_cooldown: float = 0.0

func _ready() -> void:
	_entity = owner as CharacterBody2D
	_stat_manager = _entity.get_node("StatManager")
	_aggro_zone = _entity.get_node_or_null("components/AggroZone")
	
	if multiplayer.is_server():
		if _aggro_zone != null:
			_aggro_zone.set_collision_mask_value(1, false)
			_aggro_zone.set_collision_mask_value(3, true)
			_aggro_zone.area_entered.connect(_on_aggro_entered)
			_aggro_zone.area_exited.connect(_on_aggro_exited)
			
		var dir_to_center := _entity.global_position.direction_to(Vector2.ZERO)
		wander_direction = dir_to_center.rotated(randf_range(-0.5, 0.5)).normalized()
		state_timer = randf_range(2.0, 5.0)

func trigger_cooldown(duration: float = 2.0) -> void:
	aggro_cooldown = duration
	_return_to_wander()

func _physics_process(delta: float) -> void:
	if not multiplayer.is_server() or not is_instance_valid(_entity): return

	if aggro_cooldown > 0.0:
		aggro_cooldown -= delta

	match current_state:
		State.WANDER: _process_wander(delta)
		State.CHASE:  _process_chase()
		State.FLEE:   _process_flee()
			
	_entity.move_and_slide()
	_entity.update_facing(_entity.velocity)

func _process_wander(delta: float) -> void:
	state_timer -= delta
	
	## Wall Bounce Mechanic using built-in physics
	if _entity.is_on_wall():
		var normal := _entity.get_wall_normal()
		wander_direction = normal.rotated(randf_range(-0.5, 0.5)).normalized()
		state_timer = randf_range(2.0, 4.0)
	elif state_timer <= 0.0:
		_pick_new_wander_direction()
		
	_entity.velocity = wander_direction * (_stat_manager.speed * wander_speed_multiplier)

func _process_chase() -> void:
	if not _is_target_valid(): return
	var direction := _entity.global_position.direction_to(target.global_position)
	
	## Apply the chase speed multiplier
	_entity.velocity = direction * (_stat_manager.speed * chase_speed_multiplier)

func _process_flee() -> void:
	if not _is_target_valid(): return
	## Swim away with slight noise so it feels like a panicked fish
	var away_dir := target.global_position.direction_to(_entity.global_position)
	away_dir = away_dir.rotated(randf_range(-0.2, 0.2)).normalized()
	
	## Apply the flee speed multiplier
	_entity.velocity = away_dir * (_stat_manager.speed * flee_speed_multiplier)

func _is_target_valid() -> bool:
	if not is_instance_valid(target) or target.is_queued_for_deletion():
		_return_to_wander()
		return false
	if _entity.global_position.distance_to(target.global_position) > max_chase_distance:
		_return_to_wander()
		return false
	return true

func _pick_new_wander_direction() -> void:
	wander_direction = Vector2(randf_range(-1, 1), randf_range(-1, 1)).normalized()
	state_timer = randf_range(2.0, 5.0)

func _return_to_wander() -> void:
	target = null
	current_state = State.WANDER
	_pick_new_wander_direction()

func _on_aggro_entered(area: Area2D) -> void:
	if current_state != State.WANDER or aggro_cooldown > 0.0: return
	if not area is BodyArea: return
		
	var potential_target := area.get_parent().get_parent() as CharacterBody2D
	if potential_target == null or potential_target == _entity: return
	if potential_target.is_in_group("npc_invisible"): return
	
	target = potential_target
	var target_stat := target.get_node_or_null("StatManager") as StatManager
	
	if target_stat and target_stat.level > _stat_manager.level:
		## Target is stronger. Chance to flee.
		if randf() <= flee_chance:
			current_state = State.FLEE
	else:
		## Target is weaker. Chance to chase.
		if randf() <= chase_chance:
			current_state = State.CHASE

func _on_aggro_exited(area: Area2D) -> void:
	if current_state != State.CHASE: return
	if not area is BodyArea: return
	
	var potential_target := area.get_parent().get_parent() as CharacterBody2D
	
	## If the target we are chasing left our aggro radius
	if potential_target == target:
		## Roll the chance again. If we fail the roll, we give up!
		if randf() > chase_chance:
			_return_to_wander()

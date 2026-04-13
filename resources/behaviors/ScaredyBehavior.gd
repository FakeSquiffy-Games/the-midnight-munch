class_name ScaredyBehavior
extends Node

enum State { WANDER, FLEE }

@export var wander_speed_multiplier: float = 1.0
@export var flee_speed_multiplier: float = 2.0

var _entity: CharacterBody2D
var _stat_manager: StatManager
var _aggro_zone: Area2D

var current_state: State = State.WANDER
var target: CharacterBody2D = null
var move_direction: Vector2 = Vector2.RIGHT
var state_timer: float = 0.0

func _ready() -> void:
	_entity = owner as CharacterBody2D
	_stat_manager = _entity.get_node("StatManager")
	_aggro_zone = _entity.get_node_or_null("components/AggroZone")
	
	if multiplayer.is_server():
		if _aggro_zone:
			_aggro_zone.set_collision_mask_value(1, false)
			_aggro_zone.set_collision_mask_value(3, true)
			_aggro_zone.area_entered.connect(_on_aggro_entered)
		_pick_new_wander_direction()

func trigger_cooldown(duration: float = 2.0) -> void:
	target = null
	current_state = State.WANDER
	_pick_new_wander_direction()

func _physics_process(delta: float) -> void:
	if not multiplayer.is_server() or not is_instance_valid(_entity): return

	if current_state == State.WANDER:
		state_timer -= delta
		if _entity.is_on_wall() or state_timer <= 0.0:
			_pick_new_wander_direction()
		_entity.velocity = move_direction * (_stat_manager.speed * wander_speed_multiplier)
		
	elif current_state == State.FLEE:
		if not is_instance_valid(target) or target.is_queued_for_deletion() or _entity.global_position.distance_to(target.global_position) > 800.0:
			trigger_cooldown()
		else:
			## Constantly adjust direction away from the threat
			var away_dir = target.global_position.direction_to(_entity.global_position)
			## Add slight noise to simulate panic
			away_dir = away_dir.rotated(randf_range(-0.1, 0.1)).normalized()
			
			## Apply the new flee speed multiplier here!
			_entity.velocity = away_dir * (_stat_manager.speed * flee_speed_multiplier)

	_entity.move_and_slide()
	_entity.update_facing(_entity.velocity)

func _pick_new_wander_direction() -> void:
	move_direction = Vector2(randf_range(-1, 1), randf_range(-1, 1)).normalized()
	state_timer = randf_range(2.0, 5.0)

func _on_aggro_entered(area: Area2D) -> void:
	if current_state == State.FLEE: return
	if not area is BodyArea: return
	
	var potential_target := area.get_parent().get_parent() as CharacterBody2D
	if potential_target == null or potential_target == _entity: return
	
	## Scaredy fish flee from EVERYTHING.
	target = potential_target
	current_state = State.FLEE

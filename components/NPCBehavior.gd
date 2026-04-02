## NPCBehavior.gd
class_name NPCBehavior
extends Node

enum State { WANDER, LUNGE }

@export var is_inedible: bool = false
@export var wander_speed_multiplier: float = 0.4

var _entity: CharacterBody2D
var _stat_manager: StatManager
var _aggro_zone: Area2D

var current_state: State = State.WANDER
var target: CharacterBody2D = null
var wander_direction: Vector2 = Vector2.RIGHT
var state_timer: float = 0.0

func _ready() -> void:
	_entity = owner as CharacterBody2D
	_stat_manager = _entity.get_node("components/StatManager")
	_aggro_zone = _entity.get_node_or_null("AggroZone")
	
	if is_inedible:
		_entity.add_to_group("npc_inedible")
	
	if multiplayer.is_server():
		if _aggro_zone != null:
			_aggro_zone.area_entered.connect(_on_aggro_entered)
			
		## Ensure they start by swimming roughly toward the center of the arena
		var dir_to_center := _entity.global_position.direction_to(Vector2.ZERO)
		wander_direction = dir_to_center.rotated(randf_range(-0.5, 0.5)).normalized()
		state_timer = randf_range(2.0, 5.0)

func _physics_process(delta: float) -> void:
	if not multiplayer.is_server(): return
	if not is_instance_valid(_entity): return

	match current_state:
		State.WANDER:
			_process_wander(delta)
		State.LUNGE:
			_process_lunge()
			
	_entity.move_and_slide()
	_update_facing(_entity.velocity)

func _process_wander(delta: float) -> void:
	state_timer -= delta
	if state_timer <= 0.0:
		_pick_new_wander_direction()
		
	_entity.velocity = wander_direction * (_stat_manager.speed * wander_speed_multiplier)
	
	## Prevent jitter trap: Force direction inward using abs() instead of *= -1
	if _entity.global_position.x > 1700.0:
		wander_direction.x = -abs(wander_direction.x)
	elif _entity.global_position.x < -1700.0:
		wander_direction.x = abs(wander_direction.x)

	if _entity.global_position.y > 950.0:
		wander_direction.y = -abs(wander_direction.y)
	elif _entity.global_position.y < -950.0:
		wander_direction.y = abs(wander_direction.y)

func _process_lunge() -> void:
	if not is_instance_valid(target) or target.is_queued_for_deletion():
		_return_to_wander()
		return
		
	var dist := _entity.global_position.distance_to(target.global_position)
	if dist > 600.0: # Lose aggro if target escapes too far
		_return_to_wander()
		return

	var direction := _entity.global_position.direction_to(target.global_position)
	_entity.velocity = direction * _stat_manager.speed
	
	#print("NPCBehavior: Lunging towards %s" % str(direction))

func _pick_new_wander_direction() -> void:
	wander_direction = Vector2(randf_range(-1, 1), randf_range(-1, 1)).normalized()
	state_timer = randf_range(2.0, 5.0)

func _return_to_wander() -> void:
	target = null
	current_state = State.WANDER
	_pick_new_wander_direction()

func _on_aggro_entered(area: Area2D) -> void:
	if current_state == State.LUNGE: return
	if not area is BodyArea: return
	
	var potential_target := area.get_parent().get_parent() as CharacterBody2D
	if potential_target == null or potential_target == _entity: return
	if potential_target.is_in_group("npc_inedible"): return
	
	target = potential_target
	current_state = State.LUNGE

func _update_facing(direction: Vector2) -> void:
	if direction.x > 0.01:
		_entity.sync_flip_h = false
	elif direction.x < -0.01:
		_entity.sync_flip_h = true

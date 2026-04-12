class_name RammerBehavior
extends Node

enum State { WANDER, TELEGRAPH, DASH }

@export var wander_speed_multiplier: float = 0.4
@export var dash_speed_multiplier: float = 3.0

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
	state_timer = duration
	_pick_new_wander_direction()

func _physics_process(delta: float) -> void:
	if not multiplayer.is_server() or not is_instance_valid(_entity): return

	match current_state:
		State.WANDER:
			state_timer -= delta
			if _entity.is_on_wall() or state_timer <= 0.0:
				_pick_new_wander_direction()
			_entity.velocity = move_direction * (_stat_manager.speed * wander_speed_multiplier)
			_entity.update_facing(_entity.velocity)
			
		State.TELEGRAPH:
			state_timer -= delta
			_entity.velocity = Vector2.ZERO # Stop moving to "charge up"
			if state_timer <= 0.0:
				current_state = State.DASH
				state_timer = 1.5 # Dash duration
				
		State.DASH:
			state_timer -= delta
			_entity.velocity = move_direction * (_stat_manager.speed * dash_speed_multiplier)
			if state_timer <= 0.0 or _entity.is_on_wall():
				trigger_cooldown()

	_entity.move_and_slide()

func _pick_new_wander_direction() -> void:
	move_direction = Vector2(randf_range(-1, 1), randf_range(-1, 1)).normalized()
	state_timer = randf_range(2.0, 5.0)

func _on_aggro_entered(area: Area2D) -> void:
	if current_state != State.WANDER: return
	if not area is BodyArea: return
		
	var potential_target := area.get_parent().get_parent() as CharacterBody2D
	if potential_target == null or potential_target == _entity: return
	if potential_target.is_in_group("npc_inedible"): return
	
	target = potential_target
	var target_stat := target.get_node_or_null("StatManager") as StatManager
	
	## Only attack if the target is weaker or equal!
	if target_stat and target_stat.level <= _stat_manager.level:
		current_state = State.TELEGRAPH
		state_timer = 1.0 # 1 second warning before charging
		move_direction = _entity.global_position.direction_to(target.global_position)
		_entity.update_facing(move_direction) # Face the target while charging up

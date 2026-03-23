class_name PlayerController
extends Node


# =========================================================
# CONSTANTS
# =========================================================

const BOOST_MULTIPLIER: float = 1.8


# =========================================================
# NODE REFERENCES
# =========================================================

var _player:       CharacterBody2D
var _stat_manager: StatManager
var _sprite:       AnimatedSprite2D
var _mouth: MouthArea  # New reference


# =========================================================
# LIFECYCLE
# =========================================================

func _ready() -> void:
	_player       = owner as CharacterBody2D
	_stat_manager = owner.get_node("components/StatManager") as StatManager


func _physics_process(_delta: float) -> void:
	## Guard against processing after the player node has been freed
	## or during the elimination cleanup window.
	if not is_instance_valid(_player) or not is_instance_valid(_stat_manager):
		return

	if not _player.is_multiplayer_authority():
		return

	var direction   := _get_input_direction()
	var wants_boost := Input.is_action_pressed("boost")
	var delta       := get_physics_process_delta_time()

	if multiplayer.is_server():
		_set_boost_intent(wants_boost)
	else:
		## Mirror the server's energy logic locally so current_energy
		## reaches zero at the same frame on the client, preventing
		## a one-frame boost overshoot while waiting for the sync.
		if wants_boost and _stat_manager.current_energy > 0.0:
			_stat_manager.current_energy -= _stat_manager.energy_drain_rate * delta
			_stat_manager.current_energy  = maxf(_stat_manager.current_energy, 0.0)
			_stat_manager.is_boosting     = _stat_manager.current_energy > 0.0
		else:
			_stat_manager.is_boosting    = false
			_stat_manager.current_energy = minf(
				_stat_manager.current_energy + _stat_manager.energy_regen_rate * delta,
				_stat_manager.max_energy)
		_set_boost_intent.rpc_id(1, wants_boost)
	
	#print("Energy: %.1f | Boosting: %s" % [_stat_manager.current_energy, str(_stat_manager.is_boosting)])
	
	var current_speed := _stat_manager.speed
	if _stat_manager.is_boosting:
		current_speed *= BOOST_MULTIPLIER

	_player.velocity = direction * current_speed
	_player.move_and_slide()

	_update_facing(direction)

	if not multiplayer.is_server():
		_report_position.rpc_id(1, _player.global_position)


# =========================================================
# INPUT
# =========================================================

func _get_input_direction() -> Vector2:
	var dir := Vector2.ZERO
	dir.x    = Input.get_axis("move_left", "move_right")
	dir.y    = Input.get_axis("move_up", "move_down")
	return dir.normalized()


## Replace _update_facing in PlayerController.gd
func _update_facing(direction: Vector2) -> void:
	if direction.x > 0.01:
		_player.sync_flip_h = false
	elif direction.x < -0.01:
		_player.sync_flip_h = true


# =========================================================
# BOOST RPC
# =========================================================

@rpc("any_peer", "call_local", "unreliable")
func _set_boost_intent(wants_boost: bool) -> void:
	if not multiplayer.is_server():
		return

	var delta := get_physics_process_delta_time()

	if wants_boost and _stat_manager.current_energy > 0.0:
		_stat_manager.current_energy -= _stat_manager.energy_drain_rate * delta
		_stat_manager.current_energy  = maxf(_stat_manager.current_energy, 0.0)
		_stat_manager.is_boosting     = _stat_manager.current_energy > 0.0
	else:
		_stat_manager.is_boosting    = false
		_stat_manager.current_energy = minf(
			_stat_manager.current_energy + _stat_manager.energy_regen_rate * delta,
			_stat_manager.max_energy)

	## Use RPC emit so the signal fires on all peers, not just the server.
	## This ensures the client's HUD receives the update.
	SignalBus.emit_energy_changed.rpc(
		_player.get_multiplayer_authority(),
		_stat_manager.current_energy,
		_stat_manager.max_energy)


# =========================================================
# POSITION REPORTING
# =========================================================

@rpc("any_peer", "call_remote", "unreliable")
func _report_position(client_pos: Vector2) -> void:
	if not multiplayer.is_server():
		return
	_player.global_position = client_pos

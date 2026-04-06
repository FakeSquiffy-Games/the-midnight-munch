## PlayerController.gd
## Handles input and movement for the local player fish.
## Runs movement locally on the authority client for responsiveness.
## Boost intent is sent to the server via RPC — energy is server-authoritative.
class_name PlayerController
extends Node


# =========================================================
# CONSTANTS
# =========================================================

const BOOST_MULTIPLIER: float = 1.8
const SPECTATOR_SPEED: float = 1000.0


# =========================================================
# NODE REFERENCES
# =========================================================

var _player:       CharacterBody2D
var _stat_manager: StatManager
var _mouth:        MouthArea
var is_spectating: bool = false


# =========================================================
# LIFECYCLE
# =========================================================

func _ready() -> void:
	_player       = owner as CharacterBody2D
	_stat_manager = owner.get_node("StatManager") as StatManager
	## _mouth is assigned by Player.load_model() after the model is instantiated.
	## It is null here — do not access it in _ready().


func _physics_process(_delta: float) -> void:
	## Guard against processing after elimination or before model is loaded.
	if not is_instance_valid(_player) or not is_instance_valid(_stat_manager):
		return

	if not _player.is_multiplayer_authority():
		return

	var direction   := _get_input_direction()
	
	if is_spectating:
		## Simple ghost movement: ignore boost/energy/flipping
		_player.velocity = direction * SPECTATOR_SPEED
		_player.move_and_slide()
		return
	
	var wants_boost := Input.is_action_pressed("boost")
	var delta       := get_physics_process_delta_time()

	if multiplayer.is_server():
		_set_boost_intent(wants_boost)
	else:
		## Mirror server energy logic locally to prevent one-frame overshoot.
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

	var current_speed := _stat_manager.speed
	if _stat_manager.is_boosting:
		current_speed *= BOOST_MULTIPLIER

	_player.velocity = direction * current_speed
	_player.move_and_slide()

	_player.update_facing(direction)

	if not multiplayer.is_server():
		_report_position.rpc_id(1, _player.global_position)


# =========================================================
# INPUT
# =========================================================

## Returns a normalised movement vector from arrow key input.
func _get_input_direction() -> Vector2:
	var dir := Vector2.ZERO
	dir.x    = Input.get_axis("move_left", "move_right")
	dir.y    = Input.get_axis("move_up", "move_down")
	return dir.normalized()


### Updates sync_flip_h on the Player root to flip the entire node
### including CollisionPolygons. MouthArea follows automatically.
#func _update_facing(direction: Vector2) -> void:
	#if direction.x > 0.01:
		#_player.sync_flip_h = false
	#elif direction.x < -0.01:
		#_player.sync_flip_h = true


# =========================================================
# BOOST RPC
# =========================================================

## Received by the server from the authority client each physics frame.
## Server resolves energy drain/regen and sets is_boosting authoritatively.
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

	SignalBus.emit_energy_changed.rpc(
		_player.get_multiplayer_authority(),
		_stat_manager.current_energy,
		_stat_manager.max_energy)


# =========================================================
# POSITION REPORTING
# =========================================================

## Received by the server each physics frame from the authority client.
## Updates server-side position for reconciliation in Player.gd.
@rpc("any_peer", "call_remote", "unreliable")
func _report_position(client_pos: Vector2) -> void:
	if not multiplayer.is_server():
		return
	_player.global_position = client_pos

class_name EffectComponent
extends Node

@export var stat: StatManager.StatType
@export var boost_amount: float
@export var duration: float # 0 = permanent, >0 = timed

func apply_to(target: CharacterBody2D) -> void:
	if not multiplayer.is_server(): return
	
	var peer_id := target.get_multiplayer_authority()
	
	## Tell ALL peers that this specific player got a boost.
	## "call_local" ensures the server also applies it to its own simulation.
	SignalBus.emit_boost_applied.rpc(peer_id, stat, boost_amount, duration)
	
	owner.queue_free() # Destroy the collectible entity

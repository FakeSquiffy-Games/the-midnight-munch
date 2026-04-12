class_name EffectComponent
extends Node

@export var stat: StatManager.StatType
@export var boost_amount: float
@export var duration: float # 0 = permanent, >0 = timed

## PHASE 8.5: HAZARD & COMBAT TOGGLES
@export var destroy_on_consume: bool = true # True for Collectibles, False for Hazards
@export var apply_on_attack: bool = false   # E.g., Venomous bite
@export var apply_on_defend: bool = true    # E.g., Poison spikes / Collectible

func apply_to(target: CharacterBody2D) -> void:
	if not multiplayer.is_server(): return
	
	## Use the absolute NodePath so the correct entity gets the boost
	var target_path := str(target.get_path())
	
	## Tell ALL peers that this specific player got a boost.
	## "call_local" ensures the server also applies it to its own simulation.
	SignalBus.emit_boost_applied.rpc(target_path, stat, boost_amount, duration)
	
	if destroy_on_consume:
		owner.queue_free()

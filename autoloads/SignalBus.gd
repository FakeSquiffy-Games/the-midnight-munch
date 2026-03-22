## SignalBus.gd
## Global event relay autoload. Components emit signals here; systems listen here.
## This node never holds state — it is a pure communication channel.
extends Node


# =========================================================
# COMBAT SIGNALS
# =========================================================

## Emitted by MouthArea on the authority client when an overlap is detected.
## Not used for state — just a local trigger before the RPC is sent.
signal mouth_connected(attacker: Node, defender: Node)

## Emitted by CombatResolver on the server after a bite XP drain is applied.
signal xp_changed(peer_id: int, new_xp: float)

## Emitted by CombatResolver on the server after a level change is derived from XP.
signal level_changed(peer_id: int, new_level: int)

## Emitted by CombatResolver on the server after a tier shift is detected.
signal tier_changed(peer_id: int, new_tier: int)

## Emitted by CombatResolver on the server when a player reaches the death floor
## and is eliminated. Listened to by GameState and the match loop.
signal player_eliminated(peer_id: int)


# =========================================================
# ENERGY / BOOST SIGNALS
# =========================================================

## Emitted by the server after authoritative energy state changes.
## Listened to by HUD to update the energy bar.
signal energy_changed(peer_id: int, current: float, maximum: float)

## Emitted by the server when boost active state changes.
## Listened to by AnimationHandler and VFX nodes.
signal boost_state_changed(peer_id: int, is_boosting: bool)


# =========================================================
# COLLECTIBLE SIGNALS
# =========================================================

## Emitted by EffectComponent on the server when a collectible is collected.
signal collectible_collected(player: Node, effect: Node)

## Emitted by EffectComponent on the server after a stat boost is applied.
## Carries duration = 0 for permanent boosts.
signal boost_applied(peer_id: int, stat: int, amount: float, duration: float)


# =========================================================
# MATCH SIGNALS
# =========================================================

## Emitted by GameState on the server when exactly one player remains alive.
signal match_ended(winner_peer_id: int)

## Emits energy_changed on all peers via RPC.
## Called by PlayerController on the server instead of emitting directly.
@rpc("authority", "call_local", "reliable")
func emit_energy_changed(peer_id: int, current: float, maximum: float) -> void:
	energy_changed.emit(peer_id, current, maximum)

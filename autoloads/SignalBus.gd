## SignalBus.gd
## Global event relay autoload. Components emit signals here; systems listen here.
## Never holds state — pure communication channel.
## RPC emitters are used for signals that must fire on all peers.
extends Node


# =========================================================
# COMBAT SIGNALS
# =========================================================

## Emitted locally when MouthArea detects an overlap before RPC is sent.
signal mouth_connected(attacker: Node, defender: Node)

## Emitted on all peers when a bite XP drain is applied.
signal xp_changed(peer_id: int, new_xp: float)

## Emitted on all peers when a player's derived level changes.
signal level_changed(peer_id: int, new_level: int)

## Emitted on all peers when a player's tier changes.
signal tier_changed(peer_id: int, new_tier: int)

## Emitted on all peers when a player is eliminated.
signal player_eliminated(peer_id: int)


# =========================================================
# ENERGY / BOOST SIGNALS
# =========================================================

## Emitted on all peers when energy state changes.
signal energy_changed(peer_id: int, current: float, maximum: float)

## Emitted on all peers when boost active state changes.
signal boost_state_changed(peer_id: int, is_boosting: bool)


# =========================================================
# COLLECTIBLE SIGNALS
# =========================================================

## Emitted on all peers when a collectible is collected.
signal collectible_collected(player: Node, effect: Node)

## Emitted on all peers after a stat boost is applied.
signal boost_applied(target_path: String, stat: int, amount: float, duration: float)


# =========================================================
# MATCH SIGNALS
# =========================================================

## Emitted on all peers when exactly one player remains alive.
signal match_ended(winner_peer_id: int)


# =========================================================
# RPC EMITTERS
# =========================================================

## Broadcasts energy_changed to all peers.
@rpc("authority", "call_local", "reliable")
func emit_energy_changed(peer_id: int, current: float, maximum: float) -> void:
	energy_changed.emit(peer_id, current, maximum)


## Broadcasts xp_changed to all peers.
@rpc("authority", "call_local", "reliable")
func emit_xp_changed(peer_id: int, new_xp: float) -> void:
	xp_changed.emit(peer_id, new_xp)


## Broadcasts level_changed to all peers.
@rpc("authority", "call_local", "reliable")
func emit_level_changed(peer_id: int, new_level: int) -> void:
	level_changed.emit(peer_id, new_level)


## Broadcasts tier_changed to all peers.
@rpc("authority", "call_local", "reliable")
func emit_tier_changed(peer_id: int, new_tier: int) -> void:
	tier_changed.emit(peer_id, new_tier)


## Broadcasts player_eliminated to all peers.
@rpc("authority", "call_local", "reliable")
func emit_player_eliminated(peer_id: int) -> void:
	player_eliminated.emit(peer_id)


## Broadcasts boost_applied to all peers.
@rpc("authority", "call_local", "reliable")
func emit_boost_applied(target_path: String, stat: int, amount: float, duration: float) -> void:
	boost_applied.emit(target_path, stat, amount, duration)

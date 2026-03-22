## CombatResolver.gd
## Stateless combat resolution. All methods are static.
## Only called on the server — never on clients.
class_name CombatResolver
extends Node


# =========================================================
# CONSTANTS
# =========================================================

## Extra distance tolerance added to bite validation to account for
## LAN latency between client overlap detection and server receipt.
const NETWORK_MARGIN: float = 80.0

## Base XP drained from defender per bite before attacker level scaling.
const BASE_BITE_XP: float = 8.0

## XP drain scales upward by this fraction per attacker level.
## Lv 1 bite ≈ 9.2 XP | Lv 10 bite ≈ 20.0 XP.
const BITE_SCALE_PER_LEVEL: float = 0.15

## Fraction of drained XP awarded to the attacker on a BITE result.
## Tune during playtesting — lower if level skips feel too frequent.
const BITE_XP_ATTACKER_SHARE: float = 0.50

## Fraction of defender's current XP awarded to attacker on a KILL/ELIMINATION.
## Tune during playtesting.
const KILL_XP_ATTACKER_SHARE: float = 0.25

## Minimum XP awarded to attacker on ELIMINATION regardless of defender XP.
## Prevents zero-reward kills at the death floor.
const ELIMINATION_MIN_XP: float = 25.0


# =========================================================
# RESULT ENUM
# =========================================================

enum Result { ELIMINATION, KILL, BITE }


# =========================================================
# PUBLIC API
# =========================================================

## Entry point called by Player.request_bite() on the server.
## Validates attack distance then applies the resolved outcome.
## Returns false if the request was rejected, true if applied.
static func process_bite_request(
		attacker: CharacterBody2D,
		defender: CharacterBody2D) -> bool:

	if not _validate_distance(attacker, defender):
		print("CombatResolver: Rejected bite — distance too large.")
		return false

	apply(attacker, defender)
	return true


# =========================================================
# RESOLUTION
# =========================================================

## Resolves and applies the combat outcome for attacker vs defender.
## Must only be called on the server.
static func apply(
		attacker: CharacterBody2D,
		defender: CharacterBody2D) -> void:

	var result           := resolve(attacker, defender)
	var defender_peer_id := defender.get_multiplayer_authority()
	var attacker_peer_id := attacker.get_multiplayer_authority()
	var is_npc_attacker  := not attacker.is_in_group("players")

	match result:

		Result.ELIMINATION:
			print("CombatResolver: ELIMINATION — peer %d eliminated by peer %d." \
				% [defender_peer_id, attacker_peer_id])
			## Award XP to attacker unless it is an NPC.
			if not is_npc_attacker:
				var d_stat: StatManager = defender.get_node("components/StatManager")
				var reward := maxf(
					d_stat.current_xp * KILL_XP_ATTACKER_SHARE,
					ELIMINATION_MIN_XP)
				_apply_xp_gain(attacker, reward)
			GameState.eliminate_player(defender_peer_id)
			SignalBus.emit_player_eliminated.rpc(defender_peer_id)

		Result.KILL:
			if attacker.is_in_group("players"):
				## PvP KILL — immediate elimination with XP reward.
				print("CombatResolver: PvP KILL — peer %d eliminated by peer %d." \
					% [defender_peer_id, attacker_peer_id])
				var d_stat: StatManager = defender.get_node("components/StatManager")
				var reward := maxf(
					d_stat.current_xp * KILL_XP_ATTACKER_SHARE,
					ELIMINATION_MIN_XP)
				_apply_xp_gain(attacker, reward)
				GameState.eliminate_player(defender_peer_id)
				SignalBus.emit_player_eliminated.rpc(defender_peer_id)
			else:
				## NPC KILL — subtract one level's XP gap, no XP reward.
				print("CombatResolver: NPC KILL — peer %d demoted by NPC." \
					% defender_peer_id)
				_apply_npc_demotion(defender)

		Result.BITE:
			_apply_bite_xp_drain(attacker, defender)


## Pure resolution — returns Result without applying state.
## Checks death floor first, then tier/level hierarchy.
static func resolve(
		attacker: CharacterBody2D,
		defender: CharacterBody2D) -> Result:

	var d_stat: StatManager = defender.get_node("components/StatManager")
	var a_stat: StatManager = attacker.get_node("components/StatManager")

	## Death floor — any hit at Level 0 / 0 XP is always elimination.
	if d_stat.level == 0 and d_stat.current_xp <= 0.0:
		return Result.ELIMINATION

	## NPC KILL at Level 0 regardless of XP — no level below to subtract.
	if d_stat.level == 0 and not attacker.is_in_group("players"):
		return Result.KILL

	var a_tier  := a_stat.tier
	var a_level := a_stat.level
	var d_tier  := d_stat.tier
	var d_level := d_stat.level

	if a_tier > d_tier:
		return Result.KILL

	if a_tier == d_tier and a_level >= d_level + 2:
		return Result.KILL

	return Result.BITE


# =========================================================
# OUTCOME APPLIERS
# =========================================================

## Drains XP from defender and awards a share to the attacker.
static func _apply_bite_xp_drain(
		attacker: CharacterBody2D,
		defender: CharacterBody2D) -> void:

	var a_stat: StatManager  = attacker.get_node("components/StatManager")
	var d_stat: StatManager  = defender.get_node("components/StatManager")
	var defender_peer_id     := defender.get_multiplayer_authority()

	var xp_loss := _calculate_bite_xp(a_stat.level)

	## Clamp actual drain to what the defender actually has.
	## Prevents over-draining below zero and inflating attacker reward.
	var actual_drain := minf(xp_loss, d_stat.current_xp)

	_apply_xp_loss(defender, actual_drain)

	## Attacker gains a share of the actual XP drained.
	var attacker_gain := actual_drain * BITE_XP_ATTACKER_SHARE
	_apply_xp_gain(attacker, attacker_gain)

	print("CombatResolver: BITE — peer %d lost %.1f XP, peer %d gained %.1f XP." \
		% [defender_peer_id, actual_drain,
		   attacker.get_multiplayer_authority(), attacker_gain])


## Subtracts one full level's XP gap from the defender (NPC KILL path).
## NPC attacker gains no XP.
static func _apply_npc_demotion(defender: CharacterBody2D) -> void:
	var d_stat: StatManager = defender.get_node("components/StatManager")
	var xp_gap              := d_stat.get_level_xp_gap()
	_apply_xp_loss(defender, xp_gap)

	print("CombatResolver: NPC demotion — peer %d lost %.1f XP. New XP: %.1f." \
		% [defender.get_multiplayer_authority(), xp_gap, d_stat.current_xp])


# =========================================================
# XP MUTATION HELPERS
# =========================================================

## Subtracts [amount] XP from [target], clamps to 0, then broadcasts
## xp_changed and any resulting level/tier changes to all peers.
static func _apply_xp_loss(target: CharacterBody2D, amount: float) -> void:
	var stat: StatManager = target.get_node("components/StatManager")
	var peer_id           := target.get_multiplayer_authority()
	var old_level         := stat.level
	var old_tier          := stat.tier

	stat.current_xp = maxf(stat.current_xp - amount, 0.0)

	_broadcast_xp_changes(target, peer_id, old_level, old_tier)


## Adds [amount] XP to [target], then broadcasts xp_changed and any
## resulting level/tier changes to all peers.
static func _apply_xp_gain(target: CharacterBody2D, amount: float) -> void:
	var stat: StatManager = target.get_node("components/StatManager")
	var peer_id           := target.get_multiplayer_authority()
	var old_level         := stat.level
	var old_tier          := stat.tier

	## Cap XP at the maximum threshold (Level 10).
	var max_xp := StatManager.XP_THRESHOLDS[StatManager.XP_THRESHOLDS.size() - 1]
	stat.current_xp = minf(stat.current_xp + amount, max_xp)

	print("CombatResolver: XP gain — peer %d gained %.1f XP. New XP: %.1f." \
		% [peer_id, amount, stat.current_xp])

	_broadcast_xp_changes(target, peer_id, old_level, old_tier)


## Emits xp_changed, level_changed, and tier_changed RPCs as needed
## after any XP mutation. Updates GameState records if values changed.
static func _broadcast_xp_changes(
		target: CharacterBody2D,
		peer_id: int,
		old_level: int,
		old_tier: int) -> void:

	var stat: StatManager = target.get_node("components/StatManager")

	## Always sync XP — update GameState record and broadcast to all peers.
	GameState.update_player_xp(peer_id, stat.current_xp)
	SignalBus.emit_xp_changed.rpc(peer_id, stat.current_xp)

	if stat.level != old_level:
		print("CombatResolver: Level changed — peer %d is now Level %d." \
			% [peer_id, stat.level])
		SignalBus.emit_level_changed.rpc(peer_id, stat.level)
		if GameState.player_states.has(peer_id):
			GameState.player_states[peer_id].level = stat.level

	if stat.tier != old_tier:
		print("CombatResolver: Tier changed — peer %d is now Tier %d." \
			% [peer_id, stat.tier])
		SignalBus.emit_tier_changed.rpc(peer_id, stat.tier)


# =========================================================
# HELPERS
# =========================================================

## Returns XP drained per bite, scaled to attacker level.
static func _calculate_bite_xp(attacker_level: int) -> float:
	return BASE_BITE_XP * (1.0 + attacker_level * BITE_SCALE_PER_LEVEL)


## Validates that attacker and defender are close enough for the bite
## to be plausible given LAN latency.
static func _validate_distance(
		attacker: CharacterBody2D,
		defender: CharacterBody2D) -> bool:

	var dist     := attacker.global_position.distance_to(defender.global_position)
	var max_dist := 120.0 + NETWORK_MARGIN
	return dist <= max_dist

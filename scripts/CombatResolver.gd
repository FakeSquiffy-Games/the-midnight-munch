## CombatResolver.gd
## Stateless combat resolution. All methods are static.
## Only called on the server — never on clients.
class_name CombatResolver
extends Node

# =========================================================
# CONSTANTS
# =========================================================

const NETWORK_MARGIN: float         = 80.0
const BASE_BITE_XP: float           = 8.0
const BITE_SCALE_PER_LEVEL: float   = 0.15
const BITE_XP_ATTACKER_SHARE: float = 0.50
const KILL_XP_ATTACKER_SHARE: float = 0.25
const ELIMINATION_MIN_XP: float     = 25.0

# =========================================================
# RESULT ENUM
# =========================================================

enum Result { ELIMINATION, KILL, BITE, IGNORE }

# =========================================================
# PUBLIC API
# =========================================================

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

static func apply(attacker: CharacterBody2D, defender: CharacterBody2D) -> void:
	
	## PHASE 8.5: INTERCEPT EFFECTS (Collectibles & Hazards)
	var def_effect := defender.get_node_or_null("components/EffectComponent") as EffectComponent
	if def_effect and def_effect.apply_on_defend:
		def_effect.apply_to(attacker)
		if def_effect.destroy_on_consume:
			AudioManager.play_spatial_sound("power_up", attacker.global_position)

	var att_effect := attacker.get_node_or_null("components/EffectComponent") as EffectComponent
	if att_effect and att_effect.apply_on_attack:
		att_effect.apply_to(defender)

	var result           := resolve(attacker, defender)
	var defender_peer_id := defender.get_multiplayer_authority()
	var a_is_player      := attacker.is_in_group("players")
	var d_is_player      := defender.is_in_group("players")
	
	if result == Result.IGNORE: return
	
	AudioManager.play_spatial_sound("bite", defender.global_position)
	match result:
		Result.ELIMINATION, Result.KILL:
			
			if result == Result.KILL and not a_is_player and d_is_player:
				print("CombatResolver: NPC KILL — peer %d demoted by NPC." % defender_peer_id)
				_apply_npc_demotion(defender)
				return
			
			if a_is_player:
				var counts := true
				if not d_is_player and defender is NPC:
					counts = defender.counts_as_kill
				if counts:
					GameState.record_kill(attacker.get_multiplayer_authority(), d_is_player)
				
				var d_stat: StatManager = defender.get_node("StatManager")
				var reward := maxf(d_stat.current_xp * KILL_XP_ATTACKER_SHARE, ELIMINATION_MIN_XP)
				_apply_xp_gain(attacker, reward)
				print("CombatResolver: %s gained %.1f XP from killing %s." \
					% [attacker.name, reward, defender.name])

			if defender.has_method("play_elimination"):
				defender.play_elimination.rpc()

			if d_is_player:
				print("CombatResolver: Player %d eliminated by %s." \
					%[defender_peer_id, attacker.name])
				GameState.eliminate_player(defender_peer_id)
				SignalBus.emit_player_eliminated.rpc(defender_peer_id)
			else:
				var tree := defender.get_tree()
				if tree:
					tree.create_timer(1.0).timeout.connect(defender.queue_free)

		Result.BITE:
			_apply_bite_xp_drain(attacker, defender)


static func resolve(
		attacker: CharacterBody2D,
		defender: CharacterBody2D) -> Result:

	var d_stat: StatManager = defender.get_node("StatManager")
	var a_stat: StatManager = attacker.get_node("StatManager")
	var a_is_player         := attacker.is_in_group("players")
	var d_is_player         := defender.is_in_group("players")

	if d_stat.level == 0 and d_stat.current_xp <= 0.0:
		return Result.ELIMINATION

	var a_tier  := a_stat.tier
	var a_level := a_stat.level
	var d_tier  := d_stat.tier
	var d_level := d_stat.level

	if a_is_player and d_is_player:
		if a_level <= 0 and d_level <= 0: return Result.IGNORE
		if a_tier < 1 and d_tier < 1: return Result.BITE
		if a_tier > d_tier: return Result.KILL
		if a_tier == d_tier and a_level >= d_level + 2: return Result.KILL
	elif not a_is_player and d_is_player:
		if a_tier > d_tier: return Result.KILL
		if a_tier == d_tier and a_level >= d_level + 2: return Result.KILL
	else:
		if a_level > d_level: return Result.KILL

	return Result.BITE


# =========================================================
# OUTCOME APPLIERS
# =========================================================

static func _apply_bite_xp_drain(
		attacker: CharacterBody2D,
		defender: CharacterBody2D) -> void:

	var a_stat: StatManager  = attacker.get_node("StatManager")
	var d_stat: StatManager  = defender.get_node("StatManager")
	var defender_peer_id     := defender.get_multiplayer_authority()

	## Subphase 1.3: Apply Attacker's Bite Power
	var base_drain := _calculate_bite_xp(a_stat.level)
	base_drain *= maxf(a_stat.bite_power, 0.0) 

	## Subphase 1.3: Apply Defender's Damage Reduction
	## (damage_reduction is already clamped 0.0 - 1.0 in StatManager)
	var effective_drain := base_drain * (1.0 - d_stat.damage_reduction)

	var actual_drain := minf(effective_drain, d_stat.current_xp)

	_apply_xp_loss(defender, actual_drain)

	var attacker_gain := 0.0
	if attacker.is_in_group("players"):
		attacker_gain = actual_drain * BITE_XP_ATTACKER_SHARE
		_apply_xp_gain(attacker, attacker_gain)

	var target_path := str(defender.get_path())
	SignalBus.emit_boost_applied.rpc(target_path, StatManager.StatType.SPEED, 150.0, 1.5)

	var a_ai := attacker.get_node_or_null("components/ChaserBehavior") as ChaserBehavior
	var d_ai := defender.get_node_or_null("components/ChaserBehavior") as ChaserBehavior
	if a_ai: a_ai.trigger_cooldown()
	if d_ai: d_ai.trigger_cooldown()

	print("CombatResolver: BITE — peer %d lost %.1f XP, peer %d gained %.1f XP." \
		%[defender_peer_id, actual_drain,
		   attacker.get_multiplayer_authority(), attacker_gain])


static func _apply_npc_demotion(defender: CharacterBody2D) -> void:
	var d_stat: StatManager = defender.get_node("StatManager")
	var xp_gap              := d_stat.get_level_xp_gap()
	
	## Demotion acts as True Damage, bypassing Damage Reduction.
	_apply_xp_loss(defender, xp_gap)

	print("CombatResolver: NPC demotion — peer %d lost %.1f XP. New XP: %.1f." \
		%[defender.get_multiplayer_authority(), xp_gap, d_stat.current_xp])


# =========================================================
# XP MUTATION HELPERS
# =========================================================

static func _apply_xp_loss(target: CharacterBody2D, amount: float) -> void:
	var stat: StatManager = target.get_node("StatManager")
	var peer_id           := target.get_multiplayer_authority()
	var old_level         := stat.level
	var old_tier          := stat.tier

	stat.current_xp = maxf(stat.current_xp - amount, 0.0)
	_broadcast_xp_changes(target, peer_id, old_level, old_tier)


static func _apply_xp_gain(target: CharacterBody2D, amount: float) -> void:
	if not target.is_in_group("players"):
		return
	
	var stat: StatManager = target.get_node("StatManager")
	var peer_id           := target.get_multiplayer_authority()
	var old_level         := stat.level
	var old_tier          := stat.tier

	## Subphase 1.3: Apply XP Gain Multiplier (Cannot be negative)
	var effective_amount := amount * maxf(stat.xp_gain_multiplier, 0.0)

	var max_xp := StatManager.XP_THRESHOLDS[StatManager.XP_THRESHOLDS.size() - 1]
	stat.current_xp = minf(stat.current_xp + effective_amount, max_xp)

	print("CombatResolver: XP gain — peer %d gained %.1f XP. New XP: %.1f." \
		%[peer_id, effective_amount, stat.current_xp])

	GameState.record_xp_gained(peer_id, effective_amount, stat.level)
	_broadcast_xp_changes(target, peer_id, old_level, old_tier)


static func _broadcast_xp_changes(
		target: CharacterBody2D,
		peer_id: int,
		old_level: int,
		old_tier: int) -> void:

	var stat: StatManager = target.get_node("StatManager")

	if target.is_in_group("players"):
		GameState.update_player_xp(peer_id, stat.current_xp)
		SignalBus.emit_xp_changed.rpc(peer_id, stat.current_xp)

		if stat.level != old_level:
			SignalBus.emit_level_changed.rpc(peer_id, stat.level)
			if GameState.player_states.has(peer_id):
				GameState.player_states[peer_id].level = stat.level

		if stat.tier != old_tier:
			SignalBus.emit_tier_changed.rpc(peer_id, stat.tier)


# =========================================================
# HELPERS
# =========================================================

static func _calculate_bite_xp(attacker_level: int) -> float:
	return BASE_BITE_XP * (1.0 + attacker_level * BITE_SCALE_PER_LEVEL)

static func _validate_distance(attacker: CharacterBody2D, defender: CharacterBody2D) -> bool:
	var attacker_id := attacker.get_multiplayer_authority()
	var one_way_ping_ms := 0
	
	if attacker_id != 1 and attacker.multiplayer.multiplayer_peer is ENetMultiplayerPeer:
		var enet := attacker.multiplayer.multiplayer_peer as ENetMultiplayerPeer
		var rtt  := enet.get_peer(attacker_id).get_statistic(ENetPacketPeer.PEER_ROUND_TRIP_TIME)
		one_way_ping_ms = rtt / 2
	
	var def_path := str(defender.get_path())
	var past_pos := LagCompensator.get_historical_position(def_path, one_way_ping_ms)
	
	var def_pos := defender.global_position if past_pos == Vector2.INF else past_pos
	var dist    := attacker.global_position.distance_to(def_pos)
	
	var a_scale := 1.0
	var d_scale := 1.0
	if attacker is Entity: a_scale = attacker.current_scale_mult
	if defender is Entity: d_scale = defender.current_scale_mult
	
	var base_radius := 180.0
	var a_radius := base_radius * a_scale
	var d_radius := base_radius * d_scale
	
	var vel_margin := attacker.velocity.length() * 0.2
	var max_dist := a_radius + d_radius + NETWORK_MARGIN + vel_margin
	
	if dist > max_dist:
		return false
	return true

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

enum Result { ELIMINATION, KILL, BITE, IGNORE }


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
static func apply(attacker: CharacterBody2D, defender: CharacterBody2D) -> void:
	
	## PHASE 8.5: INTERCEPT EFFECTS (Collectibles & Hazards)
	var def_effect := defender.get_node_or_null("components/EffectComponent") as EffectComponent
	if def_effect and def_effect.apply_on_defend:
		def_effect.apply_to(attacker)
		if def_effect.destroy_on_consume:
			AudioManager.play_spatial_sound("level_up", attacker.global_position)
			#return # Stop combat, entity was consumed

	var att_effect := attacker.get_node_or_null("components/EffectComponent") as EffectComponent
	if att_effect and att_effect.apply_on_attack:
		att_effect.apply_to(defender)
		#if att_effect.destroy_on_consume:
			#return # Stop combat, entity was consumed

	var result           := resolve(attacker, defender)
	var defender_peer_id := defender.get_multiplayer_authority()
	var a_is_player      := attacker.is_in_group("players")
	var d_is_player      := defender.is_in_group("players")
	
	if result == Result.IGNORE: return
	
	AudioManager.play_spatial_sound("bite", defender.global_position)
	match result:
		Result.ELIMINATION, Result.KILL:
			
			## 1. Handle the "Demotion" exception (NPC killing a Player, but not at Death Floor)
			if result == Result.KILL and not a_is_player and d_is_player:
				print("CombatResolver: NPC KILL — peer %d demoted by NPC." % defender_peer_id)
				_apply_npc_demotion(defender)
				return
			
			## 2. All other Kills/Eliminations result in the defender dying.
			##    If the attacker is a player, calculate and award the XP share.
			if a_is_player:
				## RECORD THE KILL STAT
				var counts := true
				if not d_is_player and defender is NPC:
					counts = defender.counts_as_kill_stat
				if counts:
					GameState.record_kill(attacker.get_multiplayer_authority(), d_is_player)
				var d_stat: StatManager = defender.get_node("StatManager")
				var reward := maxf(d_stat.current_xp * KILL_XP_ATTACKER_SHARE, ELIMINATION_MIN_XP)
				_apply_xp_gain(attacker, reward)
				print("CombatResolver: %s gained %.1f XP from killing %s." \
					% [attacker.name, reward, defender.name])

			if defender.has_method("play_elimination"):
				defender.play_elimination.rpc()

			## 3. Process the defender's actual removal
			if d_is_player:
				print("CombatResolver: Player %d eliminated by %s." \
					% [defender_peer_id, attacker.name])
				GameState.eliminate_player(defender_peer_id)
				SignalBus.emit_player_eliminated.rpc(defender_peer_id)
			else:
				## Standard NPC removal (Will be swapped to Pool return in 6.5B)
				var tree := defender.get_tree()
				if tree:
					## FIX: Connect directly to the method. No lambda capture needed!
					tree.create_timer(1.0).timeout.connect(defender.queue_free)
				#defender.queue_free()

		Result.BITE:
			_apply_bite_xp_drain(attacker, defender)


## Pure resolution — returns Result without applying state.
## Checks death floor first, then tier/level hierarchy.
static func resolve(
		attacker: CharacterBody2D,
		defender: CharacterBody2D) -> Result:

	var d_stat: StatManager = defender.get_node("StatManager")
	var a_stat: StatManager = attacker.get_node("StatManager")
	var a_is_player         := attacker.is_in_group("players")
	var d_is_player         := defender.is_in_group("players")

	## Death floor — any hit at Level 0 / 0 XP is always elimination.
	if d_stat.level == 0 and d_stat.current_xp <= 0.0:
		return Result.ELIMINATION

	### NPC KILL at Level 0 regardless of XP — no level below to subtract.
	#if d_stat.level == 0 and not attacker.is_in_group("players"):
		#return Result.KILL

	var a_tier  := a_stat.tier
	var a_level := a_stat.level
	var d_tier  := d_stat.tier
	var d_level := d_stat.level

	if a_is_player and d_is_player:
		## Player vs Player (The Privilege applies to the defender)
		if a_level <= 0 and d_level <= 0: return Result.IGNORE
		if a_tier < 1 and d_tier < 1: return Result.BITE
		if a_tier > d_tier: return Result.KILL
		if a_tier == d_tier and a_level >= d_level + 2: return Result.KILL
	elif not a_is_player and d_is_player:
		## NPC vs Player (The Privilege applies to the defender)
		if a_tier > d_tier: return Result.KILL
		if a_tier == d_tier and a_level >= d_level + 2: return Result.KILL
	else:
		## Fast Combat: Player vs NPC, or NPC vs NPC
		if a_level > d_level: return Result.KILL

	return Result.BITE


# =========================================================
# OUTCOME APPLIERS
# =========================================================

## Drains XP from defender and awards a share to the attacker.
static func _apply_bite_xp_drain(
		attacker: CharacterBody2D,
		defender: CharacterBody2D) -> void:

	var a_stat: StatManager  = attacker.get_node("StatManager")
	var d_stat: StatManager  = defender.get_node("StatManager")
	var defender_peer_id     := defender.get_multiplayer_authority()

	var xp_loss := _calculate_bite_xp(a_stat.level)

	## Clamp actual drain to what the defender actually has.
	## Prevents over-draining below zero and inflating attacker reward.
	var actual_drain := minf(xp_loss, d_stat.current_xp)

	_apply_xp_loss(defender, actual_drain)

	## Attacker gains a share of the actual XP drained.
	var attacker_gain := 0.0
	if attacker.is_in_group("players"):
		attacker_gain = actual_drain * BITE_XP_ATTACKER_SHARE
		_apply_xp_gain(attacker, attacker_gain)

	## NEW: Escape Burst! Defender gets a 1.5s flat +150 speed boost to escape.
	var target_path := str(defender.get_path())
	SignalBus.emit_boost_applied.rpc(target_path, StatManager.StatType.SPEED, 150.0, 1.5)

	## NEW: Trigger Aggro Cooldown on AI to prevent infinite lunge loops
	var a_ai := attacker.get_node_or_null("components/ChaserBehavior") as ChaserBehavior
	var d_ai := defender.get_node_or_null("components/ChaserBehavior") as ChaserBehavior
	if a_ai: a_ai.trigger_cooldown()
	if d_ai: d_ai.trigger_cooldown()

	print("CombatResolver: BITE — peer %d lost %.1f XP, peer %d gained %.1f XP." \
		% [defender_peer_id, actual_drain,
		   attacker.get_multiplayer_authority(), attacker_gain])


## Subtracts one full level's XP gap from the defender (NPC KILL path).
## NPC attacker gains no XP.
static func _apply_npc_demotion(defender: CharacterBody2D) -> void:
	var d_stat: StatManager = defender.get_node("StatManager")
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
	var stat: StatManager = target.get_node("StatManager")
	var peer_id           := target.get_multiplayer_authority()
	var old_level         := stat.level
	var old_tier          := stat.tier

	stat.current_xp = maxf(stat.current_xp - amount, 0.0)

	_broadcast_xp_changes(target, peer_id, old_level, old_tier)


## Adds [amount] XP to [target], then broadcasts xp_changed and any
## resulting level/tier changes to all peers.
static func _apply_xp_gain(target: CharacterBody2D, amount: float) -> void:
	if not target.is_in_group("players"):
		return
	
	var stat: StatManager = target.get_node("StatManager")
	var peer_id           := target.get_multiplayer_authority()
	var old_level         := stat.level
	var old_tier          := stat.tier

	## Cap XP at the maximum threshold (Level 10).
	var max_xp := StatManager.XP_THRESHOLDS[StatManager.XP_THRESHOLDS.size() - 1]
	stat.current_xp = minf(stat.current_xp + amount, max_xp)

	print("CombatResolver: XP gain — peer %d gained %.1f XP. New XP: %.1f." \
		% [peer_id, amount, stat.current_xp])

	## RECORD THE XP STAT
	GameState.record_xp_gained(peer_id, amount, stat.level)

	_broadcast_xp_changes(target, peer_id, old_level, old_tier)


## Emits xp_changed, level_changed, and tier_changed RPCs as needed
## after any XP mutation. Updates GameState records if values changed.
static func _broadcast_xp_changes(
		target: CharacterBody2D,
		peer_id: int,
		old_level: int,
		old_tier: int) -> void:

	var stat: StatManager = target.get_node("StatManager")

	## Safety Guard: Only update GameState and Broadcast to HUDs 
	## if the entity is an actual player.
	if target.is_in_group("players"):
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
	
	## FIX: Use a highly generous base radius. 
	## Some fish models are long, putting the mouth far from the center.
	## Since the client's physics engine already proved the polygons touched,
	## this check just prevents extreme map-wide hacking.
	var a_scale := 1.0
	var d_scale := 1.0
	if attacker is Entity: a_scale = attacker.current_scale_mult
	if defender is Entity: d_scale = defender.current_scale_mult
	
	var base_radius := 180.0
	var a_radius := base_radius * a_scale
	var d_radius := base_radius * d_scale
	
	## Include a velocity margin (approx 200ms of movement) to account for 
	## the attacker's own slight position desync over the network.
	var vel_margin := attacker.velocity.length() * 0.2
	var max_dist := a_radius + d_radius + NETWORK_MARGIN + vel_margin
	
	if dist > max_dist:
		print("CombatResolver: Bite rejected! Dist: %.1f, Max: %.1f" % [dist, max_dist])
		return false
	return true

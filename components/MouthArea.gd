## MouthArea.gd
## Collision area at the fish snout. Detects BodyArea overlaps on the
## authority client only and sends request_bite RPC to the server.
## Positioned and scaled via PlayerModel — no hardcoded offsets needed.
class_name MouthArea
extends Area2D


# =========================================================
# NODE REFERENCES
# =========================================================

var _player: CharacterBody2D


# =========================================================
# LIFECYCLE
# =========================================================

func _ready() -> void:
	## Walk up: MouthArea → PlayerModel → Player (CharacterBody2D).
	_player = get_parent().get_parent() as CharacterBody2D

	## Only the authority client monitors overlaps — prevents duplicate
	## bite requests from all peers simultaneously.
	monitoring = _player.is_multiplayer_authority()

	area_entered.connect(_on_area_entered)


# =========================================================
# FACING
# =========================================================

## update_facing() is no longer needed — the Player root scale.x flip
## propagates to MouthArea automatically via the scene tree.
## Kept as a stub to avoid breaking any existing call sites.
func update_facing(_facing_right: bool) -> void:
	pass


# =========================================================
# OVERLAP DETECTION
# =========================================================

## Fires on the authority client when MouthArea overlaps a BodyArea.
## Sends bite request to server for authoritative validation.
func _on_area_entered(area: Area2D) -> void:
	if not area is BodyArea:
		return

	## BodyArea → PlayerModel → Player (CharacterBody2D)
	var target := area.get_parent().get_parent() as CharacterBody2D
	if target == null or target == _player:
		return

	## Send the absolute NodePath instead of peer_id to uniquely 
	## identify players, NPCs, and collectibles.
	var target_path      := str(target.get_path())
	var attacker_peer_id := _player.get_multiplayer_authority()

	print("MouthArea: Detected overlap with %s — sending request_bite." \
		% target.name)

	if multiplayer.is_server():
		if _player.is_in_group("players"):
			## Host Player attacking
			_player.request_bite(attacker_peer_id, target_path)
		else:
			## NPC attacking — resolve immediately
			if target.is_in_group("npc_inedible"):
				return
			CombatResolver.process_bite_request(_player, target)
	else:
		## Client Player attacking
		if _player.is_in_group("players"):
			_player.request_bite.rpc_id(1, attacker_peer_id, target_path)

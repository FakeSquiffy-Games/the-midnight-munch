class_name MouthArea
extends Area2D


# =========================================================
# CONSTANTS
# =========================================================

## Horizontal offset from fish center to snout when facing right.
## Matches half the fish width (40px / 2 = 20) plus the circle radius (8).
const SNOUT_OFFSET_X: float = 28.0


# =========================================================
# NODE REFERENCES
# =========================================================

var _player: CharacterBody2D


# =========================================================
# LIFECYCLE
# =========================================================

func _ready() -> void:
	## Walk up the tree: MouthArea → components → Player (CharacterBody2D)
	_player = get_parent().get_parent() as CharacterBody2D

	monitoring = _player.is_multiplayer_authority()
	area_entered.connect(_on_area_entered)


# =========================================================
# FACING SYNC
# =========================================================

## Called by PlayerController when the fish changes horizontal direction.
## Moves the MouthArea to always sit at the front (snout) of the fish.
## [facing_right] — true if fish is facing right, false if facing left.
func update_facing(facing_right: bool) -> void:
	position.x = SNOUT_OFFSET_X if facing_right else -SNOUT_OFFSET_X


# =========================================================
# OVERLAP DETECTION
# =========================================================

## Fires on the authority client when MouthArea overlaps a BodyArea.
## Sends a bite request RPC to the server for authoritative validation.
func _on_area_entered(area: Area2D) -> void:
	if not area is BodyArea:
		return

	var target := area.get_parent().get_parent() as CharacterBody2D
	if target == null:
		return
	if target == _player:
		return

	var target_peer_id   := target.get_multiplayer_authority()
	var attacker_peer_id := _player.get_multiplayer_authority()

	print("MouthArea: Detected overlap with peer %d — sending request_bite." \
		% target_peer_id)

	## Pass attacker_peer_id explicitly so the server can identify
	## the attacker without relying on get_remote_sender_id(),
	## which returns 0 for local (host) calls.
	if multiplayer.is_server():
		_player.request_bite(attacker_peer_id, target_peer_id)
	else:
		_player.request_bite.rpc_id(1, attacker_peer_id, target_peer_id)

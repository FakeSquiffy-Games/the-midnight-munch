## World.gd
## Root scene for active gameplay.
## Phase 3A fix 2: server waits for all peers to report ready before spawning,
## preventing spawn packets from arriving before the client scene is loaded.
extends Node2D


# =========================================================
# CONSTANTS
# =========================================================

const PLAYER_COLORS: Array[Color] = [
	Color(0.2, 0.6, 1.0),  ## Player 1 — blue
	Color(1.0, 0.3, 0.3),  ## Player 2 — red
	Color(0.2, 0.9, 0.2),  ## Player 3 — green
	Color(1.0, 0.8, 0.1),  ## Player 4 — yellow
]

const SPAWN_POSITIONS: Array[Vector2] = [
	Vector2(200, 360),
	Vector2(1080, 360),
	Vector2(640, 180),
	Vector2(640, 540),
]


# =========================================================
# NODE REFERENCES
# =========================================================

@onready var spawner: MultiplayerSpawner = $MultiplayerSpawner


# =========================================================
# STATE
# =========================================================

## Tracks which peers have confirmed their World scene is ready.
## Server only — used to gate _spawn_all_players().
var _peers_ready: Array = []


# =========================================================
# LIFECYCLE
# =========================================================

func _ready() -> void:
	print("World: Loaded on peer ID %d. Is server: %s." \
		% [multiplayer.get_unique_id(), str(multiplayer.is_server())])

	## Assign spawn function on all peers — must be set before any
	## spawn packets arrive, which is guaranteed since we set it here
	## in _ready() before notifying the server.
	spawner.spawn_function = _spawn_player

	## Every peer notifies the server that their World scene is ready.
	## rpc_id(1, ...) targets only the server (peer ID 1).
	_notify_ready.rpc_id(1)


# =========================================================
# READY HANDSHAKE
# =========================================================

## Called on the server by each peer (including the server itself via rpc_id).
## Once all expected peers have checked in, spawning begins.
@rpc("any_peer", "call_local", "reliable")
func _notify_ready() -> void:
	if not multiplayer.is_server():
		return

	var sender_id := multiplayer.get_remote_sender_id()

	## get_remote_sender_id() returns 0 when called locally (server calling
	## itself via call_local) — map 0 to peer ID 1 (the server's own ID).
	if sender_id == 0:
		sender_id = 1

	if not _peers_ready.has(sender_id):
		_peers_ready.append(sender_id)
		print("World: Peer %d reported ready. (%d / %d)" \
			% [sender_id, _peers_ready.size(), GameState.player_states.size()])

	## Spawn once every registered peer has reported in.
	if _peers_ready.size() >= GameState.player_states.size():
		print("World: All peers ready — spawning players.")
		_spawn_all_players()


# =========================================================
# SPAWNING
# =========================================================

## Iterates all registered peers and calls spawner.spawn() for each.
## Only runs on the server after all peers are confirmed ready.
func _spawn_all_players() -> void:
	var peer_ids: Array = GameState.player_states.keys()
	for i in peer_ids.size():
		var peer_id: int = peer_ids[i]
		var data := {
			"peer_id":  peer_id,
			"color":    PLAYER_COLORS[i % PLAYER_COLORS.size()],
			"position": SPAWN_POSITIONS[i % SPAWN_POSITIONS.size()],
		}
		spawner.spawn(data)
		print("World: Spawning player for peer %d at slot %d." % [peer_id, i])


## Spawn function — called on ALL peers by MultiplayerSpawner.
## Must return the Node to be added to the scene tree.
func _spawn_player(data: Dictionary) -> Node:
	var player_scene := preload("res://scenes/player/Player.tscn")
	var player       := player_scene.instantiate()

	var peer_id: int   = data["peer_id"]
	player.name        = "Player_%d" % peer_id
	player.spawn_color    = data["color"]
	player.spawn_position = data["position"]
	player.spawn_peer_id  = peer_id

	return player

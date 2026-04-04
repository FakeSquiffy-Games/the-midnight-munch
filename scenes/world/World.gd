## World.gd
## Root scene for active gameplay.
## Spawns players via MultiplayerSpawner after all peers confirm ready.
extends Node2D


# =========================================================
# CONSTANTS
# =========================================================

const PLAYER_COLORS: Array[Color] = [
	Color(0.2, 0.6, 1.0),  ## Slot 0 — blue
	Color(1.0, 0.3, 0.3),  ## Slot 1 — red
	Color(0.2, 0.9, 0.2),  ## Slot 2 — green
	Color(1.0, 0.8, 0.1),  ## Slot 3 — yellow
]

const SPAWN_POSITIONS: Array[Vector2] = [
	Vector2(-640, -360),
	Vector2(640, -360),
	Vector2(-640, 360),
	Vector2(640, 360),
]


# =========================================================
# EXPORTS
# =========================================================

## Paths to fish model PackedScenes assigned per player slot.
## Slot 0 = host, slots 1-3 = clients in join order.
## Replace with a character selection screen in a future phase.
## Current assignment: [BlackSeadevil, Fangtooth, BlackSeadevil, BlackSeadevil]
@export var PLAYER_MODELS: Array[String]


# =========================================================
# NODE REFERENCES
# =========================================================

@onready var spawner: MultiplayerSpawner = $MultiplayerSpawner


# =========================================================
# STATE
# =========================================================

## Tracks which peers have confirmed their World scene is ready.
## Server only — gates _spawn_all_players().
var _peers_ready: Array = []


# =========================================================
# LIFECYCLE
# =========================================================

func _ready() -> void:
	print("World: Loaded on peer ID %d. Is server: %s." \
		% [multiplayer.get_unique_id(), str(multiplayer.is_server())])

	add_to_group("world")
	spawner.spawn_function = _spawn_player
	
	if multiplayer.is_server():
		## Check if everyone is somehow already ready, otherwise wait for signal
		if GameState._peers_world_ready.size() >= GameState.player_states.size():
			_spawn_all_players()
		else:
			GameState.all_ready_for_world.connect(_spawn_all_players)

	## Notify the server's Autoload that this specific peer has loaded the scene
	GameState.notify_world_loaded.rpc_id(1)


# =========================================================
# READY HANDSHAKE
# =========================================================

@rpc("any_peer", "call_local", "reliable")
func _notify_ready() -> void:
	if not multiplayer.is_server():
		return

	var sender_id := multiplayer.get_remote_sender_id()
	if sender_id == 0:
		sender_id = 1

	if not _peers_ready.has(sender_id):
		_peers_ready.append(sender_id)
		print("World: Peer %d reported ready. (%d / %d)" \
			% [sender_id, _peers_ready.size(), GameState.player_states.size()])

	if _peers_ready.size() >= GameState.player_states.size():
		print("World: All peers ready — spawning players.")
		_spawn_all_players()


# =========================================================
# SPAWNING
# =========================================================

func _spawn_all_players() -> void:
	var peer_ids: Array = GameState.player_states.keys()
	for i in peer_ids.size():
		var peer_id: int = peer_ids[i]
		var data := {
			"peer_id":    peer_id,
			"color":      PLAYER_COLORS[i % PLAYER_COLORS.size()],
			"position":   SPAWN_POSITIONS[i % SPAWN_POSITIONS.size()],
			"model_path": PLAYER_MODELS[i % PLAYER_MODELS.size()],
		}
		spawner.spawn(data)
		print("World: Spawning player for peer %d at slot %d." % [peer_id, i])


## Spawn function called on ALL peers by MultiplayerSpawner.
## Must return the Node to be added to the scene tree.
func _spawn_player(data: Dictionary) -> Node:
	var player_scene := preload("res://scenes/entities/player/Player.tscn")
	var player       := player_scene.instantiate()

	var peer_id: int      = data["peer_id"]
	player.name           = "Player_%d" % peer_id
	player.spawn_position = data["position"]
	player.spawn_peer_id  = peer_id

	var model_path: String   = data["model_path"]
	var model_resource       = load(model_path)
	if model_resource is PackedScene:
		player.fish_model = model_resource
	else:
		push_error("World: Failed to load fish model at path: %s" % model_path)

	return player

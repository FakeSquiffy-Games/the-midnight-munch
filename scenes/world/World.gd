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

func _physics_process(_delta: float) -> void:
	if not multiplayer.is_server(): return
	if GameState.match_phase != GameState.MatchPhase.IN_GAME: return
	if GameState._peers_world_ready.size() < GameState.player_states.size(): return # Wait for spawn

	if GameState.is_single_player:
		
		var p1 = GameState.player_states.get(1)
		if p1:
			if not p1.is_alive:
				_trigger_end_match(0, "Game Over")
			elif p1.level >= 10:
				_trigger_end_match(1, GameState.player_names.get(1, "Player 1"))
	else:
		if GameState.alive_peers.size() <= 1:
			var winner_id = GameState.alive_peers[0] if GameState.alive_peers.size() == 1 else 0
			var winner_name = GameState.player_names.get(winner_id, "Draw") if winner_id != 0 else "Draw"
			_trigger_end_match(winner_id, winner_name)


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
			"scene_path": GameState.player_characters[peer_id] # Grab locked prefab
		}
		spawner.spawn(data)
		print("World: Spawning player for peer %d." % peer_id)

func _spawn_player(data: Dictionary) -> Node:
	var player_scene := load(data["scene_path"]) as PackedScene
	var player       := player_scene.instantiate() as Entity

	var peer_id: int      = data["peer_id"]
	player.name           = "Player_%d" % peer_id
	player.spawn_position = data["position"]
	player.spawn_peer_id  = peer_id

	## Note: We no longer load 'fish_model' here because the prefab already contains it!
	
	return player


# END
func _trigger_end_match(winner_id: int, winner_name: String) -> void:
	GameState.match_phase = GameState.MatchPhase.ENDED
	var end_time := Time.get_ticks_msec()
	
	## 1. Finalize survival times for anyone still alive
	for state in GameState.player_states.values():
		if state.is_alive:
			state.time_survived = (end_time - GameState.match_start_time_msec) / 1000.0

	## 2. Broadcast the winner UI
	_show_results.rpc(winner_id, winner_name)

	## 3. Send personal stats specifically to each client
	for peer_id in GameState.player_states.keys():
		var st = GameState.player_states[peer_id]
		var stats_dict = {
			"max_level": st.max_level_reached,
			"p_kills": st.total_player_kills,
			"n_kills": st.total_npc_kills,
			"xp": st.total_xp_collected,
			"time": st.time_survived
		}
		if peer_id == 1:
			SignalBus.personal_stats_received.emit(stats_dict)
		else:
			_send_stats.rpc_id(peer_id, stats_dict)

@rpc("authority", "call_local", "reliable")
func _show_results(_winner_id: int, winner_name: String) -> void:
	var results_scene = preload("res://scenes/ui/ResultsUI.tscn")
	if results_scene:
		var ui = results_scene.instantiate()
		get_tree().root.add_child(ui)
		ui.setup(winner_name)

@rpc("authority", "call_remote", "reliable")
func _send_stats(stats_dict: Dictionary) -> void:
	SignalBus.personal_stats_received.emit(stats_dict)

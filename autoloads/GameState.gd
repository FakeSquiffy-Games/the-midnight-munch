## GameState.gd
## Server-authoritative match state. Only the server writes to this autoload.
## Clients read replicated values via MultiplayerSynchronizer — never directly.
extends Node

signal all_ready_for_world
var _peers_world_ready: Array =[]
var is_single_player: bool = false


# =========================================================
# TYPES
# =========================================================

## Per-player state record stored in player_states.
class PlayerState:
	var peer_id:  int   = 0
	var level:    int   = 0
	var xp:       float = 0.0
	var is_alive: bool  = true

	## PHASE 8: MATCH STATS
	var max_level_reached:  int   = 0
	var total_player_kills: int   = 0
	var total_npc_kills:    int   = 0
	var total_xp_collected: float = 0.0
	var time_survived:      float = 0.0

	func _init(id: int) -> void:
		peer_id = id


# =========================================================
# STATE
# =========================================================

enum MatchPhase { LOBBY, IN_GAME, ENDED }

var match_phase:   MatchPhase  = MatchPhase.LOBBY
var player_states: Dictionary  = {}
var alive_peers:   Array       = []
var player_nodes:  Dictionary  = {}

## Tracks the exact millisecond the match begins
var match_start_time_msec: int = 0

## PHASE 8: LOBBY SELECTION
var player_characters: Dictionary = {} # peer_id -> String (PackedScene path)
var player_names:      Dictionary = {} # peer_id -> String (Username)


# =========================================================
# PLAYER REGISTRATION
# =========================================================

## Registers a new peer when they join the lobby.
func register_player(peer_id: int) -> void:
	if player_states.has(peer_id):
		return
	player_states[peer_id] = PlayerState.new(peer_id)
	if not alive_peers.has(peer_id):
		alive_peers.append(peer_id)
	print("GameState: Registered peer %d. Total peers: %d." \
		% [peer_id, player_states.size()])


## Removes a peer's state and node reference entirely.
func unregister_player(peer_id: int) -> void:
	player_states.erase(peer_id)
	alive_peers.erase(peer_id)
	player_nodes.erase(peer_id)
	print("GameState: Unregistered peer %d." % peer_id)


## Marks a player as eliminated and removes them from the alive list.
func eliminate_player(peer_id: int) -> void:
	if player_states.has(peer_id):
		player_states[peer_id].is_alive = false
		## Calculate exact survival time in seconds
		var survived = (Time.get_ticks_msec() - match_start_time_msec) / 1000.0
		player_states[peer_id].time_survived = survived
	alive_peers.erase(peer_id)
	player_nodes.erase(peer_id)
	print("GameState: Eliminated peer %d. Alive peers: %s." \
		% [peer_id, str(alive_peers)])

func record_kill(attacker_id: int, is_player_kill: bool) -> void:
	if player_states.has(attacker_id):
		if is_player_kill:
			player_states[attacker_id].total_player_kills += 1
		else:
			player_states[attacker_id].total_npc_kills += 1
			print("NPC Kill")

func record_xp_gained(peer_id: int, amount: float, new_level: int) -> void:
	if player_states.has(peer_id):
		player_states[peer_id].total_xp_collected += amount
		if new_level > player_states[peer_id].max_level_reached:
			player_states[peer_id].max_level_reached = new_level

## Updates the XP record for a peer in player_states.
## Called by CombatResolver after every XP mutation.
## Server only — clients never write to GameState directly.
func update_player_xp(peer_id: int, new_xp: float) -> void:
	if player_states.has(peer_id):
		player_states[peer_id].xp = new_xp
		print("GameState: Updated XP for peer %d to %.1f." % [peer_id, new_xp])

## Resets all match state for a rematch.
func reset() -> void:
	player_states.clear()
	alive_peers.clear()
	player_nodes.clear()
	_peers_world_ready.clear()
	match_phase = MatchPhase.LOBBY
	is_single_player = false
	match_start_time_msec = 0
	player_characters.clear()
	player_names.clear()
	print("GameState: Reset.")


# =========================================================
# NODE REGISTRATION
# =========================================================

## Called by Player.gd in _ready() to register the live node reference.
func register_player_node(peer_id: int, node: Node) -> void:
	player_nodes[peer_id] = node
	print("GameState: Registered node for peer %d." % peer_id)


## Returns the live node for a peer, or null if not found.
func get_player_node(peer_id: int) -> Node:
	return player_nodes.get(peer_id, null)


# =========================================================
# LEVEL HELPERS (server only — called by NPCSpawner)
# =========================================================

## Returns the mean level of all alive players. Returns 1.0 if none.
func average_player_level() -> float:
	if alive_peers.is_empty():
		return 1.0
	var total: float = 0.0
	for peer_id in alive_peers:
		if player_states.has(peer_id):
			total += player_states[peer_id].level
	return total / alive_peers.size()


## Returns the highest level among all alive players. Returns 1 if none.
func max_player_level() -> int:
	var mx: int = 1
	for peer_id in alive_peers:
		if player_states.has(peer_id):
			mx = max(mx, player_states[peer_id].level)
	return mx

# Add the new Autoload Handshake RPC
@rpc("any_peer", "call_local", "reliable")
func notify_world_loaded() -> void:
	if not multiplayer.is_server(): return
	var sender := multiplayer.get_remote_sender_id()
	if sender == 0: sender = 1

	if not _peers_world_ready.has(sender):
		_peers_world_ready.append(sender)
		print("GameState: Peer %d loaded World. (%d/%d)" % [sender, _peers_world_ready.size(), player_states.size()])

	if _peers_world_ready.size() >= player_states.size():
		all_ready_for_world.emit()

# =========================================================
# REMATCH FLOW
# =========================================================

@rpc("any_peer", "call_local", "reliable")
func request_return_to_lobby() -> void:
	if not multiplayer.is_server(): return
	_execute_return_to_lobby.rpc()

@rpc("authority", "call_local", "reliable")
func _execute_return_to_lobby() -> void:
	print("GameState: Returning to lobby...")
	
	## 1. Clear Match State
	alive_peers = player_states.keys().duplicate()
	player_nodes.clear()
	_peers_world_ready.clear()
	match_phase = MatchPhase.LOBBY
	match_start_time_msec = 0
	
	## 2. FIX: Do NOT clear player_characters or player_names. 
	## We keep them so the LobbyUI can automatically re-select the fish!
	
	## 3. Reset personal stats for the next round
	for state in player_states.values():
		state.level = 0
		state.xp = 0.0
		state.is_alive = true
		state.max_level_reached = 0
		state.total_player_kills = 0
		state.total_npc_kills = 0
		state.total_xp_collected = 0.0
		state.time_survived = 0.0

	## 4. Remove any existing ResultsUI overlays
	var results = get_tree().root.get_node_or_null("ResultsScreen")
	if results: results.queue_free()

	## 5. FIX: Await one engine frame. This gives the RPC queue time to finish 
	## processing BEFORE the World is destroyed, preventing "Node not found" errors.
	await get_tree().process_frame

	## 6. Transition scene
	get_tree().change_scene_to_file("res://scenes/ui/Lobby.tscn")

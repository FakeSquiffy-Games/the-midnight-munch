## GameState.gd
## Server-authoritative match state. Only the server writes to this autoload.
## Clients read replicated values via MultiplayerSynchronizer — never directly.
extends Node


# =========================================================
# TYPES
# =========================================================

## Per-player state record stored in player_states.
class PlayerState:
	var peer_id:  int   = 0
	var level:    int   = 0
	var xp:       float = 0.0
	var is_alive: bool  = true

	func _init(id: int) -> void:
		peer_id = id


# =========================================================
# STATE
# =========================================================

enum MatchPhase { LOBBY, IN_GAME, ENDED }

var match_phase:   MatchPhase  = MatchPhase.LOBBY
var player_states: Dictionary  = {}
var alive_peers:   Array       = []

## Dictionary[int, Node] — live player node references keyed by peer_id.
## Populated by World.gd on spawn; cleared on reset.
## Used by CombatResolver and NPCSpawner to look up nodes directly.
var player_nodes:  Dictionary  = {}


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
	alive_peers.erase(peer_id)
	player_nodes.erase(peer_id)
	print("GameState: Eliminated peer %d. Alive peers: %s." \
		% [peer_id, str(alive_peers)])


## Resets all match state for a rematch.
func reset() -> void:
	player_states.clear()
	alive_peers.clear()
	player_nodes.clear()
	match_phase = MatchPhase.LOBBY
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

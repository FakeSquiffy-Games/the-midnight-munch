## Player.gd
## Root script for the player fish entity.
## Phase 4C: handles player_eliminated signal to remove node and HUD.
extends CharacterBody2D


# =========================================================
# CONSTANTS
# =========================================================

@export var reconcile_threshold: float = 50.0
@export var fish_model:          PackedScene 


# =========================================================
# SPAWN DATA
# =========================================================

var spawn_color:    Color   = Color.WHITE
var spawn_position: Vector2 = Vector2.ZERO
var spawn_peer_id:  int     = 1


# =========================================================
# NODE REFERENCES
# =========================================================

@onready var sprite:            AnimatedSprite2D        = null
@onready var stat_manager:      StatManager             = $components/StatManager
@onready var player_controller: PlayerController        = $components/PlayerController
@onready var mouth_area:        MouthArea               = null
@onready var body_area:         BodyArea                = null
@onready var synchronizer:      MultiplayerSynchronizer = $MultiplayerSynchronizer
@onready var camera:            Camera2D                = $Camera2D


# =========================================================
# STATE
# =========================================================

## Reference to this player's HUD — only set for the local player.
var _hud: Node = null
var sync_flip_h: bool = false:
	set(value):
		scale.x *= -1 if (sync_flip_h != value) else 1
		sync_flip_h = value

# =========================================================
# ENTER TREE
# =========================================================

func _enter_tree() -> void:
	set_multiplayer_authority(spawn_peer_id)


# =========================================================
# LIFECYCLE
# =========================================================

func _ready() -> void:
	global_position = spawn_position
	#sprite.modulate = spawn_color
	load_model(fish_model)

	add_to_group("players")

	var peer_id := get_multiplayer_authority()
	GameState.register_player_node(peer_id, self)

	_configure_synchronizer()

	## Listen for elimination on all peers — not just the local player.
	## Every peer needs to remove the eliminated node from its scene tree.
	SignalBus.player_eliminated.connect(_on_player_eliminated)

	if is_multiplayer_authority():
		_setup_local_player()

	if multiplayer.is_server() and is_multiplayer_authority():
		stat_manager.current_xp = 1000.0  ## puts host at Level 5

	## Initialise facing direction.
	mouth_area.update_facing(true)

	## Sync initial synchronizer state.
	synchronizer.synchronized.connect(_on_synchronized)

	print("Player: Ready. Authority peer ID = %d. Is local: %s." \
		% [peer_id, str(is_multiplayer_authority())])

func load_model(model_scene: PackedScene):
	# Remove old model if it exists
	for child in get_children():
		if child is PlayerModel:
			child.queue_free()

	var new_model = model_scene.instantiate()
	add_child(new_model)

	# Re-link the Player's variables to the Model's nodes
	sprite = new_model.sprite
	mouth_area = new_model.mouth
	body_area = new_model.body

	# Apply species-specific scale
	scale = Vector2.ONE * new_model.base_scale
	
	if player_controller:
		player_controller._sprite = new_model.sprite
		player_controller._mouth = new_model.mouth


# =========================================================
# LOCAL PLAYER SETUP
# =========================================================

func _setup_local_player() -> void:
	camera.enabled = true
	camera.make_current()

	var hud := preload("res://scenes/ui/HUD.tscn").instantiate()
	if hud == null:
		push_error("Player: Failed to instantiate HUD.tscn.")
		return

	get_tree().root.add_child(hud)
	hud.call_deferred("initialise", get_multiplayer_authority(), stat_manager)

	## Store reference so we can remove HUD on elimination.
	_hud = hud


# =========================================================
# ELIMINATION HANDLER
# =========================================================

## Called on all peers when any player is eliminated.
## Removes the eliminated player's node and HUD from the scene tree.
func _on_player_eliminated(peer_id: int) -> void:
	if get_multiplayer_authority() != peer_id:
		return

	print("Player: Peer %d eliminated — removing." % peer_id)

	## Disconnect immediately to prevent re-entry.
	SignalBus.player_eliminated.disconnect(_on_player_eliminated)

	## Stop all processing on all peers immediately.
	## This prevents PlayerController from sending further RPCs
	## for this node after elimination is triggered.
	_disable_all_processing()

	## Remove HUD on any peer that owns it.
	if _hud != null:
		_hud.queue_free()
		_hud = null

	## Server calls queue_free() — MultiplayerSpawner handles the rest.
	## Do NOT null the replication config — this breaks the spawner's
	## ability to send the despawn packet to clients.
	## Do NOT call queue_free() on clients — MultiplayerSpawner sends
	## a despawn packet that removes the client copy automatically.
	## Do NOT use a timer — free immediately so no sync packets are
	## sent for a node that is being removed.
	if multiplayer.is_server():
		queue_free()


## Disables physics and regular processing on this node and all descendants.
func _disable_all_processing() -> void:
	set_process(false)
	set_physics_process(false)
	set_process_input(false)
	for child in get_children():
		child.set_process(false)
		child.set_physics_process(false)
		child.set_process_input(false)
		for grandchild in child.get_children():
			grandchild.set_process(false)
			grandchild.set_physics_process(false)
			grandchild.set_process_input(false)


# =========================================================
# COMBAT — request_bite RPC
# =========================================================

@rpc("any_peer", "call_remote", "reliable")
func request_bite(attacker_peer_id: int, target_peer_id: int) -> void:
	if not multiplayer.is_server():
		return

	## Ignore bites targeting already-eliminated peers.
	if not GameState.alive_peers.has(target_peer_id):
		print("Player: request_bite ignored — target peer %d already eliminated." \
			% target_peer_id)
		return

	## Ignore bites from already-eliminated attackers.
	if not GameState.alive_peers.has(attacker_peer_id):
		print("Player: request_bite ignored — attacker peer %d already eliminated." \
			% attacker_peer_id)
		return

	print("Player: request_bite received — attacker peer %d → target peer %d." \
		% [attacker_peer_id, target_peer_id])

	var attacker := GameState.get_player_node(attacker_peer_id) as CharacterBody2D
	var defender := GameState.get_player_node(target_peer_id)   as CharacterBody2D

	if attacker == null:
		push_warning("Player: request_bite — attacker node not found for peer %d." \
			% attacker_peer_id)
		return

	if defender == null:
		push_warning("Player: request_bite — defender node not found for peer %d." \
			% target_peer_id)
		return

	CombatResolver.process_bite_request(attacker, defender)


# =========================================================
# SYNCHRONIZER CONFIGURATION
# =========================================================

func _configure_synchronizer() -> void:
	var config := SceneReplicationConfig.new()

	var props := [
		{"path": ".:position",                            "on_change": false, "spawn": true},
		{"path": ".:rotation",                            "on_change": false, "spawn": true},
		{"path": ".:scale",                               "on_change": true,  "spawn": true},
		{"path": ".:sync_flip_h", "on_change": true, "spawn": true},
		{"path": "components/StatManager:is_boosting",    "on_change": true,  "spawn": true},
		{"path": "components/StatManager:current_energy", "on_change": true,  "spawn": true},
		{"path": "components/StatManager:current_xp",     "on_change": true,  "spawn": true},
	]

	for prop in props:
		config.add_property(prop["path"])
		config.property_set_replication_mode(
			prop["path"],
			SceneReplicationConfig.REPLICATION_MODE_ON_CHANGE
				if prop["on_change"]
				else SceneReplicationConfig.REPLICATION_MODE_ALWAYS)
		config.property_set_spawn(prop["path"], prop["spawn"])

	synchronizer.replication_config = config


# =========================================================
# SYNC HANDLER
# =========================================================

func _on_synchronized() -> void:
	if is_multiplayer_authority():
		return
	mouth_area.update_facing(not sprite.flip_h)


# =========================================================
# PHYSICS — server reconciliation
# =========================================================

func _physics_process(_delta: float) -> void:
	if not multiplayer.is_server():
		return
	if is_multiplayer_authority():
		return
	_validate_client_position()


func _validate_client_position() -> void:
	var client_pos := global_position
	var server_pos := _get_server_authoritative_position()
	if client_pos.distance_to(server_pos) > reconcile_threshold:
		_correct_position.rpc_id(get_multiplayer_authority(), server_pos)


func _get_server_authoritative_position() -> Vector2:
	return global_position


@rpc("authority", "call_remote", "reliable")
func _correct_position(server_pos: Vector2) -> void:
	global_position = server_pos
	print("Player: Position corrected by server to %s." % str(server_pos))

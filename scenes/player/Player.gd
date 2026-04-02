## Player.gd
## Root script for the player fish entity.
## Phase XA: cleaned up dead code, fixed _on_synchronized, removed debug XP line.
extends CharacterBody2D


# =========================================================
# EXPORTS
# =========================================================

@export var reconcile_threshold: float = 50.0

## The fish model PackedScene to instantiate on spawn.
## Assigned by World._spawn_player() from the PLAYER_MODELS array.
@export var fish_model: PackedScene


# =========================================================
# SPAWN DATA
## Set by World._spawn_player() before the node enters the tree.
# =========================================================

var spawn_position: Vector2 = Vector2.ZERO
var spawn_peer_id:  int     = 1


# =========================================================
# NODE REFERENCES
## sprite, mouth_area, body_area are null until load_model() runs in _ready().
## They are assigned by load_model() from the instantiated PlayerModel.
# =========================================================

var sprite:     AnimatedSprite2D = null
var mouth_area: MouthArea        = null
var body_area:  BodyArea         = null

@onready var stat_manager:      StatManager             = $components/StatManager
@onready var player_controller: PlayerController        = $components/PlayerController
@onready var synchronizer:      MultiplayerSynchronizer = $MultiplayerSynchronizer
@onready var camera:            Camera2D                = $Camera2D


# =========================================================
# STATE
# =========================================================

## Reference to this player's HUD — only set for the local player.
var _hud: Node = null

## Synced flip state — drives scale.x on the Player root so that
## CollisionPolygons and the model flip together as a unit.
var sync_flip_h: bool = false:
	set(value):
		if sync_flip_h != value:
			scale.x *= -1
		sync_flip_h = value


# =========================================================
# ENTER TREE
# =========================================================

func _enter_tree() -> void:
	## Must be set here so MultiplayerSynchronizer gets a valid
	## network ID before it initialises in _ready().
	set_multiplayer_authority(spawn_peer_id)


# =========================================================
# LIFECYCLE
# =========================================================

func _ready() -> void:
	global_position = spawn_position

	## Load and instantiate the fish model first — assigns sprite,
	## mouth_area, and body_area before anything else accesses them.
	load_model(fish_model)

	add_to_group("players")

	var peer_id := get_multiplayer_authority()
	GameState.register_player_node(peer_id, self)

	_configure_synchronizer()

	SignalBus.player_eliminated.connect(_on_player_eliminated)

	if is_multiplayer_authority():
		_setup_local_player()

	synchronizer.synchronized.connect(_on_synchronized)

	print("Player: Ready. Authority peer ID = %d. Is local: %s." \
		% [peer_id, str(is_multiplayer_authority())])


# =========================================================
# MODEL LOADING
# =========================================================

## Instantiates [model_scene] and wires sprite, mouth_area, body_area.
## Removes any previously loaded model first.
func load_model(model_scene: PackedScene) -> void:
	if model_scene == null:
		push_error("Player: load_model() called with null PackedScene.")
		return

	## Remove existing model if present.
	for child in get_children():
		if child is PlayerModel:
			child.queue_free()

	var new_model := model_scene.instantiate() as PlayerModel
	if new_model == null:
		push_error("Player: model_scene did not instantiate as PlayerModel.")
		return

	add_child(new_model)

	## Wire references from model to Player.
	sprite     = new_model.sprite
	mouth_area = new_model.mouth
	body_area  = new_model.body

	## Apply species-specific base scale.
	scale = Vector2.ONE * new_model.base_scale

	## Update PlayerController references if it is already initialised.
	if player_controller:
		player_controller._mouth = new_model.mouth


# =========================================================
# LOCAL PLAYER SETUP
# =========================================================

func _setup_local_player() -> void:
	camera.enabled = true
	camera.make_current()
	
	## Clamp camera to world boundaries so it never pans outside.
	## World spans -3840 to 3840 on X, -2160 to 2160 on Y.
	camera.limit_left   = -1727.5
	camera.limit_right  =  1727.5
	camera.limit_top    = -972
	camera.limit_bottom =  972

	var hud := preload("res://scenes/ui/HUD.tscn").instantiate()
	if hud == null:
		push_error("Player: Failed to instantiate HUD.tscn.")
		return

	get_tree().root.add_child(hud)
	hud.call_deferred("initialise", get_multiplayer_authority(), stat_manager)

	_hud = hud


# =========================================================
# ELIMINATION HANDLER
# =========================================================

func _on_player_eliminated(peer_id: int) -> void:
	if get_multiplayer_authority() != peer_id:
		return

	print("Player: Peer %d eliminated — removing." % peer_id)

	SignalBus.player_eliminated.disconnect(_on_player_eliminated)
	_disable_all_processing()

	if _hud != null:
		_hud.queue_free()
		_hud = null

	if multiplayer.is_server():
		queue_free()


## Disables physics and processing on this node and all descendants.
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
func request_bite(attacker_peer_id: int, target_path_str: String) -> void:
	if not multiplayer.is_server():
		return

	if not GameState.alive_peers.has(attacker_peer_id):
		return

	var attacker := GameState.get_player_node(attacker_peer_id) as CharacterBody2D
	if attacker == null:
		return

	## Resolve the exact node (Player, NPC, or Collectible)
	var defender := get_node_or_null(NodePath(target_path_str)) as CharacterBody2D
	if defender == null:
		push_warning("Player: request_bite — target not found at path: %s" % target_path_str)
		return

	## If the target is a player, ensure they are still alive
	if defender.is_in_group("players"):
		var target_peer_id := defender.get_multiplayer_authority()
		if not GameState.alive_peers.has(target_peer_id):
			print("Player: request_bite ignored — target peer %d already eliminated." % target_peer_id)
			return

	CombatResolver.process_bite_request(attacker, defender)


# =========================================================
# SYNCHRONIZER CONFIGURATION
# =========================================================

func _configure_synchronizer() -> void:
	var config := SceneReplicationConfig.new()

	var props := [
		{"path": ".:position",                                "on_change": false, "spawn": true},
		{"path": ".:rotation",                                "on_change": false, "spawn": true},
		{"path": ".:scale",                                   "on_change": true,  "spawn": true},
		{"path": ".:sync_flip_h",                             "on_change": true,  "spawn": true},
		{"path": "components/StatManager:is_boosting",        "on_change": true,  "spawn": true},
		{"path": "components/StatManager:current_energy",     "on_change": true,  "spawn": true},
		{"path": "components/StatManager:current_xp",         "on_change": true,  "spawn": true},
		#{"path": "components/StatManager:speed",              "on_change": true, "spawn": true},
		#{"path": "components/StatManager:turn_rate",          "on_change": true, "spawn": true},
		#{"path": "components/StatManager:xp_gain_multiplier", "on_change": true, "spawn": true},
		#{"path": "components/StatManager:bite_power",         "on_change": true, "spawn": true},
		#{"path": "components/StatManager:max_energy",         "on_change": true, "spawn": true},
		#{"path": "components/StatManager:energy_regen_rate",  "on_change": true, "spawn": true},
		#{"path": "components/StatManager:energy_drain_rate",  "on_change": true, "spawn": true},
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
	## sync_flip_h setter handles scale.x on the Player root.
	## No additional facing update needed on non-authority peers.
	pass


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

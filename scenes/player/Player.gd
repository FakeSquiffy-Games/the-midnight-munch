## Player.gd
## Root script for the player fish entity.
## Phase 3D: enables Camera2D and instantiates HUD for the local player only.
extends CharacterBody2D


# =========================================================
# CONSTANTS
# =========================================================

@export var reconcile_threshold: float = 50.0


# =========================================================
# SPAWN DATA
# =========================================================

var spawn_color:    Color   = Color.WHITE
var spawn_position: Vector2 = Vector2.ZERO
var spawn_peer_id:  int     = 1


# =========================================================
# NODE REFERENCES
# =========================================================

@onready var sprite:            Sprite2D               = $Sprite2D
@onready var stat_manager:      StatManager            = $components/StatManager
@onready var player_controller: PlayerController       = $components/PlayerController
@onready var synchronizer:      MultiplayerSynchronizer = $MultiplayerSynchronizer
@onready var camera:            Camera2D               = $Camera2D


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
	sprite.modulate = spawn_color

	add_to_group("players")

	var peer_id := get_multiplayer_authority()
	GameState.register_player_node(peer_id, self)

	_configure_synchronizer()

	## Only the local peer gets a camera and HUD.
	if is_multiplayer_authority():
		_setup_local_player()

	print("Player: Ready. Authority peer ID = %d. Is local: %s." \
		% [peer_id, str(is_multiplayer_authority())])


# =========================================================
# LOCAL PLAYER SETUP
# =========================================================

## Enables the camera and instantiates the HUD for the local peer only.
## Called only when is_multiplayer_authority() is true.
func _setup_local_player() -> void:
	camera.enabled = true
	camera.make_current()

	var hud_scene: PackedScene = preload("res://scenes/ui/HUD.tscn")
	var hud := hud_scene.instantiate()

	## Verify the instance loaded correctly before adding to tree.
	if hud == null:
		push_error("Player: Failed to instantiate HUD.tscn — check the file path.")
		return

	get_tree().root.add_child(hud)

	## Cast after confirming non-null.
	var hud_typed := hud as HUD
	if hud_typed == null:
		push_error("Player: HUD instance is not of type HUD — check class_name in HUD.gd.")
		return

	hud_typed.initialise(get_multiplayer_authority(), stat_manager)


# =========================================================
# SYNCHRONIZER CONFIGURATION
# =========================================================

func _configure_synchronizer() -> void:
	var config := SceneReplicationConfig.new()

	var props := [
		{"path": ".:position",                                   "on_change": false, "spawn": true},
		{"path": ".:rotation",                                   "on_change": false, "spawn": true},
		{"path": ".:scale",                                      "on_change": true,  "spawn": true},
		{"path": "components/StatManager:is_boosting",           "on_change": true,  "spawn": true},
		{"path": "components/StatManager:current_energy",        "on_change": true,  "spawn": true},
		{"path": "components/StatManager:current_xp",            "on_change": true,  "spawn": true},
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

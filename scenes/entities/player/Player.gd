## Player.gd
## Root script for the player fish entity.
## Phase XA: cleaned up dead code, fixed _on_synchronized, removed debug XP line.
extends Entity
class_name Player

# =========================================================
# EXPORTS
# =========================================================

## Add these at the top of Player.gd (under the existing exports)
@export var character_name: String = "Unnamed Fish"
@export_multiline var character_description: String = "A fish."

@export var reconcile_threshold: float = 50.0

## The fish model PackedScene to instantiate on spawn.
## Assigned by World._spawn_player() from the PLAYER_MODELS array.
#@export var fish_model: PackedScene


# =========================================================
# SPAWN DATA
## Set by World._spawn_player() before the node enters the tree.
# =========================================================

var spawn_position: Vector2 = Vector2.ZERO
var spawn_peer_id:  int     = 1


# =========================================================
# NODE REFERENCES
## sprite, mouth_area, body_area are null until load_model() runs in _ready().
## They are assigned by load_model() from the instantiated EntityModel.
# =========================================================

@onready var player_controller: PlayerController        = $components/PlayerController
@onready var camera:            Camera2D                = $components/Camera2D


# =========================================================
# STATE
# =========================================================

## Reference to this player's HUD — only set for the local player.
var _hud: Node = null


# =========================================================
# ENTER TREE
# =========================================================

func _enter_tree() -> void:
	## Must be set here so MultiplayerSynchronizer gets a valid
	## network ID before it initialises in _ready().
	set_multiplayer_authority(spawn_peer_id)


# =========================================================
# CLEANUP
# =========================================================

func _exit_tree() -> void:
	## When the World unloads (or if the player disconnects), 
	## ensure the HUD doesn't get left behind on the root window!
	if is_instance_valid(_hud):
		_hud.queue_free()


# =========================================================
# LIFECYCLE
# =========================================================

func _ready() -> void:
	global_position = spawn_position

	## 1. Let the parent (Entity.gd) find the baked-in EntityModel, 
	## generate the world collision, and configure the synchronizer!
	super._ready()

	## 2. Now do Player-specific setup
	add_to_group("players")
	var peer_id := get_multiplayer_authority()
	GameState.register_player_node(peer_id, self)

	SignalBus.player_eliminated.connect(_on_player_eliminated)
	synchronizer.synchronized.connect(_on_synchronized)

	if is_multiplayer_authority():
		_setup_local_player()

	print("Player: Ready. Authority peer ID = %d. Is local: %s." \
		% [peer_id, str(is_multiplayer_authority())])


# =========================================================
# MODEL LOADING
# =========================================================

### Instantiates [model_scene] and wires sprite, mouth_area, body_area.
### Removes any previously loaded model first.
#func load_model() -> void:
	#if fish_model == null:
		#push_error("Player: load_model() called with null PackedScene.")
		#return
#
	### Remove existing model if present.
	##for child in get_children():
		##if child is EntityModel:
			##child.queue_free()
#
	##var new_model := model_scene.instantiate() as EntityModel
	##if new_model == null:
		##push_error("Player: model_scene did not instantiate as EntityModel.")
		##return
#
	##add_child(new_model)
#
	### Wire references from model to Player.
	#sprite     = fish_model.sprite
	#mouth_area = fish_model.mouth
	#body_area  = fish_model.body
#
	### Apply species-specific base scale.
	#scale = Vector2.ONE * fish_model.base_scale
#
	### Update PlayerController references if it is already initialised.
	#if player_controller:
		#player_controller._mouth = fish_model.mouth


# =========================================================
# LOCAL PLAYER SETUP
# =========================================================

func _setup_local_player() -> void:
	camera.enabled = true
	camera.make_current()
	
	## Clamp camera to world boundaries so it never pans outside.
	## World spans -3840 to 3840 on X, -2160 to 2160 on Y.
	camera.limit_left   = -1727
	camera.limit_right  =  1727
	camera.limit_top    = -972
	camera.limit_bottom =  972

	var overlay := CanvasModulate.new()
	overlay.name = "DarkOverlay"
	overlay.color = Color(0.0, 0.153, 0.247, 1.0)
	get_tree().current_scene.call_deferred("add_child", overlay)

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
	else:
		var p_name = GameState.player_names.get(peer_id, "Player %d" % peer_id)
		ToastManager.show_toast("%s was eliminated!" % p_name, Color(1.0, 0.4, 0.4))
	
	if not is_multiplayer_authority():
		return

	print("Player: Peer %d eliminated — shifting to spcectating." % peer_id)

	## FIX: Re-enable physics on the ROOT (Entity.gd)
	## The Entity.play_elimination RPC turned this off. Without the root
	## processing physics, move_and_slide() on the body does nothing.
	self.set_physics_process(true)
	self.set_process(true) # Ensure the root can also process

	## 1. Remove the Dark Overlay to restore full visibility for spectating
	var overlay = get_tree().current_scene.get_node_or_null("DarkOverlay")
	if overlay:
		overlay.queue_free()
	
	## 2. Remove the local player's BioluminescentComponent
	var bio_light = components.get_node_or_null("BioluminescentComponent")
	if bio_light:
		bio_light.queue_free()

	if SignalBus.player_eliminated.is_connected(_on_player_eliminated):
		SignalBus.player_eliminated.disconnect(_on_player_eliminated)

	## Tell the controller to switch to spectator movement
	if player_controller:
		player_controller.is_spectating = true


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

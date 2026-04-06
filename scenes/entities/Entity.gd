## Entity.gd
## The foundation for all physical actors in the game.
## Handles model references, dynamic physics, and network sync.
class_name Entity
extends CharacterBody2D

# =========================================================
# NODE REFERENCES
# =========================================================

@export var disable_mouth: bool = false

@onready var stat_manager: StatManager = $StatManager
@onready var synchronizer: MultiplayerSynchronizer = $MultiplayerSynchronizer
@onready var components:   Node2D               = $components

## References extracted from the EntityModel at runtime
var model:      EntityModel      = null
var sprite:     AnimatedSprite2D = null
var body_area:  BodyArea         = null
var mouth_area: MouthArea        = null
var _world_poly: CollisionPolygon2D = null

# =========================================================
# SYNCED STATE
# =========================================================

## Drives scale.x to flip visuals and hitboxes together.
var sync_flip_h: bool = false:
	set(value):
		sync_flip_h = value
		_update_transform()

var current_scale_mult: float = 1.0:
	set(value):
		current_scale_mult = value
		_update_transform()

var _poly_base_scale: Vector2 = Vector2.ONE


# =========================================================
# LIFECYCLE
# =========================================================

func _ready() -> void:
	_initialize_model_references()
	_generate_world_collision()
	_configure_synchronizer()

# =========================================================
# INITIALIZATION
# =========================================================

## Finds the EntityModel and extracts components for high-level access.
func _initialize_model_references() -> void:
	for child in get_children():
		if child is EntityModel:
			model      = child
			sprite     = child.sprite
			body_area  = child.body
			mouth_area = child.mouth
			
			## Disable mouth collision shape
			if disable_mouth:
				(mouth_area as MouthArea).get_node("MouthPolygon").set_deferred("disabled", true)
			
			## Apply species-specific base scale
			scale = Vector2.ONE * model.base_scale
			break
	
	if model == null:
		push_warning("Entity: No EntityModel found on %s." % name)


## Duplicates the BodyPolygon to the root so the entity bumps into world walls.
func _generate_world_collision() -> void:
	if body_area == null: return
	
	var source_poly = body_area.get_node_or_null("BodyPolygon") as CollisionPolygon2D
	if source_poly == null: return
	
	## Create a physical clone for the CharacterBody2D
	_world_poly = source_poly.duplicate() as CollisionPolygon2D
	if _world_poly == null: return
	
	if model == null:
		model = self.get_node_or_null("EntityModel") as EntityModel
	if model == null: return
	_poly_base_scale = source_poly.scale
	
	add_child(_world_poly)
	
	_update_transform()

## Safely scales and flips the hitboxes and visuals without breaking the physics root.
func _update_transform() -> void:
	if model == null: return
	
	var base_s := model.base_scale * current_scale_mult
	var sign_x := -1.0 if sync_flip_h else 1.0
	
	model.scale = Vector2(base_s * sign_x, base_s)
	
	if _world_poly:
		_world_poly.scale = Vector2(
			base_s * sign_x * _poly_base_scale.x, 
			base_s * _poly_base_scale.y
		)

## Sets up replication based on whether this is a local player or a server-actor.
func _configure_synchronizer() -> void:
	var config := SceneReplicationConfig.new()
	var auth   := get_multiplayer_authority()
	
	## Position and Flip are mandatory for all
	config.add_property(".:position")
	config.add_property(".:sync_flip_h")
	
	## If Authority != 1, this is a Client-Predicted Player.
	## We sync position ALWAYS but flip ON_CHANGE.
	if auth != 1:
		config.property_set_replication_mode(".:position", SceneReplicationConfig.REPLICATION_MODE_ALWAYS)
	else:
		## If Authority == 1, this is a Server-Owned NPC or Collectible.
		config.property_set_replication_mode(".:position", SceneReplicationConfig.REPLICATION_MODE_ON_CHANGE)
		
		## ONLY Server-owned entities (NPCs) use the Synchronizer for XP.
		## Client Players receive XP updates via the SignalBus instead!
		config.add_property("StatManager:current_xp")
		config.property_set_replication_mode("StatManager:current_xp", SceneReplicationConfig.REPLICATION_MODE_ON_CHANGE)

	config.property_set_replication_mode(".:sync_flip_h", SceneReplicationConfig.REPLICATION_MODE_ON_CHANGE)
	
	### Sync vital stats for all entities
	#config.add_property("StatManager:current_xp")
	#config.property_set_replication_mode("StatManager:current_xp", SceneReplicationConfig.REPLICATION_MODE_ON_CHANGE)
	
	synchronizer.replication_config = config

func update_facing(direction: Vector2) -> void:
	if direction.x > 0.01:
		sync_flip_h = false
	elif direction.x < -0.01:
		sync_flip_h = true

# =========================================================
# ELIMINATION SEQUENCE
# =========================================================

@rpc("any_peer", "call_local", "reliable")
func play_elimination() -> void:
	## 1. Safety: Only the server is allowed to trigger this RPC
	if not multiplayer.is_server() and multiplayer.get_remote_sender_id() != 1:
		return
	
	## 2. Stop the synchronizer immediately to prevent network jitter/errors
	if synchronizer:
		synchronizer.public_visibility = false
		synchronizer.process_mode = PROCESS_MODE_DISABLED
	
	## Disable physical interactions immediately on all clients
	if body_area: 
		body_area.set_deferred("monitorable", false)
		body_area.set_deferred("monitoring", false)
	if mouth_area: 
		mouth_area.set_deferred("monitoring", false)
		mouth_area.set_deferred("monitorable", false)
	
	#set_physics_process(false)
	
	## Play spatial death sound
	if self.is_in_group("players"):
		AudioManager.play_spatial_sound("death", global_position)
	
	var anim := components.get_node_or_null("AnimationHandler") as AnimationHandler
	if anim:
		anim.play_death_animation()
	else:
		## Fallback if no animation handler exists
		visible = false
	
	## 4. Physics/Collision Shift
	# Set Layer to 0 so living fish swim through the ghost
	collision_layer = 0 
	# Keep Mask 1 so the ghost still bumps into world boundaries
	#set_collision_mask_value(1, true) 

	## 5. Persistence Check
	if not is_in_group("players"):
		## NPCs are deleted after the animation
		var tree = get_tree()
		if tree:
			tree.create_timer(1.0).timeout.connect(queue_free)
	else:
		## Players transition to Spectator Mode
		_enter_spectator_mode()

func _enter_spectator_mode() -> void:
	print("Entity: %s entering spectator mode." % name)
	# Hide the visuals and nametag after the death animation finishes
	var tree = get_tree()
	if tree:
		await tree.create_timer(1.0).timeout
		if is_instance_valid(model): 
			model.visible = false

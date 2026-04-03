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

# =========================================================
# SYNCED STATE
# =========================================================

## Drives scale.x to flip visuals and hitboxes together.
var sync_flip_h: bool = false:
	set(value):
		if sync_flip_h != value:
			scale.x *= -1
		sync_flip_h = value

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
	var world_poly := source_poly.duplicate() as CollisionPolygon2D
	if world_poly == null: return
	if model == null:
		model = self.get_node_or_null("EntityModel") as EntityModel
	if model == null: return
	world_poly.scale = model.scale
	add_child(world_poly)

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

	config.property_set_replication_mode(".:sync_flip_h", SceneReplicationConfig.REPLICATION_MODE_ON_CHANGE)
	
	## Sync vital stats for all entities
	config.add_property("StatManager:current_xp")
	config.property_set_replication_mode("StatManager:current_xp", SceneReplicationConfig.REPLICATION_MODE_ON_CHANGE)
	
	synchronizer.replication_config = config

func update_facing(direction: Vector2) -> void:
	if direction.x > 0.01:
		sync_flip_h = false
	elif direction.x < -0.01:
		sync_flip_h = true

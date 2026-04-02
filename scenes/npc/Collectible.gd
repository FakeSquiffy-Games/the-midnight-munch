## Collectible.gd
## Root script for collectible entities. Supports the PlayerModel pattern.
class_name Collectible
extends CharacterBody2D

# =========================================================
# NODE REFERENCES
# =========================================================

var sprite:     AnimatedSprite2D = null
var body_area:  BodyArea         = null
var mouth_area: MouthArea        = null

@onready var stat_manager: StatManager = $components/StatManager
@onready var effect:       EffectComponent = $components/EffectComponent

# =========================================================
# STATE
# =========================================================

## Synced flip state. Drives scale.x on the root to flip the model and hitboxes.
var sync_flip_h: bool = false:
	set(value):
		if sync_flip_h != value:
			scale.x *= -1
		sync_flip_h = value

# =========================================================
# LIFECYCLE
# =========================================================

func _ready() -> void:
	## Find the Model child (assumed to be added in the Variant scene)
	for child in get_children():
		if child is PlayerModel:
			sprite     = child.sprite
			body_area  = child.body
			mouth_area = child.mouth
			
			## Apply base scale from the model
			scale = Vector2.ONE * child.base_scale
			break
	
	if body_area == null:
		push_warning("Collectible: No PlayerModel found on %s." % name)
	
	_configure_synchronizer()

# =========================================================
# SYNCHRONIZER CONFIGURATION
# =========================================================

func _configure_synchronizer() -> void:
	var sync := $MultiplayerSynchronizer as MultiplayerSynchronizer
	var config := SceneReplicationConfig.new()

	config.add_property(".:position")
	config.property_set_replication_mode(".:position", SceneReplicationConfig.REPLICATION_MODE_ALWAYS)
	config.property_set_spawn(".:position", true)
	
	config.add_property(".:sync_flip_h")
	config.property_set_replication_mode(".:sync_flip_h", SceneReplicationConfig.REPLICATION_MODE_ON_CHANGE)
	config.property_set_spawn(".:sync_flip_h", true)

	sync.replication_config = config

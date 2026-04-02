## NPC.gd
class_name NPC
extends CharacterBody2D

var spawn_level: int = 1

var sprite:     AnimatedSprite2D = null
var body_area:  BodyArea         = null
var mouth_area: MouthArea        = null

@onready var stat_manager: StatManager = $components/StatManager
@onready var synchronizer: MultiplayerSynchronizer = $MultiplayerSynchronizer

var sync_flip_h: bool = false:
	set(value):
		if sync_flip_h != value:
			scale.x *= -1
		sync_flip_h = value

func _ready() -> void:
	add_to_group("npcs")
	
	## Find the Model child (assumed to be added in the Variant scene)
	for child in get_children():
		## Assuming your NPC visual setups also use the PlayerModel template
		if child is PlayerModel:
			sprite     = child.sprite
			body_area  = child.body
			mouth_area = child.mouth
			scale      = Vector2.ONE * child.base_scale
			break
			
	if body_area == null:
		push_warning("NPC: No PlayerModel found on %s." % name)
		
	_configure_synchronizer()
	
	if multiplayer.is_server():
		stat_manager.current_xp = StatManager.XP_THRESHOLDS[spawn_level]

func _configure_synchronizer() -> void:
	var config := SceneReplicationConfig.new()
	
	config.add_property(".:position")
	config.property_set_replication_mode(".:position", SceneReplicationConfig.REPLICATION_MODE_ALWAYS)
	config.property_set_spawn(".:position", true)
	
	config.add_property(".:sync_flip_h")
	config.property_set_replication_mode(".:sync_flip_h", SceneReplicationConfig.REPLICATION_MODE_ON_CHANGE)
	config.property_set_spawn(".:sync_flip_h", true)
	
	synchronizer.replication_config = config

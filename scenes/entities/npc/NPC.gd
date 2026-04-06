## NPC.gd
class_name NPC
extends Entity

var spawn_level: int = 0

## PHASE 8: Toggle whether killing this NPC increments the player's stat
@export var counts_as_kill_stat: bool = true

func _ready() -> void:
	add_to_group("npcs")
	
	_initialize_model_references()
	_generate_world_collision()
	_configure_synchronizer()
	
	stat_manager.current_xp = StatManager.XP_THRESHOLDS[spawn_level]

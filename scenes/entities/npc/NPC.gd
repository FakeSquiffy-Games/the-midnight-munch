## NPC.gd
class_name NPC
extends Entity

var spawn_level: int = 0

## PHASE 8: Toggle whether killing this NPC increments the player's stat
@export var counts_as_kill: bool = true
@export var npc_invisible: bool = false

## PHASE 8.5: Ecosystem Level Restrictions
@export var min_spawn_level: int = 0
@export var max_spawn_level: int = 10

func _ready() -> void:
	add_to_group("npcs")
	
	if npc_invisible:
		add_to_group("npc_invisible")
	
	_initialize_model_references()
	_generate_world_collision()
	_configure_synchronizer()
	
	stat_manager.current_xp = StatManager.XP_THRESHOLDS[spawn_level]

## NPC.gd
class_name NPC
extends Entity

var spawn_level: int = 0

func _ready() -> void:
	add_to_group("npcs")
	
	_initialize_model_references()
	_generate_world_collision()
	_configure_synchronizer()
	
	if multiplayer.is_server():
		stat_manager.current_xp = StatManager.XP_THRESHOLDS[spawn_level]

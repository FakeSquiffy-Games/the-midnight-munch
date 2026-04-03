## NPCSpawner.gd
class_name NPCSpawner
extends Node

@export var npc_soft_cap:       int   = 15
@export var spawn_interval:     float = 3.0
@export var fodder_floor_count: int   = 5
@export var fodder_levels:      Array[int] =[1, 2]

## Models to spawn (e.g. FangtoothModel, BlackSeadevilModel)
@export var npc_scenes: Array[PackedScene] = []

var active_npcs: int = 0

func _ready() -> void:
	if not multiplayer.is_server():
		return
		
	var timer := Timer.new()
	timer.wait_time = spawn_interval
	timer.autostart = true
	timer.timeout.connect(_on_spawn_timer_timeout)
	add_child(timer)

func _on_spawn_timer_timeout() -> void:
	if active_npcs >= npc_soft_cap or npc_scenes.is_empty():
		return
		
	var level := _pick_spawn_level()
	_spawn_from_edge(level)

func _pick_spawn_level() -> int:
	## Ensure fodder floor is maintained first
	var fodder_alive := _count_npcs_in_levels(fodder_levels)
	if fodder_alive < fodder_floor_count:
		return fodder_levels.pick_random()
		
	## Dynamic range based on player population
	var avg_level := int(round(GameState.average_player_level()))
	var max_level := GameState.max_player_level()
	
	## Weighted table: level -> weight
	var weights := {
		max(1, avg_level - 1): 30,  # slightly below average
		avg_level: 35,              # at average
		min(10, avg_level + 1): 20, # slightly above average
		min(10, max_level): 10,     # at the current ceiling
		1: 5                        # always some fodder
	}
	
	return _weighted_random(weights)

func _count_npcs_in_levels(levels: Array[int]) -> int:
	var count := 0
	for child in get_children():
		if child is NPC:
			## Access stat_manager safely
			var stat = child.get_node_or_null("StatManager")
			if stat and stat.level in levels:
				count += 1
	return count

func _weighted_random(weights: Dictionary) -> int:
	var total_weight := 0
	for weight in weights.values():
		total_weight += weight
		
	var roll := randi() % total_weight
	var current_sum := 0
	
	for level in weights.keys():
		current_sum += weights[level]
		if roll < current_sum:
			return level
			
	return 1

## Replace _spawn_from_edge with this updated version:
func _spawn_from_edge(level: int) -> void:
	var npc_scene: PackedScene = npc_scenes.pick_random()
	var npc := npc_scene.instantiate() as NPC
	
	npc.spawn_level = level
	
	## Spawn slightly outside the ±1727.5 boundaries
	var is_left := randf() > 0.5
	var start_x := -1800.0 if is_left else 1800.0
	var start_y := randf_range(-850.0, 850.0)
	
	npc.global_position = Vector2(start_x, start_y)
	
	npc.tree_exited.connect(func(): active_npcs -= 1)
	
	add_child(npc, true)
	active_npcs += 1

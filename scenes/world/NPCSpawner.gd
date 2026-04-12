## NPCSpawner.gd
class_name NPCSpawner
extends Node

@export var npc_soft_cap:       int   = 15
@export var spawn_interval:     float = 3.0
@export var fodder_floor_count: int   = 5
@export var fodder_levels:      Array[int] = [0, 1]

## Models to spawn (e.g. FangtoothModel, BlackSeadevilModel)
@export var npc_scenes: Array[PackedScene] = []

var active_npcs: int = 0
@onready var spawner: MultiplayerSpawner = $NPCSynchronizer

## CACHE for fast performance
var _scene_level_cache: Dictionary = {} # index -> {min, max}

func _ready() -> void:
	## Both Server and Client must register the spawn function!
	spawner.spawn_function = _spawn_custom
	
	if not multiplayer.is_server():
		return
	
	## 1. Build the fast-access cache of level restrictions
	for i in npc_scenes.size():
		var scene = npc_scenes[i]
		if scene:
			var temp = scene.instantiate()
			if temp is NPC:
				_scene_level_cache[i] = {"min": temp.min_spawn_level, "max": temp.max_spawn_level}
			else:
				_scene_level_cache[i] = {"min": 0, "max": 10}
			temp.free()
	
	var timer := Timer.new()
	timer.wait_time = spawn_interval
	timer.autostart = true
	timer.timeout.connect(_on_spawn_timer_timeout)
	add_child(timer)

func _on_spawn_timer_timeout() -> void:
	if active_npcs >= npc_soft_cap or npc_scenes.is_empty():
		return
		
	var level := _pick_spawn_level()

	## 3. Filter valid scenes based on the rolled level
	var valid_indices =[]
	for i in _scene_level_cache.keys():
		var bounds = _scene_level_cache[i]
		if level >= bounds["min"] and level <= bounds["max"]:
			valid_indices.append(i)
			
	if valid_indices.is_empty():
		return # No valid NPC for this level right now, skip spawn.
		
	var scene_index = valid_indices.pick_random()
	
	var is_left := randf() > 0.5
	var start_x := -1800.0 if is_left else 1800.0
	var start_y := randf_range(-850.0, 850.0)
	var pos := Vector2(start_x, start_y)
	
	## Tell the spawner to execute _spawn_custom on all peers
	spawner.spawn({
		"scene_index": scene_index,
		"level": level,
		"pos": pos
	})

## Executes on ALL peers to build the node perfectly before it enters the tree.
func _spawn_custom(data: Dictionary) -> Node:
	var npc_scene: PackedScene = npc_scenes[data["scene_index"]]
	var npc := npc_scene.instantiate() as NPC
	
	npc.spawn_level     = data["level"]
	npc.global_position = data["pos"]
	
	if multiplayer.is_server():
		npc.tree_exited.connect(func(): active_npcs -= 1)
		active_npcs += 1
		
	return npc

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

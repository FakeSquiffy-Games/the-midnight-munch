## LagCompensator.gd
extends Node

const MAX_HISTORY_MS: int = 300
var history: Dictionary = {} # node_path -> Array of {time, pos}

func _physics_process(_delta: float) -> void:
	if not multiplayer.is_server(): return
	
	var now := Time.get_ticks_msec()
	var players := get_tree().get_nodes_in_group("players")
	var npcs    := get_tree().get_nodes_in_group("npcs")
	
	for entity in (players + npcs):
		var path := str(entity.get_path())
		if not history.has(path): history[path] = []
		
		history[path].append({"time": now, "pos": entity.global_position})
		
		## Prune entries older than 300ms
		while history[path].size() > 0 and (now - history[path][0].time) > MAX_HISTORY_MS:
			history[path].pop_front()

## Rewinds time to find where an entity was X milliseconds ago.
func get_historical_position(path: String, time_ago_ms: int) -> Vector2:
	if not history.has(path) or history[path].is_empty(): 
		return Vector2.INF
		
	var target_time := Time.get_ticks_msec() - time_ago_ms
	
	var best_pos: Vector2 = history[path].back().pos
	var smallest_diff: float = 999999
	
	for entry in history[path]:
		var diff: float = abs(entry.time - target_time)
		if diff < smallest_diff:
			smallest_diff = diff
			best_pos = entry.pos
			
	return best_pos

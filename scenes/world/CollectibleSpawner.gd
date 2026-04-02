## CollectibleSpawner.gd
class_name CollectibleSpawner
extends Node

# =========================================================
# EXPORTS
# =========================================================

@export var max_special_fish:        int   = 4
@export var max_floating_items:      int   = 6
@export var special_fish_interval:   float = 18.0
@export var floating_item_interval:  float = 12.0

@export var floating_item_scenes: Array[PackedScene] = []
@export var special_fish_scenes:  Array[PackedScene] = []

# =========================================================
# STATE
# =========================================================

var active_special_fish:   int = 0
var active_floating_items: int = 0

# =========================================================
# LIFECYCLE
# =========================================================

func _ready() -> void:
	if not multiplayer.is_server():
		return
		
	## Dynamically create timers to keep the node self-contained
	var sf_timer := Timer.new()
	sf_timer.wait_time = special_fish_interval
	sf_timer.autostart = true
	sf_timer.timeout.connect(_on_special_fish_timer_timeout)
	add_child(sf_timer)
	
	var fi_timer := Timer.new()
	fi_timer.wait_time = floating_item_interval
	fi_timer.autostart = true
	fi_timer.timeout.connect(_on_floating_item_timer_timeout)
	add_child(fi_timer)

# =========================================================
# TIMEOUT HANDLERS
# =========================================================

func _on_special_fish_timer_timeout() -> void:
	if active_special_fish >= max_special_fish or special_fish_scenes.is_empty():
		return
	
	var scene: PackedScene = special_fish_scenes.pick_random()
	_spawn_from_edge(scene)

func _on_floating_item_timer_timeout() -> void:
	if active_floating_items >= max_floating_items or floating_item_scenes.is_empty():
		return
		
	var scene: PackedScene = floating_item_scenes.pick_random()
	_spawn_from_bottom(scene)

# =========================================================
# SPAWN ROUTING
# =========================================================

func _spawn_from_edge(scene: PackedScene) -> void:
	var entity := scene.instantiate() as Node2D
	
	## Spawn slightly outside the ±1727.5 boundaries
	var is_left := randf() > 0.5
	var start_x := -1800.0 if is_left else 1800.0
	var start_y := randf_range(-850.0, 850.0)
	
	entity.global_position = Vector2(start_x, start_y)
	
	## Use tree_exited to reliably decrement the count regardless of how it is destroyed
	entity.tree_exited.connect(func(): active_special_fish -= 1)
	
	## Ensure network consistency with true flag
	add_child(entity, true) 
	active_special_fish += 1

func _spawn_from_bottom(scene: PackedScene) -> void:
	var entity := scene.instantiate() as Node2D
	
	var start_x := randf_range(-1600.0, 1600.0)
	var start_y := 1050.0 ## Spawn slightly below the ±972 boundary
	
	entity.global_position = Vector2(start_x, start_y)
	
	## Decrement reliably on destruction
	entity.tree_exited.connect(func(): active_floating_items -= 1)
	
	add_child(entity, true)
	active_floating_items += 1

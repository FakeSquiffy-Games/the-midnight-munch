## NPCSpawner.gd
## Server-only node responsible for dynamic NPC ecosystem spawning.
## Scales NPC levels to alive player population and maintains a fodder floor.
## Full implementation in Phase 6 — this is the Phase 1B stub.
extends Node


# =========================================================
# EXPORTS (tunable without code changes)
# =========================================================

@export var npc_soft_cap:       int   = 20
@export var spawn_interval:     float = 3.0
@export var fodder_floor_count: int   = 5
@export var fodder_levels:      Array[int] = [1, 2]


# =========================================================
# STATE
# =========================================================

var active_npcs: int = 0


# =========================================================
# LIFECYCLE
# =========================================================

func _ready() -> void:
	# Only the server runs the spawner.
	if not multiplayer.is_server():
		return
	push_warning("NPCSpawner._ready() — spawner not yet implemented (Phase 6).")

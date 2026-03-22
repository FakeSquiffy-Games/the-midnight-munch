## CollectibleSpawner.gd
## Server-only node managing the independent collectible pool.
## Special fish and floating items are tracked and spawned separately
## from NPCSpawner — their rates are never affected by NPC ecosystem changes.
## Full implementation in Phase 5 — this is the Phase 1B stub.
extends Node


# =========================================================
# EXPORTS (tunable without code changes)
# =========================================================

@export var max_special_fish:        int   = 4
@export var max_floating_items:      int   = 6
@export var special_fish_interval:   float = 18.0
@export var floating_item_interval:  float = 12.0


# =========================================================
# STATE
# =========================================================

var active_special_fish:   int = 0
var active_floating_items: int = 0


# =========================================================
# LIFECYCLE
# =========================================================

func _ready() -> void:
	# Only the server runs the spawner.
	if not multiplayer.is_server():
		return
	push_warning("CollectibleSpawner._ready() — spawner not yet implemented (Phase 5).")

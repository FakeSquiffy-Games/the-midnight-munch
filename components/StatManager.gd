## StatManager.gd
## Single source of truth for all fish stats.
## Attached to every fish entity (players and NPCs).
## Level and tier are derived from current_xp — never stored separately.
## All writes to combat-relevant stats are server-authoritative.
class_name StatManager
extends Node


# =========================================================
# XP TABLE
# =========================================================

## XP required to reach each level. Index = level.
## Level 0 threshold is 0 by definition.
## Values are placeholders — tune during Phase 4 playtesting.
const XP_THRESHOLDS: Array[float] = [
	0.0,     ## Level 0
	100.0,   ## Level 1
	250.0,   ## Level 2
	450.0,   ## Level 3
	700.0,   ## Level 4
	1000.0,  ## Level 5 — Tier Shift: Baby → Teen
	1350.0,  ## Level 6
	1750.0,  ## Level 7
	2200.0,  ## Level 8 — Tier Shift: Teen → Adult
	2700.0,  ## Level 9
	3250.0,  ## Level 10
]


# =========================================================
# STAT ENUM
# =========================================================

## Used by EffectComponent (Phase 5) to identify which stat to boost.
enum StatType {
	SPEED,
	TURN_RATE,
	XP_GAIN_MULTIPLIER,
	BITE_POWER,
	MAX_ENERGY,
	ENERGY_REGEN_RATE,
	ENERGY_DRAIN_RATE,
}

## Emitted when is_boosting changes. Listened to by PlayerController
## to update its local _boost_active cache without polling.
signal changed_boosting(value: bool)


# =========================================================
# BASE STATS
# =========================================================

## Movement speed in pixels per second.
@export var speed:               float = 200.0

## Not used for movement — reserved for future collectible effect.
@export var turn_rate:           float = 1.0

## Multiplier applied to all XP gains.
@export var xp_gain_multiplier:  float = 1.0

## Multiplier applied to outgoing bite XP drain.
@export var bite_power:          float = 1.0


# =========================================================
# ENERGY STATS
# =========================================================

@export var max_energy:          float = 100.0
@export var energy_regen_rate:   float = 20.0   ## per second
@export var energy_drain_rate:   float = 30.0   ## per second while boosting


# =========================================================
# RUNTIME STATE
## Written only by the server. Replicated to clients via
## MultiplayerSynchronizer (configured in Phase 3C).
# =========================================================

var current_xp:     float = 0.0
var current_energy: float = 100.0
var is_boosting:    bool  = false


# =========================================================
# DERIVED PROPERTIES
# =========================================================

## Derives level from current_xp by scanning XP_THRESHOLDS high to low.
## Never stored — always computed fresh from XP.
var level: int:
	get:
		for i in range(XP_THRESHOLDS.size() - 1, -1, -1):
			if current_xp >= XP_THRESHOLDS[i]:
				return i
		return 0

## Derives tier from level.
## 0 = Baby (Levels 0-4), 1 = Teen (Levels 5-7), 2 = Adult (Levels 8-10).
var tier: int:
	get:
		if level >= 8: return 2
		if level >= 5: return 1
		return 0

## Returns the XP gap between the current level and the one below it.
## Used by CombatResolver for NPC KILL demotion calculation.
func get_level_xp_gap() -> float:
	var lv := level
	if lv <= 0:
		return 0.0
	return XP_THRESHOLDS[lv] - XP_THRESHOLDS[lv - 1]


# =========================================================
# BOOST APPLICATION (server only)
## Called by EffectComponent in Phase 5.
# =========================================================

## Applies a stat boost of [amount] to [stat] for [duration] seconds.
## duration = 0 means permanent. Full implementation in Phase 5.
func apply_boost(stat: StatType, amount: float, duration: float) -> void:
	push_warning("StatManager.apply_boost() — not yet implemented (Phase 5).")

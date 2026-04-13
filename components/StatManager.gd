## StatManager.gd
## Single source of truth for all fish stats.
## Level and tier are derived from current_xp.
## Features a Recalculation Pipeline to prevent float-drift and infinite stat stacking.
class_name StatManager
extends Node


# =========================================================
# XP TABLE
# =========================================================

const XP_THRESHOLDS: Array[float] =[
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
# STAT ENUM & SIGNALS
# =========================================================

enum StatType {
	SPEED,
	XP_GAIN_MULTIPLIER,
	BITE_POWER,
	MAX_ENERGY,
	ENERGY_REGEN_RATE,
	ENERGY_DRAIN_RATE,
	LIGHT_ENERGY,
	LIGHT_RADIUS_MULTIPLIER,
	DAMAGE_REDUCTION
}


# =========================================================
# BASE STATS (Inspector Editable)
# =========================================================

@export var base_speed:                   float = 300.0
@export var base_light_radius_multiplier: float = 1.0
@export var base_xp_gain_multiplier:      float = 1.0
@export var base_bite_power:              float = 1.0
@export var base_damage_reduction:        float = 0.0

@export var base_max_energy:              float = 100.0
@export var base_energy_regen_rate:       float = 20.0
@export var base_energy_drain_rate:       float = 30.0


# =========================================================
# COMPUTED STATS (Accessed by external logic)
# =========================================================

var speed:                   float
var light_radius_multiplier: float
var xp_gain_multiplier:      float
var bite_power:              float
var damage_reduction:        float

var max_energy:              float
var energy_regen_rate:       float
var energy_drain_rate:       float


# =========================================================
# RUNTIME STATE
# =========================================================

var current_xp:     float = 0.0
var current_energy: float = 100.0
var is_boosting:    bool  = false

## Dictionary keyed by StatType. 
## Value is a Dictionary: {"amount": float, "time_left": float}
var _active_boosts: Dictionary = {}


# =========================================================
# DERIVED PROPERTIES
# =========================================================

var level: int:
	get:
		for i in range(XP_THRESHOLDS.size() - 1, -1, -1):
			if current_xp >= XP_THRESHOLDS[i]:
				return i
		return 0

var tier: int:
	get:
		if level >= 8: return 2
		if level >= 5: return 1
		return 0

func get_level_xp_gap() -> float:
	var lv := level
	if lv <= 0:
		return 0.0
	return XP_THRESHOLDS[lv] - XP_THRESHOLDS[lv - 1]


# =========================================================
# LIFECYCLE
# =========================================================

func _ready() -> void:
	## Compute initial runtime stats from base exports
	_recalculate_stats()
	current_energy = max_energy
	
	set_process(false)
	SignalBus.boost_applied.connect(_on_boost_applied)
	SignalBus.xp_changed.connect(_on_network_xp_changed)

func _process(delta: float) -> void:
	var needs_recalc := false
	
	## Iterate safely through active boost keys
	var keys = _active_boosts.keys()
	for stat in keys:
		var boost = _active_boosts[stat]
		boost.time_left -= delta
		
		if boost.time_left <= 0.0:
			_active_boosts.erase(stat)
			needs_recalc = true
	
	if needs_recalc:
		_recalculate_stats()
	
	if _active_boosts.is_empty():
		set_process(false)


# =========================================================
# BOOST APPLICATION (The Pipeline)
# =========================================================

func _on_boost_applied(target_path: String, stat: int, amount: float, duration: float) -> void:
	if str(owner.get_path()) != target_path:
		return
		
	var stat_type = stat as StatType
	
	## Handle Non-Modifying Resources (e.g., instant heals)
	if stat_type == StatType.LIGHT_ENERGY:
		return # Handled locally by BioluminescentComponent

	## Handle Permanent Stat Upgrades
	if duration <= 0.0:
		_modify_base_stat(stat_type, amount)
		_recalculate_stats()
		return

	## Handle Timed Boosts (Strict 1-Buff-Per-Stat Policy)
	if _active_boosts.has(stat_type):
		var existing = _active_boosts[stat_type]
		
		## Overwrite if stronger magnitude
		if abs(amount) > abs(existing.amount):
			_active_boosts[stat_type] = { "amount": amount, "time_left": duration }
		## Refresh timer if it's the exact same buff
		elif amount == existing.amount:
			existing.time_left = maxf(existing.time_left, duration)
	else:
		## Apply brand new buff
		_active_boosts[stat_type] = { "amount": amount, "time_left": duration }
		set_process(true)
		
	_recalculate_stats()


func _modify_base_stat(stat: StatType, amount: float) -> void:
	match stat:
		StatType.SPEED:                   base_speed += amount
		StatType.XP_GAIN_MULTIPLIER:      base_xp_gain_multiplier += amount
		StatType.BITE_POWER:              base_bite_power += amount
		StatType.DAMAGE_REDUCTION:        base_damage_reduction += amount
		StatType.MAX_ENERGY:              base_max_energy += amount
		StatType.ENERGY_REGEN_RATE:       base_energy_regen_rate += amount
		StatType.ENERGY_DRAIN_RATE:       base_energy_drain_rate += amount
		StatType.LIGHT_RADIUS_MULTIPLIER: base_light_radius_multiplier += amount


func _recalculate_stats() -> void:
	## 1. Reset all computed properties to their base values
	speed                   = base_speed
	xp_gain_multiplier      = base_xp_gain_multiplier
	bite_power              = base_bite_power
	damage_reduction        = base_damage_reduction
	light_radius_multiplier = base_light_radius_multiplier
	energy_regen_rate       = base_energy_regen_rate
	energy_drain_rate       = base_energy_drain_rate
	
	var old_max_energy      = max_energy
	max_energy              = base_max_energy
	
	## 2. Layer all active boosts cleanly on top
	for stat in _active_boosts.keys():
		var amt: float = _active_boosts[stat].amount
		match stat:
			StatType.SPEED:                   speed += amt
			StatType.XP_GAIN_MULTIPLIER:      xp_gain_multiplier += amt
			StatType.BITE_POWER:              bite_power += amt
			StatType.DAMAGE_REDUCTION:        damage_reduction += amt
			StatType.MAX_ENERGY:              max_energy += amt
			StatType.ENERGY_REGEN_RATE:       energy_regen_rate += amt
			StatType.ENERGY_DRAIN_RATE:       energy_drain_rate += amt
			StatType.LIGHT_RADIUS_MULTIPLIER: light_radius_multiplier += amt
			
	## 3. Apply safe boundaries
	damage_reduction = clampf(damage_reduction, 0.0, 1.0)
	
	if max_energy != old_max_energy:
		current_energy = minf(current_energy, max_energy)

## Ensures the local client player actually updates their XP variable
func _on_network_xp_changed(peer_id: int, new_xp: float) -> void:
	if owner.is_in_group("players") and owner.get_multiplayer_authority() == peer_id:
		current_xp = new_xp

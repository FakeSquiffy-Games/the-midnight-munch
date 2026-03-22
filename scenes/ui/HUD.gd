## HUD.gd
## Heads-up display for the local player only.
## Shows current level, XP progress, and energy bar.
## Listens to SignalBus signals emitted by the server.
class_name HUD
extends CanvasLayer


# =========================================================
# NODE REFERENCES
# =========================================================

@onready var level_label: Label       = $VBoxContainer/LevelLabel
@onready var xp_bar:      ProgressBar = $VBoxContainer/XPBar
@onready var energy_bar:  ProgressBar = $VBoxContainer/EnergyBar


# =========================================================
# STATE
# =========================================================

## The peer ID this HUD belongs to. Set by Player.gd on initialisation.
var _peer_id: int = -1


# =========================================================
# INITIALISATION
# =========================================================

## Called by Player.gd immediately after instancing the HUD.
## [peer_id]      — the local player's peer ID, used to filter signals
## [stat_manager] — reference to read initial stat values from
func initialise(peer_id: int, stat_manager: StatManager) -> void:
	#print("HUD.initialise: peer_id=%d, current_xp=%.1f, current_energy=%.1f" \
		#% [peer_id, stat_manager.current_xp, stat_manager.current_energy])
	_peer_id = peer_id

	energy_bar.max_value = stat_manager.max_energy

	## Read initial values directly from StatManager rather than
	## waiting for signals — the HUD may connect after the first
	## emit fires, causing it to miss the initial state entirely.
	_update_xp(stat_manager.current_xp)
	_update_energy(stat_manager.current_energy, stat_manager.max_energy)

	SignalBus.xp_changed.connect(_on_xp_changed)
	SignalBus.energy_changed.connect(_on_energy_changed)


# =========================================================
# SIGNAL HANDLERS
# =========================================================

## Fired by CombatResolver (Phase 4) when XP changes on the server.
func _on_xp_changed(peer_id: int, new_xp: float) -> void:
	if peer_id != _peer_id:
		return
	_update_xp(new_xp)


## Fired by PlayerController on the server when energy changes.
func _on_energy_changed(peer_id: int, current: float, maximum: float) -> void:
	if peer_id != _peer_id:
		return
	_update_energy(current, maximum)


# =========================================================
# DISPLAY HELPERS
# =========================================================

## Updates the XP bar and level label.
## [stat_manager] may be null — level is derived from XP_THRESHOLDS directly.
func _update_xp(new_xp: float) -> void:
	#print("HUD._update_xp: new_xp=%.1f, bar_min=%.1f, bar_max=%.1f, bar_value=%.1f, label=%s" \
		#% [new_xp, xp_bar.min_value, xp_bar.max_value, xp_bar.value, level_label.text])
	var derived_level := 0
	for i in range(StatManager.XP_THRESHOLDS.size() - 1, -1, -1):
		if new_xp >= StatManager.XP_THRESHOLDS[i]:
			derived_level = i
			break

	var current_threshold := StatManager.XP_THRESHOLDS[derived_level]
	var next_threshold    := StatManager.XP_THRESHOLDS[
		min(derived_level + 1, StatManager.XP_THRESHOLDS.size() - 1)]

	xp_bar.min_value = current_threshold
	xp_bar.max_value = next_threshold
	xp_bar.value     = new_xp

	level_label.text = "Level %d" % derived_level


## Updates the energy bar.
func _update_energy(current: float, maximum: float) -> void:
	energy_bar.max_value = maximum
	energy_bar.value     = current

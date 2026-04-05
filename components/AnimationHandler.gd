class_name AnimationHandler
extends Node

var _entity: Entity
var _stat_manager: StatManager

var _last_xp: float = 0.0
var _last_level: int = 0
var _current_scale_mult: float = 1.0

func _ready() -> void:
	_entity = owner as Entity
	call_deferred("_initialize")
	
	## Listen to global boosts so we can spawn "+Speed" text
	SignalBus.boost_applied.connect(_on_global_boost_applied)

func _initialize() -> void:
	_stat_manager = _entity.get_node_or_null("StatManager")
	if not _stat_manager:
		set_process(false)
		return
		
	## Set initial values
	_last_xp = _stat_manager.current_xp
	_last_level = _stat_manager.level
	_current_scale_mult = _calculate_scale_for_level(_last_level)
	_apply_scale_multiplier(_current_scale_mult)
	_update_nametag() # Call once on startup to set the initial text


func _process(_delta: float) -> void:
	if not is_instance_valid(_stat_manager): return
	
	## NEW: Counter-flip the nametag so it never reads backwards
	if is_instance_valid(_entity.model):
		var label := _entity.model.get_node_or_null("Nametag") as Label
		if label:
			label.scale.x = -1.0 if _entity.sync_flip_h else 1.0
	
	var current_xp = _stat_manager.current_xp
	if current_xp != _last_xp:
		var diff: float = current_xp - _last_xp
		
		if diff < 0:
			_flash_red()
			## Spawn "-XP" text in Red
			FloatingText.spawn(_entity.get_parent(), _entity.global_position, str(round(diff)) + " XP", Color(1.0, 0.3, 0.3))
		elif diff > 0:
			## Spawn "+XP" text in Cyan
			FloatingText.spawn(_entity.get_parent(), _entity.global_position, "+" + str(round(diff)) + " XP", Color(0.3, 1.0, 1.0))
			
		_last_xp = current_xp
		
		if not _entity.is_in_group("players"):
			return
		
		## Check for Level/Tier changes
		var current_level = _stat_manager.level
		if current_level != _last_level:
			_on_level_changed(current_level)
			_last_level = current_level

func _on_level_changed(new_level: int) -> void:
	var target_mult := _calculate_scale_for_level(new_level)
	
	var tween := create_tween()
	tween.set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)
	
	## Elegant property tweening straight to the Entity
	tween.tween_property(_entity, "current_scale_mult", target_mult, 0.4)
	
	_update_nametag() # Update the nametag when they level up

## Safely applies scale while honoring the current flip state
func _apply_scale_multiplier(mult: float) -> void:
	if not is_instance_valid(_entity.model): return
	
	var final_s := _entity.model.base_scale * mult
	var sign_x  := -1.0 if _entity.sync_flip_h else 1.0
	
	_entity.scale = Vector2(final_s * sign_x, final_s)

func _flash_red() -> void:
	if is_instance_valid(_entity.sprite):
		var tween := create_tween()
		_entity.sprite.modulate = Color(1.0, 0.3, 0.3, 1.0)
		tween.tween_property(_entity.sprite, "modulate", Color.WHITE, 0.2)

func _calculate_scale_for_level(lvl: int) -> float:
	if lvl <= 4:
		return 1.0 + (lvl * 0.1)               # Baby: 1.0x to 1.4x
	elif lvl <= 7:
		return 1.8 + ((lvl - 5) * 0.2)         # Teen: 1.8x to 2.2x
	else:
		var clamped: int = min(lvl, 10)
		return 2.8 + ((clamped - 8) * 0.2)     # Adult: 2.8x to 3.2x

## NEW: Formats and updates the nametag label
func _update_nametag() -> void:
	if not is_instance_valid(_entity.model): return
	
	var label := _entity.model.get_node_or_null("Nametag") as Label
	if label == null: return
	
	var tier_str := "B"
	if _stat_manager.tier == 1: tier_str = "T"
	elif _stat_manager.tier == 2: tier_str = "A"
	
	var entity_name := _entity.model.species_name
	
	## (Phase 8 will replace entity_name with Username for players)
	label.text = "(%s) Lvl %d | %s" % [tier_str, _stat_manager.level, entity_name]

## Listens to the global signal and spawns text if THIS entity was the one boosted
func _on_global_boost_applied(target_path: String, stat: int, amount: float, _duration: float) -> void:
	if str(_entity.get_path()) != target_path: 
		return
		
	var stat_name := ""
	match stat:
		StatManager.StatType.SPEED: stat_name = "Speed"
		StatManager.StatType.BITE_POWER: stat_name = "Bite"
		StatManager.StatType.MAX_ENERGY: stat_name = "Energy"
		_: stat_name = "Boost"
		
	var text := "+%s %s!" % [str(amount), stat_name]
	FloatingText.spawn(_entity.get_parent(), _entity.global_position, text, Color(0.3, 1.0, 0.3)) # Green

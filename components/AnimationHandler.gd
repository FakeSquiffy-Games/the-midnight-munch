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

func _process(_delta: float) -> void:
	if not is_instance_valid(_stat_manager): return
	
	var current_xp = _stat_manager.current_xp
	if current_xp != _last_xp:
		## Flash red if XP was lost
		if current_xp < _last_xp:
			_flash_red()
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

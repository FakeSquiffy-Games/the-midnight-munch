class_name BioluminescentComponent
extends Node2D

enum Mode { ACTIVE, PLAYER, DORMANT }

@export var mode: Mode = Mode.ACTIVE
@export var local_only: bool = true          # If true, only the authority peer sees this light
@export var max_radius: float = 200.0
@export var glow_color: Color = Color(1.0, 0.8, 0.4, 1.0)
@export var drain_rate: float = 20.0         
@export var dormant_trigger_radius: float = 300.0  

var current_radius: float = 0.0
var is_active: bool = false
var light: PointLight2D
var dormant_detector: Area2D

func _ready() -> void:
	var entity = owner as Entity
	
	## Check Perspective: If this light is local_only, and we don't own this entity, delete the light.
	if local_only and entity and not entity.is_multiplayer_authority():
		queue_free()
		return

	_setup_light()
	
	match mode:
		Mode.ACTIVE, Mode.PLAYER:
			current_radius = max_radius
			is_active = true
		Mode.DORMANT:
			current_radius = 0.0
			is_active = false
			_setup_dormant_detector()
			
	## Listen for Light Energy boosts to replenish!
	SignalBus.boost_applied.connect(_on_boost_applied)

func _process(delta: float) -> void:
	match mode:
		Mode.PLAYER:  _process_player_mode(delta)
		Mode.ACTIVE:  _process_active_mode()
		Mode.DORMANT: _process_dormant_mode(delta)
	_update_light()

func _process_active_mode() -> void:
	if not is_active: return
	current_radius = max_radius

func _process_player_mode(delta: float) -> void:
	if not is_active: return
	current_radius -= drain_rate * delta
	current_radius = max(current_radius, 100.0)

func _process_dormant_mode(delta: float) -> void:
	if is_active:
		current_radius = move_toward(current_radius, max_radius, 150.0 * delta)
	else:
		current_radius = move_toward(current_radius, 0.0, 150.0 * delta)

func _update_light() -> void:
	if light == null: return
	
	if current_radius <= 1.0:
		light.visible = false
		return
	light.visible = true
	light.texture_scale = current_radius / 256.0
	var pulse = 1.0 + sin(Time.get_ticks_msec() * 0.002) * 0.05
	light.energy = 1.5 * pulse

## Listens to the ECS Boost System to replenish light
func _on_boost_applied(target_path: String, stat: int, amount: float, _duration: float) -> void:
	if stat == StatManager.StatType.LIGHT_ENERGY and str(owner.get_path()) == target_path:
		current_radius = min(current_radius + amount, max_radius)

func _setup_light() -> void:
	light = PointLight2D.new()
	light.texture = _generate_light_texture()
	light.energy = 1.5
	light.texture_scale = _radius_to_scale(current_radius if current_radius > 0 else max_radius)
	light.color = glow_color
	light.visible = false
	light.shadow_enabled = false
	# This is critical - centers the light on the entity
	light.offset = Vector2.ZERO
	add_child(light)

func _generate_light_texture() -> ImageTexture:
	var size = 512
	var center = size / 2
	var img = Image.create(size, size, false, Image.FORMAT_RGBA8)
	
	for x in range(size):
		for y in range(size):
			var dist = Vector2(x - center, y - center).length()
			var normalized = dist / center  # 0.0 at center, 1.0 at edge
			var alpha: float
			if normalized >= 1.0:
				alpha = 0.0
			elif normalized < 0.3:
				alpha = 1.0
			else:
				# Smooth falloff from 0.3 to 1.0
				alpha = 1.0 - smoothstep(0.3, 1.0, normalized)
			img.set_pixel(x, y, Color(1, 1, 1, alpha))
	
	return ImageTexture.create_from_image(img)

func _radius_to_scale(radius: float) -> float:
	# GradientTexture2D is 512px, scale it to match desired radius
	return radius / 256.0

func _setup_dormant_detector() -> void:
	dormant_detector = Area2D.new()
	var shape = CollisionShape2D.new()
	var circle = CircleShape2D.new()
	circle.radius = dormant_trigger_radius
	shape.shape = circle
	dormant_detector.add_child(shape)
	dormant_detector.collision_layer = 0
	dormant_detector.collision_mask = 2  # Player layer
	dormant_detector.body_entered.connect(_on_player_entered)
	dormant_detector.body_exited.connect(_on_player_exited)
	add_child(dormant_detector)

func _on_player_entered(body: Node) -> void:
	if body is CharacterBody2D:
		is_active = true

func _on_player_exited(body: Node) -> void:
	if body is CharacterBody2D:
		is_active = false

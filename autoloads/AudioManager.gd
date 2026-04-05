## AudioManager.gd
extends Node

## Dictionary to map string names to your audio files.
## (Update these paths when your partner imports the actual assets!)
var sounds: Dictionary = {
	"bite": preload("res://assets/audio/bite.wav"),
	"level_up": preload("res://assets/audio/level_up.wav"),
	"death": preload("res://assets/audio/death.wav"),
}

## Plays a global UI sound (e.g., Level Up, Game Over)
func play_ui_sound(sound_name: String, volume_db: float = 0.0) -> void:
	var stream = sounds.get(sound_name)
	if not stream or not stream is AudioStream: return
	
	var player := AudioStreamPlayer.new()
	player.stream = stream
	player.volume_db = volume_db
	player.bus = "Master"
	
	add_child(player)
	player.play()
	player.finished.connect(player.queue_free)

## Plays a spatial sound at a specific location in the world (e.g., Bites, Eliminations)
func play_spatial_sound(sound_name: String, global_pos: Vector2, volume_db: float = 0.0) -> void:
	var stream = sounds.get(sound_name)
	if not stream or not stream is AudioStream: return
	
	var player := AudioStreamPlayer2D.new()
	player.stream = stream
	player.global_position = global_pos
	player.volume_db = volume_db
	player.max_distance = 2000.0 # Fade out distance
	player.bus = "Master"
	
	## Add to the current scene tree rather than the Autoload so it has valid spatial context
	get_tree().current_scene.add_child(player)
	player.play()
	player.finished.connect(player.queue_free)

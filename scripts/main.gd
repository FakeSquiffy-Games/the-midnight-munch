extends Node2D

@onready var hud = $HUD

const PlayerScene = preload("../scenes/player.tscn")
var spawn_positions = [Vector2(-300, 0), Vector2(0, 0), Vector2(300, 0)]

func _ready() -> void:
	NetworkManager.player_disconnected.connect(_on_player_disconnected)
	if multiplayer.is_server():
		_spawn_all_players()

func _on_player_disconnected(peer_id: int) -> void:
	# Remove disconnected player from scene
	var player = $Players.get_node_or_null("Player_" + str(peer_id))
	if player:
		player.queue_free()

func _spawn_all_players() -> void:
	var all_ids = [1] + Array(multiplayer.get_peers())
	for i in range(min(all_ids.size(), spawn_positions.size())):
		spawn_player.rpc(all_ids[i], spawn_positions[i])

@rpc("authority", "call_local", "reliable")
func spawn_player(id: int, pos: Vector2) -> void:
	var player = PlayerScene.instantiate()
	player.name = "Player_" + str(id)
	player.position = pos
	$Players.add_child(player)
	player.setup(id)
	print("Spawned player id: ", id, " | my id: ", multiplayer.get_unique_id())

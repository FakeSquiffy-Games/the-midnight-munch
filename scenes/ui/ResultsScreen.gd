extends CanvasLayer

@onready var winner_page: Control = $WinnerPage
@onready var stats_page: Control = $StatsPage
@onready var winner_label: Label = $WinnerPage/WinnerLabel
@onready var next_button: TextureButton = $WinnerPage/NextButton
@onready var stats_label: Label = $StatsPage/StatsLabel
@onready var lobby_button: TextureButton = $StatsPage/LobbyButton
@onready var wait_label: Label = $StatsPage/WaitLabel

func _ready() -> void:
	winner_page.visible = true
	stats_page.visible = false
	next_button.pressed.connect(_on_next_pressed)
	lobby_button.pressed.connect(_on_lobby_pressed)
	
	SignalBus.personal_stats_received.connect(_on_stats_received)
	
	## Only Host can click "Return to Lobby"
	if multiplayer.is_server():
		lobby_button.visible = true
		wait_label.visible = false
	else:
		lobby_button.visible = false
		wait_label.visible = true

func setup(winner_name: String) -> void:
	if winner_name == "Game Over":
		winner_label.text = "You Were Eliminated!"
	elif winner_name == "Draw":
		winner_label.text = "Draw!"
	else:
		winner_label.text = "%s Wins!" % winner_name

func _on_next_pressed() -> void:
	winner_page.visible = false
	stats_page.visible = true

func _on_stats_received(stats: Dictionary) -> void:
	stats_label.text = "--- Personal Stats ---\n\n"
	stats_label.text += "Max Level Reached: %d\n" % stats["max_level"]
	stats_label.text += "Players Eliminated: %d\n" % stats["p_kills"]
	stats_label.text += "NPCs Eaten: %d\n" % stats["n_kills"]
	stats_label.text += "Total XP Collected: %d\n" % round(stats["xp"])
	stats_label.text += "Time Survived: %.1f seconds\n" % stats["time"]

func _on_lobby_pressed() -> void:
	lobby_button.disabled = true
	GameState.request_return_to_lobby.rpc_id(1)

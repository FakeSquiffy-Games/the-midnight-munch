## LobbyUI.gd
## Entry point UI for hosting or joining a LAN session.
## Phase 2C: Start Game button, countdown display, and scene transition.
extends Control


# =========================================================
# NODE REFERENCES
# =========================================================

@onready var title_label:  Label    = $VBoxContainer/TitleLabel
@onready var host_button:  Button   = $VBoxContainer/HostButton
@onready var key_label:    Label    = $VBoxContainer/KeyLabel
@onready var key_input:    LineEdit = $VBoxContainer/KeyInput
@onready var join_button:  Button   = $VBoxContainer/JoinButton
@onready var status_label: Label    = $VBoxContainer/StatusLabel
@onready var start_button: Button   = $VBoxContainer/StartButton


# =========================================================
# LIFECYCLE
# =========================================================

func _ready() -> void:
	title_label.text          = "Feeding Frenzy"
	host_button.text          = "Host Game"
	join_button.text          = "Join Game"
	start_button.text         = "Start Game"
	start_button.visible      = false
	start_button.disabled     = true
	key_label.text            = ""
	key_input.max_length      = NetworkManager.KEY_LENGTH
	key_input.placeholder_text = "Enter session key..."
	status_label.text         = "Host a new game or enter a key to join."

	host_button.pressed.connect(_on_host_pressed)
	join_button.pressed.connect(_on_join_pressed)
	start_button.pressed.connect(_on_start_pressed)

	NetworkManager.player_connected.connect(_on_player_connected)
	NetworkManager.player_disconnected.connect(_on_player_disconnected)
	NetworkManager.connected_to_server.connect(_on_connected_to_server)
	NetworkManager.connection_failed.connect(_on_connection_failed)
	NetworkManager.server_disconnected.connect(_on_server_disconnected)
	NetworkManager.discovery_failed.connect(_on_discovery_failed)
	NetworkManager.countdown_tick.connect(_on_countdown_tick)


# =========================================================
# BUTTON HANDLERS
# =========================================================

func _on_host_pressed() -> void:
	NetworkManager.host_game()
	key_label.text        = "Session key:  %s" % NetworkManager.session_key
	status_label.text     = "Hosting — share the key with other players."
	host_button.disabled  = true
	join_button.disabled  = true
	key_input.editable    = false
	## Show Start Game immediately so host can solo-test transition if needed.
	start_button.visible  = true
	start_button.disabled = true


func _on_join_pressed() -> void:
	var key: String = key_input.text.strip_edges().to_upper()
	if key.length() != NetworkManager.KEY_LENGTH:
		status_label.text = "Key must be exactly %d characters." % NetworkManager.KEY_LENGTH
		return
	status_label.text     = "Searching for host with key '%s'..." % key
	host_button.disabled  = true
	join_button.disabled  = true
	key_input.editable    = false
	NetworkManager.join_game(key)


## Only callable by the host — triggers the server-driven countdown RPC.
func _on_start_pressed() -> void:
	if not multiplayer.is_server():
		return
	start_button.disabled = true
	NetworkManager.start_game()


# =========================================================
# NETWORKMANAGER SIGNAL HANDLERS
# =========================================================

func _on_player_connected(peer_id: int) -> void:
	if multiplayer.is_server():
		status_label.text = "Player connected — peer ID %d. Total: %d." \
			% [peer_id, GameState.player_states.size()]
		## Enable Start once at least one client has joined (total >= 2).
		start_button.disabled = GameState.player_states.size() < 2
	else:
		if peer_id == 1:
			return
		status_label.text = "Another player joined — peer ID %d." % peer_id


func _on_player_disconnected(peer_id: int) -> void:
	status_label.text = "Player disconnected — peer ID %d." % peer_id
	## Re-disable Start if player count drops below 2 again.
	if multiplayer.is_server():
		start_button.disabled = GameState.player_states.size() < 2


func _on_connected_to_server() -> void:
	status_label.text = "Connected! My peer ID: %d." % multiplayer.get_unique_id()


func _on_connection_failed() -> void:
	status_label.text = "Connection failed. Check the key and try again."
	_reset_ui()


func _on_server_disconnected() -> void:
	status_label.text = "Host disconnected. Returned to lobby."
	key_label.text    = ""
	_reset_ui()


func _on_discovery_failed() -> void:
	status_label.text = "No host found for that key. Is the host running?"
	_reset_ui()


## Updates the status label during the countdown RPC.
func _on_countdown_tick(seconds_remaining: int) -> void:
	status_label.text = "Game starting in %d..." % seconds_remaining


# =========================================================
# HELPERS
# =========================================================

func _reset_ui() -> void:
	host_button.disabled  = false
	join_button.disabled  = false
	key_input.editable    = true
	key_input.text        = ""
	start_button.visible  = false
	start_button.disabled = true

## LobbyUI.gd
## Entry point UI for hosting or joining a LAN session.
## Phase 2C: Start Game button, countdown display, and scene transition.
extends Control


# =========================================================
# NODE REFERENCES
# =========================================================

#@onready var title_label:  Label    = $VBoxContainer/TitleLabel
@onready var host_button:  Button   = $VBoxContainer/HostButton
@onready var key_label:    Label    = $VBoxContainer/KeyLabel
@onready var key_input:    LineEdit = $VBoxContainer/KeyInput
@onready var join_button:  Button   = $VBoxContainer/JoinButton
@onready var leave_button: Button   = $VBoxContainer/LeaveButton
@onready var status_label: Label    = $VBoxContainer/StatusLabel
@onready var start_button: Button   = $VBoxContainer/StartButton
@onready var single_player_button: Button = $VBoxContainer/SinglePlayerButton

@onready var username_input: LineEdit = $VBoxContainer/UsernameInput
@onready var prev_button:    Button   = $VBoxContainer/CarouselContainer/PrevButton
@onready var next_button:    Button   = $VBoxContainer/CarouselContainer/NextButton
@onready var char_texture:   TextureRect = $VBoxContainer/CarouselContainer/CharacterDisplay/CharTexture
@onready var char_name:      Label    = $VBoxContainer/CarouselContainer/CharacterDisplay/CharName
@onready var char_desc:      Label    = $VBoxContainer/CarouselContainer/CharacterDisplay/CharDesc
@onready var ready_button:   Button   = $VBoxContainer/ReadyButton

## Drag your Player.tscn prefabs here in the Inspector!
@export var available_characters: Array[PackedScene] =[]

var current_index: int = 0
var is_ready: bool = false
var locked_indices: Dictionary = {} # peer_id -> index


# =========================================================
# LIFECYCLE
# =========================================================

func _ready() -> void:
	host_button.pressed.connect(_on_host_pressed)
	join_button.pressed.connect(_on_join_pressed)
	leave_button.pressed.connect(_on_leave_pressed)
	start_button.pressed.connect(_on_start_pressed)
	single_player_button.pressed.connect(_on_single_player_pressed)

	prev_button.pressed.connect(func(): _shift_carousel(-1))
	next_button.pressed.connect(func(): _shift_carousel(1))
	ready_button.pressed.connect(_on_ready_pressed)

	NetworkManager.player_connected.connect(_on_player_connected)
	NetworkManager.player_disconnected.connect(_on_player_disconnected)
	NetworkManager.connected_to_server.connect(_on_connected_to_server)
	NetworkManager.connection_failed.connect(_on_connection_failed)
	NetworkManager.server_disconnected.connect(_on_server_disconnected)
	NetworkManager.discovery_failed.connect(_on_discovery_failed)
	NetworkManager.countdown_tick.connect(_on_countdown_tick)
	
	## FIX: Specifically check if we are in an active LAN session (ENet)
	var peer = multiplayer.multiplayer_peer
	var is_lan_connected = (peer is ENetMultiplayerPeer) and (peer.get_connection_status() == MultiplayerPeer.CONNECTION_CONNECTED)
	
	if is_lan_connected:
		_restore_active_connection()
	else:
		## Fresh boot OR returning from Single Player: Reset to default state!
		_reset_ui()
	
	AudioManager.stop_sound("ambience")
	AudioManager.play_ui_sound("intro")


# =========================================================
# BUTTON HANDLERS
# =========================================================

func _on_host_pressed() -> void:
	NetworkManager.host_game()
	key_label.text        = "Session key:  %s" % NetworkManager.session_key
	status_label.text     = "Hosting — share the key with other players."
	single_player_button.disabled = true
	host_button.disabled  = true
	join_button.disabled  = true
	key_input.editable    = false
	## Show Start Game immediately so host can solo-test transition if needed.
	start_button.visible  = true
	start_button.disabled = true
	leave_button.visible = true


func _on_join_pressed() -> void:
	var key: String = key_input.text.strip_edges().to_upper()
	if key.length() != NetworkManager.KEY_LENGTH:
		status_label.text = "Key must be exactly %d characters." % NetworkManager.KEY_LENGTH
		return
	status_label.text     = "Searching for host with key '%s'..." % key
	single_player_button.disabled = true
	host_button.disabled  = true
	join_button.disabled  = true
	key_input.editable    = false
	NetworkManager.join_game(key)

func _on_leave_pressed() -> void:
	if is_ready:
		## Tell the server to unlock my fish so others can have it immediately
		request_unlock.rpc_id(1)
		## Give the engine one frame to flush the RPC buffer before closing the connection
		await get_tree().process_frame
	NetworkManager.leave_game()
	_reset_ui()

## Only callable by the host — triggers the server-driven countdown RPC.
func _on_start_pressed() -> void:
	if not multiplayer.is_server():
		return
	start_button.disabled = true
	NetworkManager.start_game()

func _on_single_player_pressed() -> void:
	var uname := username_input.text.strip_edges()
	if uname == "": uname = "Player 1"
	var scene_path := available_characters[current_index].resource_path
	NetworkManager.start_single_player(scene_path, uname)


# =========================================================
# NETWORKMANAGER SIGNAL HANDLERS
# =========================================================

#func _on_player_connected(peer_id: int) -> void:
	#if multiplayer.is_server():
		#status_label.text = "Player connected — peer ID %d. Total: %d." \
			#% [peer_id, GameState.player_states.size()]
		### Enable Start once at least one client has joined (total >= 2).
		#start_button.disabled = GameState.player_states.size() < 2
	#else:
		#if peer_id == 1:
			#return
		#status_label.text = "Another player joined — peer ID %d." % peer_id

func _on_player_connected(peer_id: int) -> void:
	if multiplayer.is_server():
		## Send existing locks to the newly joined player
		_sync_lobby_state.rpc_id(peer_id, locked_indices)

@rpc("authority", "call_remote", "reliable")
func _sync_lobby_state(state: Dictionary) -> void:
	locked_indices = state
	_update_carousel()

func _check_start_condition() -> void:
	if multiplayer.is_server():
		var total_peers := GameState.player_states.size()
		var is_everyone_ready := (locked_indices.size() == total_peers)
		start_button.disabled = not (is_everyone_ready and total_peers >= 2)

func _on_player_disconnected(peer_id: int) -> void:
	status_label.text = "Player disconnected — peer ID %d." % peer_id
	if multiplayer.is_server():
		status_label.text = "Player %d disconnected. Total: %d." \
			% [peer_id, GameState.player_states.size()]
		
		## FIX: If the disconnected player had a fish locked, force an unlock broadcast
		if locked_indices.has(peer_id):
			_confirm_unlock.rpc(peer_id)
			
		## Re-enable Start button check in case the group size changed
		_check_start_condition()
	else:
		if peer_id == 1:
			return # Host handled by _on_server_disconnected
		status_label.text = "Another player left — peer ID %d." % peer_id

func _on_connected_to_server() -> void:
	status_label.text = "Connected! My peer ID: %d." % multiplayer.get_unique_id()
	leave_button.visible = true


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
# CAROUSEL & VISUALS
# =========================================================

func _shift_carousel(dir: int) -> void:
	if available_characters.is_empty(): return
	current_index = wrap(current_index + dir, 0, available_characters.size())
	_update_carousel()

func _update_carousel() -> void:
	if available_characters.is_empty(): return
	
	var scene := available_characters[current_index]
	
	if scene == null:
		char_name.text = "Missing Scene"
		char_desc.text = "Assign a Player Prefab in the LobbyUI Inspector!"
		char_texture.texture = null
		ready_button.disabled = true
		return
		
	var temp := scene.instantiate()
	if temp:
		char_name.text = temp.get("character_name") if "character_name" in temp else "Unnamed"
		char_desc.text = temp.get("character_description") if "character_description" in temp else ""
		
		## FIX: Get the EntityModel directly from the children since it's already built-in!
		var model = temp.get_node_or_null("EntityModel")
		if model:
			var sprite = model.get_node_or_null("AnimatedSprite2D") as AnimatedSprite2D
			if sprite and sprite.sprite_frames:
				var anim_name = "idle" 
				if not sprite.sprite_frames.has_animation("idle"):
					anim_name = "default"
				char_texture.texture = sprite.sprite_frames.get_frame_texture(anim_name, 0)
			else:
				char_texture.texture = null
		else:
			char_texture.texture = null
			char_desc.text += "\n[Error: No 'EntityModel' child node found]"
			
		temp.free()

	## Check if someone ELSE locked this character
	var is_taken_by_others = false
	if multiplayer.multiplayer_peer != null:
		var my_id = multiplayer.get_unique_id()
		for peer in locked_indices:
			if peer != my_id and locked_indices[peer] == current_index:
				is_taken_by_others = true
			
	if is_taken_by_others:
		char_name.text += " (Taken)"
		char_texture.modulate = Color(0.3, 0.3, 0.3, 0.8)
		ready_button.disabled = true
	else:
		char_texture.modulate = Color.WHITE
		## FIX: If I am ready, the button must be enabled so I can click "Cancel"
		## If I am not ready, the button is enabled only if the fish isn't taken.
		ready_button.disabled = false if is_ready else false
		# Simplified: ready_button.disabled = false

# =========================================================
# READY & LOCKING RPCs
# =========================================================

func _on_ready_pressed() -> void:
	var uname := username_input.text.strip_edges()
	if uname == "": uname = "Player %d" % multiplayer.get_unique_id()
	
	if is_ready:
		request_unlock.rpc_id(1)
	else:
		request_lock.rpc_id(1, current_index, uname)

@rpc("any_peer", "call_local", "reliable")
func request_lock(index: int, username: String) -> void:
	if not multiplayer.is_server(): return
	var sender := multiplayer.get_remote_sender_id()
	if sender == 0: sender = 1
	
	for peer in locked_indices:
		if peer != sender and locked_indices[peer] == index:
			return # Rejected! Already taken.
			
	_confirm_lock.rpc(sender, index, username)

@rpc("authority", "call_local", "reliable")
func _confirm_lock(peer_id: int, index: int, username: String) -> void:
	locked_indices[peer_id] = index
	GameState.player_characters[peer_id] = available_characters[index].resource_path
	GameState.player_names[peer_id] = username
	
	if peer_id == multiplayer.get_unique_id():
		is_ready = true
		ready_button.text = "Cancel"
		prev_button.disabled = true
		next_button.disabled = true
		username_input.editable = false
		
	_update_carousel()
	_check_start_condition()

@rpc("any_peer", "call_local", "reliable")
func request_unlock() -> void:
	if not multiplayer.is_server(): return
	var sender := multiplayer.get_remote_sender_id()
	if sender == 0: sender = 1
	_confirm_unlock.rpc(sender)

@rpc("authority", "call_local", "reliable")
func _confirm_unlock(peer_id: int) -> void:
	locked_indices.erase(peer_id)
	GameState.player_characters.erase(peer_id)
	GameState.player_names.erase(peer_id)
	
	if peer_id == multiplayer.get_unique_id():
		is_ready = false
		ready_button.text = "Ready"
		prev_button.disabled = false
		next_button.disabled = false
		username_input.editable = true
		
	_update_carousel()
	_check_start_condition()


# =========================================================
# HELPERS & REMATCH RESTORE
# =========================================================

## Restores the Lobby layout and selections after a match ends
func _restore_active_connection() -> void:
	host_button.disabled  = true
	join_button.disabled  = true
	single_player_button.disabled = true
	key_input.editable    = false
	leave_button.visible  = true
	
	var my_id = multiplayer.get_unique_id()
	
	if multiplayer.is_server():
		status_label.text = "Hosting — share the key with other players."
		key_label.text    = "Session key:  %s" % NetworkManager.session_key
		start_button.visible = true
		_check_start_condition()
	else:
		status_label.text = "Connected! My peer ID: %d." % my_id

	## Restore previous character selection
	if GameState.player_characters.has(my_id):
		var saved_path = GameState.player_characters[my_id]
		for i in available_characters.size():
			if available_characters[i].resource_path == saved_path:
				current_index = i
				break
				
	if GameState.player_names.has(my_id):
		username_input.text = GameState.player_names[my_id]

	## Reset locking states so everyone must click "Ready" again
	locked_indices.clear()
	is_ready = false
	ready_button.text = "Ready"
	ready_button.disabled = false
	
	_update_carousel()

func _reset_ui() -> void:
	host_button.disabled  = false
	join_button.disabled  = false
	key_input.editable    = true
	key_input.text        = "Enter session key..."
	start_button.visible  = false
	start_button.disabled = true
	leave_button.visible  = false
	single_player_button.disabled = false
	status_label.text     = "Play solo, host a new game, or enter a key to join."
	locked_indices.clear()
	_update_carousel()

extends Control

@onready var lobby_ui = $LobbyUI
@onready var start_btn = $Start

@onready var host_btn = $LobbyUI/Panel/VBox/HostBtn
@onready var join_btn = $LobbyUI/Panel/VBox/JoinBtn
@onready var status_label = $LobbyUI/Panel/VBox/StatusLabel
@onready var my_ip_label = $LobbyUI/Panel/VBox/MyIPLabel
@onready var server_list: ItemList = $LobbyUI/Panel/VBox/ServerList

var found_hosts: Array = []

func _ready() -> void:
	lobby_ui.visible = false
	NetworkManager.game_ready.connect(_on_game_ready)
	NetworkManager.host_found.connect(_on_host_found)
	NetworkManager.connection_failed.connect(_on_connection_failed)
	NetworkManager.server_disconnected.connect(_on_server_disconnected)
	host_btn.pressed.connect(_on_host_pressed)
	join_btn.pressed.connect(_on_join_pressed)

func _on_host_pressed() -> void:
	NetworkManager.stop_listening()
	var ip = NetworkManager.host_game()
	if ip == "":
		status_label.text = "Failed to host!"
		return
	my_ip_label.text = "Your IP: " + ip
	status_label.text = "Waiting for players..."
	host_btn.disabled = true
	join_btn.disabled = true

func _on_join_pressed() -> void:
	var selected = server_list.get_selected_items()
	if selected.is_empty():
		status_label.text = "No server selected!"
		return
	var ip = found_hosts[selected[0]]
	status_label.text = "Connecting to " + ip + "..."
	host_btn.disabled = true
	join_btn.disabled = true
	NetworkManager.stop_listening()
	NetworkManager.join_game(ip)

func _on_host_found(ip: String) -> void:
	if ip not in found_hosts:
		found_hosts.append(ip)
		server_list.add_item("Game at " + ip)
	status_label.text = str(found_hosts.size()) + " server(s) found"

func _on_connection_failed() -> void:
	status_label.text = "Failed. Try again."
	host_btn.disabled = false
	join_btn.disabled = false
	NetworkManager.start_listening()

func _on_server_disconnected() -> void:
	status_label.text = "Host disconnected."
	host_btn.disabled = false
	join_btn.disabled = false
	found_hosts.clear()
	server_list.clear()
	NetworkManager.start_listening()
	
func _on_start_pressed() -> void:
	lobby_ui.visible = true
	start_btn.visible = false
	NetworkManager.start_listening()
	if OS.is_debug_build():
		found_hosts.append("127.0.0.1")
		server_list.add_item("Local Test (127.0.0.1)")
		
func _on_game_ready() -> void:
	get_tree().call_deferred("change_scene_to_file", "res://scenes/Main.tscn")

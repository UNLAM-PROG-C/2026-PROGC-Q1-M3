extends Control

enum LobbyState { DISCONNECTED, CONNECTING, IN_HOST_ROOM, READY_ROOM }

var _state: LobbyState = LobbyState.DISCONNECTED

@onready var name_input: LineEdit    = $VBoxContainer/NameInput
@onready var ip_input: LineEdit      = $VBoxContainer/HBox_Conexion/IPInput
@onready var host_button: Button     = $VBoxContainer/HBox_Conexion/HostButton
@onready var join_button: Button     = $VBoxContainer/HBox_Conexion/JoinButton
@onready var player_list: ItemList   = $VBoxContainer/PlayerList
@onready var status_label: Label     = $VBoxContainer/StatusLabel
@onready var start_button: Button    = $VBoxContainer/StartButton
@onready var leave_button: Button    = $VBoxContainer/LeaveButton


func _ready() -> void:
	if "--debug_solo" in OS.get_cmdline_args():
		get_tree().change_scene_to_file.call_deferred("res://scenes/game/game.tscn")
		return
	GameNetwork.player_list_changed.connect(_on_player_list_changed)
	GameNetwork.connection_succeeded.connect(_on_connection_succeeded)
	GameNetwork.connection_failed.connect(_on_connection_failed)
	GameNetwork.server_disconnected.connect(_on_server_disconnected)
	_set_state(LobbyState.DISCONNECTED)


func _set_state(new_state: LobbyState) -> void:
	_state = new_state
	match new_state:
		LobbyState.DISCONNECTED:
			name_input.editable = true
			ip_input.editable = true
			host_button.visible = true
			host_button.disabled = false
			join_button.visible = true
			join_button.disabled = false
			start_button.hide()
			leave_button.hide()
			player_list.clear()
		LobbyState.CONNECTING:
			name_input.editable = false
			ip_input.editable = false
			host_button.disabled = true
			join_button.disabled = true
			start_button.hide()
			leave_button.show()
			status_label.text = "Conectando..."
		LobbyState.IN_HOST_ROOM:
			name_input.editable = false
			ip_input.editable = false
			host_button.hide()
			join_button.hide()
			start_button.show()
			start_button.disabled = true
			leave_button.show()
		LobbyState.READY_ROOM:
			name_input.editable = false
			ip_input.editable = false
			host_button.hide()
			join_button.hide()
			start_button.hide()
			leave_button.show()
			status_label.text = "Esperando al host..."


func _resolve_name() -> String:
	var n := name_input.text.strip_edges()
	if n.is_empty():
		n = "Player_%d" % (randi() % 1000)
	return n


func _refresh_player_list() -> void:
	player_list.clear()
	var my_id := GameNetwork.get_my_id()
	for id in GameNetwork.players:
		var entry: String = GameNetwork.players[id]["name"]
		if id == 1:
			entry += " (host)"
		if id == my_id:
			entry += " (tú)"
		player_list.add_item(entry)
	if _state == LobbyState.IN_HOST_ROOM:
		start_button.disabled = GameNetwork.players.size() < 2
	elif _state == LobbyState.READY_ROOM:
		status_label.text = "Esperando al host... (%d jugadores)" % GameNetwork.players.size()


func _on_host_pressed() -> void:
	if _state != LobbyState.DISCONNECTED:
		return
	var nombre := _resolve_name()
	var err := GameNetwork.create_server(nombre)
	if err != OK:
		status_label.text = "Error al crear servidor (%d)" % err
		return
	_set_state(LobbyState.IN_HOST_ROOM)
	_show_host_ips()


func _show_host_ips() -> void:
	var ips: Array = []
	for addr in IP.get_local_addresses():
		# Filtrar solo IPv4 no-loopback
		if "." in addr and not addr.begins_with("127.") and not addr.begins_with("169.254."):
			ips.append(addr)
	if ips.is_empty():
		status_label.text = "Servidor creado. Puerto: %d" % GameNetwork.DEFAULT_PORT
	else:
		status_label.text = "Tu IP: %s  Puerto: %d" % [", ".join(ips), GameNetwork.DEFAULT_PORT]


func _on_join_pressed() -> void:
	if _state != LobbyState.DISCONNECTED:
		return
	var ip := ip_input.text.strip_edges()
	if ip.is_empty():
		ip = "127.0.0.1"
	var nombre := _resolve_name()
	var err := GameNetwork.join_server(ip, nombre)
	if err != OK:
		status_label.text = "Error al conectar (%d)" % err
		return
	_set_state(LobbyState.CONNECTING)


func _on_start_pressed() -> void:
	if GameNetwork.is_host():
		load_game.rpc()


func _on_leave_pressed() -> void:
	GameNetwork.disconnect_from_game()
	_set_state(LobbyState.DISCONNECTED)
	status_label.text = "Desconectado"


func _on_player_list_changed() -> void:
	_refresh_player_list()


func _on_connection_succeeded() -> void:
	_set_state(LobbyState.READY_ROOM)


func _on_connection_failed() -> void:
	_set_state(LobbyState.DISCONNECTED)
	status_label.text = "Error al conectar"


func _on_server_disconnected() -> void:
	_set_state(LobbyState.DISCONNECTED)
	status_label.text = "El servidor se cerró"


@rpc("authority", "call_local", "reliable")
func load_game() -> void:
	get_tree().change_scene_to_file("res://scenes/game/game.tscn")

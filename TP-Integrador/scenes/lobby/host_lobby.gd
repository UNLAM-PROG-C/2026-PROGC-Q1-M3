extends Control

enum State { SETUP, WAITING }

var _state: State = State.SETUP

@onready var title_label: Label         = $Content/LeftPanel/Margin/LeftSection/TitleLabel
@onready var name_input: LineEdit       = $Content/LeftPanel/Margin/LeftSection/NameInput
@onready var create_btn: Button         = $Content/LeftPanel/Margin/LeftSection/SetupButtonsRow/CreateButton
@onready var back_btn: Button           = $Content/LeftPanel/Margin/LeftSection/SetupButtonsRow/BackButton
@onready var setup_buttons_row: HBoxContainer = $Content/LeftPanel/Margin/LeftSection/SetupButtonsRow
@onready var ip_display: LineEdit       = $Content/LeftPanel/Margin/LeftSection/IPDisplay
@onready var players_label: Label       = $Content/LeftPanel/Margin/LeftSection/PlayersLabel
@onready var player_list: VBoxContainer = $Content/LeftPanel/Margin/LeftSection/PlayerList
@onready var buttons_row: HBoxContainer = $Content/LeftPanel/Margin/LeftSection/ButtonsRow
@onready var start_btn: Button          = $Content/LeftPanel/Margin/LeftSection/ButtonsRow/StartButton
@onready var leave_btn: Button          = $Content/LeftPanel/Margin/LeftSection/ButtonsRow/LeaveButton


func _ready() -> void:
	LobbyMusic.play()
	GameNetwork.player_list_changed.connect(_on_player_list_changed)
	# Si regresamos desde game.tscn con la conexión ENet activa, saltar el SETUP.
	if GameNetwork.is_host() and not GameNetwork.players.is_empty():
		_set_state(State.WAITING)
		_refresh_player_list()
	else:
		_set_state(State.SETUP)


func _set_state(new_state: State) -> void:
	_state = new_state
	match new_state:
		State.SETUP:
			name_input.visible = true
			name_input.editable = true
			setup_buttons_row.visible = true
			ip_display.visible = false
			players_label.visible = false
			player_list.visible = false
			buttons_row.visible = false
		State.WAITING:
			name_input.visible = false
			setup_buttons_row.visible = false
			ip_display.visible = true
			players_label.visible = true
			player_list.visible = true
			buttons_row.visible = true
			start_btn.disabled = true
			_show_host_ip()


func _resolve_name() -> String:
	var n := name_input.text.strip_edges()
	if n.is_empty():
		n = "Player_%d" % (randi() % 1000)
	return n


func _show_host_ip() -> void:
	# En PCs con VPN, VirtualBox, Hyper-V, WSL, etc. get_local_addresses() puede
	# devolver varias IPs y la primera no es necesariamente la de la red LAN real.
	# Priorizamos las de interfaces físicas (Wi-Fi/Ethernet) sobre las virtuales.
	var virtual_keywords := ["virtual", "vethernet", "virtualbox", "vmware", "hyper-v",
		"loopback", "tailscale", "zerotier", "tap", "wsl", "docker", "npcap"]
	var all_candidates: Array[String] = []
	var preferred: Array[String] = []
	for iface in IP.get_local_interfaces():
		var friendly: String = str(iface.get("friendly", iface.get("name", ""))).to_lower()
		var is_virtual := virtual_keywords.any(func(k): return friendly.contains(k))
		for addr in iface.get("addresses", []):
			if "." in addr and not addr.begins_with("127.") and not addr.begins_with("169.254."):
				all_candidates.append(addr)
				if not is_virtual:
					preferred.append(addr)
	var candidates := preferred if not preferred.is_empty() else all_candidates
	if candidates.is_empty():
		ip_display.text = "127.0.0.1"
		return
	ip_display.text = candidates[0]
	if all_candidates.size() > 1:
		print("GameNetwork: IPs locales detectadas: %s (mostrando %s). Si el cliente no logra conectar, probá con otra de estas IPs." % [all_candidates, candidates[0]])


func _refresh_player_list() -> void:
	for row in player_list.get_children():
		player_list.remove_child(row)
		row.queue_free()
	var my_id := GameNetwork.get_my_id()
	for id in GameNetwork.players:
		var player_name: String = GameNetwork.players[id]["name"]
		player_list.add_child(PlayerRow.create(player_name, id == 1, id == my_id))
	players_label.text = "Jugadores  (%d/%d)" % [GameNetwork.players.size(), GameNetwork.MAX_PLAYERS]
	start_btn.disabled = GameNetwork.players.size() < 2


func _on_create_pressed() -> void:
	var nombre := _resolve_name()
	var err := GameNetwork.create_server(nombre)
	if err != OK:
		title_label.text = "Error al crear servidor (%d)" % err
		return
	_set_state(State.WAITING)


func _on_back_pressed() -> void:
	get_tree().change_scene_to_file("res://scenes/ui/main_menu.tscn")


func _on_start_pressed() -> void:
	if GameNetwork.is_host():
		load_game.rpc()


func _on_leave_pressed() -> void:
	GameNetwork.disconnect_from_game()
	get_tree().change_scene_to_file("res://scenes/ui/main_menu.tscn")


func _on_player_list_changed() -> void:
	if _state == State.WAITING:
		_refresh_player_list()


@rpc("authority", "call_local", "reliable")
func load_game() -> void:
	get_tree().change_scene_to_file("res://scenes/game/game.tscn")

extends Control

enum State { SETUP, CONNECTING, CONNECTED }

var _state: State = State.SETUP

@onready var name_input: LineEdit          = $Content/RightPanel/Margin/RightSection/NameInput
@onready var ip_input: LineEdit            = $Content/RightPanel/Margin/RightSection/IPInput
@onready var setup_buttons_row: HBoxContainer = $Content/RightPanel/Margin/RightSection/SetupButtonsRow
@onready var connect_btn: Button           = $Content/RightPanel/Margin/RightSection/SetupButtonsRow/ConnectButton
@onready var back_btn: Button              = $Content/RightPanel/Margin/RightSection/SetupButtonsRow/BackButton
@onready var status_label: Label           = $Content/RightPanel/Margin/RightSection/StatusLabel
@onready var players_label: Label          = $Content/RightPanel/Margin/RightSection/PlayersLabel
@onready var player_list: ItemList         = $Content/RightPanel/Margin/RightSection/PlayerList
@onready var leave_btn: Button             = $Content/RightPanel/Margin/RightSection/LeaveButton


func _ready() -> void:
	_style_panel()
	_style_buttons()
	GameNetwork.connection_succeeded.connect(_on_connection_succeeded)
	GameNetwork.connection_failed.connect(_on_connection_failed)
	GameNetwork.player_list_changed.connect(_on_player_list_changed)
	GameNetwork.server_disconnected.connect(_on_server_disconnected)
	# Si regresamos desde game.tscn con la conexión ENet activa, saltar al estado CONNECTED.
	if multiplayer.has_multiplayer_peer() and not GameNetwork.players.is_empty():
		_set_state(State.CONNECTED)
		_refresh_player_list()
	else:
		_set_state(State.SETUP)


func _style_panel() -> void:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.995, 0.990, 0.984)
	style.set_border_width_all(1)
	style.border_color = Color(0.820, 0.800, 0.780)
	style.set_corner_radius_all(14)
	style.content_margin_left = 0.0
	style.content_margin_right = 0.0
	style.content_margin_top = 0.0
	style.content_margin_bottom = 0.0
	$Content/RightPanel.add_theme_stylebox_override("panel", style)


func _apply_button_style(button: Button) -> void:
	var normal := StyleBoxFlat.new()
	normal.bg_color = Color(0.96, 0.945, 0.925)
	normal.set_border_width_all(2)
	normal.border_color = Color(0.42, 0.40, 0.38)
	normal.set_corner_radius_all(10)
	normal.content_margin_left = 24.0
	normal.content_margin_right = 24.0
	normal.content_margin_top = 12.0
	normal.content_margin_bottom = 12.0
	button.add_theme_stylebox_override("normal", normal)
	var hover := normal.duplicate()
	hover.bg_color = Color(0.84, 0.82, 0.79)
	button.add_theme_stylebox_override("hover", hover)
	var pressed := normal.duplicate()
	pressed.bg_color = Color(0.74, 0.72, 0.69)
	button.add_theme_stylebox_override("pressed", pressed)
	button.add_theme_color_override("font_color", Color(0.12, 0.12, 0.12))
	button.add_theme_font_size_override("font_size", 18)


func _style_buttons() -> void:
	for btn in [connect_btn, back_btn, leave_btn] as Array[Button]:
		_apply_button_style(btn)


func _set_state(new_state: State) -> void:
	_state = new_state
	match new_state:
		State.SETUP:
			name_input.visible = true
			name_input.editable = true
			ip_input.visible = true
			ip_input.editable = true
			setup_buttons_row.visible = true
			connect_btn.disabled = false
			status_label.visible = false
			players_label.visible = false
			player_list.visible = false
			leave_btn.visible = false
		State.CONNECTING:
			name_input.editable = false
			ip_input.editable = false
			setup_buttons_row.visible = false
			status_label.visible = true
			status_label.text = "Conectando..."
			leave_btn.visible = true
		State.CONNECTED:
			name_input.visible = false
			ip_input.visible = false
			setup_buttons_row.visible = false
			status_label.visible = false
			players_label.visible = true
			player_list.visible = true
			leave_btn.visible = true


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
	players_label.text = "Jugadores  (%d/%d)" % [GameNetwork.players.size(), GameNetwork.MAX_PLAYERS]


func _on_connect_pressed() -> void:
	var ip := ip_input.text.strip_edges()
	if ip.is_empty():
		ip = "127.0.0.1"
	var nombre := _resolve_name()
	var err := GameNetwork.join_server(ip, nombre)
	if err != OK:
		status_label.visible = true
		status_label.text = "Error al conectar (%d)" % err
		return
	_set_state(State.CONNECTING)


func _on_back_pressed() -> void:
	get_tree().change_scene_to_file("res://scenes/ui/main_menu.tscn")


func _on_leave_pressed() -> void:
	GameNetwork.disconnect_from_game()
	get_tree().change_scene_to_file("res://scenes/ui/main_menu.tscn")


func _on_connection_succeeded() -> void:
	_set_state(State.CONNECTED)
	_refresh_player_list()


func _on_connection_failed() -> void:
	_set_state(State.SETUP)
	status_label.visible = true
	status_label.text = "Error al conectar. Verificá la IP e intentá de nuevo."


func _on_server_disconnected() -> void:
	_set_state(State.SETUP)
	status_label.visible = true
	status_label.text = "El servidor se cerró."


func _on_player_list_changed() -> void:
	if _state == State.CONNECTED or _state == State.CONNECTING:
		_refresh_player_list()


@rpc("authority", "call_local", "reliable")
func load_game() -> void:
	get_tree().change_scene_to_file("res://scenes/game/game.tscn")

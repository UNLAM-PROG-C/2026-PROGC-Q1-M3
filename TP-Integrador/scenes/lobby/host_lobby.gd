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
@onready var player_list: ItemList      = $Content/LeftPanel/Margin/LeftSection/PlayerList
@onready var buttons_row: HBoxContainer = $Content/LeftPanel/Margin/LeftSection/ButtonsRow
@onready var start_btn: Button          = $Content/LeftPanel/Margin/LeftSection/ButtonsRow/StartButton
@onready var leave_btn: Button          = $Content/LeftPanel/Margin/LeftSection/ButtonsRow/LeaveButton


func _ready() -> void:
	_style_panel()
	_style_buttons()
	GameNetwork.player_list_changed.connect(_on_player_list_changed)
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
	$Content/LeftPanel.add_theme_stylebox_override("panel", style)


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
	for btn in [create_btn, back_btn, start_btn, leave_btn] as Array[Button]:
		_apply_button_style(btn)


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
	for addr in IP.get_local_addresses():
		if "." in addr and not addr.begins_with("127.") and not addr.begins_with("169.254."):
			ip_display.text = addr
			return
	ip_display.text = "127.0.0.1"


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

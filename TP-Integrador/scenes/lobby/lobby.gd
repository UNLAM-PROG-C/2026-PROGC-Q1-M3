extends Control

@onready var ip_input = $VBoxContainer/IPInput
@onready var status_label = $VBoxContainer/StatusLabel

func _ready():
	if "--debug_solo" in OS.get_cmdline_args():
		get_tree().change_scene_to_file("res://scenes/game/game.tscn")
		return
	GameNetwork.player_connected.connect(_on_player_connected)
	GameNetwork.connection_failed.connect(_on_connection_failed)

func _on_host_pressed():
	GameNetwork.host_game()
	status_label.text = "Esperando jugador..."

func _on_join_pressed():
	var address = ip_input.text
	if address.is_empty():
		address = "127.0.0.1"
	GameNetwork.join_game(address)
	status_label.text = "Conectando..."

func _on_player_connected(id: int):
	status_label.text = "Jugador conectado! ID: " + str(id)
	if multiplayer.is_server():
		load_game.rpc()

@rpc("authority", "call_local", "reliable")
func load_game():
	get_tree().change_scene_to_file("res://scenes/game/game.tscn")

func _on_connection_failed():
	status_label.text = "Error al conectar"

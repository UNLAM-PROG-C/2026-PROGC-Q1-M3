extends Node3D

@onready var npc_thread_pool = $NPCThreadPool
@onready var pause_menu = $PauseMenu


func _ready():
	process_mode = Node.PROCESS_MODE_ALWAYS
	pause_menu.resume_requested.connect(_resume_game)
	pause_menu.quit_requested.connect(_quit_to_desktop)

	# Modo debug: corre en singleplayer
	if "--debug_solo" in OS.get_cmdline_args():
		spawn_player(1)
		npc_thread_pool.set_player_count(1)
		return
	
	if multiplayer.is_server():
		spawn_player.rpc(1)
		for id in multiplayer.get_peers():
			spawn_player.rpc(id)
		npc_thread_pool.set_player_count(_get_player_count())

@rpc("authority", "call_local", "reliable")
func spawn_player(peer_id: int):
	var player = preload("res://scenes/player/player.tscn").instantiate()
	player.name = str(peer_id)
	player.position = Vector3(0, 1, 0)
	add_child(player)
	player.set_multiplayer_authority(peer_id)
	npc_thread_pool.set_player_count(_get_player_count())


func _get_player_count() -> int:
	if "--debug_solo" in OS.get_cmdline_args():
		return 1

	if multiplayer.has_multiplayer_peer():
		return multiplayer.get_peers().size() + 1

	return 1

func _input(event):
	if event.is_action_pressed("ui_cancel"):
		_toggle_pause_menu()
		get_viewport().set_input_as_handled()

func _toggle_pause_menu():
	if get_tree().paused:
		_resume_game()
	else:
		_pause_game()

func _pause_game():
	get_tree().paused = true
	pause_menu.show_menu()

func _resume_game():
	get_tree().paused = false
	pause_menu.hide_menu()

func _quit_to_desktop():
	multiplayer.multiplayer_peer = null
	get_tree().quit()

extends Node3D

@onready var npc_thread_pool = $NPCThreadPool
@onready var pause_menu = $PauseMenu

const CAPTURE_MAX_DISTANCE := 5.0   ## 3m de alcance del cliente + 2m tolerancia latencia

# Combate / fin de ronda (last-man-standing).
var end_screen                  
var _alive: Array[int] = []     
var _game_over := false         
var _local_done := false        


# Conteo de vivos para el HUD (mirror local en TODOS los peers; el array _alive del
# servidor sigue siendo la autoridad del juego).
signal players_alive_changed(alive: int, total: int)
var _alive_count := 0
var _total_count := 0

func get_alive_count() -> int:
	return _alive_count

func get_total_count() -> int:
	return _total_count


func _ready():
	process_mode = Node.PROCESS_MODE_ALWAYS
	# Para todos los peers (incluido debug_solo): _get_player_count() devuelve el total correcto.
	_total_count = _get_player_count()
	_alive_count = _total_count
	pause_menu.resume_requested.connect(_resume_game)
	pause_menu.quit_requested.connect(_quit_to_desktop)
	end_screen = preload("res://scenes/ui/end_screen.gd").new()
	add_child(end_screen)

	if "--debug_solo" in OS.get_cmdline_args():
		spawn_player(1)
		npc_thread_pool.set_player_count(1)
		return

	if multiplayer.is_server():
		spawn_player.rpc(1)
		for id in multiplayer.get_peers():
			spawn_player.rpc(id)
		npc_thread_pool.set_player_count(_get_player_count())
		_alive.append(1)
		for id in multiplayer.get_peers():
			_alive.append(id)

@rpc("authority", "call_local", "reliable")
func spawn_player(peer_id: int):
	var player = preload("res://scenes/player/player.tscn").instantiate()
	player.name = str(peer_id)
	player.position = Vector3(0, 1, 0)
	add_child(player)
	player.set_multiplayer_authority(peer_id)
	npc_thread_pool.set_player_count(_get_player_count())


@rpc("any_peer", "reliable")
func report_capture(victim_id: int) -> void:
	if not multiplayer.is_server() or _game_over:
		return

	var attacker_id := multiplayer.get_remote_sender_id()
	if attacker_id == 0:
		attacker_id = 1
	if attacker_id == victim_id:
		return
	if not _alive.has(attacker_id) or not _alive.has(victim_id):
		return

	# validacion de proximidad real por server → anticheat
	var attacker = get_node_or_null(str(attacker_id))
	var victim = get_node_or_null(str(victim_id))
	if attacker == null or victim == null:
		return
	if attacker.global_position.distance_to(victim.global_position) > CAPTURE_MAX_DISTANCE:
		return

	_alive.erase(victim_id)
	var winner_id := -1
	if _alive.size() == 1:
		winner_id = _alive[0]
		_game_over = true
	apply_elimination.rpc(victim_id, winner_id)


@rpc("authority", "call_local", "reliable")
func apply_elimination(victim_id: int, winner_id: int) -> void:
	var me := multiplayer.get_unique_id()

	var victim = get_node_or_null(str(victim_id))
	if victim:
		victim.set_eliminated()

	_alive_count = maxi(0, _alive_count - 1)
	players_alive_changed.emit(_alive_count, _total_count)

	if me == victim_id:
		end_screen.show_wasted()
		_local_done = true

	if winner_id != -1:
		_game_over = true
		if me == winner_id:
			end_screen.show_win()
			_local_done = true
		get_tree().paused = true  # ronda terminada: congela todo


func _get_player_count() -> int:
	if "--debug_solo" in OS.get_cmdline_args():
		return 1

	if multiplayer.has_multiplayer_peer():
		return multiplayer.get_peers().size() + 1

	return 1

func _input(event):
	if _local_done:
		return  # ronda terminada para mí: no abrir la pausa sobre la pantalla de fin
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

extends Node3D

@onready var npc_thread_pool = $NPCThreadPool
@onready var pause_menu = $PauseMenu
@onready var ambient_people: AudioStreamPlayer = $AmbientPeople

const CAPTURE_MAX_DISTANCE := 5.0   ## 3m de alcance del cliente + 2m tolerancia latencia
## Segundos antes de regresar al lobby cuando termina la ronda.
## Modifica este valor para cambiar el tiempo de espera post-victoria.
const LOBBY_RETURN_DELAY := 10

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

# Modo espectador: activo en el peer local del jugador eliminado.
var _in_spectator_mode := false
var _spectator_index := 0
var _active_spectator_cam: Camera3D = null
## true mientras el espectador ve la animación de muerte del jugador observado.
var _watching_spectated_die := false


func get_alive_count() -> int:
	return _alive_count

func get_total_count() -> int:
	return _total_count


func _ready():
	process_mode = Node.PROCESS_MODE_ALWAYS
	LobbyMusic.stop()
	_setup_ambient_people()
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


func _setup_ambient_people() -> void:
	if ambient_people.stream is AudioStreamMP3:
		ambient_people.stream.loop = true
	if ambient_people.stream and not ambient_people.playing:
		ambient_people.play()

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
	if winner_id != -1:
		start_return_countdown.rpc()


## Valida y aplica la muerte de un NPC disparado por un jugador.
## El servidor verifica que el atacante esté vivo. No valida distancia porque las
## simulaciones de NPC no están sincronizadas entre peers (cada uno tiene posiciones propias).
@rpc("any_peer", "reliable")
func report_npc_kill(npc_index: int) -> void:
	if _game_over or not multiplayer.is_server():
		return
	var attacker_id := multiplayer.get_remote_sender_id()
	if attacker_id == 0:
		attacker_id = 1
	var is_solo := "--debug_solo" in OS.get_cmdline_args()
	if not is_solo and not _alive.has(attacker_id):
		return
	var attacker = get_node_or_null(str(attacker_id))
	var alarm_pos : Vector3 = attacker.global_position if attacker else Vector3.ZERO
	apply_npc_kill.rpc(npc_index, alarm_pos)


## Aplica la muerte del NPC en todos los peers y genera la alarma posicional.
@rpc("authority", "call_local", "reliable")
func apply_npc_kill(npc_index: int, kill_pos: Vector3) -> void:
	npc_thread_pool.kill_npc(npc_index)
	_spawn_alarm_at(kill_pos)


## Crea un AudioStreamPlayer3D posicional en kill_pos con atenuación logarítmica.
## Coloca tu archivo de alarma en res://audio/sfx/alarm.ogg para que se escuche.
func _spawn_alarm_at(pos: Vector3) -> void:
	var player3d := AudioStreamPlayer3D.new()
	player3d.position = pos
	player3d.attenuation_model = AudioStreamPlayer3D.ATTENUATION_LOGARITHMIC
	player3d.unit_size = 4.0
	player3d.max_distance = 80.0
	if ResourceLoader.exists("res://audio/sfx/alarm.ogg"):
		player3d.stream = load("res://audio/sfx/alarm.ogg")
	add_child(player3d)
	if player3d.stream:
		player3d.play()
	get_tree().create_timer(8.0).timeout.connect(player3d.queue_free)


@rpc("authority", "call_local", "reliable")
func apply_elimination(victim_id: int, winner_id: int) -> void:
	var me := multiplayer.get_unique_id()
	var victim = get_node_or_null(str(victim_id))
	if victim:
		victim.set_eliminated()
	_alive_count = maxi(0, _alive_count - 1)
	players_alive_changed.emit(_alive_count, _total_count)
	_handle_local_elimination(me, victim_id, winner_id)
	if winner_id != -1:
		_game_over = true
		end_screen.show_winner_name(_resolve_player_name(winner_id))


## Maneja el estado visual y de input del peer local según si murió, ganó o está especteando.
func _handle_local_elimination(me: int, victim_id: int, winner_id: int) -> void:
	if me == victim_id:
		# Muerte propia: la death cam ya se activó en set_eliminated().
		end_screen.show_wasted()
		_local_done = true
		end_screen.spectate_requested.connect(_enter_spectator_mode, CONNECT_ONE_SHOT)
		return
	if _is_spectating_player(victim_id):
		_spectated_player_died(victim_id)
		return
	if winner_id != -1 and me == winner_id:
		end_screen.show_win()
		_local_done = true


## Resuelve el nombre de un jugador por su peer_id.
func _resolve_player_name(peer_id: int) -> String:
	var node = get_node_or_null(str(peer_id))
	if node and node.has_method("get_display_name"):
		return node.get_display_name()
	var players_dict: Dictionary = GameNetwork.get_players()
	if players_dict.has(peer_id) and players_dict[peer_id].has("name"):
		return players_dict[peer_id]["name"]
	return "Player"


## Activa el modo espectador: des-pausa, cambia a la cámara del primer jugador vivo.
func _enter_spectator_mode() -> void:
	_in_spectator_mode = true
	_spectator_index = 0
	get_tree().paused = false
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_switch_spectator_cam(0)


## Cambia la cámara activa al jugador vivo en la posición (index mod size) del array.
func _switch_spectator_cam(index: int) -> void:
	var alive_players := get_tree().get_nodes_in_group("players")
	if alive_players.is_empty():
		return
	if _active_spectator_cam:
		_active_spectator_cam.current = false
	_spectator_index = posmod(index, alive_players.size())
	var target := alive_players[_spectator_index]
	_active_spectator_cam = target.get_camera()
	if _active_spectator_cam:
		_active_spectator_cam.current = true
	end_screen.show_spectator_label(target.get_display_name())


## Retorna true si el espectador local está observando al jugador con victim_id.
func _is_spectating_player(victim_id: int) -> bool:
	if not _in_spectator_mode or _active_spectator_cam == null:
		return false
	# La cámara vive en Head/Camera3D → Head → Player (hijo directo de game).
	var node := _active_spectator_cam as Node
	while node and node != self:
		if node.get_parent() == self:
			return node.name == str(victim_id)
		node = node.get_parent()
	return false


## El jugador que estamos especteando murió: cambiar a su death cam y mostrar WASTED.
func _spectated_player_died(victim_id: int) -> void:
	_watching_spectated_die = true
	var victim = get_node_or_null(str(victim_id))
	if victim:
		var dcam: Camera3D = victim.get_death_cam()
		if dcam:
			if _active_spectator_cam:
				_active_spectator_cam.current = false
			_active_spectator_cam = dcam
			dcam.current = true
	end_screen.show_wasted_spectator(_auto_switch_next)


## Callback tras el fade del WASTED del espectado: volver al siguiente jugador vivo.
func _auto_switch_next() -> void:
	_watching_spectated_die = false
	var alive_players := get_tree().get_nodes_in_group("players")
	if alive_players.is_empty():
		return
	_switch_spectator_cam(_spectator_index)


## LMB avanza al siguiente jugador, RMB retrocede. Bloqueado mientras ve morir al observado.
func _handle_spectator_input(event: InputEvent) -> void:
	if _watching_spectated_die:
		return
	if not (event is InputEventMouseButton) or not event.pressed:
		return
	if event.button_index == MOUSE_BUTTON_LEFT:
		_switch_spectator_cam(_spectator_index + 1)
	elif event.button_index == MOUSE_BUTTON_RIGHT:
		_switch_spectator_cam(_spectator_index - 1)


## Inicia el countdown visible para todos y des-pausa el árbol para que el timer corra.
@rpc("authority", "call_local", "reliable")
func start_return_countdown() -> void:
	get_tree().paused = false
	end_screen.show_return_timer(LOBBY_RETURN_DELAY)
	if multiplayer.is_server():
		_schedule_lobby_return()


## Solo el servidor programa el regreso real; los demás reciben return_to_lobby vía RPC.
func _schedule_lobby_return() -> void:
	var t := get_tree().create_timer(float(LOBBY_RETURN_DELAY), true, false, true)
	t.timeout.connect(_do_return_to_lobby)


func _do_return_to_lobby() -> void:
	return_to_lobby.rpc()


@rpc("authority", "call_local", "reliable")
func return_to_lobby() -> void:
	if multiplayer.is_server():
		get_tree().change_scene_to_file("res://scenes/lobby/host_lobby.tscn")
	else:
		get_tree().change_scene_to_file("res://scenes/lobby/join_lobby.tscn")


func _get_player_count() -> int:
	if "--debug_solo" in OS.get_cmdline_args():
		return 1
	if multiplayer.has_multiplayer_peer():
		return multiplayer.get_peers().size() + 1
	return 1

func _input(event: InputEvent) -> void:
	if _in_spectator_mode:
		_handle_spectator_input(event)
	if event.is_action_pressed("ui_cancel"):
		# Bloquear pausa solo durante la transición WASTED (antes de entrar a espectador).
		if _local_done and not _in_spectator_mode:
			return
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

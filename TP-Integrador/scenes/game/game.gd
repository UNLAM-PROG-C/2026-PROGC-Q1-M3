extends Node3D

@onready var npc_thread_pool = $NPCThreadPool
@onready var pause_menu = $PauseMenu
@onready var ambient_people: AudioStreamPlayer = $AmbientPeople

const CAPTURE_MAX_DISTANCE := 5.0   ## 3m de alcance del cliente + 2m tolerancia latencia
## Segundos antes de regresar al lobby cuando termina la ronda.
## Modifica este valor para cambiar el tiempo de espera post-victoria.
const LOBBY_RETURN_DELAY := 10

const SPECTATOR_CAM_DISTANCE := 4.0 
const SPECTATOR_CAM_HEIGHT := 2.0 
const SPECTATOR_CAM_LOOK_HEIGHT := 1.2 
const SPECTATOR_CAM_COLLISION_MASK := 1
const SPECTATOR_CAM_MARGIN := 0.3

# Handshake de spawn: el server espera a que todos confirmen escena lista.
var _ready_peers := {}          # peer_id -> true (quiénes confirmaron game.tscn cargada)
var _players_spawned := false   

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
var _spectator_cam: Camera3D = null 
var _spectated_node: Node3D = null
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
	pause_menu.main_menu_requested.connect(_return_to_main_menu)
	pause_menu.quit_requested.connect(_quit_to_desktop)
	GameNetwork.server_disconnected.connect(_on_server_disconnected)
	end_screen = preload("res://scenes/ui/end_screen.gd").new()
	add_child(end_screen)

	if "--debug_solo" in OS.get_cmdline_args():
		spawn_player(1, _pick_spawn_pos([]))
		npc_thread_pool.set_player_count(1)
		return

	if multiplayer.is_server():
		multiplayer.peer_disconnected.connect(_on_peer_left_during_start)
		_ready_peers[1] = true       # el host ya tiene su escena cargada
		_try_spawn_all()             # spawnea cuando estén todos (o si no hay peers)
	elif multiplayer.has_multiplayer_peer():
		notify_ready.rpc_id(1)       # avisar al server: mi escena está lista


# El server no spawnea hasta que host + todos los peers confirmen tener game.tscn cargada.
@rpc("any_peer", "reliable")
func notify_ready() -> void:
	if not multiplayer.is_server():
		return
	_ready_peers[multiplayer.get_remote_sender_id()] = true
	_try_spawn_all()


func _try_spawn_all() -> void:
	if _players_spawned:
		return
	if not _ready_peers.has(1):
		return
	for id in multiplayer.get_peers():
		if not _ready_peers.has(id):
			return               # falta alguien: esperar
	_players_spawned = true
	_spawn_all_players()


func _spawn_all_players() -> void:
	var used: Array[Vector3] = []
	var pos_server := _pick_spawn_pos(used)
	used.append(pos_server)
	spawn_player.rpc(1, pos_server)
	_alive.append(1)
	for id in multiplayer.get_peers():
		var pos := _pick_spawn_pos(used)
		used.append(pos)
		spawn_player.rpc(id, pos)
		_alive.append(id)
	npc_thread_pool.set_player_count(_get_player_count())


# Si un peer se cae mientras cargaba, sacarlo de la espera para no colgar el spawn.
func _on_peer_left_during_start(id: int) -> void:
	_ready_peers.erase(id)
	_try_spawn_all()


func _setup_ambient_people() -> void:
	if ambient_people.stream is AudioStreamMP3:
		ambient_people.stream.loop = true
	if ambient_people.stream and not ambient_people.playing:
		ambient_people.play()

func _pick_spawn_pos(used: Array[Vector3]) -> Vector3:
	var points := get_tree().get_nodes_in_group("SpawnPoints")
	if points.is_empty():
		return Vector3(0, 1, 0)
	points.shuffle()
	for p in points:
		var pos: Vector3 = p.global_position
		if not used.has(pos):
			return pos
	# Todos usados (más jugadores que spawn points): reutilizar al azar.
	return points[randi() % points.size()].global_position


@rpc("authority", "call_local", "reliable")
func spawn_player(peer_id: int, spawn_pos: Vector3):
	var player = preload("res://scenes/player/player.tscn").instantiate()
	player.name = str(peer_id)
	player.position = spawn_pos
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


@rpc("any_peer", "reliable")
func report_npc_kill(npc_index: int) -> void:
	if _game_over:
		return
	# Aceptar offline (sin peer); si hay red, solo el server resuelve.
	if multiplayer.has_multiplayer_peer() and not multiplayer.is_server():
		return
	var attacker_id := multiplayer.get_remote_sender_id()
	if attacker_id == 0:
		attacker_id = 1
	var is_solo := "--debug_solo" in OS.get_cmdline_args()
	if multiplayer.has_multiplayer_peer() and not is_solo and not _alive.has(attacker_id):
		return
	var attacker = get_node_or_null(str(attacker_id))
	var alarm_pos : Vector3 = attacker.global_position if attacker else Vector3.ZERO
	if multiplayer.has_multiplayer_peer():
		apply_npc_kill.rpc(npc_index, alarm_pos)
	else:
		apply_npc_kill(npc_index, alarm_pos)  # offline: aplicar local


@rpc("authority", "call_local", "reliable")
func apply_npc_kill(npc_index: int, kill_pos: Vector3) -> void:
	npc_thread_pool.kill_npc(npc_index)
	_spawn_alarm_at(kill_pos)


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


func _resolve_player_name(peer_id: int) -> String:
	var node = get_node_or_null(str(peer_id))
	if node and node.has_method("get_display_name"):
		return node.get_display_name()
	var players_dict: Dictionary = GameNetwork.get_players()
	if players_dict.has(peer_id) and players_dict[peer_id].has("name"):
		return players_dict[peer_id]["name"]
	return "Player"


func _enter_spectator_mode() -> void:
	_in_spectator_mode = true
	_spectator_index = 0
	get_tree().paused = false
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_switch_spectator_cam(0)


func _switch_spectator_cam(index: int) -> void:
	var alive_players := get_tree().get_nodes_in_group("players")
	if alive_players.is_empty():
		return
	_ensure_spectator_cam()
	if _active_spectator_cam and _active_spectator_cam != _spectator_cam:
		_active_spectator_cam.current = false
	_spectator_index = posmod(index, alive_players.size())
	var target: Node3D = alive_players[_spectator_index]
	_spectated_node = target
	_active_spectator_cam = _spectator_cam
	_update_spectator_follow(false)
	_spectator_cam.current = true
	end_screen.show_spectator_label(target.get_display_name())


func _ensure_spectator_cam() -> void:
	if _spectator_cam != null:
		return
	_spectator_cam = Camera3D.new()
	_spectator_cam.name = "SpectatorCam"
	add_child(_spectator_cam)


func _physics_process(_delta: float) -> void:
	if _spectator_cam and _spectator_cam.current:
		_update_spectator_follow()


func _update_spectator_follow(avoid_walls: bool = true) -> void:
	if _spectator_cam == null or _spectated_node == null or not is_instance_valid(_spectated_node):
		return
	var pivot := _spectated_node.global_position + Vector3.UP * SPECTATOR_CAM_LOOK_HEIGHT
	var back := _spectated_node.global_transform.basis.z  # el jugador mira hacia -z
	var desired := _spectated_node.global_position + Vector3.UP * SPECTATOR_CAM_HEIGHT + back * SPECTATOR_CAM_DISTANCE
	var cam_pos := desired
	if avoid_walls:
		var space := get_world_3d().direct_space_state
		var query := PhysicsRayQueryParameters3D.create(
			pivot, desired, SPECTATOR_CAM_COLLISION_MASK, [_spectated_node.get_rid()])
		var hit := space.intersect_ray(query)
		if hit:
			cam_pos = hit.position + (pivot - desired).normalized() * SPECTATOR_CAM_MARGIN
	_spectator_cam.global_position = cam_pos
	_spectator_cam.look_at(pivot, Vector3.UP)


func _is_spectating_player(victim_id: int) -> bool:
	if not _in_spectator_mode or _spectated_node == null or not is_instance_valid(_spectated_node):
		return false
	return _spectated_node.name == str(victim_id)


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


func _auto_switch_next() -> void:
	_watching_spectated_die = false
	var alive_players := get_tree().get_nodes_in_group("players")
	if alive_players.is_empty():
		return
	_switch_spectator_cam(_spectator_index)


func _handle_spectator_input(event: InputEvent) -> void:
	if _watching_spectated_die:
		return
	if not (event is InputEventMouseButton) or not event.pressed:
		return
	if event.button_index == MOUSE_BUTTON_LEFT:
		_switch_spectator_cam(_spectator_index + 1)
	elif event.button_index == MOUSE_BUTTON_RIGHT:
		_switch_spectator_cam(_spectator_index - 1)


@rpc("authority", "call_local", "reliable")
func start_return_countdown() -> void:
	get_tree().paused = false
	end_screen.show_return_timer(LOBBY_RETURN_DELAY)
	if multiplayer.is_server():
		_schedule_lobby_return()


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

func _return_to_main_menu():
	get_tree().paused = false
	GameNetwork.disconnect_from_game()
	get_tree().change_scene_to_file("res://scenes/ui/main_menu.tscn")

func _on_server_disconnected():
	# El host cerró la partida: el autoload ya limpió la conexión, solo volvemos al menú.
	get_tree().paused = false
	get_tree().change_scene_to_file("res://scenes/ui/main_menu.tscn")

func _quit_to_desktop():
	multiplayer.multiplayer_peer = null
	get_tree().quit()

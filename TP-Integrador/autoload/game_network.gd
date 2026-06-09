extends Node

const DEFAULT_PORT := 7777
const MAX_PLAYERS := 4

# --- Signals  ---
signal player_list_changed
signal connection_succeeded
signal connection_failed
signal server_disconnected
signal player_joined(peer_id)
signal player_left(peer_id)

# --- Players Info ---
# peer_id -> { "id": int, "name": String, "model": int, "part_colors": Dictionary }
# model: indice de modelo en CharacterAppearance.MODEL_PATHS
var players: Dictionary = {}

var _pending_name: String = ""

var _awaiting_confirmation: bool = false


func _ready() -> void:
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.connected_to_server.connect(_on_connected_to_server)
	multiplayer.connection_failed.connect(_on_connection_failed)
	multiplayer.server_disconnected.connect(_on_server_disconnected)


# ---------------------------------------------------------------------------
# API
# ---------------------------------------------------------------------------

func create_server(player_name: String) -> Error:
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_server(DEFAULT_PORT, MAX_PLAYERS)
	if err != OK:
		push_error("No se pudo crear el servidor en el puerto %d (error %d)" % [DEFAULT_PORT, err])
		return err
	multiplayer.multiplayer_peer = peer
	players = { 1: _make_player_record(1, player_name) }
	player_list_changed.emit()
	return OK


func join_server(ip: String, player_name: String) -> Error:
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_client(ip, DEFAULT_PORT)
	if err != OK:
		push_error("No se pudo crear el cliente hacia %s (error %d)" % [ip, err])
		return err
	_pending_name = player_name
	_awaiting_confirmation = true
	multiplayer.multiplayer_peer = peer
	return OK


func disconnect_from_game() -> void:
	multiplayer.multiplayer_peer = null
	_awaiting_confirmation = false
	players.clear()
	player_list_changed.emit()


func is_host() -> bool:
	return multiplayer.has_multiplayer_peer() and multiplayer.is_server()


func get_my_id() -> int:
	if multiplayer.has_multiplayer_peer():
		return multiplayer.get_unique_id()
	return 0


func get_players() -> Dictionary:
	return players.duplicate(true)


# Crea el registro de un jugador. TODOS los jugadores comparten la misma apariencia.
func _make_player_record(id: int, player_name: String) -> Dictionary:
	return {
		"id": id,
		"name": player_name,
		"model": CharacterAppearance.PLAYER_MODEL_INDEX,
		"part_colors": CharacterAppearance.player_part_colors(),
	}

@rpc("any_peer", "reliable")
func _register_player(player_name: String) -> void:
	if not multiplayer.is_server():
		return
	var sender := multiplayer.get_remote_sender_id()
	players[sender] = _make_player_record(sender, player_name)
	_sync_player_list.rpc(players)
	player_joined.emit(sender)

@rpc("authority", "call_local", "reliable")
func _sync_player_list(list: Dictionary) -> void:
	players = list.duplicate(true)
	player_list_changed.emit()

	if _awaiting_confirmation and players.has(get_my_id()):
		_awaiting_confirmation = false
		connection_succeeded.emit()


# ---------------------------------------------------------------------------
# Callbacks MultiplayerAPI
# ---------------------------------------------------------------------------

func _on_peer_connected(_id: int) -> void:
	pass


func _on_peer_disconnected(id: int) -> void:
	if not multiplayer.is_server():
		return
	if players.has(id):
		players.erase(id)
		_sync_player_list.rpc(players)
		player_left.emit(id)


func _on_connected_to_server() -> void:
	_register_player.rpc_id(1, _pending_name)


func _on_connection_failed() -> void:
	multiplayer.multiplayer_peer = null
	_awaiting_confirmation = false
	players.clear()
	connection_failed.emit()


func _on_server_disconnected() -> void:
	multiplayer.multiplayer_peer = null
	_awaiting_confirmation = false
	players.clear()
	server_disconnected.emit()

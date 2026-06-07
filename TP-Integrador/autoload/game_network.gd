extends Node

const PORT = 7777
const MAX_PEERS = 2

signal player_connected(id)
signal player_disconnected(id)
signal connection_failed()
signal server_disconnected()

func host_game():
	var peer = ENetMultiplayerPeer.new()
	var error = peer.create_server(PORT, MAX_PEERS)
	if error != OK:
		print("Error creando servidor: ", error)
		return
	multiplayer.multiplayer_peer = peer
	print("Servidor iniciado en puerto ", PORT)

func join_game(address: String):
	var peer = ENetMultiplayerPeer.new()
	var error = peer.create_client(address, PORT)
	if error != OK:
		print("Error conectando: ", error)
		return
	multiplayer.multiplayer_peer = peer
	print("Conectando a ", address)

func _ready():
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.connected_to_server.connect(_on_connected_to_server)
	multiplayer.connection_failed.connect(_on_connection_failed)
	multiplayer.server_disconnected.connect(_on_server_disconnected)

func _on_peer_connected(id: int):
	print("Peer conectado: ", id)
	player_connected.emit(id)

func _on_peer_disconnected(id: int):
	player_disconnected.emit(id)

func _on_connected_to_server():
	print("Conectado al servidor. Mi ID: ", multiplayer.get_unique_id())

func _on_connection_failed():
	multiplayer.multiplayer_peer = null
	connection_failed.emit()

func _on_server_disconnected():
	multiplayer.multiplayer_peer = null
	server_disconnected.emit()

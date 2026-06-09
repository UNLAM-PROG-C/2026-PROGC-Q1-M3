extends CharacterBody3D

const SPEED = 7.0
const GRAVITY = -9.8
const MOUSE_SENSITIVITY = 0.005

## Ajuste fino de orientacion del modelo respecto al frente del jugador.
const MODEL_YAW_OFFSET := PI
## Umbral de velocidad (u/s) para considerar que el jugador se esta moviendo.
const WALK_SPEED_THRESHOLD := 0.3

## Los modelos de Mixamo vienen a ~56u de alto; 0.03 los deja en ~1.7u.
@export var model_scale := 0.03
## Desplazamiento vertical del modelo para apoyar los pies en la base de la capsula.
@export var model_y_offset := -1.0

@onready var head = $Head
@onready var camera = $Head/Camera3D

var _model: Node3D
var _anim_player: AnimationPlayer
var _walk_model_index := 0
var _last_anim_position := Vector3.ZERO

func is_local_player() -> bool:
	return "--debug_solo" in OS.get_cmdline_args() or is_multiplayer_authority()

func _ready():
	_setup_synchronizer()
	# La autoridad de este nodo se asigna JUSTO DESPUÉS de add_child()
	# Por eso diferimos la configuración local hasta que la autoridad ya sea la correcta.
	call_deferred("_setup_local")
	call_deferred("_setup_appearance")

func _setup_local():
	# Solo el jugador dueño de este nodo captura el mouse y usa su cámara.
	if is_local_player():
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		camera.current = true

## Construye el modelo 3D del jugador (corre en TODOS los peers: cada uno renderiza
## a todos los jugadores). El jugador local oculta su propio modelo (primera persona).
func _setup_appearance():
	var appearance := _resolve_appearance()
	var model_index := int(appearance["model"])
	_model = CharacterAppearance.build_model(model_index)
	if _model == null:
		return

	add_child(_model)
	_model.scale = Vector3.ONE * model_scale
	_model.position.y = model_y_offset
	_model.rotation.y = MODEL_YAW_OFFSET

	CharacterAppearance.apply_part_colors(_model, appearance["part_colors"])

	_anim_player = CharacterAppearance.find_animation_player(_model)
	_walk_model_index = model_index
	_last_anim_position = global_position

	# Primera persona: el jugador local no ve su propio cuerpo (salvo espejo, futuro).
	if is_local_player():
		_model.visible = false

func _resolve_appearance() -> Dictionary:
	var peer_id := name.to_int()
	var players: Dictionary = GameNetwork.get_players()
	if players.has(peer_id) and players[peer_id].has("model"):
		return {
			"model": int(players[peer_id]["model"]),
			"part_colors": players[peer_id].get("part_colors", {}),
		}
	# Fallback (ej. --debug_solo, sin lista de red): mismo look canónico de jugador.
	return {
		"model": CharacterAppearance.PLAYER_MODEL_INDEX,
		"part_colors": CharacterAppearance.player_part_colors(),
	}

## La animacion de caminata se decide por el desplazamiento real, de modo que
## funciona igual en el dueño y en los peers remotos (que reciben la posicion replicada).
func _process(delta: float):
	if _anim_player == null or delta <= 0.0:
		return

	var speed := (global_position - _last_anim_position).length() / delta
	_last_anim_position = global_position

	if speed > WALK_SPEED_THRESHOLD:
		if not _anim_player.is_playing():
			CharacterAppearance.play_walk(_anim_player, _walk_model_index)
	elif _anim_player.is_playing():
		_anim_player.pause()

func _setup_synchronizer():
	if "--debug_solo" in OS.get_cmdline_args():
		return  # sin red en modo solo
	var config := SceneReplicationConfig.new()
	config.add_property(NodePath(".:position"))
	config.property_set_replication_mode(NodePath(".:position"), SceneReplicationConfig.REPLICATION_MODE_ALWAYS)
	config.add_property(NodePath(".:rotation"))
	config.property_set_replication_mode(NodePath(".:rotation"), SceneReplicationConfig.REPLICATION_MODE_ALWAYS)
	var sync := MultiplayerSynchronizer.new()
	sync.name = "PlayerSync"
	sync.replication_config = config
	# root_path por defecto es ".." → este nodo Player. add_child lo deja con la
	# autoridad correcta cuando game.gd llama set_multiplayer_authority(recursive).
	add_child(sync)

func _unhandled_input(event):
	if not is_local_player():
		return
	# Rotación de cámara con el mouse
	if event is InputEventMouseMotion:
		rotate_y(-event.relative.x * MOUSE_SENSITIVITY)
		head.rotate_x(-event.relative.y * MOUSE_SENSITIVITY)
		# Limitar la mirada arriba/abajo a 90 grados
		head.rotation.x = clamp(head.rotation.x, -PI/2, PI/2)

func _physics_process(delta):
	# Solo el dueño procesa input y mueve el cuerpo; en los demás peers la posición
	# la escribe el MultiplayerSynchronizer.
	if not is_local_player():
		return

	# Gravedad
	if not is_on_floor():
		velocity.y += GRAVITY * delta

	# Movimiento con WASD
	var input = Vector3.ZERO
	input.x = Input.get_axis("move_left", "move_right")
	input.z = Input.get_axis("move_forward", "move_back")

	# Mover en la dirección que mira el jugador
	var direction = (transform.basis * input).normalized()
	velocity.x = direction.x * SPEED
	velocity.z = direction.z * SPEED

	move_and_slide()

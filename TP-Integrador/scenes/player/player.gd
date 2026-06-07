extends CharacterBody3D

const SPEED = 7.0
const GRAVITY = -9.8
const MOUSE_SENSITIVITY = 0.005

@onready var head = $Head
@onready var camera = $Head/Camera3D

func is_local_player() -> bool:
	return "--debug_solo" in OS.get_cmdline_args() or is_multiplayer_authority()

func _ready():
	_setup_synchronizer()
	# La autoridad de este nodo se asigna JUSTO DESPUÉS de add_child()
	# Por eso diferimos la configuración local hasta que la autoridad ya sea la correcta.
	call_deferred("_setup_local")

func _setup_local():
	# Solo el jugador dueño de este nodo captura el mouse y usa su cámara.
	if is_local_player():
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		camera.current = true

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

extends CharacterBody3D

const SPEED = 7.0
const GRAVITY = -9.8
const MOUSE_SENSITIVITY = 0.005

@onready var head = $Head
@onready var camera = $Head/Camera3D

func is_local_player() -> bool:
	return "--debug_solo" in OS.get_cmdline_args() or is_multiplayer_authority()

func _ready():
	# Solo el jugador dueño de este nodo captura el mouse y procesa input
	if is_local_player():
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		camera.current = true

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
	
	# Sincronizar posición y rotación al otro jugador
	sync_state.rpc(position, rotation)

@rpc("any_peer", "unreliable_ordered")
func sync_state(pos: Vector3, rot: Vector3):
	if not is_local_player():
		position = pos
		rotation = rot

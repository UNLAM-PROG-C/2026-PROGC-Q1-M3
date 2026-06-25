extends CharacterBody3D

const SPEED = 7.0
const GRAVITY = -9.8
const MOUSE_SENSITIVITY = 0.005
const FIRST_PERSON_MODEL_LAYER := 1 << 2
const SPRINT_SPEED_MULTIPLIER := 2.0
const MAX_SPRINT_DURATION := 2.0
const SPRINT_COOLDOWN_DURATION := 5.0
const SPRINT_REGEN_RATE := 0.7   ## stamina-seg recuperados por segundo al no correr (tuneable)

const CAPTURE_RANGE := 3.0   ## Alcance (m). Antes 8.0.
const FIRE_COOLDOWN := 1.0   ## segs de cooldown

const EXPLOSION_COLOR := Color(1.0, 0.55, 0.1) ## particulas naranjas
const FALL_ANGLE := PI / 2 ## cae al piso

## Ajuste fino de orientacion del modelo respecto al frente del jugador.
const MODEL_YAW_OFFSET := PI
## Umbral de velocidad (u/s) para considerar que el jugador se esta moviendo.
const WALK_SPEED_THRESHOLD := 0.3

## Los modelos de Mixamo vienen a ~56u de alto; 0.03 los deja en ~1.7u.
@export var model_scale := 0.03
## Desplazamiento vertical del modelo para apoyar los pies en la base de la capsula.
@export var model_y_offset := -1.0

@onready var head = $Head
@onready var camera: Camera3D = $Head/Camera3D

var _hud  # HUD de primera persona; solo existe para el jugador local
var _model: Node3D
var _anim_player: AnimationPlayer
var _walk_model_index := 0
var _is_walking := false  # replicado: el dueño lo setea según su velocity; todos animan según esto

# Combate
var _current_target = null            # otro player vivo bajo la mira (objetivo capturable)
var _cooldown_left := 0.0
var _eliminated := false              # capturado: congelado y no apuntable
var _last_anim_position := Vector3.ZERO
var _sprint_time_left := MAX_SPRINT_DURATION
var _sprint_cooldown_left := 0.0

func is_local_player() -> bool:
	return "--debug_solo" in OS.get_cmdline_args() or is_multiplayer_authority()

func _ready():
	add_to_group("players")  # para TODOS: así el raycast de apuntado puede identificarlos
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
		# HUD de primera persona (un CanvasLayer dibuja en toda la pantalla,
		# por eso se instancia solo para el jugador local)
		_hud = preload("res://scenes/ui/hud.tscn").instantiate()
		add_child(_hud)
		camera.cull_mask &= ~FIRST_PERSON_MODEL_LAYER
		# Nombre propio + contador de vivos (valor inicial + updates por señal del game).
		_hud.set_player_name(_resolve_my_name())
		var game = get_parent()
		_hud.set_players_alive(game.get_alive_count(), game.get_total_count())
		game.players_alive_changed.connect(_hud.set_players_alive)

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

	# Primera persona: el jugador local no ve su propio cuerpo (salvo espejo, futuro).
	if is_local_player():
		_set_visual_layer_recursive(_model, FIRST_PERSON_MODEL_LAYER)


func _set_visual_layer_recursive(node: Node, layer: int) -> void:
	if node is VisualInstance3D:
		node.layers = layer

	for child in node.get_children():
		_set_visual_layer_recursive(child, layer)

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

## Nombre del jugador local, leído de la lista de red (fallback para --debug_solo).
func _resolve_my_name() -> String:
	var players: Dictionary = GameNetwork.get_players()
	var my_id := name.to_int()
	if players.has(my_id) and players[my_id].has("name"):
		return players[my_id]["name"]
	return "Player"

## La animacion de caminata se decide por _is_walking (lo setea el dueño según su
## velocity y se replica), de modo que funciona igual en el dueño y en los peers remotos.
func _process(_delta: float):
	if _anim_player == null:
		return

	if _is_walking:
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
	config.add_property(NodePath(".:_is_walking"))
	config.property_set_replication_mode(NodePath(".:_is_walking"), SceneReplicationConfig.REPLICATION_MODE_ON_CHANGE)
	var sync := MultiplayerSynchronizer.new()
	sync.name = "PlayerSync"
	sync.replication_config = config
	# root_path por defecto es ".." → este nodo Player. add_child lo deja con la
	# autoridad correcta cuando game.gd llama set_multiplayer_authority(recursive).
	add_child(sync)

func _unhandled_input(event):
	if not is_local_player() or _eliminated:
		return
	# Rotación de cámara con el mouse
	if event is InputEventMouseMotion:
		rotate_y(-event.relative.x * MOUSE_SENSITIVITY)
		head.rotate_x(-event.relative.y * MOUSE_SENSITIVITY)
		# Limitar la mirada arriba/abajo a 90 grados
		head.rotation.x = clamp(head.rotation.x, -PI/2, PI/2)

	# Disparo: recoil + cooldown siempre; captura si hay objetivo válido.
	if event.is_action_pressed("fire"):
		_try_fire()

func _physics_process(delta):
	# Solo el dueño procesa input y mueve el cuerpo; en los demás peers la posición
	# la escribe el MultiplayerSynchronizer.
	if not is_local_player():
		return

	if _eliminated:
		velocity = Vector3.ZERO
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
	_update_sprint_cooldown(delta)

	var current_speed := SPEED
	var is_sprinting := direction != Vector3.ZERO and Input.is_action_pressed("sprint") and _can_sprint()
	if is_sprinting:
		current_speed *= SPRINT_SPEED_MULTIPLIER
		_sprint_time_left = maxf(0.0, _sprint_time_left - delta)
		if _sprint_time_left <= 0.0:
			_start_sprint_cooldown()   # se agotó del todo → 5s de penalización
	elif _sprint_cooldown_left <= 0.0:
		# No corriendo y sin penalización: la stamina se regenera.
		_sprint_time_left = minf(MAX_SPRINT_DURATION, _sprint_time_left + delta * SPRINT_REGEN_RATE)

	velocity.x = direction.x * current_speed
	velocity.z = direction.z * current_speed

	move_and_slide()

	# Estado de caminar: lo replica el synchronizer → los demás peers animan igual.
	_is_walking = Vector2(velocity.x, velocity.z).length() > WALK_SPEED_THRESHOLD

	# Avisar al HUD la velocidad planar para el bob del arma + estado de stamina
	if _hud:
		_hud.set_moving(Vector2(velocity.x, velocity.z).length())
		var on_cd := _sprint_cooldown_left > 0.0
		var stamina_frac := _sprint_time_left / MAX_SPRINT_DURATION
		if on_cd:
			stamina_frac = 1.0 - (_sprint_cooldown_left / SPRINT_COOLDOWN_DURATION)  # recarga visible
		_hud.set_stamina(stamina_frac, on_cd)

	# Cooldown del arma + apuntado (raycast desde la cámara), tras el movimiento.
	if _cooldown_left > 0.0:
		_cooldown_left -= delta
	_update_target()


func _update_target() -> void:
	var from := camera.global_position
	var to := from - camera.global_transform.basis.z * CAPTURE_RANGE
	var query := PhysicsRayQueryParameters3D.create(from, to)
	query.collision_mask = 1
	query.exclude = [get_rid()]

	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	var new_target = null
	if not hit.is_empty() and hit.collider.is_in_group("players"):
		new_target = hit.collider

	if new_target == _current_target:
		return

	_current_target = new_target
	if _hud:
		_hud.set_target_acquired(_current_target != null)


func _try_fire() -> void:
	if _cooldown_left > 0.0:
		return
	_cooldown_left = FIRE_COOLDOWN
	if _hud:
		_hud.play_fire()  # recoil siempre
	if is_instance_valid(_current_target):
		var victim_id: int = _current_target.name.to_int()
		var game = get_parent()
		if multiplayer.is_server():
			game.report_capture(victim_id)            # ya soy el server: lo resuelvo directo
		else:
			game.report_capture.rpc_id(1, victim_id)  # soy cliente: le aviso al server


func set_eliminated() -> void:
	if _eliminated:
		return
	_eliminated = true
	velocity = Vector3.ZERO
	_is_walking = false
	remove_from_group("players")
	collision_layer = 0
	_current_target = null
	if _hud:
		_hud.set_target_acquired(false)
	_play_capture_fx()


## efecto de captura → explosion
func _play_capture_fx() -> void:
	var burst := CPUParticles3D.new()
	burst.process_mode = Node.PROCESS_MODE_ALWAYS 
	burst.one_shot = true
	burst.explosiveness = 1.0
	burst.amount = 32
	burst.lifetime = 0.7
	burst.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	burst.emission_sphere_radius = 0.4
	burst.direction = Vector3.UP
	burst.spread = 180.0
	burst.initial_velocity_min = 3.0
	burst.initial_velocity_max = 6.0
	burst.gravity = Vector3(0.0, -9.8, 0.0)
	burst.scale_amount_min = 0.6
	burst.scale_amount_max = 1.2

	var pmesh := SphereMesh.new()
	pmesh.radius = 0.05
	pmesh.height = 0.1
	var pmat := StandardMaterial3D.new()
	pmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	pmat.albedo_color = EXPLOSION_COLOR
	pmesh.material = pmat
	burst.mesh = pmesh

	add_child(burst)
	burst.emitting = true
	burst.finished.connect(burst.queue_free)

	if _model:
		var tw := burst.create_tween()
		tw.tween_property(_model, "rotation:x", FALL_ANGLE, 0.4).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)


func _can_sprint() -> bool:
	return _sprint_time_left > 0.0 and _sprint_cooldown_left <= 0.0

func _update_sprint_cooldown(delta: float) -> void:
	if _sprint_cooldown_left <= 0.0:
		return

	_sprint_cooldown_left = maxf(0.0, _sprint_cooldown_left - delta)
	if _sprint_cooldown_left <= 0.0:
		_sprint_time_left = MAX_SPRINT_DURATION

func _start_sprint_cooldown() -> void:
	_sprint_cooldown_left = SPRINT_COOLDOWN_DURATION
	_sprint_time_left = 0.0

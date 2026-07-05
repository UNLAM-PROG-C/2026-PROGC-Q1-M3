extends CharacterBody3D

const SPEED = 3.0
const GRAVITY = -9.8
const MOUSE_SENSITIVITY = 0.005
const FIRST_PERSON_MODEL_LAYER := 1 << 2
const SPRINT_SPEED_MULTIPLIER := 2.0
const MAX_SPRINT_DURATION := 2.0
const SPRINT_COOLDOWN_DURATION := 5.0
const SPRINT_REGEN_RATE := 0.7   ## stamina-seg recuperados por segundo al no correr (tuneable)

const CAPTURE_RANGE := 3.0   ## Alcance (m). Antes 8.0.
const FIRE_COOLDOWN := 1.0   ## segs de cooldown
const WALK_STEP_INTERVAL := 0.42   ## segs entre pasos al caminar
const SPRINT_STEP_INTERVAL := 0.28   ## segs entre pasos al correr

const EXPLOSION_COLOR := Color(1.0, 0.55, 0.1) ## particulas naranjas
const FALL_ANGLE := PI / 2 ## cae al piso

## Altura (m) de la cámara cenital sobre el cadáver al morir (estilo GTA).
const DEATH_CAM_HEIGHT := 3.0

## Ajuste fino de orientacion del modelo respecto al frente del jugador.
const MODEL_YAW_OFFSET := PI
## Umbral de velocidad (u/s) para considerar que el jugador se esta moviendo.
const WALK_SPEED_THRESHOLD := 0.3

## Los modelos de Mixamo vienen a ~56u de alto; 0.03 los deja en ~1.7u.
@export var model_scale := 0.03
## Desplazamiento vertical del modelo para apoyar los pies en la base de la capsula.
@export var model_y_offset := -1.0
@export var step_sound_1: AudioStream
@export var step_sound_2: AudioStream
@export var step_volume_db := -16.0

@onready var head = $Head
@onready var camera: Camera3D = $Head/Camera3D

var _hud  # HUD de primera persona; solo existe para el jugador local
var _model: Node3D
var _anim_player: AnimationPlayer
var _walk_model_index := 0
var _is_walking := false  # replicado: el dueño lo setea según su velocity; todos animan según esto

# Combate
var _current_target = null            # otro player vivo bajo la mira (objetivo capturable)
var _current_npc_target = null        # NPC bajo la mira (apuntado, genera alarma al disparar)
var _cooldown_left := 0.0
var _eliminated := false              # capturado: congelado y no apuntable
var _death_cam: Camera3D               # cámara cenital creada al morir
var _last_anim_position := Vector3.ZERO
var _sprint_time_left := MAX_SPRINT_DURATION
var _sprint_cooldown_left := 0.0
var _step_player_1: AudioStreamPlayer
var _step_player_2: AudioStreamPlayer
var _step_timer := 0.0
var _next_step_sound := 0

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
		_setup_step_sound()


func _setup_step_sound() -> void:
	if step_sound_1 == null and ResourceLoader.exists("res://audio/sfx/step-slow1.mp3"):
		step_sound_1 = load("res://audio/sfx/step-slow1.mp3")
	if step_sound_2 == null and ResourceLoader.exists("res://audio/sfx/step-slow2.mp3"):
		step_sound_2 = load("res://audio/sfx/step-slow2.mp3")
	_step_player_1 = AudioStreamPlayer.new()
	_step_player_1.stream = step_sound_1
	_step_player_1.volume_db = step_volume_db
	add_child(_step_player_1)
	_step_player_2 = AudioStreamPlayer.new()
	_step_player_2.stream = step_sound_2
	_step_player_2.volume_db = step_volume_db
	add_child(_step_player_2)

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

	# Primera persona: el jugador local no ve su propio cuerpo (salvo en el espejo)
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
	# Fallback (ej. --debug_solo, sin lista de red): apariencia aleatoria.
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	return CharacterAppearance.random_player_appearance(rng)

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
	var planar_speed := Vector2(velocity.x, velocity.z).length()
	_is_walking = planar_speed > WALK_SPEED_THRESHOLD
	_update_step_sound(delta, is_sprinting)

	# Avisar al HUD la velocidad planar para el bob del arma + estado de stamina
	if _hud:
		_hud.set_moving(planar_speed)
		var on_cd := _sprint_cooldown_left > 0.0
		var stamina_frac := _sprint_time_left / MAX_SPRINT_DURATION
		if on_cd:
			stamina_frac = 1.0 - (_sprint_cooldown_left / SPRINT_COOLDOWN_DURATION)  # recarga visible
		_hud.set_stamina(stamina_frac, on_cd)

	# Cooldown del arma + apuntado (raycast desde la cámara), tras el movimiento.
	if _cooldown_left > 0.0:
		_cooldown_left -= delta
	_update_target()


## Parsea el resultado del raycast: retorna [player_node_or_null, npc_node_or_null].
func _parse_hit(hit: Dictionary) -> Array:
	if hit.is_empty():
		return [null, null]
	var col = hit.collider
	if col.is_in_group("players"):
		return [col, null]
	# El NPC tiene Area3D (capa 2, grupo "npcs") y StaticBody3D (capa 1) coincidentes; el rayo
	# (mask 1|2) puede devolver cualquiera. El ThreadedNPC (que expone kill_npc) es padre de ambos.
	var npc = col.get_parent()
	if npc != null and npc.has_method("kill_npc"):
		return [null, npc]
	return [null, null]


func _update_target() -> void:
	var from := camera.global_position
	var to := from - camera.global_transform.basis.z * CAPTURE_RANGE
	var query := PhysicsRayQueryParameters3D.create(from, to)
	query.collision_mask = 1 | 2  # capa 1: jugadores, capa 2: áreas de NPCs
	query.collide_with_areas = true
	query.exclude = [get_rid()]
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	var result := _parse_hit(hit)
	var new_player = result[0]
	var new_npc = result[1]
	if new_player == _current_target and new_npc == _current_npc_target:
		return
	_current_target = new_player
	_current_npc_target = new_npc
	_update_crosshair()


## Actualiza el color del crosshair: rojo si hay cualquier objetivo (jugador o NPC), blanco si no.
func _update_crosshair() -> void:
	if _hud == null:
		return
	var has_target := _current_target != null or _current_npc_target != null
	_hud.set_target_acquired(has_target)


func _update_step_sound(delta: float, is_sprinting: bool) -> void:
	if not _is_walking or not is_on_floor():
		_step_timer = 0.0
		return
	if _step_player_1 == null or _step_player_2 == null:
		return
	if _step_player_1.stream == null or _step_player_2.stream == null:
		return

	_step_timer -= delta
	if _step_timer <= 0.0:
		if _next_step_sound == 0:
			_step_player_1.play()
		else:
			_step_player_2.play()
		_next_step_sound = 1 - _next_step_sound
		_step_timer = SPRINT_STEP_INTERVAL if is_sprinting else WALK_STEP_INTERVAL


func _try_fire() -> void:
	if _cooldown_left > 0.0:
		return
	_cooldown_left = FIRE_COOLDOWN
	if _hud:
		_hud.play_fire()  # recoil siempre
	if is_instance_valid(_current_target):
		_fire_at_player()
	elif is_instance_valid(_current_npc_target) and not _current_npc_target.is_dead():
		_fire_at_npc()


func _fire_at_player() -> void:
	var victim_id: int = _current_target.name.to_int()
	var game = get_parent()
	if multiplayer.is_server():
		game.report_capture(victim_id)
	else:
		game.report_capture.rpc_id(1, victim_id)


func _fire_at_npc() -> void:
	var game = get_parent()
	var npc_idx: int = _current_npc_target.npc_index
	if multiplayer.has_multiplayer_peer() and not multiplayer.is_server():
		game.report_npc_kill.rpc_id(1, npc_idx)  # cliente → server
	else:
		game.report_npc_kill(npc_idx)            # server u offline/solo: directo


func set_eliminated() -> void:
	if _eliminated:
		return
	_eliminated = true
	velocity = Vector3.ZERO
	_is_walking = false
	remove_from_group("players")
	collision_layer = 0
	_current_target = null
	_current_npc_target = null
	if _hud:
		_hud.set_target_acquired(false)
	_play_capture_fx()
	activate_death_cam()


## Crea una Camera3D cenital que mira hacia abajo al cadáver.
## Devuelve el modelo a la capa visible (para el jugador local) y oculta el HUD.
func activate_death_cam() -> Camera3D:
	_death_cam = Camera3D.new()
	_death_cam.name = "DeathCam"
	add_child(_death_cam)
	_death_cam.position = Vector3(0.0, DEATH_CAM_HEIGHT, 0.0)
	_death_cam.rotation.x = -PI / 2.0
	# Jugador local: hacer visible su propio modelo y ocultar el HUD/arma.
	if is_local_player():
		if _model:
			_set_visual_layer_recursive(_model, 1)
		if _hud:
			_hud.hide()
		_death_cam.current = true
	return _death_cam


## Retorna la death cam si existe (para que los espectadores puedan usarla).
func get_death_cam() -> Camera3D:
	return _death_cam


## Retorna la cámara de primera persona de este jugador (usada por el modo espectador).
func get_camera() -> Camera3D:
	return camera


## Retorna el nombre display del jugador (leído de GameNetwork o fallback).
func get_display_name() -> String:
	return _resolve_my_name()


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

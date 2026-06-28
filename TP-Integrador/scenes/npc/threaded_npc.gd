extends Node3D

## Offset de orientacion para alinear al npc con la dirección con la que camina (así no hace moonwalking)
const ORIENT_OFFSET := 0.0

## Escala del modelo para encajarlo con el mundo (similar a la capsula del jugador).
@export var model_scale := 0.03
## Desplazamiento vertical del modelo para apoyar los pies en el piso
@export var model_y_offset := -1.0

## Color de las partículas de sangre al morir
const BLOOD_COLOR := Color(0.55, 0.0, 0.0)
## Ángulo de caída del modelo (PI/2 = tumbado en el piso)
const FALL_ANGLE := PI / 2.0
const STEP_DISTANCE := 1.25

var facing_rotation_y := 0.0
## Índice dentro del NPCThreadPool; asignado por el pool en _rebuild_npcs.
var npc_index := -1

@export var step_sound_1: AudioStream
@export var step_sound_2: AudioStream
@export var step_volume_db := -22.0
@export var step_max_distance := 12.0

var _model: Node3D
var _anim_player: AnimationPlayer
var _model_index := 0
var _is_idle := false
var _dead := false
var _area: Area3D
var _static_body: StaticBody3D
var _step_player_1: AudioStreamPlayer3D
var _step_player_2: AudioStreamPlayer3D
var _next_step_sound := 0
var _last_step_position := Vector3.ZERO
var _distance_until_next_step := STEP_DISTANCE


func _ready() -> void:
	_setup_collision()
	_setup_step_sound()
	_last_step_position = global_position
	_distance_until_next_step = randf_range(0.0, STEP_DISTANCE)


## Llamado por el pool justo despues de instanciar y agregar al arbol.
func setup(appearance: Dictionary) -> void:
	var model_index := int(appearance.get("model", 0))
	var part_colors: Dictionary = appearance.get("part_colors", {})
	_model_index = model_index

	_model = CharacterAppearance.build_model(model_index)
	if _model == null:
		return

	add_child(_model)
	_model.scale = Vector3.ONE * model_scale
	_model.position.y = model_y_offset

	CharacterAppearance.apply_part_colors(_model, part_colors)

	_anim_player = CharacterAppearance.find_animation_player(_model)
	CharacterAppearance.play_walk(_anim_player, _model_index)


## Crea un Area3D (para raycasts de disparo) y un StaticBody3D (para que el jugador no traspase).
func _setup_collision() -> void:
	var capsule := CapsuleShape3D.new()
	capsule.radius = 0.35
	capsule.height = 1.7

	_area = Area3D.new()
	_area.collision_layer = 2
	_area.collision_mask = 0
	_area.add_to_group("npcs")
	var area_shape := CollisionShape3D.new()
	area_shape.shape = capsule
	_area.add_child(area_shape)
	add_child(_area)

	_static_body = StaticBody3D.new()
	_static_body.collision_layer = 1
	_static_body.collision_mask = 0
	var body_shape := CollisionShape3D.new()
	body_shape.shape = capsule
	_static_body.add_child(body_shape)
	add_child(_static_body)


func is_dead() -> bool:
	return _dead


## Mata al NPC: detiene movimiento futuro, tira el modelo y emite partículas de sangre.
func kill_npc() -> void:
	if _dead:
		return
	_dead = true
	_stop_step_sound()
	_disable_area()
	if _anim_player and _anim_player.is_playing():
		_anim_player.pause()
	_spawn_blood_particles()
	_fall_model()


func _disable_area() -> void:
	if _area != null:
		_area.set_deferred("monitoring", false)
		_area.set_deferred("monitorable", false)
	if _static_body != null:
		_static_body.set_deferred("collision_layer", 0)


func _fall_model() -> void:
	if _model == null:
		return
	var tw := create_tween()
	tw.tween_property(_model, "rotation:x", FALL_ANGLE, 0.4)\
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)


func _spawn_blood_particles() -> void:
	var burst := CPUParticles3D.new()
	_configure_burst(burst)
	burst.mesh = _make_blood_mesh()
	add_child(burst)
	burst.emitting = true
	burst.finished.connect(burst.queue_free)


func _configure_burst(burst: CPUParticles3D) -> void:
	burst.process_mode = Node.PROCESS_MODE_ALWAYS
	burst.one_shot = true
	burst.explosiveness = 1.0
	burst.amount = 28
	burst.lifetime = 0.8
	burst.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	burst.emission_sphere_radius = 0.3
	burst.direction = Vector3.UP
	burst.spread = 180.0
	burst.initial_velocity_min = 2.0
	burst.initial_velocity_max = 5.0
	burst.gravity = Vector3(0.0, -9.8, 0.0)
	burst.scale_amount_min = 0.5
	burst.scale_amount_max = 1.0


func _make_blood_mesh() -> SphereMesh:
	var pmesh := SphereMesh.new()
	pmesh.radius = 0.05
	pmesh.height = 0.1
	var pmat := StandardMaterial3D.new()
	pmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	pmat.albedo_color = BLOOD_COLOR
	pmesh.material = pmat
	return pmesh


func _setup_step_sound() -> void:
	if step_sound_1 == null and ResourceLoader.exists("res://audio/sfx/step-slow1.mp3"):
		step_sound_1 = load("res://audio/sfx/step-slow1.mp3")
	if step_sound_2 == null and ResourceLoader.exists("res://audio/sfx/step-slow2.mp3"):
		step_sound_2 = load("res://audio/sfx/step-slow2.mp3")
	_step_player_1 = _make_step_player(step_sound_1)
	_step_player_2 = _make_step_player(step_sound_2)


func _make_step_player(stream: AudioStream) -> AudioStreamPlayer3D:
	var player := AudioStreamPlayer3D.new()
	player.stream = stream
	player.volume_db = step_volume_db
	player.max_distance = step_max_distance
	player.attenuation_model = AudioStreamPlayer3D.ATTENUATION_LOGARITHMIC
	add_child(player)
	return player


func _stop_step_sound() -> void:
	if _step_player_1:
		_step_player_1.stop()
	if _step_player_2:
		_step_player_2.stop()


func _update_step_sound(next_position: Vector3, is_idle: bool) -> void:
	if is_idle or _dead:
		_last_step_position = next_position
		return
	if _step_player_1 == null or _step_player_2 == null:
		return
	if _step_player_1.stream == null or _step_player_2.stream == null:
		return

	var from := Vector2(_last_step_position.x, _last_step_position.z)
	var to := Vector2(next_position.x, next_position.z)
	_distance_until_next_step -= from.distance_to(to)
	_last_step_position = next_position
	if _distance_until_next_step > 0.0:
		return

	if _next_step_sound == 0:
		_step_player_1.play()
	else:
		_step_player_2.play()
	_next_step_sound = 1 - _next_step_sound
	_distance_until_next_step = STEP_DISTANCE


## Si el NPC está muerto, ignora las actualizaciones de posición del thread pool.
func apply_simulation_state(next_position: Vector3, next_rotation_y: float, is_idle: bool = false) -> void:
	if _dead:
		return
	_update_step_sound(next_position, is_idle)
	global_position = next_position
	facing_rotation_y = next_rotation_y
	if _model != null:
		_model.rotation.y = next_rotation_y + ORIENT_OFFSET
	_update_animation(is_idle)


func _update_animation(should_idle: bool) -> void:
	if _anim_player == null or _is_idle == should_idle:
		return
	_is_idle = should_idle
	if should_idle:
		CharacterAppearance.play_idle(_anim_player, _model_index)
	else:
		CharacterAppearance.play_walk(_anim_player, _model_index)

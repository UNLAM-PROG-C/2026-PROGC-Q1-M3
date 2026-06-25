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

var facing_rotation_y := 0.0
## Índice dentro del NPCThreadPool; asignado por el pool en _rebuild_npcs.
var npc_index := -1

var _model: Node3D
var _anim_player: AnimationPlayer
var _model_index := 0
var _is_idle := false
var _dead := false
var _area: Area3D


func _ready() -> void:
	_setup_collision()


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


## Crea un Area3D con forma de cápsula para que los raycasts del jugador puedan detectar al NPC.
## Usa collision_layer = 2 (bit 1) para diferenciarse de los jugadores (layer 1).
func _setup_collision() -> void:
	_area = Area3D.new()
	_area.collision_layer = 2
	_area.collision_mask = 0
	_area.add_to_group("npcs")
	var shape := CollisionShape3D.new()
	var capsule := CapsuleShape3D.new()
	capsule.radius = 0.35
	capsule.height = 1.7
	shape.shape = capsule
	_area.add_child(shape)
	add_child(_area)


func is_dead() -> bool:
	return _dead


## Mata al NPC: detiene movimiento futuro, tira el modelo y emite partículas de sangre.
func kill_npc() -> void:
	if _dead:
		return
	_dead = true
	_disable_area()
	if _anim_player and _anim_player.is_playing():
		_anim_player.pause()
	_spawn_blood_particles()
	_fall_model()


func _disable_area() -> void:
	if _area == null:
		return
	_area.set_deferred("monitoring", false)
	_area.set_deferred("monitorable", false)


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


## Si el NPC está muerto, ignora las actualizaciones de posición del thread pool.
func apply_simulation_state(next_position: Vector3, next_rotation_y: float, is_idle: bool = false) -> void:
	if _dead:
		return
	position = next_position
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

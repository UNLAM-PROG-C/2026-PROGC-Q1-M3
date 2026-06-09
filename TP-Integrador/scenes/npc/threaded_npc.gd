extends Node3D



## Offset de orientacion para alinear al npc con la dirección con la que camina (así no hace moonwalking)
const ORIENT_OFFSET := 0.0

## Escala del modelo para encajarlo con el mundo (similar a la capsula del jugador).
@export var model_scale := 0.03
## Desplazamiento vertical del modelo para apoyar los pies en el piso
@export var model_y_offset := -1.0

var facing_rotation_y := 0.0

var _model: Node3D
var _anim_player: AnimationPlayer


## Llamado por el pool justo despues de instanciar y agregar al arbol.
func setup(appearance: Dictionary) -> void:
	var model_index := int(appearance.get("model", 0))
	var part_colors: Dictionary = appearance.get("part_colors", {})

	_model = CharacterAppearance.build_model(model_index)
	if _model == null:
		return

	add_child(_model)
	_model.scale = Vector3.ONE * model_scale
	_model.position.y = model_y_offset

	CharacterAppearance.apply_part_colors(_model, part_colors)

	_anim_player = CharacterAppearance.find_animation_player(_model)
	CharacterAppearance.play_walk(_anim_player, model_index)


func apply_simulation_state(next_position: Vector3, next_rotation_y: float) -> void:
	position = next_position
	facing_rotation_y = next_rotation_y
	if _model != null:
		_model.rotation.y = next_rotation_y + ORIENT_OFFSET

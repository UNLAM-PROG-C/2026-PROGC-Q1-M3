extends Node3D

const FRONT_FRAME := 0
const BACK_FRAME := 1
const COMPOSITE_SIZE := Vector2i(469, 563)
const SPRITE_ROOT := "res://scenes/npc/sprites"
const REQUIRED_PARTS := [
	{
		"folder": "piernas",
		"prefix": "pierna_",
		"y": 304,
	},
	{
		"folder": "zapatos",
		"prefix": "zapato_",
		"y": 514,
	},
	{
		"folder": "torsos",
		"prefix": "torso_",
		"y": 148,
	},
	{
		"folder": "cabezas",
		"prefix": "cabeza_",
		"y": 8,
	},
]

var facing_rotation_y := 0.0
var _rng := RandomNumberGenerator.new()

@onready var character_sprite: Sprite3D = $CharacterSprite


func _ready():
	_rng.randomize()
	_build_random_character()


func _process(_delta):
	_update_sprite_frame()


func apply_simulation_state(next_position: Vector3, next_rotation_y: float):
	position = next_position
	facing_rotation_y = next_rotation_y
	_update_sprite_frame()


func _update_sprite_frame():
	var camera := get_viewport().get_camera_3d()
	if camera == null:
		return

	var to_camera: Vector3 = camera.global_position - global_position
	to_camera.y = 0.0
	if to_camera.length_squared() <= 0.0001:
		return

	var forward := Vector3(sin(facing_rotation_y), 0.0, cos(facing_rotation_y))

	if forward.normalized().dot(to_camera.normalized()) >= 0.0:
		_set_frame(FRONT_FRAME)
	else:
		_set_frame(BACK_FRAME)


func _build_random_character():
	var image := Image.create(COMPOSITE_SIZE.x, COMPOSITE_SIZE.y, false, Image.FORMAT_RGBA8)
	image.fill(Color.TRANSPARENT)

	for part in REQUIRED_PARTS:
		_draw_random_part(image, part)

	character_sprite.texture = ImageTexture.create_from_image(image)


func _draw_random_part(target: Image, part: Dictionary):
	var file_path := _pick_random_file(part["folder"], part["prefix"])
	if file_path.is_empty():
		return

	var part_image := Image.load_from_file(file_path)
	if part_image == null:
		return

	var offset := Vector2i(
		int(round(float(COMPOSITE_SIZE.x - part_image.get_width()) * 0.5)),
		int(part["y"])
	)
	target.blend_rect(part_image, Rect2i(Vector2i.ZERO, part_image.get_size()), offset)


func _pick_random_file(folder: String, prefix: String) -> String:
	var files := _get_part_files(folder, prefix)
	if files.is_empty():
		return ""

	return files[_rng.randi_range(0, files.size() - 1)]


func _get_part_files(folder: String, prefix: String) -> Array[String]:
	var files: Array[String] = []
	var dir := DirAccess.open("%s/%s" % [SPRITE_ROOT, folder])
	if dir == null:
		return files

	dir.list_dir_begin()
	var file_name := dir.get_next()
	while not file_name.is_empty():
		if not dir.current_is_dir() and file_name.begins_with(prefix) and file_name.ends_with(".png"):
			files.append("%s/%s/%s" % [SPRITE_ROOT, folder, file_name])
		file_name = dir.get_next()

	dir.list_dir_end()
	files.sort()
	return files


func _set_frame(frame: int):
	character_sprite.frame = frame

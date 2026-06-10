@tool
extends EditorPlugin

const MIRROR_SCENE_PATH := "res://scenes/objects/mirror/mirror.tscn"
const DEFAULT_MIRROR_SCALE := Vector3(0.8, 0.8, 0.8)
const RAY_LENGTH := 1000.0

var _enabled := false
var _mirror_scene: PackedScene
var _button: Button


func _enter_tree() -> void:
	_mirror_scene = load(MIRROR_SCENE_PATH)
	add_tool_menu_item("Activar colocacion de espejos", _toggle_mirror_placement)
	_button = Button.new()
	_button.text = "Espejos"
	_button.toggle_mode = true
	_button.tooltip_text = "Click en la vista 3D para colocar espejos"
	_button.toggled.connect(_set_mirror_placement)
	add_control_to_container(EditorPlugin.CONTAINER_SPATIAL_EDITOR_MENU, _button)
	set_input_event_forwarding_always_enabled()


func _exit_tree() -> void:
	remove_tool_menu_item("Activar colocacion de espejos")
	if _button != null:
		remove_control_from_container(EditorPlugin.CONTAINER_SPATIAL_EDITOR_MENU, _button)
		_button.queue_free()
		_button = null


func _toggle_mirror_placement() -> void:
	_set_mirror_placement(not _enabled)


func _set_mirror_placement(enabled: bool) -> void:
	_enabled = enabled
	if _button != null:
		_button.set_block_signals(true)
		_button.button_pressed = _enabled
		_button.set_block_signals(false)
	var label := "activada" if _enabled else "desactivada"
	print("Colocacion de espejos %s. Click izquierdo en la vista 3D para colocar." % label)


func _forward_3d_gui_input(viewport_camera: Camera3D, event: InputEvent) -> int:
	if not _enabled:
		return EditorPlugin.AFTER_GUI_INPUT_PASS

	if event is InputEventMouseButton:
		var mouse_event := event as InputEventMouseButton
		if mouse_event.button_index == MOUSE_BUTTON_LEFT and mouse_event.pressed:
			_place_mirror(viewport_camera, mouse_event.position)
			return EditorPlugin.AFTER_GUI_INPUT_STOP

	return EditorPlugin.AFTER_GUI_INPUT_PASS


func _place_mirror(viewport_camera: Camera3D, mouse_position: Vector2) -> void:
	var edited_root := get_editor_interface().get_edited_scene_root()
	if edited_root == null:
		push_warning("Abri una escena antes de colocar espejos.")
		return

	if _mirror_scene == null:
		push_warning("No se pudo cargar %s" % MIRROR_SCENE_PATH)
		return

	var hit_position := _raycast_scene(viewport_camera, mouse_position)
	if hit_position == null:
		push_warning("No se encontro una superficie con colision bajo el cursor.")
		return

	var mirror := _mirror_scene.instantiate() as Node3D
	mirror.name = _unique_child_name(edited_root, "Mirror")
	mirror.scale = DEFAULT_MIRROR_SCALE
	mirror.global_position = hit_position
	_face_camera_on_y(mirror, viewport_camera.global_position)

	var undo := get_undo_redo()
	undo.create_action("Colocar espejo")
	undo.add_do_method(edited_root, "add_child", mirror)
	undo.add_do_property(mirror, "owner", edited_root)
	undo.add_undo_method(edited_root, "remove_child", mirror)
	undo.commit_action()

	get_editor_interface().edit_node(mirror)


func _raycast_scene(viewport_camera: Camera3D, mouse_position: Vector2) -> Variant:
	var origin := viewport_camera.project_ray_origin(mouse_position)
	var target := origin + viewport_camera.project_ray_normal(mouse_position) * RAY_LENGTH
	var world := viewport_camera.get_world_3d()
	if world == null:
		return null

	var query := PhysicsRayQueryParameters3D.create(origin, target)
	query.collide_with_areas = true
	query.collide_with_bodies = true

	var hit := world.direct_space_state.intersect_ray(query)
	if hit.is_empty():
		return null

	return hit["position"]


func _face_camera_on_y(mirror: Node3D, camera_position: Vector3) -> void:
	var direction := camera_position - mirror.global_position
	direction.y = 0.0
	if direction.length_squared() <= 0.001:
		return

	mirror.rotation.y = atan2(direction.x, direction.z)


func _unique_child_name(parent: Node, base_name: String) -> String:
	var index := 1
	var candidate := base_name
	while parent.has_node(candidate):
		index += 1
		candidate = "%s%d" % [base_name, index]
	return candidate

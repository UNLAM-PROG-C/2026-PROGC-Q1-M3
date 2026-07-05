extends Node3D

const MIRROR_SURFACE_LAYER := 1 << 1
const FIRST_PERSON_MODEL_LAYER := 1 << 2
const MIRROR_MODEL_LAYER := 1 << 3
const REFLECTION_OCCLUDER_LAYER := 1 << 19
const MIRROR_LOCAL_CENTER := Vector3(0.0737, 94.5454, 1.6341)
const WORLD_VISUAL_LAYER := 1 << 0

@export var mirror_mesh_path: NodePath
@export var mirror_mesh_name := "mirrorAMirror_mirrorA_Mat_0"
@export var surface_normal_local := Vector3.FORWARD
@export var viewport_size := Vector2i(768, 768)
@export var activation_radius := 30.0
@export var reflection_occluder_probe_distance := 1.5
@export var reflection_occluder_probe_width := 0.7
@export var reflection_occluder_probe_height := 1.7
@export var flip_reflection_x := true
@export var flip_reflection_y := true
@export var collision_enabled := true
@export_flags_3d_physics var collision_layer: int = 1
@export_flags_3d_physics var collision_mask: int = 1
@export_flags_3d_physics var activation_mask: int = 1
@export var reflect_mirror_models := false

@onready var _viewport: SubViewport = $ReflectionViewport
@onready var _reflection_camera: Camera3D = $ReflectionViewport/ReflectionCamera
@onready var _collision_body: StaticBody3D = $CollisionBody
@onready var _activation_area: Area3D = $ActivationArea
@onready var _activation_shape: CollisionShape3D = $ActivationArea/CollisionShape3D

var _mirror_mesh: MeshInstance3D
var _source_camera: Camera3D
var _local_player_in_area := false
var _reflection_active := false


func _ready() -> void:
	_viewport.size = viewport_size
	_viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	_reflection_camera.current = true
	call_deferred("_use_main_world")
	_setup_activation_area()

	_mirror_mesh = _resolve_mirror_mesh()
	if _mirror_mesh == null:
		push_warning("No se encontro el mesh de superficie del espejo: %s" % mirror_mesh_name)
		return

	_set_visual_layer_recursive($Model, MIRROR_MODEL_LAYER)
	_mirror_mesh.layers = MIRROR_SURFACE_LAYER
	_mirror_mesh.visible = true
	_apply_reflection_material()
	_build_collision()
	_set_reflection_active(true)
	call_deferred("_mark_reflection_occluders")


func _use_main_world() -> void:
	_viewport.world_3d = get_viewport().world_3d


func _build_collision() -> void:
	for child in _collision_body.get_children():
		child.queue_free()

	if not collision_enabled:
		_collision_body.collision_layer = 0
		_collision_body.collision_mask = 0
		return

	_collision_body.collision_layer = collision_layer
	_collision_body.collision_mask = collision_mask
	_add_mesh_collisions($Model)


func _add_mesh_collisions(node: Node) -> void:
	if node is MeshInstance3D and node.mesh != null:
		var shape: Shape3D = node.mesh.create_trimesh_shape()
		if shape != null:
			var collision_shape := CollisionShape3D.new()
			collision_shape.name = "%sCollision" % node.name
			collision_shape.shape = shape
			collision_shape.transform = _collision_body.global_transform.affine_inverse() * node.global_transform
			_collision_body.add_child(collision_shape)

	for child in node.get_children():
		_add_mesh_collisions(child)


func _setup_activation_area() -> void:
	var shape := SphereShape3D.new()
	shape.radius = activation_radius
	_activation_shape.shape = shape
	_activation_area.collision_layer = 0
	_activation_area.collision_mask = activation_mask
	_activation_area.monitoring = true
	_activation_area.monitorable = false
	_activation_area.body_entered.connect(_on_activation_body_entered)
	_activation_area.body_exited.connect(_on_activation_body_exited)


func _process(_delta: float) -> void:
	if _mirror_mesh == null:
		return

	_source_camera = _find_source_camera()
	if _source_camera == null:
		_set_reflection_active(false)
		return

	_source_camera.cull_mask |= REFLECTION_OCCLUDER_LAYER
	_update_activation(_source_camera)
	_set_reflection_active(_local_player_in_area)
	if not _reflection_active:
		return

	_sync_reflection_camera(_source_camera)


func _resolve_mirror_mesh() -> MeshInstance3D:
	if mirror_mesh_path != NodePath():
		var mesh_from_path := get_node_or_null(mirror_mesh_path)
		if mesh_from_path is MeshInstance3D:
			return mesh_from_path

	return _find_mesh_by_name(self, mirror_mesh_name)


func _find_mesh_by_name(node: Node, target_name: String) -> MeshInstance3D:
	if node is MeshInstance3D and node.name == target_name:
		return node

	for child in node.get_children():
		var found := _find_mesh_by_name(child, target_name)
		if found != null:
			return found

	return null


func _apply_reflection_material() -> void:
	var shader := Shader.new()
	shader.code = """
shader_type spatial;
render_mode unshaded, cull_disabled;

uniform sampler2D reflection_texture : source_color, filter_linear_mipmap;
uniform bool flip_x = true;
uniform bool flip_y = false;

varying vec3 local_vertex;

void vertex() {
	local_vertex = VERTEX;
}

void fragment() {
	vec2 projected_uv = vec2(
		(local_vertex.x + 28.2311) / 56.6096,
		(local_vertex.y - 14.7576) / 159.5757
	);
	projected_uv = clamp(projected_uv, vec2(0.0), vec2(1.0));

	if (flip_x) {
		projected_uv.x = 1.0 - projected_uv.x;
	}
	if (flip_y) {
		projected_uv.y = 1.0 - projected_uv.y;
	}

	ALBEDO = texture(reflection_texture, projected_uv).rgb;
	ROUGHNESS = 0.02;
	METALLIC = 1.0;
}
"""
	var material := ShaderMaterial.new()
	material.shader = shader
	material.set_shader_parameter("reflection_texture", _viewport.get_texture())
	material.set_shader_parameter("flip_x", flip_reflection_x)
	material.set_shader_parameter("flip_y", flip_reflection_y)
	_mirror_mesh.set_surface_override_material(0, material)


func _set_reflection_active(active: bool) -> void:
	if _reflection_active == active:
		return

	_reflection_active = active
	_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS if active else SubViewport.UPDATE_DISABLED


func _update_activation(source_camera: Camera3D) -> void:
	_local_player_in_area = false

	if _is_position_near_mirror(source_camera.global_position):
		_local_player_in_area = true
		return

	for body in _activation_area.get_overlapping_bodies():
		if _is_local_player_body(body):
			_local_player_in_area = true
			return

	var local_player := _find_local_player()
	if local_player == null:
		return

	_local_player_in_area = _is_position_near_mirror(local_player.global_position)


func _is_position_near_mirror(_position: Vector3) -> bool:
	var anchors: Array[Vector3] = [global_position]
	if _mirror_mesh != null:
		anchors.append(_mirror_mesh.global_position)
		anchors.append(_mirror_mesh.to_global(MIRROR_LOCAL_CENTER))

	for anchor in anchors:
		var flat_position := _position
		flat_position.y = anchor.y
		if flat_position.distance_to(anchor) <= activation_radius:
			return true

	return false


func _on_activation_body_entered(body: Node3D) -> void:
	if _is_local_player_body(body):
		_local_player_in_area = true


func _on_activation_body_exited(body: Node3D) -> void:
	if _is_local_player_body(body):
		_local_player_in_area = false


func _is_local_player_body(body: Node) -> bool:
	if not body.is_in_group("players"):
		return false
	if body.has_method("is_local_player"):
		return body.is_local_player()
	return true


func _find_local_player() -> Node3D:
	for player in get_tree().get_nodes_in_group("players"):
		if player is Node3D and _is_local_player_body(player):
			return player
	return null


func _find_source_camera() -> Camera3D:
	var viewport_camera := get_viewport().get_camera_3d()
	if viewport_camera != _reflection_camera:
		return viewport_camera
	return _source_camera


func _sync_reflection_camera(source_camera: Camera3D) -> void:
	var plane_point := _mirror_mesh.to_global(MIRROR_LOCAL_CENTER)
	var plane_normal := (_mirror_mesh.global_transform.basis * surface_normal_local).normalized()

	_reflection_camera.global_position = _reflect_point(source_camera.global_position, plane_point, plane_normal)

	var reflected_forward := _reflect_vector(-source_camera.global_transform.basis.z, plane_normal).normalized()
	var reflected_up := _reflect_vector(source_camera.global_transform.basis.y, plane_normal).normalized()
	_reflection_camera.look_at(_reflection_camera.global_position + reflected_forward, reflected_up)

	_reflection_camera.fov = source_camera.fov
	_reflection_camera.near = source_camera.near
	_reflection_camera.far = source_camera.far
	_reflection_camera.cull_mask = source_camera.cull_mask | FIRST_PERSON_MODEL_LAYER
	_reflection_camera.cull_mask &= ~MIRROR_SURFACE_LAYER
	_reflection_camera.cull_mask &= ~REFLECTION_OCCLUDER_LAYER
	if not reflect_mirror_models:
		_reflection_camera.cull_mask &= ~MIRROR_MODEL_LAYER


func _mark_reflection_occluders() -> void:
	if _mirror_mesh == null:
		return

	await get_tree().physics_frame

	var plane_point := _mirror_mesh.to_global(MIRROR_LOCAL_CENTER)
	var plane_normal := (_mirror_mesh.global_transform.basis * surface_normal_local).normalized()
	var mirror_right := _mirror_mesh.global_transform.basis.x.normalized()
	var mirror_up := _mirror_mesh.global_transform.basis.y.normalized()
	var probe_offsets: Array[Vector3] = [
		Vector3.ZERO,
		mirror_right * reflection_occluder_probe_width,
		-mirror_right * reflection_occluder_probe_width,
		mirror_up * reflection_occluder_probe_height,
		-mirror_up * reflection_occluder_probe_height,
		mirror_right * reflection_occluder_probe_width + mirror_up * reflection_occluder_probe_height,
		-mirror_right * reflection_occluder_probe_width + mirror_up * reflection_occluder_probe_height,
		mirror_right * reflection_occluder_probe_width - mirror_up * reflection_occluder_probe_height,
		-mirror_right * reflection_occluder_probe_width - mirror_up * reflection_occluder_probe_height,
	]

	for offset in probe_offsets:
		var probe_origin := plane_point + offset
		_mark_reflection_occluder_from_ray(probe_origin, plane_normal)
		_mark_reflection_occluder_from_ray(probe_origin, -plane_normal)


func _mark_reflection_occluder_from_ray(origin: Vector3, direction: Vector3) -> void:
	var query := PhysicsRayQueryParameters3D.create(
		origin + direction * 0.03,
		origin + direction * reflection_occluder_probe_distance
	)
	query.collision_mask = collision_mask
	query.exclude = [_collision_body.get_rid()]

	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	if hit.is_empty():
		return

	var collider := hit.get("collider") as Node
	if collider == null or collider.is_in_group("players") or collider.is_in_group("npcs"):
		return

	var visual_mesh := _find_visual_mesh_for_collider(collider)
	if visual_mesh == null or _is_mirror_node(visual_mesh) or not _is_wall_node(visual_mesh):
		return

	visual_mesh.layers = (visual_mesh.layers & ~WORLD_VISUAL_LAYER) | REFLECTION_OCCLUDER_LAYER


func _find_visual_mesh_for_collider(collider: Node) -> MeshInstance3D:
	var node := collider
	while node != null and node != get_tree().current_scene:
		if node is MeshInstance3D:
			return node

		var descendant_mesh := _find_first_mesh_descendant(node)
		if descendant_mesh != null:
			return descendant_mesh

		node = node.get_parent()

	return null


func _find_first_mesh_descendant(node: Node) -> MeshInstance3D:
	for child in node.get_children():
		if child is MeshInstance3D:
			return child

		var found := _find_first_mesh_descendant(child)
		if found != null:
			return found

	return null


func _is_wall_node(node: Node) -> bool:
	var current := node
	while current != null:
		var node_name := current.name.to_lower()
		if "floor" in node_name or "piso" in node_name or "ceiling" in node_name or "techo" in node_name:
			return false
		if "wall" in node_name or "pared" in node_name:
			return true
		current = current.get_parent()

	return false


func _is_mirror_node(node: Node) -> bool:
	var current := node
	while current != null:
		if current == self:
			return true
		current = current.get_parent()

	return false


func _reflect_point(point: Vector3, plane_point: Vector3, plane_normal: Vector3) -> Vector3:
	return point - (2.0 * plane_normal.dot(point - plane_point) * plane_normal)


func _reflect_vector(vector: Vector3, plane_normal: Vector3) -> Vector3:
	return vector - (2.0 * plane_normal.dot(vector) * plane_normal)


func _set_visual_layer_recursive(node: Node, layer: int) -> void:
	if node is VisualInstance3D:
		node.layers = layer

	for child in node.get_children():
		_set_visual_layer_recursive(child, layer)

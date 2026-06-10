extends Node3D

const MIRROR_SURFACE_LAYER := 1 << 1
const FIRST_PERSON_MODEL_LAYER := 1 << 2
const MIRROR_MODEL_LAYER := 1 << 3
const MIRROR_LOCAL_CENTER := Vector3(0.0737, 94.5454, 1.6341)

@export var mirror_mesh_path: NodePath
@export var mirror_mesh_name := "mirrorAMirror_mirrorA_Mat_0"
@export var surface_normal_local := Vector3.FORWARD
@export var viewport_size := Vector2i(768, 768)
@export var update_when_far := false
@export var max_update_distance := 30.0
@export var flip_reflection_x := true
@export var flip_reflection_y := true
@export var collision_enabled := true
@export_flags_3d_physics var collision_layer: int = 1
@export_flags_3d_physics var collision_mask: int = 1
@export var reflect_mirror_models := false

@onready var _viewport: SubViewport = $ReflectionViewport
@onready var _reflection_camera: Camera3D = $ReflectionViewport/ReflectionCamera
@onready var _collision_body: StaticBody3D = $CollisionBody

var _mirror_mesh: MeshInstance3D
var _source_camera: Camera3D


func _ready() -> void:
	_viewport.size = viewport_size
	_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	_reflection_camera.current = true
	call_deferred("_use_main_world")

	_mirror_mesh = _resolve_mirror_mesh()
	if _mirror_mesh == null:
		push_warning("No se encontro el mesh de superficie del espejo: %s" % mirror_mesh_name)
		return

	_set_visual_layer_recursive($Model, MIRROR_MODEL_LAYER)
	_mirror_mesh.layers = MIRROR_SURFACE_LAYER
	_mirror_mesh.visible = true
	_apply_reflection_material()
	_build_collision()


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


func _process(_delta: float) -> void:
	if _mirror_mesh == null:
		return

	_source_camera = _find_source_camera()
	if _source_camera == null:
		return

	var distance := _source_camera.global_position.distance_to(global_position)
	_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS if update_when_far or distance <= max_update_distance else SubViewport.UPDATE_DISABLED
	if _viewport.render_target_update_mode == SubViewport.UPDATE_DISABLED:
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
	if not reflect_mirror_models:
		_reflection_camera.cull_mask &= ~MIRROR_MODEL_LAYER


func _reflect_point(point: Vector3, plane_point: Vector3, plane_normal: Vector3) -> Vector3:
	return point - (2.0 * plane_normal.dot(point - plane_point) * plane_normal)


func _reflect_vector(vector: Vector3, plane_normal: Vector3) -> Vector3:
	return vector - (2.0 * plane_normal.dot(vector) * plane_normal)


func _set_visual_layer_recursive(node: Node, layer: int) -> void:
	if node is VisualInstance3D:
		node.layers = layer

	for child in node.get_children():
		_set_visual_layer_recursive(child, layer)

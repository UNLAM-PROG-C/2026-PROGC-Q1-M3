extends RefCounted
class_name CharacterAppearance

## Una "apariencia" es un Dictionary: { "model": int (0..MODEL_COUNT-1), "part_colors": Dictionary }
## donde part_colors mapea un fragmento del NOMBRE del material (en minuscula) a un color.
## Ej: { "pelo": Color.RED } recolorea el pelo. part_colors vacio = aspecto original del modelo.
##
## Los modelos usan materiales planos (StandardMaterial3D sin textura) nombrados por
## parte: piel, pelo, ojos, ropa_1..8, zapatos, gorra, anteojos. Como no hay textura,
## albedo_color reemplaza el color de la parte por completo.

const MODEL_PATHS := [
	"res://personajes/personaje_1_animado.glb",
	"res://personajes/personaje_2_animado.glb",
	"res://personajes/personaje_3_animado.glb",
	"res://personajes/personaje_4_animado.glb",
	"res://personajes/personaje_5_animado.glb",
	"res://personajes/personaje_6_animado.glb",
]

const MODEL_COUNT := 6

# ---------------------------------------------------------------------------
# Paletas de color. El color de cada parte se elige de estas listas.
# ---------------------------------------------------------------------------
const HAIR_COLORS: Array[Color] = [
	Color("1a1a1a"),  # negro
	Color("3b2412"),  # castaño oscuro
	Color("6b4226"),  # castaño
	Color("c9a227"),  # rubio
	Color("a33b1f"),  # pelirrojo
	Color("b8b8b8"),  # canoso
]

const EYE_COLORS: Array[Color] = [
	Color("3b2412"),  # marrón oscuro
	Color("8a5a2b"),  # miel
	Color("4a7a3a"),  # verde
	Color("3a6ea5"),  # azul
	Color("7a8a8f"),  # gris
]

const CLOTHES_COLORS: Array[Color] = [
	Color("b13030"),  # rojo
	Color("d97a2b"),  # naranja
	Color("e0c040"),  # amarillo
	Color("3f9d4a"),  # verde
	Color("3a6ea5"),  # azul
	Color("7a3f9d"),  # púrpura
	Color("2fa6a0"),  # turquesa
	Color("c75b9c"),  # rosa
]

## Combinación canónica (índice de cada paleta) que usan TODOS los jugadores. Los
## NPCs nunca pueden quedar exactamente en esta terna (ver random_npc_appearance).
const PLAYER_PALETTE := { "pelo": 0, "ojos": 0, "ropa": 0 }

const PLAYER_MODEL_INDEX := 0
const WALK_ANIMATION_OVERRIDES := {}
const IDLE_ANIMATION_OVERRIDES := {}

## Instancia el modelo .glb indicado, envuelto en un wrapper Node3D re-centrado.
## Devuelve el wrapper (o null si el indice es invalido).

static func build_model(model_index: int) -> Node3D:
	if model_index < 0 or model_index >= MODEL_PATHS.size():
		push_error("CharacterAppearance: indice de modelo invalido %d" % model_index)
		return null

	var scene: PackedScene = load(MODEL_PATHS[model_index])
	if scene == null:
		push_error("CharacterAppearance: no se pudo cargar %s (¿esta importado?)" % MODEL_PATHS[model_index])
		return null

	var glb := scene.instantiate() as Node3D
	var wrapper := Node3D.new()
	wrapper.name = "ModelWrapper"
	wrapper.add_child(glb)
	glb.position = -_recenter_offset(glb)
	return wrapper


## Offset (en espacio del .glb) de la base-centro de la malla respecto del origen.
static func _recenter_offset(glb: Node) -> Vector3:
	var aabb := _combined_mesh_aabb(glb)
	if aabb.size == Vector3.ZERO:
		return Vector3.ZERO
	return Vector3(
		aabb.position.x + aabb.size.x * 0.5,  # centro horizontal X
		aabb.position.y,                       # base (pies)
		aabb.position.z + aabb.size.z * 0.5,  # centro horizontal Z
	)


## AABB combinado de las mallas, en el espacio local de `root` (asumiendo que las
## MeshInstance3D estan bajo un Skeleton3D a identidad, como en estos .glb).
static func _combined_mesh_aabb(root: Node) -> AABB:
	var result := AABB()
	var first := true
	for node in _collect_mesh_instances(root):
		var mi := node as MeshInstance3D
		var box: AABB = mi.transform * mi.get_aabb()
		if first:
			result = box
			first = false
		else:
			result = result.merge(box)
	return result


## Recolorea partes del modelo segun part_colors (nombre_material_parcial -> Color).
## Duplica cada material afectado para que la instancia no comparta materiales con otras.
static func apply_part_colors(model_root: Node3D, part_colors: Dictionary) -> void:
	if model_root == null or part_colors.is_empty():
		return

	for node in _collect_mesh_instances(model_root):
		var mesh_instance := node as MeshInstance3D
		var surface_count := mesh_instance.get_surface_override_material_count()
		for i in range(surface_count):
			var material := mesh_instance.get_active_material(i)
			if material == null:
				continue

			var mat_name := material.resource_name.to_lower()
			for key in part_colors:
				if mat_name.begins_with(String(key)):
					var tinted := material.duplicate() as BaseMaterial3D
					if tinted != null:
						tinted.albedo_color = part_colors[key]
						mesh_instance.set_surface_override_material(i, tinted)
					break


## Devuelve el primer AnimationPlayer dentro del modelo (o null).
static func find_animation_player(model_root: Node) -> AnimationPlayer:
	if model_root == null:
		return null

	var matches := model_root.find_children("*", "AnimationPlayer", true, false)
	if matches.is_empty():
		return null

	return matches[0] as AnimationPlayer


## Reproduce en loop la animacion de caminata del modelo `model_index`.
static func play_walk(anim_player: AnimationPlayer, model_index: int) -> void:
	if anim_player == null:
		return

	var anim_name := _walk_animation_name(anim_player, model_index)
	if anim_name.is_empty():
		return

	var anim := anim_player.get_animation(anim_name)
	if anim != null:
		anim.loop_mode = Animation.LOOP_LINEAR
		_strip_root_motion(anim)

	anim_player.play(anim_name)


## Reproduce idle si el modelo lo trae; si no, deja congelada la pose actual.
static func play_idle(anim_player: AnimationPlayer, model_index: int) -> void:
	if anim_player == null:
		return

	var anim_name := _idle_animation_name(anim_player, model_index)
	if anim_name.is_empty():
		anim_player.pause()
		return

	var anim := anim_player.get_animation(anim_name)
	if anim != null:
		anim.loop_mode = Animation.LOOP_LINEAR
		_strip_root_motion(anim)

	anim_player.play(anim_name)


## Colores de las partes del JUGADOR: Todos los jugadores lucen igual.
static func player_part_colors() -> Dictionary:
	return {
		"pelo": HAIR_COLORS[int(PLAYER_PALETTE["pelo"])],
		"ojos": EYE_COLORS[int(PLAYER_PALETTE["ojos"])],
		"ropa": CLOTHES_COLORS[int(PLAYER_PALETTE["ropa"])],
	}


## Genera una apariencia de NPC: modelo aleatorio + pelo/ojos/ropa elegidos de laspaletas. 
static func random_npc_appearance(rng: RandomNumberGenerator) -> Dictionary:
	var hi := rng.randi_range(0, HAIR_COLORS.size() - 1)
	var ei := rng.randi_range(0, EYE_COLORS.size() - 1)
	var ci := rng.randi_range(0, CLOTHES_COLORS.size() - 1)

	# Evitar exactamente la terna del jugador.
	if hi == int(PLAYER_PALETTE["pelo"]) and ei == int(PLAYER_PALETTE["ojos"]) and ci == int(PLAYER_PALETTE["ropa"]):
		ci = (ci + 1) % CLOTHES_COLORS.size()

	return {
		"model": rng.randi_range(0, MODEL_COUNT - 1),
		"part_colors": {
			"pelo": HAIR_COLORS[hi],
			"ojos": EYE_COLORS[ei],
			"ropa": CLOTHES_COLORS[ci],
		},
	}


# ---------------------------------------------------------------------------
# Internos
# ---------------------------------------------------------------------------

static func _collect_mesh_instances(node: Node) -> Array:
	var result: Array = []
	if node is MeshInstance3D:
		result.append(node)
	for child in node.get_children():
		result.append_array(_collect_mesh_instances(child))
	return result


static func _find_skeleton(model_root: Node) -> Skeleton3D:
	if model_root == null:
		return null
	var matches := model_root.find_children("*", "Skeleton3D", true, false)
	if matches.is_empty():
		return null
	return matches[0] as Skeleton3D


static func _walk_animation_name(anim_player: AnimationPlayer, model_index: int) -> String:
	if WALK_ANIMATION_OVERRIDES.has(model_index):
		return WALK_ANIMATION_OVERRIDES[model_index]

	var names := anim_player.get_animation_list()
	if names.is_empty():
		return ""

	# Sin nombres descriptivos (vienen de Mixamo): usar el primer clip.
	return names[0]


static func _idle_animation_name(anim_player: AnimationPlayer, model_index: int) -> String:
	if IDLE_ANIMATION_OVERRIDES.has(model_index):
		return IDLE_ANIMATION_OVERRIDES[model_index]

	var names := anim_player.get_animation_list()
	for name in names:
		if String(name).to_lower().find("idle") != -1:
			return name

	return ""


## Quita el "root motion" de la animacion porque sino el movimiento de "cadera" hace que se desplace el
## modelo del eje y se vea mal.
static func _strip_root_motion(anim: Animation) -> void:
	for t in range(anim.get_track_count()):
		if anim.track_get_type(t) != Animation.TYPE_POSITION_3D:
			continue
		if String(anim.track_get_path(t)).to_lower().find("hips") == -1:
			continue

		anim.remove_track(t)
		return

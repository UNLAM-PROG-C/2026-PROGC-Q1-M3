extends Node3D

@export var npc_scene: PackedScene
@export var path_node_path: NodePath
@export var paths_root_path: NodePath
@export var path_name_prefix := "NPCPath"
@export var npcs_per_player := 30
@export var worker_count := 4
@export var movement_radius := 1.25
@export var movement_speed := 3.0
@export var npc_spacing := 1.8
@export var hop_height := 0.0
@export var hop_frequency := 7.5
@export var random_offset_min := 0.10
@export var random_offset_max := 0.50
@export var player_detection_radius := 4.0
@export var look_at_player_duration_min := 1.0
@export var look_at_player_duration_max := 3.0
@export_range(0.0, 1.0, 0.05) var look_at_player_chance := 0.30
@export_range(0.0, 1.0, 0.05) var sprint_chance := 0.10
@export var sprint_duration_min := 1.0
@export var sprint_duration_max := 3.0
@export var sprint_speed_multiplier := 2.0
@export var sprint_check_interval := 3.0

var _workers: Array[Thread] = []
var _job_semaphore := Semaphore.new()
var _job_mutex := Mutex.new()
var _state_mutex := Mutex.new()
var _rng := RandomNumberGenerator.new()
var _jobs: Array[Dictionary] = []
var _states: Array[Dictionary] = []
var _npcs: Array[Node3D] = []
var _origins: Array[Vector3] = []
var _path_distance_offsets: Array[float] = []
var _lateral_offsets: Array[float] = []
var _pause_until_times: Array[float] = []
var _pause_elapsed_offsets: Array[float] = []
var _player_was_near: Array[bool] = []
var _look_rotation_y: Array[float] = []
var _reacts_to_players: Array[bool] = []
var _sprint_until_times: Array[float] = []
var _sprint_movement_offsets: Array[float] = []
var _next_sprint_check_times: Array[float] = []
var _path_caches: Array[Dictionary] = []
var _path_assignments: Array[int] = []
var _path_assignment_counts: Array[int] = []
var _running := false
var _queued_jobs := 0
var _finished_jobs := 0
var _elapsed_time := 0.0


func _ready():
	if npc_scene == null:
		npc_scene = preload("res://scenes/npc/threaded_npc.tscn")

	_rng.randomize()
	_refresh_path_cache()
	_start_workers()
	set_player_count(_get_current_player_count())


func _process(delta):
	_elapsed_time += delta
	_apply_finished_states()
	_update_npc_player_reactions(delta)
	_update_npc_sprints(delta)
	_queue_frame_jobs()


func _exit_tree():
	_stop_workers()


func set_player_count(player_count: int):
	_refresh_path_cache()
	var npc_count: int = int(max(1, player_count)) * npcs_per_player
	_rebuild_npcs(npc_count)


func refresh_path():
	_wait_for_pending_jobs()
	_refresh_path_cache()


func _get_current_player_count() -> int:
	if "--debug_solo" in OS.get_cmdline_args():
		return 1

	if multiplayer.has_multiplayer_peer():
		return multiplayer.get_peers().size() + 1

	return 1


func _start_workers():
	_running = true
	var count: int = int(max(1, worker_count))

	for i in range(count):
		var worker := Thread.new()
		_workers.append(worker)
		worker.start(_worker_loop)


func _stop_workers():
	_job_mutex.lock()
	_running = false
	_job_mutex.unlock()

	for worker in _workers:
		_job_semaphore.post()

	for worker in _workers:
		if worker.is_started():
			worker.wait_to_finish()

	_workers.clear()


func _rebuild_npcs(npc_count: int):
	_wait_for_pending_jobs()

	for npc in _npcs:
		npc.queue_free()

	_npcs.clear()
	_origins.clear()
	_states.clear()
	_path_distance_offsets.clear()
	_lateral_offsets.clear()
	_pause_until_times.clear()
	_pause_elapsed_offsets.clear()
	_player_was_near.clear()
	_look_rotation_y.clear()
	_reacts_to_players.clear()
	_sprint_until_times.clear()
	_sprint_movement_offsets.clear()
	_next_sprint_check_times.clear()
	_path_assignments.clear()
	_path_assignment_counts.clear()

	_build_balanced_path_assignments(npc_count)
	var path_used_counts: Array[int] = []
	for i in range(_path_caches.size()):
		path_used_counts.append(0)

	for i in range(npc_count):
		_path_distance_offsets.append(_balanced_path_distance(i, path_used_counts))
		_lateral_offsets.append(_random_signed_offset())
		_pause_until_times.append(0.0)
		_pause_elapsed_offsets.append(0.0)
		_player_was_near.append(false)
		_look_rotation_y.append(0.0)
		_reacts_to_players.append(_rng.randf() <= look_at_player_chance)
		_sprint_until_times.append(0.0)
		_sprint_movement_offsets.append(0.0)
		_next_sprint_check_times.append(_elapsed_time + _rng.randf_range(0.0, sprint_check_interval))

		var npc := npc_scene.instantiate() as Node3D
		var origin := _calculate_origin(i)

		npc.name = "ThreadedNPC_%02d" % i
		npc.position = origin
		add_child(npc)
		# Cada NPC recolorea al menos el pelo, por lo que nunca queda identico a un
		# jugador que use el mismo modelo.
		npc.setup(CharacterAppearance.random_npc_appearance(_rng))
		npc.npc_index = i  # usado por player.gd para reportar muertes al servidor

		_npcs.append(npc)
		_origins.append(origin)
		_states.append({
			"position": origin,
			"rotation_y": 0.0,
			"is_idle": false,
		})


func _calculate_origin(index: int) -> Vector3:
	var path_cache := _get_path_cache(index)
	if not path_cache.is_empty():
		var distance: float = _calculate_path_distance(index)
		var sample: Dictionary = _sample_path(
			path_cache["points"],
			float(path_cache["length"]),
			distance,
			bool(path_cache.get("is_closed", false))
		)
		return sample["position"] + sample["right"] * _calculate_lateral_offset(index)

	var columns: int = int(max(1, int(ceil(sqrt(float(npcs_per_player))))))
	var player_index: int = int(index / npcs_per_player)
	var local_index: int = index % npcs_per_player
	var x: float = float(local_index % columns) * npc_spacing
	var z: float = float(int(local_index / columns)) * npc_spacing
	var player_offset: Vector3 = Vector3(float(player_index) * npc_spacing * float(columns + 2), 0.0, 0.0)

	return Vector3(-6.0 + x, 1.0, -6.0 + z) + player_offset


## Retorna la posicion global del NPC en el indice dado, o Vector3.ZERO si no existe / ya murio.
func get_npc_position(index: int) -> Vector3:
	if index < 0 or index >= _npcs.size():
		return Vector3.ZERO
	var npc := _npcs[index]
	if not is_instance_valid(npc) or npc.is_dead():
		return Vector3.ZERO
	return npc.global_position


## Mata el NPC en el indice dado (llamado desde game.gd vía RPC apply_npc_kill).
func kill_npc(index: int) -> void:
	if index < 0 or index >= _npcs.size():
		return
	var npc := _npcs[index]
	if is_instance_valid(npc) and not npc.is_dead():
		npc.kill_npc()


func _queue_frame_jobs():
	if _has_pending_jobs() or _npcs.is_empty():
		return

	var jobs: Array[Dictionary] = []

	for i in range(_npcs.size()):
		# No encolar jobs para NPCs muertos: su apply_simulation_state retorna early,
		# pero es más eficiente no calcularlos en los workers.
		if is_instance_valid(_npcs[i]) and _npcs[i].is_dead():
			continue
		var is_paused := _is_npc_paused(i)
		jobs.append({
			"index": i,
			"origin": _origins[i],
			"time": _elapsed_time - _get_pause_elapsed_offset(i),
			"phase": float(i) * 0.37,
			"movement_radius": movement_radius,
			"movement_speed": movement_speed,
			"hop_height": hop_height,
			"hop_frequency": hop_frequency,
			"path_cache": _get_path_cache(i),
			"path_offset": _calculate_path_distance(i),
			"lateral_offset": _calculate_lateral_offset(i),
			"is_paused": is_paused,
			"paused_position": _states[i]["position"],
			"look_rotation_y": _get_look_rotation_y(i),
			"is_sprinting": _is_npc_sprinting(i),
			"sprint_movement_offset": _get_sprint_movement_offset(i),
		})

	_job_mutex.lock()
	_jobs.append_array(jobs)
	_queued_jobs = jobs.size()
	_finished_jobs = 0
	_job_mutex.unlock()

	for i in range(jobs.size()):
		_job_semaphore.post()


func _has_pending_jobs() -> bool:
	_job_mutex.lock()
	var pending: bool = _queued_jobs > 0 and _finished_jobs < _queued_jobs
	_job_mutex.unlock()
	return pending


func _apply_finished_states():
	if _npcs.is_empty():
		return

	_state_mutex.lock()
	var states: Array = _states.duplicate(true)
	_state_mutex.unlock()

	for i in range(int(min(_npcs.size(), states.size()))):
		_npcs[i].apply_simulation_state(states[i]["position"], states[i]["rotation_y"], bool(states[i].get("is_idle", false)))


func _wait_for_pending_jobs():
	while _has_pending_jobs():
		OS.delay_msec(1)


# precalculo y guardado en cache de los puntos del path con su longitud total
func _refresh_path_cache():
	_path_caches.clear()

	var paths: Array[Path3D] = _find_npc_paths()
	for path in paths:
		if path.curve == null:
			continue
		var baked_points: PackedVector3Array = path.curve.get_baked_points()
		var points: Array[Vector3] = []
		for point in baked_points:
			points.append(path.to_global(point))
		var is_closed := bool(path.curve.get("closed"))
		var length := _calculate_path_length(points, is_closed)
		if length <= 0.0:
			continue
		_path_caches.append({
			"points": points,
			"length": length,
			"is_closed": is_closed,
		})


func _find_npc_paths() -> Array[Path3D]:
	var paths: Array[Path3D] = []

	if not String(path_node_path).is_empty():
		var explicit_path: Path3D = get_node_or_null(path_node_path) as Path3D
		if explicit_path != null:
			paths.append(explicit_path)

	var root: Node = null
	if not String(paths_root_path).is_empty():
		root = get_node_or_null(paths_root_path)
	if root == null:
		root = get_parent()
	if root == null:
		return paths

	_collect_npc_paths(root, paths)
	return paths


func _collect_npc_paths(node: Node, paths: Array[Path3D]) -> void:
	if node is Path3D and _is_npc_path(node):
		var path := node as Path3D
		if not paths.has(path):
			paths.append(path)

	for child in node.get_children():
		_collect_npc_paths(child, paths)


func _is_npc_path(node: Node) -> bool:
	if path_name_prefix.is_empty():
		return true
	return String(node.name).begins_with(path_name_prefix)


func _build_balanced_path_assignments(npc_count: int) -> void:
	if _path_caches.is_empty():
		return

	var path_count := _path_caches.size()
	var assignments: Array[int] = []
	for i in range(path_count):
		_path_assignment_counts.append(0)

	for i in range(npc_count):
		assignments.append(i % path_count)

	for i in range(assignments.size() - 1, 0, -1):
		var swap_index := _rng.randi_range(0, i)
		var value := assignments[i]
		assignments[i] = assignments[swap_index]
		assignments[swap_index] = value

	for assignment in assignments:
		var path_index := int(assignment)
		_path_assignments.append(path_index)
		_path_assignment_counts[path_index] += 1


func _calculate_path_length(points: Array[Vector3], is_closed: bool = false) -> float:
	if points.size() < 2:
		return 0.0

	var length: float = 0.0
	var segment_count := points.size()
	if not is_closed:
		segment_count -= 1

	for i in range(segment_count):
		length += points[i].distance_to(points[(i + 1) % points.size()])

	return length


# devuelve el punto en donde estaria si se recorren X de distancia sobre ese path
# ej: distance = 5, la func devuelve el punto en donde estaria si avanzo 5 sobre
#     el path
func _sample_path_position(distance: float) -> Vector3:
	var path_cache := _get_path_cache(0)
	if path_cache.is_empty():
		return Vector3.ZERO
	var sample: Dictionary = _sample_path(
		path_cache["points"],
		float(path_cache["length"]),
		distance,
		bool(path_cache.get("is_closed", false))
	)
	return sample["position"]


func _calculate_path_distance(index: int) -> float:
	return _get_offset(_path_distance_offsets, index)


func _calculate_lateral_offset(index: int) -> float:
	return _get_offset(_lateral_offsets, index)


func _get_pause_elapsed_offset(index: int) -> float:
	return _get_offset(_pause_elapsed_offsets, index)


func _get_look_rotation_y(index: int) -> float:
	return _get_offset(_look_rotation_y, index)


func _is_npc_paused(index: int) -> bool:
	return index >= 0 and index < _pause_until_times.size() and _elapsed_time < _pause_until_times[index]


func _reacts_to_player(index: int) -> bool:
	return index >= 0 and index < _reacts_to_players.size() and _reacts_to_players[index]


func _random_look_at_player_duration() -> float:
	var min_duration := look_at_player_duration_min
	var max_duration := look_at_player_duration_max
	if min_duration > max_duration:
		min_duration = look_at_player_duration_max
		max_duration = look_at_player_duration_min
	return _rng.randf_range(min_duration, max_duration)


func _get_sprint_movement_offset(index: int) -> float:
	return _get_offset(_sprint_movement_offsets, index)


func _is_npc_sprinting(index: int) -> bool:
	return index >= 0 and index < _sprint_until_times.size() and _elapsed_time < _sprint_until_times[index]


func _random_sprint_duration() -> float:
	var min_duration := sprint_duration_min
	var max_duration := sprint_duration_max
	if min_duration > max_duration:
		min_duration = sprint_duration_max
		max_duration = sprint_duration_min
	return _rng.randf_range(min_duration, max_duration)


func _update_npc_sprints(delta: float) -> void:
	if _npcs.is_empty():
		return

	var check_interval := sprint_check_interval
	if check_interval < 0.1:
		check_interval = 0.1

	var speed_multiplier := sprint_speed_multiplier
	if speed_multiplier < 1.0:
		speed_multiplier = 1.0

	for i in range(_npcs.size()):
		if _is_npc_paused(i):
			continue

		if _is_npc_sprinting(i):
			_sprint_movement_offsets[i] += movement_speed * (speed_multiplier - 1.0) * delta
			continue

		if i >= _next_sprint_check_times.size() or _elapsed_time < _next_sprint_check_times[i]:
			continue

		_next_sprint_check_times[i] = _elapsed_time + check_interval
		if _rng.randf() <= sprint_chance:
			_sprint_until_times[i] = _elapsed_time + _random_sprint_duration()
			_next_sprint_check_times[i] = _sprint_until_times[i] + check_interval


func _update_npc_player_reactions(delta: float) -> void:
	if _npcs.is_empty():
		return

	var players := get_tree().get_nodes_in_group("players")
	if players.is_empty():
		for i in range(_player_was_near.size()):
			_player_was_near[i] = false
		return

	var detection_radius_sq := player_detection_radius * player_detection_radius
	_state_mutex.lock()
	var states: Array = _states.duplicate(true)
	_state_mutex.unlock()

	for i in range(_npcs.size()):
		if _is_npc_paused(i):
			_pause_elapsed_offsets[i] += delta

		var npc_position: Vector3 = states[i]["position"]
		var nearest_player_position := Vector3.ZERO
		var nearest_distance_sq := INF

		for player in players:
			if not is_instance_valid(player) or not (player is Node3D):
				continue

			var player_position: Vector3 = (player as Node3D).global_position
			var distance_sq := npc_position.distance_squared_to(player_position)
			if distance_sq < nearest_distance_sq:
				nearest_distance_sq = distance_sq
				nearest_player_position = player_position

		var player_is_near := nearest_distance_sq <= detection_radius_sq
		if player_is_near:
			var look_direction := nearest_player_position - npc_position
			look_direction.y = 0.0
			if look_direction.length_squared() > 0.001:
				_look_rotation_y[i] = atan2(look_direction.x, look_direction.z)

			if _reacts_to_player(i) and not _player_was_near[i] and not _is_npc_paused(i):
				_pause_until_times[i] = _elapsed_time + _random_look_at_player_duration()

		_player_was_near[i] = player_is_near


func _random_signed_offset() -> float:
	var magnitude: float = _rng.randf_range(random_offset_min, random_offset_max)
	var sign: float = 1.0

	if _rng.randi_range(0, 1) == 0:
		sign = -1.0

	return magnitude * sign


func _balanced_path_distance(index: int, path_used_counts: Array[int]) -> float:
	var path_cache := _get_path_cache(index)
	if path_cache.is_empty():
		return 0.0

	var path_index := _get_assigned_path_index(index)
	var path_length := float(path_cache["length"])
	var path_total := 1
	if path_index >= 0 and path_index < _path_assignment_counts.size():
		path_total = int(max(1, _path_assignment_counts[path_index]))

	var path_slot := 0
	if path_index >= 0 and path_index < path_used_counts.size():
		path_slot = path_used_counts[path_index]
		path_used_counts[path_index] += 1

	var slot_size := path_length / float(path_total)
	var jitter := _rng.randf_range(-0.35, 0.35) * slot_size
	return fposmod((float(path_slot) + 0.5) * slot_size + jitter, path_length)


func _get_path_cache(index: int) -> Dictionary:
	if _path_caches.is_empty():
		return {}

	var path_index := _get_assigned_path_index(index)
	return _path_caches[path_index]


func _get_assigned_path_index(index: int) -> int:
	if _path_caches.is_empty():
		return 0

	var path_index := 0
	if index >= 0 and index < _path_assignments.size():
		path_index = _path_assignments[index]
	return posmod(path_index, _path_caches.size())


func _get_offset(offsets: Array[float], index: int) -> float:
	if index >= 0 and index < offsets.size():
		return offsets[index]

	return 0.0


## func que reparte la simulacion de NPCs entre varios hilos
## esto es para que en vez de tener 500 NPCs en un hilo principal
## se separen en varios workers
## ej: worker 1: NPC 10, NPC 7 y NPC 2
##     worker 2: NPC 3, NPC 9 y NPC 1
func _worker_loop():
	while true:
		_job_semaphore.wait()

		_job_mutex.lock()
		if not _running and _jobs.is_empty():
			_job_mutex.unlock()
			break

		if _jobs.is_empty():
			_job_mutex.unlock()
			continue

		var job: Dictionary = _jobs.pop_back()
		_job_mutex.unlock()

		var state: Dictionary = _simulate_npc(job)

		_state_mutex.lock()
		_states[int(job["index"])] = state
		_state_mutex.unlock()

		_job_mutex.lock()
		_finished_jobs += 1
		_job_mutex.unlock()


## movimiento tipo saltito del NPC + si no hay path se mueve en circulo 
func _simulate_npc(job: Dictionary) -> Dictionary:
	if bool(job["is_paused"]):
		return {
			"position": job["paused_position"],
			"rotation_y": float(job["look_rotation_y"]),
			"is_idle": true,
		}

	var time: float = float(job["time"])
	var phase: float = float(job["phase"])
	var origin: Vector3 = job["origin"]
	var radius: float = float(job["movement_radius"])
	var speed: float = float(job["movement_speed"])
	var sprint_movement_offset: float = float(job["sprint_movement_offset"])
	var hop: float = abs(sin(time * float(job["hop_frequency"]) + phase)) * float(job["hop_height"])
	var angle: float = time * speed + phase + sprint_movement_offset
	var next_position: Vector3
	var rotation_y: float

	var path_cache: Dictionary = job["path_cache"]
	if not path_cache.is_empty():
		var points: Array = path_cache["points"]
		var path_length := float(path_cache["length"])
		var distance: float = time * speed + sprint_movement_offset + float(job["path_offset"])
		var path_sample: Dictionary = _sample_path(
			points,
			path_length,
			distance,
			bool(path_cache.get("is_closed", false))
		)
		next_position = path_sample["position"] + path_sample["right"] * float(job["lateral_offset"])
		rotation_y = path_sample["rotation_y"]
	else:
		next_position = origin + Vector3(
			cos(angle) * radius,
			0.0,
			sin(angle) * radius
		)
		rotation_y = -angle

	next_position.y += hop

	return {
		"position": next_position,
		"rotation_y": rotation_y,
		"is_idle": false,
	}


## func para que un NPC se mueva sobre una lista de puntos como si fuera una 
## ruta
func _sample_path(points: Array, path_length: float, distance: float, is_closed: bool = false) -> Dictionary:
	if points.size() == 0:
		return {
			"position": Vector3.ZERO,
			"right": Vector3.RIGHT,
			"rotation_y": 0.0,
		}

	if points.size() == 1 or path_length <= 0.0:
		return {
			"position": points[0],
			"right": Vector3.RIGHT,
			"rotation_y": 0.0,
		}

	var wrapped_distance: float = fposmod(distance, path_length)
	var is_returning := false
	var segment_count := points.size()
	if not is_closed:
		var cycle_length: float = path_length * 2.0
		var cycle_distance: float = fposmod(distance, cycle_length)
		is_returning = cycle_distance > path_length
		if is_returning:
			wrapped_distance = cycle_length - cycle_distance
		else:
			wrapped_distance = cycle_distance
		segment_count -= 1

	var traveled: float = 0.0

	for i in range(segment_count):
		var from: Vector3 = points[i]
		var to: Vector3 = points[(i + 1) % points.size()]
		var segment_length: float = from.distance_to(to)
		if segment_length <= 0.001:
			continue

		if traveled + segment_length >= wrapped_distance:
			var t: float = (wrapped_distance - traveled) / segment_length
			var segment_direction: Vector3 = (to - from).normalized()
			var facing_direction: Vector3 = segment_direction
			if is_returning:
				facing_direction = -facing_direction

			return {
				"position": from.lerp(to, t),
				"right": segment_direction.cross(Vector3.UP).normalized(),
				"rotation_y": atan2(facing_direction.x, facing_direction.z),
			}

		traveled += segment_length

	var last_from_index := points.size() - 2
	var last_to_index := points.size() - 1
	if is_closed:
		last_from_index = points.size() - 1
		last_to_index = 0
	var last_segment_direction: Vector3 = (points[last_to_index] - points[last_from_index]).normalized()
	var last_facing_direction: Vector3 = last_segment_direction
	if is_returning:
		last_facing_direction = -last_facing_direction

	return {
		"position": points[points.size() - 1],
		"right": last_segment_direction.cross(Vector3.UP).normalized(),
		"rotation_y": atan2(last_facing_direction.x, last_facing_direction.z),
	}

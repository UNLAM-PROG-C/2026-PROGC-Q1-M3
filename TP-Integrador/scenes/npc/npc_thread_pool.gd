extends Node3D

@export var npc_scene: PackedScene
@export var path_node_path: NodePath
@export var npcs_per_player := 30
@export var worker_count := 4
@export var movement_radius := 1.25
@export var movement_speed := 1.5
@export var npc_spacing := 1.8
@export var hop_height := 0.18
@export var hop_frequency := 7.5
@export var random_offset_min := 0.10
@export var random_offset_max := 0.50

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
var _path_points: Array[Vector3] = []
var _path_length: float = 0.0
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

	for i in range(npc_count):
		_path_distance_offsets.append(_random_path_distance())
		_lateral_offsets.append(_random_signed_offset())

		var npc := npc_scene.instantiate() as Node3D
		var origin := _calculate_origin(i)

		npc.name = "ThreadedNPC_%02d" % i
		npc.position = origin
		add_child(npc)

		_npcs.append(npc)
		_origins.append(origin)
		_states.append({
			"position": origin,
			"rotation_y": 0.0,
		})


func _calculate_origin(index: int) -> Vector3:
	if not _path_points.is_empty():
		var distance: float = _calculate_path_distance(index)
		var sample: Dictionary = _sample_path(_path_points, _path_length, distance)
		return sample["position"] + sample["right"] * _calculate_lateral_offset(index)

	var columns: int = int(max(1, int(ceil(sqrt(float(npcs_per_player))))))
	var player_index: int = int(index / npcs_per_player)
	var local_index: int = index % npcs_per_player
	var x: float = float(local_index % columns) * npc_spacing
	var z: float = float(int(local_index / columns)) * npc_spacing
	var player_offset: Vector3 = Vector3(float(player_index) * npc_spacing * float(columns + 2), 0.0, 0.0)

	return Vector3(-6.0 + x, 1.0, -6.0 + z) + player_offset


func _queue_frame_jobs():
	if _has_pending_jobs() or _npcs.is_empty():
		return

	var jobs: Array[Dictionary] = []

	for i in range(_npcs.size()):
		jobs.append({
			"index": i,
			"origin": _origins[i],
			"time": _elapsed_time,
			"phase": float(i) * 0.37,
			"movement_radius": movement_radius,
			"movement_speed": movement_speed,
			"hop_height": hop_height,
			"hop_frequency": hop_frequency,
			"path_points": _path_points,
			"path_length": _path_length,
			"path_offset": _calculate_path_distance(i),
			"lateral_offset": _calculate_lateral_offset(i),
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
		_npcs[i].apply_simulation_state(states[i]["position"], states[i]["rotation_y"])


func _wait_for_pending_jobs():
	while _has_pending_jobs():
		OS.delay_msec(1)


# precalculo y guardado en cache de los puntos del path con su longitud total
func _refresh_path_cache():
	_path_points.clear()
	_path_length = 0.0

	if String(path_node_path).is_empty():
		return

	var path: Path3D = get_node_or_null(path_node_path) as Path3D
	if path == null or path.curve == null:
		return

	var baked_points: PackedVector3Array = path.curve.get_baked_points()
	for point in baked_points:
		_path_points.append(path.to_global(point))

	_path_length = _calculate_path_length(_path_points)


func _calculate_path_length(points: Array[Vector3]) -> float:
	var length: float = 0.0

	for i in range(points.size() - 1):
		length += points[i].distance_to(points[i + 1])

	return length


# devuelve el punto en donde estaria si se recorren X de distancia sobre ese path
# ej: distance = 5, la func devuelve el punto en donde estaria si avanzo 5 sobre
#     el path
func _sample_path_position(distance: float) -> Vector3:
	var sample: Dictionary = _sample_path(_path_points, _path_length, distance)
	return sample["position"]


func _calculate_path_distance(index: int) -> float:
	return _get_offset(_path_distance_offsets, index)


func _calculate_lateral_offset(index: int) -> float:
	return _get_offset(_lateral_offsets, index)


func _random_signed_offset() -> float:
	var magnitude: float = _rng.randf_range(random_offset_min, random_offset_max)
	var sign: float = 1.0

	if _rng.randi_range(0, 1) == 0:
		sign = -1.0

	return magnitude * sign


func _random_path_distance() -> float:
	if _path_length <= 0.0:
		return 0.0

	return _rng.randf_range(0.0, _path_length)


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
	var time: float = float(job["time"])
	var phase: float = float(job["phase"])
	var origin: Vector3 = job["origin"]
	var radius: float = float(job["movement_radius"])
	var speed: float = float(job["movement_speed"])
	var hop: float = abs(sin(time * float(job["hop_frequency"]) + phase)) * float(job["hop_height"])
	var angle: float = time * speed + phase
	var next_position: Vector3
	var rotation_y: float

	if float(job["path_length"]) > 0.0:
		var points: Array = job["path_points"]
		var distance: float = time * speed * 2.0 + float(job["path_offset"])
		var path_sample: Dictionary = _sample_path(points, float(job["path_length"]), distance)
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
	}


## func para que un NPC se mueva sobre una lista de puntos como si fuera una 
## ruta
func _sample_path(points: Array, path_length: float, distance: float) -> Dictionary:
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

	var cycle_length: float = path_length * 2.0
	var cycle_distance: float = fposmod(distance, cycle_length)
	var is_returning: bool = cycle_distance > path_length
	var wrapped_distance: float = path_length
	if is_returning:
		wrapped_distance = cycle_length - cycle_distance
	else:
		wrapped_distance = cycle_distance
	var traveled: float = 0.0

	for i in range(points.size() - 1):
		var from: Vector3 = points[i]
		var to: Vector3 = points[i + 1]
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

	var last_segment_direction: Vector3 = (points[points.size() - 1] - points[points.size() - 2]).normalized()
	var last_facing_direction: Vector3 = last_segment_direction
	if is_returning:
		last_facing_direction = -last_facing_direction

	return {
		"position": points[points.size() - 1],
		"right": last_segment_direction.cross(Vector3.UP).normalized(),
		"rotation_y": atan2(last_facing_direction.x, last_facing_direction.z),
	}

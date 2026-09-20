## ADR-003 spike harness (docs/specs/spike-surface-nets-deck.md). Streams volumetric
## chunks around a moving camera, digs every few seconds, uploads meshes with a per-frame
## cap, records raw frame times and meshing cost, and writes a JSON report at the end.
##
## Args after "--": duration=<s> workers=<n> radius=<chunks> vradius=<chunks>
##   uploads=<per frame> speed=<m/s> edit_interval=<s> seed=<n> out=<path> mode=soak|bench
extends Node3D

const CHUNK: int = 32
const PATH_RADIUS: float = 400.0
const CAMERA_HEIGHT: float = 20.0
const DIG_RADIUS: float = 3.0
const BUDGET_MS: float = 25.0
const MESHING_BUDGET_MS: float = 3.0
const FINAL_WINDOW_S: float = 300.0

var _duration: float = 1800.0
var _workers: int = 3
var _radius: int = 5
var _vradius: int = 2
var _uploads_per_frame: int = 4
var _speed: float = 8.0
var _edit_interval: float = 2.0
var _seed: int = 20260920
var _out_path: String = "spike_result.json"
var _mode: String = "soak"

var _world: VoxelWorld
var _camera: Camera3D
var _material: StandardMaterial3D
var _hud: Label
var _chunks: Dictionary = {}  # Vector3i -> MeshInstance3D
var _tris: Dictionary = {}  # Vector3i -> int
var _wanted: Dictionary = {}  # Vector3i -> true
var _camera_chunk: Vector3i = Vector3i(1 << 30, 0, 0)
var _angle: float = 0.0
var _elapsed: float = 0.0
var _since_edit: float = 0.0
var _edits_done: int = 0
var _started: bool = false
var _finished: bool = false

# Per-frame records for the whole run.
var _frame_t: PackedFloat64Array = PackedFloat64Array()
var _frame_ms: PackedFloat64Array = PackedFloat64Array()
var _frame_upload_us: PackedFloat64Array = PackedFloat64Array()
var _frame_worker_us: PackedFloat64Array = PackedFloat64Array()
var _frame_chunks: PackedInt32Array = PackedInt32Array()
var _minutes: Array[Dictionary] = []
var _next_minute: float = 60.0
var _peak_backlog: int = 0
var _empty_results: int = 0
var _total_gen_us: int = 0
var _total_mesh_us: int = 0
var _total_meshed_chunks: int = 0


func _ready() -> void:
	_parse_args()
	Engine.max_fps = 0
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	_world = VoxelWorld.new()
	_world.setup(_seed, _workers)
	if _mode == "bench":
		call_deferred("_run_bench")
		return
	_build_scene()
	_started = true
	print("spike: soak duration=%ds workers=%d radius=%d vradius=%d uploads=%d speed=%.1f edit_interval=%.1f seed=%d"
		% [int(_duration), _workers, _radius, _vradius, _uploads_per_frame, _speed, _edit_interval, _seed])


func _parse_args() -> void:
	for arg: String in OS.get_cmdline_user_args():
		var kv: PackedStringArray = arg.split("=", true, 1)
		if kv.size() != 2:
			continue
		var key: String = kv[0].trim_prefix("--")
		var value: String = kv[1]
		match key:
			"duration": _duration = float(value)
			"workers": _workers = int(value)
			"radius": _radius = int(value)
			"vradius": _vradius = int(value)
			"uploads": _uploads_per_frame = int(value)
			"speed": _speed = float(value)
			"edit_interval": _edit_interval = float(value)
			"seed": _seed = int(value)
			"out": _out_path = value
			"mode": _mode = value
			_: push_warning("unknown arg " + key)


func _build_scene() -> void:
	_camera = Camera3D.new()
	_camera.far = 700.0
	_camera.fov = 75.0
	add_child(_camera)
	var sun: DirectionalLight3D = DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50.0, 30.0, 0.0)
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 200.0
	add_child(sun)
	var env: Environment = Environment.new()
	env.background_mode = Environment.BG_SKY
	var sky: Sky = Sky.new()
	sky.sky_material = ProceduralSkyMaterial.new()
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.fog_enabled = true
	env.fog_density = 0.002
	var we: WorldEnvironment = WorldEnvironment.new()
	we.environment = env
	add_child(we)
	_material = StandardMaterial3D.new()
	_material.albedo_color = Color(0.45, 0.5, 0.38)
	_material.roughness = 1.0
	_hud = Label.new()
	_hud.position = Vector2(12.0, 8.0)
	_hud.add_theme_font_size_override("font_size", 18)
	add_child(_hud)
	_place_camera(0.0)


func _place_camera(dt: float) -> void:
	_angle += _speed * dt / PATH_RADIUS
	var x: float = cos(_angle) * PATH_RADIUS
	var z: float = sin(_angle) * PATH_RADIUS
	var y: float = _world.terrain_height(x, z) + CAMERA_HEIGHT
	_camera.position = Vector3(x, y, z)
	var ahead: Vector3 = _ahead_point(40.0)
	_camera.look_at(Vector3(ahead.x, ahead.y - 8.0, ahead.z), Vector3.UP)


func _ahead_point(distance: float) -> Vector3:
	var a: float = _angle + distance / PATH_RADIUS
	var x: float = cos(a) * PATH_RADIUS
	var z: float = sin(a) * PATH_RADIUS
	return Vector3(x, _world.terrain_height(x, z), z)


func _process(delta: float) -> void:
	if not _started or _finished:
		return
	_elapsed += delta
	_since_edit += delta
	_place_camera(delta)
	_update_streaming()
	if _since_edit >= _edit_interval:
		_since_edit = 0.0
		_dig()
	var upload_us: int = 0
	var worker_us: int = 0
	var uploaded: int = 0
	var results: Array = _world.poll(_uploads_per_frame)
	for r: Variant in results:
		var d: Dictionary = r
		var t0: int = Time.get_ticks_usec()
		_apply_result(d)
		upload_us += Time.get_ticks_usec() - t0
		var gen_us: int = d["gen_us"]
		var mesh_us: int = d["mesh_us"]
		worker_us += gen_us + mesh_us
		_total_gen_us += gen_us
		_total_mesh_us += mesh_us
		_total_meshed_chunks += 1
		uploaded += 1
	_frame_t.append(_elapsed)
	_frame_ms.append(delta * 1000.0)
	_frame_upload_us.append(float(upload_us))
	_frame_worker_us.append(float(worker_us))
	_frame_chunks.append(uploaded)
	if _elapsed >= _next_minute:
		_next_minute += 60.0
		_record_minute()
	if Engine.get_process_frames() % 10 == 0:
		_update_hud()
	if _elapsed >= _duration:
		_finish()


func _update_streaming() -> void:
	var cc: Vector3i = Vector3i(
		floori(_camera.position.x / CHUNK), floori(_camera.position.y / CHUNK), floori(_camera.position.z / CHUNK))
	if cc == _camera_chunk:
		return
	_camera_chunk = cc
	var still_wanted: Dictionary = {}
	var r2: int = _radius * _radius
	for dz: int in range(-_radius, _radius + 1):
		for dx: int in range(-_radius, _radius + 1):
			if dx * dx + dz * dz > r2:
				continue
			for dy: int in range(-_vradius, _vradius + 1):
				var c: Vector3i = cc + Vector3i(dx, dy, dz)
				still_wanted[c] = true
				if not _wanted.has(c):
					_wanted[c] = true
					_world.request(c, 100 + (dx * dx + dy * dy + dz * dz) * 10)
	for key: Variant in _wanted.keys():
		var c: Vector3i = key
		if not still_wanted.has(c):
			_wanted.erase(c)
			_world.cancel(c)
			_remove_chunk(c)


func _dig() -> void:
	var p: Vector3 = _ahead_point(20.0)
	var affected: Array[Vector3i] = _world.dig_sphere(p, DIG_RADIUS, 1.0)
	_edits_done += 1
	for c: Vector3i in affected:
		if _wanted.has(c):
			_world.request(c, 0)


func _apply_result(d: Dictionary) -> void:
	var c: Vector3i = d["coord"]
	if not _wanted.has(c):
		return
	var empty: bool = d["empty"]
	if empty:
		_empty_results += 1
		_remove_chunk(c)
		return
	var positions: PackedVector3Array = d["positions"]
	var normals: PackedVector3Array = d["normals"]
	var indices: PackedInt32Array = d["indices"]
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = positions
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh: ArrayMesh = ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	mesh.surface_set_material(0, _material)
	var mi: MeshInstance3D
	if _chunks.has(c):
		mi = _chunks[c]
	else:
		mi = MeshInstance3D.new()
		mi.position = Vector3(c) * float(CHUNK)
		add_child(mi)
		_chunks[c] = mi
	mi.mesh = mesh
	@warning_ignore("integer_division")
	_tris[c] = indices.size() / 3


func _remove_chunk(c: Vector3i) -> void:
	if _chunks.has(c):
		var mi: MeshInstance3D = _chunks[c]
		mi.queue_free()
		_chunks.erase(c)
		_tris.erase(c)


func _total_tris() -> int:
	var total: int = 0
	for v: Variant in _tris.values():
		var n: int = v
		total += n
	return total


func _backlog() -> int:
	var s: Dictionary = _world.stats()
	var queued: int = s["queued"]
	var in_flight: int = s["in_flight"]
	var waiting: int = s["results_waiting"]
	return queued + in_flight + waiting


static func _percentile(sorted: PackedFloat64Array, p: float) -> float:
	if sorted.is_empty():
		return 0.0
	var idx: int = clampi(int(ceilf(p * float(sorted.size()))) - 1, 0, sorted.size() - 1)
	return sorted[idx]


## Summary of frames with _frame_t in [t0, t1).
func _window_summary(t0: float, t1: float) -> Dictionary:
	var ms: PackedFloat64Array = PackedFloat64Array()
	var upload_us: float = 0.0
	var worker_us: float = 0.0
	var chunks: int = 0
	var over: int = 0
	for i: int in range(_frame_t.size()):
		if _frame_t[i] < t0 or _frame_t[i] >= t1:
			continue
		ms.append(_frame_ms[i])
		upload_us += _frame_upload_us[i]
		worker_us += _frame_worker_us[i]
		chunks += _frame_chunks[i]
		if _frame_ms[i] > BUDGET_MS:
			over += 1
	var frames: int = ms.size()
	ms.sort()
	var seconds: float = t1 - t0
	var f: float = maxf(float(frames), 1.0)
	return {
		"from_s": t0, "to_s": t1, "frames": frames, "fps_avg": float(frames) / maxf(seconds, 1e-6),
		"p50_ms": _percentile(ms, 0.50), "p99_ms": _percentile(ms, 0.99), "p999_ms": _percentile(ms, 0.999),
		"max_ms": _percentile(ms, 1.0), "over_budget_frac": float(over) / f,
		"worker_ms_per_frame": worker_us / 1000.0 / f, "upload_ms_per_frame": upload_us / 1000.0 / f,
		"meshing_ms_per_frame": (worker_us + upload_us) / 1000.0 / f,
		"meshing_ms_per_40fps_frame": (worker_us + upload_us) / 1000.0 / maxf(seconds, 1e-6) / 40.0,
		"upload_ms_per_40fps_frame": upload_us / 1000.0 / maxf(seconds, 1e-6) / 40.0,
		"chunks_uploaded": chunks, "chunks_per_s": float(chunks) / maxf(seconds, 1e-6),
		"upload_us_per_chunk": upload_us / maxf(float(chunks), 1.0),
		"worker_us_per_chunk": worker_us / maxf(float(chunks), 1.0),
	}


func _record_minute() -> void:
	var t1: float = _next_minute - 60.0
	var m: Dictionary = _window_summary(t1 - 60.0, t1)
	m["minute"] = _minutes.size() + 1
	m["resident_chunks"] = _chunks.size()
	m["wanted_chunks"] = _wanted.size()
	m["triangles"] = _total_tris()
	m["backlog"] = _backlog()
	m["edits"] = _edits_done
	_minutes.append(m)
	print("minute %2d  fps %.1f  p50 %.2f  p99 %.2f  p99.9 %.2f  over25 %.3f  meshing %.2f ms/40fps-frame  chunks/s %.1f  resident %d  tris %d  backlog %d"
		% [m["minute"], m["fps_avg"], m["p50_ms"], m["p99_ms"], m["p999_ms"], m["over_budget_frac"], m["meshing_ms_per_40fps_frame"],
		m["chunks_per_s"], m["resident_chunks"], m["triangles"], m["backlog"]])


func _update_hud() -> void:
	var b: int = _backlog()
	_peak_backlog = maxi(_peak_backlog, b)
	_hud.text = "surface-nets-deck  t=%4.0fs  fps %.0f  resident %d  tris %d  backlog %d  edits %d" % [
		_elapsed, Engine.get_frames_per_second(), _chunks.size(), _total_tris(), b, _edits_done]


func _finish() -> void:
	_finished = true
	var final: Dictionary = _window_summary(maxf(_duration - FINAL_WINDOW_S, 0.0), _duration + 1.0)
	var whole: Dictionary = _window_summary(0.0, _duration + 1.0)
	var s: Dictionary = _world.stats()
	var pass_frame: bool = final["p99_ms"] <= BUDGET_MS
	var pass_meshing: bool = final["meshing_ms_per_40fps_frame"] <= MESHING_BUDGET_MS
	var report: Dictionary = {
		"spike": "surface-nets-deck",
		"engine": Engine.get_version_info()["string"],
		"params": {"duration_s": _duration, "workers": _workers, "radius": _radius, "vradius": _vradius,
			"uploads_per_frame": _uploads_per_frame, "speed_m_s": _speed, "edit_interval_s": _edit_interval,
			"seed": _seed, "chunk": CHUNK, "dig_radius_m": DIG_RADIUS, "vsync": "disabled", "max_fps": 0},
		"final_window": final, "whole_run": whole, "minutes": _minutes,
		"worker_stats": s, "peak_backlog": _peak_backlog, "empty_results": _empty_results,
		"resident_chunks_end": _chunks.size(), "triangles_end": _total_tris(), "edits": _edits_done,
		"gen_us_per_meshed_chunk": float(_total_gen_us) / maxf(float(_total_meshed_chunks), 1.0),
		"mesh_us_per_meshed_chunk": float(_total_mesh_us) / maxf(float(_total_meshed_chunks), 1.0),
		"pass": {"frame_p99_within_25ms": pass_frame, "meshing_within_3ms": pass_meshing, "overall": pass_frame and pass_meshing},
	}
	var f: FileAccess = FileAccess.open(_out_path, FileAccess.WRITE)
	if f == null:
		push_error("cannot write " + _out_path)
	else:
		f.store_string(JSON.stringify(report, "  "))
		f.close()
	print("spike: done. final 5 min: p99 %.2f ms (%s), meshing %.2f ms/frame (%s) -> %s" % [
		final["p99_ms"], "pass" if pass_frame else "FAIL", final["meshing_ms_per_40fps_frame"],
		"pass" if pass_meshing else "FAIL", "PASS" if pass_frame and pass_meshing else "FAIL"])
	get_tree().quit(0 if (pass_frame and pass_meshing) else 3)


## Rust vs GDScript on the same samples (standards §9.2 Tier 1): equal output, ≥5× speed.
func _run_bench() -> void:
	var s: int = _world.sample_size()
	var coords: Array[Vector3i] = []
	for i: int in range(12):
		var x: float = cos(i * 0.7) * 300.0 + i * 37.0
		var z: float = sin(i * 0.9) * 300.0 - i * 23.0
		coords.append(Vector3i(floori(x / CHUNK), floori(_world.terrain_height(x, z) / CHUNK), floori(z / CHUNK)))
	var rows: Array[Dictionary] = []
	var rust_total: float = 0.0
	var gd_total: float = 0.0
	var all_equal: bool = true
	for c: Vector3i in coords:
		var samples: PackedFloat32Array = _world.sample_chunk(c)
		var rust_us: float = 0.0
		var rd: Dictionary = {}
		for k: int in range(5):
			rd = _world.mesh_samples(samples)
			var us: int = rd["mesh_us"]
			rust_us += float(us)
		rust_us /= 5.0
		var t0: int = Time.get_ticks_usec()
		var gd: Dictionary = SurfaceNetsGd.mesh(samples, s)
		var gd_us: float = float(Time.get_ticks_usec() - t0)
		var rp: PackedVector3Array = rd["positions"]
		var gp: PackedVector3Array = gd["positions"]
		var ri: PackedInt32Array = rd["indices"]
		var gi: PackedInt32Array = gd["indices"]
		var max_dev: float = 0.0
		var equal: bool = rp.size() == gp.size() and ri == gi
		if equal:
			for i: int in range(rp.size()):
				max_dev = maxf(max_dev, rp[i].distance_to(gp[i]))
			equal = max_dev < 1e-4
		all_equal = all_equal and equal
		rust_total += rust_us
		gd_total += gd_us
		var row: Dictionary = {"coord": [c.x, c.y, c.z], "vertices": rp.size(), "triangles": ri.size() / 3.0,
			"rust_us": rust_us, "gdscript_us": gd_us, "ratio": gd_us / maxf(rust_us, 1.0), "equal": equal, "max_position_dev": max_dev}
		rows.append(row)
		print("bench %s  verts %d  rust %.0f us  gdscript %.0f us  x%.1f  equal=%s" % [str(c), rp.size(), rust_us, gd_us, gd_us / maxf(rust_us, 1.0), str(equal)])
	var report: Dictionary = {"spike": "surface-nets-deck", "mode": "bench", "engine": Engine.get_version_info()["string"],
		"rows": rows, "rust_total_us": rust_total, "gdscript_total_us": gd_total, "ratio": gd_total / maxf(rust_total, 1.0),
		"all_equal": all_equal, "pass_5x_equal_output": all_equal and gd_total / maxf(rust_total, 1.0) >= 5.0}
	var f: FileAccess = FileAccess.open(_out_path, FileAccess.WRITE)
	if f != null:
		f.store_string(JSON.stringify(report, "  "))
		f.close()
	print("bench: ratio x%.1f  all_equal=%s" % [report["ratio"], str(all_equal)])
	get_tree().quit(0)

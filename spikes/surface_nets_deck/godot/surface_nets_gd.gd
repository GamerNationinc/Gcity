## GDScript port of the Rust surface nets in rust/src/lib.rs, same algorithm, same
## input layout, for the standards §9.2 Tier 1 comparison (≥5× with equal output).
class_name SurfaceNetsGd extends RefCounted

const CORNER: Array[Vector3] = [
	Vector3(0, 0, 0), Vector3(1, 0, 0), Vector3(0, 1, 0), Vector3(1, 1, 0),
	Vector3(0, 0, 1), Vector3(1, 0, 1), Vector3(0, 1, 1), Vector3(1, 1, 1),
]
const EDGES: Array[Vector2i] = [
	Vector2i(0, 1), Vector2i(2, 3), Vector2i(4, 5), Vector2i(6, 7),
	Vector2i(0, 2), Vector2i(1, 3), Vector2i(4, 6), Vector2i(5, 7),
	Vector2i(0, 4), Vector2i(1, 5), Vector2i(2, 6), Vector2i(3, 7),
]


static func mesh(samples: PackedFloat32Array, s: int) -> Dictionary:
	var n: int = s - 2
	var c: int = s - 1
	var cell_vertex: PackedInt32Array = PackedInt32Array()
	cell_vertex.resize(c * c * c)
	cell_vertex.fill(-1)
	var positions: PackedVector3Array = PackedVector3Array()
	var normals: PackedVector3Array = PackedVector3Array()
	var d: PackedFloat32Array = PackedFloat32Array()
	d.resize(8)
	for z: int in range(c):
		for y: int in range(c):
			for x: int in range(c):
				d[0] = samples[x + s * (y + s * z)]
				d[1] = samples[x + 1 + s * (y + s * z)]
				d[2] = samples[x + s * (y + 1 + s * z)]
				d[3] = samples[x + 1 + s * (y + 1 + s * z)]
				d[4] = samples[x + s * (y + s * (z + 1))]
				d[5] = samples[x + 1 + s * (y + s * (z + 1))]
				d[6] = samples[x + s * (y + 1 + s * (z + 1))]
				d[7] = samples[x + 1 + s * (y + 1 + s * (z + 1))]
				var mask: int = 0
				for i: int in range(8):
					if d[i] < 0.0:
						mask |= 1 << i
				if mask == 0 or mask == 0xff:
					continue
				var sum: Vector3 = Vector3.ZERO
				var count: float = 0.0
				for e: Vector2i in EDGES:
					var da: float = d[e.x]
					var db: float = d[e.y]
					if (da < 0.0) == (db < 0.0):
						continue
					var t: float = da / (da - db)
					sum += CORNER[e.x] + (CORNER[e.y] - CORNER[e.x]) * t
					count += 1.0
				positions.append(Vector3(x - 1, y - 1, z - 1) + sum / count)
				var g: Vector3 = Vector3(
					(d[1] + d[3] + d[5] + d[7]) - (d[0] + d[2] + d[4] + d[6]),
					(d[2] + d[3] + d[6] + d[7]) - (d[0] + d[1] + d[4] + d[5]),
					(d[4] + d[5] + d[6] + d[7]) - (d[0] + d[1] + d[2] + d[3]))
				normals.append(g / maxf(g.length(), 1e-12))
				cell_vertex[x + c * (y + c * z)] = positions.size() - 1
	var indices: PackedInt32Array = PackedInt32Array()
	for z: int in range(1, n + 1):
		for y: int in range(1, n + 1):
			for x: int in range(1, n + 1):
				var da: float = samples[x + s * (y + s * z)]
				var a_solid: bool = da < 0.0
				for axis: int in range(3):
					var bi: int
					var eu: Vector3i
					var ev: Vector3i
					match axis:
						0:
							bi = x + 1 + s * (y + s * z)
							eu = Vector3i(0, 1, 0)
							ev = Vector3i(0, 0, 1)
						1:
							bi = x + s * (y + 1 + s * z)
							eu = Vector3i(0, 0, 1)
							ev = Vector3i(1, 0, 0)
						_:
							bi = x + s * (y + s * (z + 1))
							eu = Vector3i(1, 0, 0)
							ev = Vector3i(0, 1, 0)
					if a_solid == (samples[bi] < 0.0):
						continue
					var q0: int = cell_vertex[(x - eu.x - ev.x) + c * ((y - eu.y - ev.y) + c * (z - eu.z - ev.z))]
					var q1: int = cell_vertex[(x - ev.x) + c * ((y - ev.y) + c * (z - ev.z))]
					var q2: int = cell_vertex[x + c * (y + c * z)]
					var q3: int = cell_vertex[(x - eu.x) + c * ((y - eu.y) + c * (z - eu.z))]
					if a_solid:
						indices.append_array(PackedInt32Array([q0, q2, q1, q0, q3, q2]))
					else:
						indices.append_array(PackedInt32Array([q0, q1, q2, q0, q2, q3]))
	return {"positions": positions, "normals": normals, "indices": indices}

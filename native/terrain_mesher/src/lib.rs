//! The wild region's chunk mesher (M7 spec claim 16; ADR-003 option B, promoted from the
//! spike `spikes/surface_nets_deck` at `cee8f1d`). Surface nets and nothing else: the
//! spike's density field, worker pool and edit overlay stay behind, because the sim owns
//! the ground (`Regions.solids`) and the client streams it (`client/terrain/`).
//!
//! One call: a block of S³ solid bytes in, one chunk's mesh out. It touches no state, so
//! the client may call it from any frame slice it likes.

use godot::prelude::*;

struct TerrainMesherExtension;

#[gdextension]
unsafe impl ExtensionLibrary for TerrainMesherExtension {}

/// Cells per chunk axis.
pub const N: usize = 32;
/// Samples per block axis: the chunk's N cells, one on the low side and one on the high
/// side, so neighbouring chunks share a row of cells and seams are watertight.
pub const S: usize = N + 2;
pub const S3: usize = S * S * S;

pub struct MeshData {
    pub positions: Vec<f32>,
    pub normals: Vec<f32>,
    pub indices: Vec<u32>,
}

/// Sample-to-sample cells per block axis (33).
const C: usize = S - 1;
/// Corner offsets of a cell, bit0 = x, bit1 = y, bit2 = z.
const CORNER: [[f32; 3]; 8] = [
    [0.0, 0.0, 0.0], [1.0, 0.0, 0.0], [0.0, 1.0, 0.0], [1.0, 1.0, 0.0],
    [0.0, 0.0, 1.0], [1.0, 0.0, 1.0], [0.0, 1.0, 1.0], [1.0, 1.0, 1.0],
];
const EDGES: [(usize, usize); 12] = [
    (0, 1), (2, 3), (4, 5), (6, 7),
    (0, 2), (1, 3), (4, 6), (5, 7),
    (0, 4), (1, 5), (2, 6), (3, 7),
];

fn idx(x: usize, y: usize, z: usize) -> usize {
    x + S * (y + S * z)
}

fn cidx(x: usize, y: usize, z: usize) -> usize {
    x + C * (y + C * z)
}

/// Naive surface nets over S³ samples, negative = solid. Positions are relative to the
/// chunk: sample index 1 is offset 0. Godot front faces are clockwise.
///
/// # Panics
///
/// If `samples` is not S³ long.
#[must_use]
pub fn surface_nets(samples: &[f32]) -> MeshData {
    assert_eq!(samples.len(), S3);
    let mut positions: Vec<f32> = Vec::new();
    let mut normals: Vec<f32> = Vec::new();
    let cell_vertex = vertices(samples, &mut positions, &mut normals);
    let indices = quads(samples, &cell_vertex);
    MeshData { positions, normals, indices }
}

/// One vertex per cell the surface passes through, at the mean of its edge crossings;
/// returns each cell's vertex index, or `u32::MAX` for none.
#[allow(clippy::cast_precision_loss, reason = "cell indices are below 34")]
fn vertices(samples: &[f32], positions: &mut Vec<f32>, normals: &mut Vec<f32>) -> Vec<u32> {
    let mut cell_vertex = vec![u32::MAX; C * C * C];
    let mut d = [0f32; 8];
    for z in 0..C {
        for y in 0..C {
            for x in 0..C {
                for (i, corner) in d.iter_mut().enumerate() {
                    *corner = samples[idx(x + (i & 1), y + ((i >> 1) & 1), z + ((i >> 2) & 1))];
                }
                let mut mask = 0u8;
                for (i, v) in d.iter().enumerate() {
                    if *v < 0.0 {
                        mask |= 1 << i;
                    }
                }
                if mask == 0 || mask == 0xff {
                    continue;
                }
                let mut sum = [0f32; 3];
                let mut count = 0.0f32;
                for (a, b) in &EDGES {
                    let da = d[*a];
                    let db = d[*b];
                    if (da < 0.0) == (db < 0.0) {
                        continue;
                    }
                    let t = da / (da - db);
                    for k in 0..3 {
                        sum[k] += CORNER[*a][k] + t * (CORNER[*b][k] - CORNER[*a][k]);
                    }
                    count += 1.0;
                }
                let inv = 1.0 / count;
                positions.push(x as f32 - 1.0 + sum[0] * inv);
                positions.push(y as f32 - 1.0 + sum[1] * inv);
                positions.push(z as f32 - 1.0 + sum[2] * inv);
                let gx = (d[1] + d[3] + d[5] + d[7]) - (d[0] + d[2] + d[4] + d[6]);
                let gy = (d[2] + d[3] + d[6] + d[7]) - (d[0] + d[1] + d[4] + d[5]);
                let gz = (d[4] + d[5] + d[6] + d[7]) - (d[0] + d[1] + d[2] + d[3]);
                let len = (gx * gx + gy * gy + gz * gz).sqrt().max(1e-12);
                normals.push(gx / len);
                normals.push(gy / len);
                normals.push(gz / len);
                cell_vertex[cidx(x, y, z)] = u32::try_from(positions.len() / 3 - 1).expect("fewer than 2^32 vertices");
            }
        }
    }
    cell_vertex
}

/// A quad across every sign-changing edge the chunk owns.
fn quads(samples: &[f32], cell_vertex: &[u32]) -> Vec<u32> {
    let mut indices: Vec<u32> = Vec::new();
    // Quads for edges whose base sample is interior (1..=N on every axis): each edge of
    // the world is owned by exactly one chunk, which is what makes seams watertight.
    for z in 1..=N {
        for y in 1..=N {
            for x in 1..=N {
                let a_solid = samples[idx(x, y, z)] < 0.0;
                for axis in 0..3 {
                    let (bx, by, bz) = match axis {
                        0 => (x + 1, y, z),
                        1 => (x, y + 1, z),
                        _ => (x, y, z + 1),
                    };
                    if a_solid == (samples[idx(bx, by, bz)] < 0.0) {
                        continue;
                    }
                    // (u, v) perpendicular axes chosen so (u, v, axis) is right-handed.
                    let (eu, ev): ([usize; 3], [usize; 3]) = match axis {
                        0 => ([0, 1, 0], [0, 0, 1]),
                        1 => ([0, 0, 1], [1, 0, 0]),
                        _ => ([1, 0, 0], [0, 1, 0]),
                    };
                    let cell = |i: usize, j: usize| -> u32 {
                        cell_vertex[cidx(x - i * eu[0] - j * ev[0], y - i * eu[1] - j * ev[1], z - i * eu[2] - j * ev[2])]
                    };
                    let q0 = cell(1, 1);
                    let q1 = cell(0, 1);
                    let q2 = cell(0, 0);
                    let q3 = cell(1, 0);
                    debug_assert!(q0 != u32::MAX && q1 != u32::MAX && q2 != u32::MAX && q3 != u32::MAX);
                    // (q0,q1,q2),(q0,q2,q3) is counter-clockwise seen from +axis. Godot's
                    // front face is clockwise, so the +axis-facing case (a solid) reverses.
                    if a_solid {
                        indices.extend_from_slice(&[q0, q2, q1, q0, q3, q2]);
                    } else {
                        indices.extend_from_slice(&[q0, q1, q2, q0, q2, q3]);
                    }
                }
            }
        }
    }
    indices
}

/// Solid bytes (non-zero = solid) to the densities surface nets reads.
#[must_use]
pub fn densities(solids: &[u8]) -> Vec<f32> {
    solids.iter().map(|b| if *b != 0 { -1.0 } else { 1.0 }).collect()
}

/// The Godot face of the mesher. Stateless.
#[derive(GodotClass)]
#[class(base = RefCounted, init)]
pub struct TerrainMesher {
    base: Base<RefCounted>,
}

#[godot_api]
impl TerrainMesher {
    /// Cells per chunk axis, for the caller to size its blocks by.
    #[constant]
    const CHUNK: i32 = 32;

    /// Meshes one chunk from a block of S³ (34³) solid bytes, ordered x fastest, then y,
    /// then z, exactly as `Regions.solids` returns them. Returns `{positions, normals,
    /// indices}`, or an empty dictionary (and an error) if the block is the wrong size.
    #[func]
    #[allow(clippy::needless_pass_by_value, reason = "godot-rust passes #[func] arguments by value")]
    fn mesh(solids: PackedByteArray) -> VarDictionary {
        let bytes = solids.as_slice();
        if bytes.len() != S3 {
            godot_error!("TerrainMesher.mesh: expected {} bytes, got {}", S3, bytes.len());
            return VarDictionary::new();
        }
        to_dict(&surface_nets(&densities(bytes)))
    }
}

fn to_dict(mesh: &MeshData) -> VarDictionary {
    let mut positions = PackedVector3Array::new();
    let mut normals = PackedVector3Array::new();
    positions.resize(mesh.positions.len() / 3);
    normals.resize(mesh.normals.len() / 3);
    {
        let ps = positions.as_mut_slice();
        let ns = normals.as_mut_slice();
        for i in 0..ps.len() {
            ps[i] = Vector3::new(mesh.positions[3 * i], mesh.positions[3 * i + 1], mesh.positions[3 * i + 2]);
            ns[i] = Vector3::new(mesh.normals[3 * i], mesh.normals[3 * i + 1], mesh.normals[3 * i + 2]);
        }
    }
    let mut indices = PackedInt32Array::new();
    indices.resize(mesh.indices.len());
    {
        let is = indices.as_mut_slice();
        for (i, v) in mesh.indices.iter().enumerate() {
            is[i] = i32::try_from(*v).expect("fewer than 2^31 indices");
        }
    }
    let mut d = VarDictionary::new();
    d.set(&"positions".to_variant(), &positions.to_variant());
    d.set(&"normals".to_variant(), &normals.to_variant());
    d.set(&"indices".to_variant(), &indices.to_variant());
    d
}

#[cfg(test)]
mod tests {
    use super::*;

    fn block(f: impl Fn(usize, usize, usize) -> bool) -> Vec<u8> {
        let mut out = vec![0u8; S3];
        for z in 0..S {
            for y in 0..S {
                for x in 0..S {
                    out[x + S * (y + S * z)] = u8::from(f(x, y, z));
                }
            }
        }
        out
    }

    #[test]
    fn empty_and_full_blocks_have_no_surface() {
        assert!(surface_nets(&densities(&block(|_, _, _| false))).indices.is_empty());
        assert!(surface_nets(&densities(&block(|_, _, _| true))).indices.is_empty());
    }

    #[test]
    fn a_flat_floor_is_one_quad_per_cell_facing_up() {
        let mesh = surface_nets(&densities(&block(|_, y, _| y < 10)));
        assert_eq!(mesh.indices.len(), N * N * 6);
        for n in mesh.normals.chunks(3) {
            assert!(n[1] > 0.99, "normal {n:?} does not face up");
        }
    }

    #[test]
    fn every_edge_of_a_closed_surface_is_shared_by_two_triangles() {
        let mesh = surface_nets(&densities(&block(|x, y, z| {
            let (dx, dy, dz) = (x.abs_diff(17), y.abs_diff(17), z.abs_diff(17));
            dx * dx + dy * dy + dz * dz < 100
        })));
        let mut edges = std::collections::HashMap::new();
        for t in mesh.indices.chunks(3) {
            for (a, b) in [(t[0], t[1]), (t[1], t[2]), (t[2], t[0])] {
                *edges.entry((a.min(b), a.max(b))).or_insert(0) += 1;
            }
        }
        assert!(!edges.is_empty());
        assert!(edges.values().all(|n| *n == 2));
    }
}

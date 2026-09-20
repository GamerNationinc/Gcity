//! ADR-003 spike: volumetric chunk meshing (naive surface nets) as a Godot 4 GDExtension.
//! Spike code (standards §9.1): deleted or promoted at ADR sign-off, never left in place.
//!
//! One class, `VoxelWorld`: a seeded density field (heightfield + caves), a sparse edit
//! overlay in the shape of `save = seed + overlay`, a worker pool over std::thread, and a
//! surface-nets mesher. Workers never touch the Godot API; the main thread converts
//! finished results to packed arrays in `poll()`.

use godot::prelude::*;
use std::cmp::Ordering as CmpOrdering;
use std::collections::{BinaryHeap, HashMap, HashSet};
use std::sync::atomic::{AtomicBool, AtomicU64, Ordering};
use std::sync::{Arc, Condvar, Mutex, RwLock};
use std::thread::JoinHandle;
use std::time::Instant;

struct SpikeExtension;

#[gdextension]
unsafe impl ExtensionLibrary for SpikeExtension {}

/// Voxels per chunk axis.
pub const N: usize = 32;
/// Density samples per chunk axis: N+1 corners plus one sample of padding on the low
/// side, so that cells overlap neighbours by one and seams are watertight.
pub const S: usize = N + 2;
pub const S3: usize = S * S * S;

type ChunkCoord = (i32, i32, i32);

// ------------------------------------------------------------------ noise / density

#[inline]
fn hash3(x: i32, y: i32, z: i32, seed: u32) -> u32 {
    let mut h = (x as u32).wrapping_mul(0x8da6b343)
        ^ (y as u32).wrapping_mul(0xd8163841)
        ^ (z as u32).wrapping_mul(0xcb1ab31f)
        ^ seed.wrapping_mul(0x9e3779b9);
    h ^= h >> 15;
    h = h.wrapping_mul(0x2c1b3c6d);
    h ^= h >> 12;
    h = h.wrapping_mul(0x297a2d39);
    h ^= h >> 15;
    h
}

#[inline]
fn lattice(x: i32, y: i32, z: i32, seed: u32) -> f32 {
    // [-1, 1]
    (hash3(x, y, z, seed) >> 8) as f32 * (2.0 / 16_777_216.0) - 1.0
}

#[inline]
fn smooth(t: f32) -> f32 {
    t * t * (3.0 - 2.0 * t)
}

fn value_noise_3d(x: f32, y: f32, z: f32, seed: u32) -> f32 {
    let xf = x.floor();
    let yf = y.floor();
    let zf = z.floor();
    let (xi, yi, zi) = (xf as i32, yf as i32, zf as i32);
    let (tx, ty, tz) = (smooth(x - xf), smooth(y - yf), smooth(z - zf));
    let l = |dx: i32, dy: i32, dz: i32| lattice(xi + dx, yi + dy, zi + dz, seed);
    let x00 = l(0, 0, 0) + (l(1, 0, 0) - l(0, 0, 0)) * tx;
    let x10 = l(0, 1, 0) + (l(1, 1, 0) - l(0, 1, 0)) * tx;
    let x01 = l(0, 0, 1) + (l(1, 0, 1) - l(0, 0, 1)) * tx;
    let x11 = l(0, 1, 1) + (l(1, 1, 1) - l(0, 1, 1)) * tx;
    let y0 = x00 + (x10 - x00) * ty;
    let y1 = x01 + (x11 - x01) * ty;
    y0 + (y1 - y0) * tz
}

fn value_noise_2d(x: f32, z: f32, seed: u32) -> f32 {
    let xf = x.floor();
    let zf = z.floor();
    let (xi, zi) = (xf as i32, zf as i32);
    let (tx, tz) = (smooth(x - xf), smooth(z - zf));
    let l = |dx: i32, dz: i32| lattice(xi + dx, 0, zi + dz, seed);
    let a = l(0, 0) + (l(1, 0) - l(0, 0)) * tx;
    let b = l(0, 1) + (l(1, 1) - l(0, 1)) * tx;
    a + (b - a) * tz
}

/// Heightfield: three octaves, amplitude about ±24 m.
pub fn terrain_height(x: f32, z: f32, seed: u32) -> f32 {
    16.0 * value_noise_2d(x / 96.0, z / 96.0, seed)
        + 6.0 * value_noise_2d(x / 48.0, z / 48.0, seed.wrapping_add(1))
        + 2.0 * value_noise_2d(x / 24.0, z / 24.0, seed.wrapping_add(2))
}

/// Signed density: > 0 air, < 0 solid, surface at 0. `h` is the terrain height at (x, z).
#[inline]
pub fn density_at(x: f32, y: f32, z: f32, h: f32, seed: u32) -> f32 {
    let ground = y - h;
    if ground > 2.0 {
        return ground; // above the surface there are no caves; skip the 3D noise
    }
    let depth = -ground;
    let fade = ((depth - 3.0) / 6.0).clamp(0.0, 1.0);
    if fade <= 0.0 {
        return ground;
    }
    let c = value_noise_3d(x / 28.0, y / 20.0, z / 28.0, seed.wrapping_add(10))
        + 0.5 * value_noise_3d(x / 13.0, y / 11.0, z / 13.0, seed.wrapping_add(11));
    let carved = (c - 0.55) * 12.0 * fade;
    if carved > ground {
        carved
    } else {
        ground
    }
}

// ------------------------------------------------------------------ world data

struct WorldData {
    seed: u32,
    /// World-sample coordinate -> density delta (positive digs air).
    edits: RwLock<HashMap<(i32, i32, i32), f32>>,
    /// Chunks whose padded sample range contains at least one edit.
    edited_chunks: RwLock<HashSet<ChunkCoord>>,
}

impl WorldData {
    /// Fills `out` (len S3) with the chunk's padded samples. Returns false if the whole
    /// chunk is trivially air (above the terrain everywhere), in which case `out` is untouched.
    fn sample_chunk(&self, coord: ChunkCoord, out: &mut [f32]) -> bool {
        let ox = coord.0 * N as i32 - 1;
        let oy = coord.1 * N as i32 - 1;
        let oz = coord.2 * N as i32 - 1;
        let mut heights = [0f32; S * S];
        let mut max_h = f32::MIN;
        for lz in 0..S {
            for lx in 0..S {
                let h = terrain_height((ox + lx as i32) as f32, (oz + lz as i32) as f32, self.seed);
                heights[lx + S * lz] = h;
                if h > max_h {
                    max_h = h;
                }
            }
        }
        let edited = self.edited_chunks.read().unwrap().contains(&coord);
        if !edited && oy as f32 > max_h + 1.0 {
            return false;
        }
        for lz in 0..S {
            for ly in 0..S {
                let y = (oy + ly as i32) as f32;
                for lx in 0..S {
                    let h = heights[lx + S * lz];
                    out[lx + S * (ly + S * lz)] =
                        density_at((ox + lx as i32) as f32, y, (oz + lz as i32) as f32, h, self.seed);
                }
            }
        }
        if edited {
            let edits = self.edits.read().unwrap();
            for lz in 0..S {
                for ly in 0..S {
                    for lx in 0..S {
                        let key = (ox + lx as i32, oy + ly as i32, oz + lz as i32);
                        if let Some(d) = edits.get(&key) {
                            out[lx + S * (ly + S * lz)] += *d;
                        }
                    }
                }
            }
        }
        true
    }
}

// ------------------------------------------------------------------ surface nets

pub struct MeshData {
    pub positions: Vec<f32>,
    pub normals: Vec<f32>,
    pub indices: Vec<u32>,
}

/// Naive surface nets over S³ samples. Positions are relative to the chunk origin
/// (sample index 1 is world offset 0). Godot front faces are clockwise.
pub fn surface_nets(samples: &[f32]) -> MeshData {
    debug_assert_eq!(samples.len(), S3);
    const C: usize = S - 1; // cells per axis (33)
    let idx = |x: usize, y: usize, z: usize| x + S * (y + S * z);
    let cidx = |x: usize, y: usize, z: usize| x + C * (y + C * z);
    let mut cell_vertex = vec![u32::MAX; C * C * C];
    let mut positions: Vec<f32> = Vec::new();
    let mut normals: Vec<f32> = Vec::new();
    // corner offsets, bit0 = x, bit1 = y, bit2 = z
    const CORNER: [[f32; 3]; 8] = [
        [0.0, 0.0, 0.0], [1.0, 0.0, 0.0], [0.0, 1.0, 0.0], [1.0, 1.0, 0.0],
        [0.0, 0.0, 1.0], [1.0, 0.0, 1.0], [0.0, 1.0, 1.0], [1.0, 1.0, 1.0],
    ];
    const EDGES: [(usize, usize); 12] = [
        (0, 1), (2, 3), (4, 5), (6, 7),
        (0, 2), (1, 3), (4, 6), (5, 7),
        (0, 4), (1, 5), (2, 6), (3, 7),
    ];
    let mut d = [0f32; 8];
    for z in 0..C {
        for y in 0..C {
            for x in 0..C {
                d[0] = samples[idx(x, y, z)];
                d[1] = samples[idx(x + 1, y, z)];
                d[2] = samples[idx(x, y + 1, z)];
                d[3] = samples[idx(x + 1, y + 1, z)];
                d[4] = samples[idx(x, y, z + 1)];
                d[5] = samples[idx(x + 1, y, z + 1)];
                d[6] = samples[idx(x, y + 1, z + 1)];
                d[7] = samples[idx(x + 1, y + 1, z + 1)];
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
                for (a, b) in EDGES.iter() {
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
                cell_vertex[cidx(x, y, z)] = (positions.len() / 3 - 1) as u32;
            }
        }
    }
    let mut indices: Vec<u32> = Vec::new();
    // Quads for edges whose base sample is interior (1..=N on every axis): each edge of
    // the world is owned by exactly one chunk, which is what makes seams watertight.
    for z in 1..=N {
        for y in 1..=N {
            for x in 1..=N {
                let da = samples[idx(x, y, z)];
                let a_solid = da < 0.0;
                for axis in 0..3 {
                    let (bx, by, bz) = match axis {
                        0 => (x + 1, y, z),
                        1 => (x, y + 1, z),
                        _ => (x, y, z + 1),
                    };
                    let db = samples[idx(bx, by, bz)];
                    if a_solid == (db < 0.0) {
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
    MeshData { positions, normals, indices }
}

// ------------------------------------------------------------------ worker pool

struct Job {
    coord: ChunkCoord,
    version: u64,
    priority: i64,
    seq: u64,
}

impl PartialEq for Job {
    fn eq(&self, other: &Self) -> bool {
        self.priority == other.priority && self.seq == other.seq
    }
}
impl Eq for Job {}
impl PartialOrd for Job {
    fn partial_cmp(&self, other: &Self) -> Option<CmpOrdering> {
        Some(self.cmp(other))
    }
}
impl Ord for Job {
    // BinaryHeap is a max-heap: lower priority value and lower seq come out first.
    fn cmp(&self, other: &Self) -> CmpOrdering {
        other.priority.cmp(&self.priority).then_with(|| other.seq.cmp(&self.seq))
    }
}

struct MeshResult {
    coord: ChunkCoord,
    version: u64,
    mesh: Option<MeshData>,
    gen_us: u64,
    mesh_us: u64,
}

#[derive(Default)]
struct Stats {
    gen_us: AtomicU64,
    mesh_us: AtomicU64,
    meshed: AtomicU64,
    skipped_air: AtomicU64,
    stale_dropped: AtomicU64,
}

struct Shared {
    world: WorldData,
    queue: Mutex<BinaryHeap<Job>>,
    cv: Condvar,
    /// Current version per wanted chunk; a job whose version is stale is skipped.
    versions: Mutex<HashMap<ChunkCoord, u64>>,
    results: Mutex<Vec<MeshResult>>,
    in_flight: AtomicU64,
    stop: AtomicBool,
    stats: Stats,
}

fn worker_loop(shared: Arc<Shared>) {
    let mut samples = vec![0f32; S3];
    loop {
        let job = {
            let mut q = shared.queue.lock().unwrap();
            loop {
                if shared.stop.load(Ordering::Relaxed) {
                    return;
                }
                if let Some(j) = q.pop() {
                    break j;
                }
                q = shared.cv.wait(q).unwrap();
            }
        };
        let current = shared.versions.lock().unwrap().get(&job.coord).copied();
        if current != Some(job.version) {
            shared.stats.stale_dropped.fetch_add(1, Ordering::Relaxed);
            continue;
        }
        shared.in_flight.fetch_add(1, Ordering::Relaxed);
        let t0 = Instant::now();
        let has_content = shared.world.sample_chunk(job.coord, &mut samples);
        let gen_us = t0.elapsed().as_micros() as u64;
        let t1 = Instant::now();
        let mesh = if has_content {
            let m = surface_nets(&samples);
            if m.indices.is_empty() {
                None
            } else {
                Some(m)
            }
        } else {
            shared.stats.skipped_air.fetch_add(1, Ordering::Relaxed);
            None
        };
        let mesh_us = t1.elapsed().as_micros() as u64;
        shared.stats.gen_us.fetch_add(gen_us, Ordering::Relaxed);
        shared.stats.mesh_us.fetch_add(mesh_us, Ordering::Relaxed);
        shared.stats.meshed.fetch_add(1, Ordering::Relaxed);
        shared.results.lock().unwrap().push(MeshResult { coord: job.coord, version: job.version, mesh, gen_us, mesh_us });
        shared.in_flight.fetch_sub(1, Ordering::Relaxed);
    }
}

struct Pool {
    shared: Arc<Shared>,
    threads: Vec<JoinHandle<()>>,
    seq: u64,
}

impl Drop for Pool {
    fn drop(&mut self) {
        self.shared.stop.store(true, Ordering::Relaxed);
        self.shared.cv.notify_all();
        for t in self.threads.drain(..) {
            let _ = t.join();
        }
    }
}

// ------------------------------------------------------------------ Godot class

#[derive(GodotClass)]
#[class(base=RefCounted, init)]
pub struct VoxelWorld {
    base: Base<RefCounted>,
    pool: Option<Pool>,
}

fn to_coord(v: Vector3i) -> ChunkCoord {
    (v.x, v.y, v.z)
}

fn from_coord(c: ChunkCoord) -> Vector3i {
    Vector3i::new(c.0, c.1, c.2)
}

/// Chunk index range whose padded sample range [c*N-1, c*N+N] contains world sample `s`.
fn chunks_touching(s: i32) -> (i32, i32) {
    let n = N as i32;
    let lo = (s - n).div_euclid(n) + if (s - n).rem_euclid(n) == 0 { 0 } else { 1 };
    let hi = (s + 1).div_euclid(n);
    (lo, hi)
}

impl VoxelWorld {
    fn shared(&self) -> &Arc<Shared> {
        &self.pool.as_ref().expect("VoxelWorld.setup() not called").shared
    }

    fn mesh_to_dict(mesh: &MeshData) -> VarDictionary {
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
                is[i] = *v as i32;
            }
        }
        let mut d = VarDictionary::new();
        dset(&mut d, "positions", positions);
        dset(&mut d, "normals", normals);
        dset(&mut d, "indices", indices);
        d
    }
}

#[godot_api]
impl VoxelWorld {
    #[func]
    fn setup(&mut self, seed: i64, workers: i64) {
        self.pool = None;
        let shared = Arc::new(Shared {
            world: WorldData { seed: seed as u32, edits: RwLock::new(HashMap::new()), edited_chunks: RwLock::new(HashSet::new()) },
            queue: Mutex::new(BinaryHeap::new()),
            cv: Condvar::new(),
            versions: Mutex::new(HashMap::new()),
            results: Mutex::new(Vec::new()),
            in_flight: AtomicU64::new(0),
            stop: AtomicBool::new(false),
            stats: Stats::default(),
        });
        let mut threads = Vec::new();
        for i in 0..workers.max(1) as usize {
            let s = Arc::clone(&shared);
            threads.push(std::thread::Builder::new().name(format!("voxel-worker-{i}")).spawn(move || worker_loop(s)).expect("spawn worker"));
        }
        self.pool = Some(Pool { shared, threads, seq: 0 });
    }

    /// Queue (or re-queue) a chunk. Lower priority values run first.
    #[func]
    fn request(&mut self, coord: Vector3i, priority: i64) {
        let pool = self.pool.as_mut().expect("setup() first");
        let c = to_coord(coord);
        pool.seq += 1;
        let seq = pool.seq;
        let version = {
            let mut v = pool.shared.versions.lock().unwrap();
            let e = v.entry(c).or_insert(0);
            *e += 1;
            *e
        };
        pool.shared.queue.lock().unwrap().push(Job { coord: c, version, priority, seq });
        pool.shared.cv.notify_one();
    }

    #[func]
    fn cancel(&mut self, coord: Vector3i) {
        self.shared().versions.lock().unwrap().remove(&to_coord(coord));
    }

    /// Digs a sphere: raises density (toward air) inside it. Returns the chunks whose
    /// meshes are now stale; the caller re-requests them.
    #[func]
    fn dig_sphere(&mut self, center: Vector3, radius: f32, strength: f32) -> Array<Vector3i> {
        let shared = Arc::clone(self.shared());
        let r = radius.max(0.0);
        let min = [(center.x - r).floor() as i32, (center.y - r).floor() as i32, (center.z - r).floor() as i32];
        let max = [(center.x + r).ceil() as i32, (center.y + r).ceil() as i32, (center.z + r).ceil() as i32];
        {
            let mut edits = shared.world.edits.write().unwrap();
            for z in min[2]..=max[2] {
                for y in min[1]..=max[1] {
                    for x in min[0]..=max[0] {
                        let dx = x as f32 - center.x;
                        let dy = y as f32 - center.y;
                        let dz = z as f32 - center.z;
                        let dist = (dx * dx + dy * dy + dz * dz).sqrt();
                        if dist < r {
                            let delta = (r - dist) * strength;
                            let e = edits.entry((x, y, z)).or_insert(0.0);
                            if delta > *e {
                                *e = delta;
                            }
                        }
                    }
                }
            }
        }
        let (x0, x1) = (chunks_touching(min[0]).0, chunks_touching(max[0]).1);
        let (y0, y1) = (chunks_touching(min[1]).0, chunks_touching(max[1]).1);
        let (z0, z1) = (chunks_touching(min[2]).0, chunks_touching(max[2]).1);
        let mut out = Array::<Vector3i>::new();
        let mut edited = shared.world.edited_chunks.write().unwrap();
        for z in z0..=z1 {
            for y in y0..=y1 {
                for x in x0..=x1 {
                    edited.insert((x, y, z));
                    out.push(Vector3i::new(x, y, z));
                }
            }
        }
        out
    }

    /// Finished chunks, newest versions only, at most `max` of them. Each entry:
    /// {coord, version, empty, gen_us, mesh_us, positions, normals, indices}.
    #[func]
    fn poll(&mut self, max: i64) -> VarArray {
        let shared = Arc::clone(self.shared());
        let mut ready: Vec<MeshResult> = Vec::new();
        {
            let mut results = shared.results.lock().unwrap();
            let take = (max.max(0) as usize).min(results.len());
            ready.extend(results.drain(..take));
        }
        let mut out = VarArray::new();
        let versions = shared.versions.lock().unwrap();
        for r in ready {
            if versions.get(&r.coord).copied() != Some(r.version) {
                shared.stats.stale_dropped.fetch_add(1, Ordering::Relaxed);
                continue;
            }
            let mut d = match &r.mesh {
                Some(m) => Self::mesh_to_dict(m),
                None => VarDictionary::new(),
            };
            dset(&mut d, "coord", from_coord(r.coord));
            dset(&mut d, "version", r.version as i64);
            dset(&mut d, "empty", r.mesh.is_none());
            dset(&mut d, "gen_us", r.gen_us as i64);
            dset(&mut d, "mesh_us", r.mesh_us as i64);
            out.push(&d.to_variant());
        }
        out
    }

    #[func]
    fn terrain_height(&self, x: f32, z: f32) -> f32 {
        terrain_height(x, z, self.shared().world.seed)
    }

    /// Synchronous: the chunk's S³ padded samples (for the GDScript comparison).
    #[func]
    fn sample_chunk(&self, coord: Vector3i) -> PackedFloat32Array {
        let mut buf = vec![0f32; S3];
        if !self.shared().world.sample_chunk(to_coord(coord), &mut buf) {
            // trivially air: fill with positive values so both meshers see the same input
            for v in buf.iter_mut() {
                *v = 1.0;
            }
        }
        PackedFloat32Array::from(buf.as_slice())
    }

    /// Synchronous meshing of given samples, timed; for the Rust-vs-GDScript comparison.
    #[func]
    fn mesh_samples(&self, samples: PackedFloat32Array) -> VarDictionary {
        let s = samples.as_slice();
        assert_eq!(s.len(), S3, "expected {S3} samples");
        let t0 = Instant::now();
        let m = surface_nets(s);
        let us = t0.elapsed().as_micros() as i64;
        let mut d = Self::mesh_to_dict(&m);
        dset(&mut d, "mesh_us", us);
        d
    }

    #[func]
    fn stats(&self) -> VarDictionary {
        let s = self.shared();
        let mut d = VarDictionary::new();
        dset(&mut d, "gen_us", s.stats.gen_us.load(Ordering::Relaxed) as i64);
        dset(&mut d, "mesh_us", s.stats.mesh_us.load(Ordering::Relaxed) as i64);
        dset(&mut d, "meshed", s.stats.meshed.load(Ordering::Relaxed) as i64);
        dset(&mut d, "skipped_air", s.stats.skipped_air.load(Ordering::Relaxed) as i64);
        dset(&mut d, "stale_dropped", s.stats.stale_dropped.load(Ordering::Relaxed) as i64);
        dset(&mut d, "queued", s.queue.lock().unwrap().len() as i64);
        dset(&mut d, "in_flight", s.in_flight.load(Ordering::Relaxed) as i64);
        dset(&mut d, "results_waiting", s.results.lock().unwrap().len() as i64);
        dset(&mut d, "edits", s.world.edits.read().unwrap().len() as i64);
        d
    }

    #[func]
    fn chunk_size(&self) -> i64 {
        N as i64
    }

    #[func]
    fn sample_size(&self) -> i64 {
        S as i64
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn touching_ranges() {
        // sample 31 is inside chunk 0 (0..=32 padded) and in chunk 1's low padding (31 = 1*32-1)
        assert_eq!(chunks_touching(31), (0, 1));
        assert_eq!(chunks_touching(0), (-1, 0));
        assert_eq!(chunks_touching(32), (0, 1));
        assert_eq!(chunks_touching(33), (1, 1));
    }

    #[test]
    fn sphere_mesh_is_closed() {
        // A sphere of radius 8 in the middle: every quad edge should be shared by two triangles.
        let mut s = vec![0f32; S3];
        for z in 0..S {
            for y in 0..S {
                for x in 0..S {
                    let dx = x as f32 - 16.0;
                    let dy = y as f32 - 16.0;
                    let dz = z as f32 - 16.0;
                    s[x + S * (y + S * z)] = (dx * dx + dy * dy + dz * dz).sqrt() - 8.0;
                }
            }
        }
        let m = surface_nets(&s);
        assert!(m.indices.len() % 3 == 0 && !m.indices.is_empty());
        let mut edges: HashMap<(u32, u32), i32> = HashMap::new();
        for t in m.indices.chunks(3) {
            for k in 0..3 {
                let a = t[k];
                let b = t[(k + 1) % 3];
                *edges.entry((a.min(b), a.max(b))).or_insert(0) += 1;
            }
        }
        assert!(edges.values().all(|c| *c == 2), "open edge found");
    }
}

fn dset(d: &mut VarDictionary, key: &str, value: impl ToGodot) {
    d.set(&key.to_variant(), &value.to_variant());
}

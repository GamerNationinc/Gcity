#!/usr/bin/env python3
"""Generate the A1 operator placeholder models (docs/specs/A1-operator-variant-assets.md).

Writes assets/models/agents/<agent_profile_id>.glb for the four concept-sheet variants
(assets/concepts/operator_variants.png) as low-poly box figures. Python stdlib only, so
there is no dependency to pin; output is deterministic, so running it twice produces
byte-identical files (spec claim 3).

Contract kept (assets/README.md): the figure faces +X, the origin is the mesh centre
0.9 m above the feet, one mesh node is named StanceChip, materials are base-colour
only, and the budgets (<= 2,000 triangles, <= 6 materials, <= 256 KiB) are printed and
enforced here.

Usage: python3 tools/asset_gen/gen_operator_models.py
"""
from __future__ import annotations

import json
import os
import struct

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
OUT_DIR = os.path.join(ROOT, "assets", "models", "agents")

ORIGIN_HEIGHT = 0.9  # the client places actor nodes at y = 0.9 (client/world_view.gd)
MAX_TRIANGLES = 2000
MAX_MATERIALS = 6
MAX_BYTES = 256 * 1024

BONE = "#d9d4c7"   # the faction mask / emblem
CHIP = "#34c06c"   # StanceChip default (goggle green); the client retints it per stance


def srgb_to_linear(channel: float) -> float:
    """glTF baseColorFactor is linear; palettes below are authored as sRGB hex."""
    if channel <= 0.04045:
        return channel / 12.92
    return ((channel + 0.055) / 1.055) ** 2.4


def rgba(hex_code: str) -> list[float]:
    r = int(hex_code[1:3], 16) / 255.0
    g = int(hex_code[3:5], 16) / 255.0
    b = int(hex_code[5:7], 16) / 255.0
    return [round(srgb_to_linear(c), 6) for c in (r, g, b)] + [1.0]


# One box: centre (x, y, z) in metres with y measured from the ground, size (sx, sy, sz).
# Per-face normals, 24 vertices, 12 triangles.
_FACES = [
    ((1, 0, 0), ((1, -1, -1), (1, 1, -1), (1, 1, 1), (1, -1, 1))),
    ((-1, 0, 0), ((-1, -1, 1), (-1, 1, 1), (-1, 1, -1), (-1, -1, -1))),
    ((0, 1, 0), ((-1, 1, -1), (-1, 1, 1), (1, 1, 1), (1, 1, -1))),
    ((0, -1, 0), ((-1, -1, 1), (-1, -1, -1), (1, -1, -1), (1, -1, 1))),
    ((0, 0, 1), ((1, -1, 1), (1, 1, 1), (-1, 1, 1), (-1, -1, 1))),
    ((0, 0, -1), ((-1, -1, -1), (-1, 1, -1), (1, 1, -1), (1, -1, -1))),
]


def add_box(prim: dict, centre: tuple[float, float, float], size: tuple[float, float, float]) -> None:
    cx, cy, cz = centre[0], centre[1] - ORIGIN_HEIGHT, centre[2]
    hx, hy, hz = size[0] / 2.0, size[1] / 2.0, size[2] / 2.0
    for normal, corners in _FACES:
        base = len(prim["positions"])
        for sx, sy, sz in corners:
            prim["positions"].append((cx + sx * hx, cy + sy * hy, cz + sz * hz))
            prim["normals"].append(normal)
        prim["indices"].extend([base, base + 1, base + 2, base, base + 2, base + 3])


def mirrored(prim: dict, centre: tuple[float, float, float], size: tuple[float, float, float]) -> None:
    add_box(prim, centre, size)
    add_box(prim, (centre[0], centre[1], -centre[2]), size)


def build_figure(spec: dict) -> dict[str, dict]:
    """Returns {material_name: primitive} for the body, plus the StanceChip primitive."""
    prims: dict[str, dict] = {
        name: {"positions": [], "normals": [], "indices": []}
        for name in ("base", "gear", "bone", "weapon", "accent", "chip")
    }
    bulk = spec["bulk"]  # 1.0 = Medium reference silhouette

    # boots and legs
    mirrored(prims["gear"], (0.03, 0.06, 0.11), (0.30, 0.12, 0.14))
    mirrored(prims["base"], (0.0, 0.485, 0.11), (0.17 * bulk, 0.73, 0.16 * bulk))
    # hips and torso
    add_box(prims["gear"], (0.0, 0.925, 0.0), (0.26 * bulk, 0.15, 0.34 * bulk))
    add_box(prims["base"], (0.0, 1.225, 0.0), (0.26 * bulk, 0.45, 0.38 * bulk))
    # vest over the torso, and the bone emblem plate on its front
    vest_x, vest_z = spec["vest"]
    add_box(prims["gear"], (0.0, 1.22, 0.0), (vest_x, 0.40, vest_z))
    add_box(prims["bone"], (vest_x / 2.0 + 0.015, 1.27, 0.0), (0.03, 0.13, 0.15))
    # arms just outside the vest
    arm_z = vest_z / 2.0 + 0.07
    mirrored(prims["base"], (0.0, 1.185, arm_z), (0.14, 0.47, 0.12))
    mirrored(prims["gear"], (0.0, 1.40, arm_z), (0.16, 0.10, 0.14))  # shoulder caps
    # neck, hood (the head), mask and the StanceChip goggle bar
    add_box(prims["base"], (0.0, 1.475, 0.0), (0.12, 0.07, 0.12))
    add_box(prims["gear"], (-0.015, 1.65, 0.0), (0.26, 0.30, 0.26))
    add_box(prims["bone"], (0.115 + 0.02, 1.575, 0.0), (0.04, 0.13, 0.16))
    add_box(prims["chip"], (0.115 + 0.025, 1.69, 0.0), (0.05, 0.07, 0.18))
    # backpack
    pack_x, pack_y, pack_z = spec["pack"]
    pack_back = -(0.26 * bulk) / 2.0 - pack_x / 2.0 - 0.005
    add_box(prims["gear"], (pack_back, 1.22, 0.0), (pack_x, pack_y, pack_z))
    if spec["antennas"]:
        for i, dz in enumerate((-0.10, 0.0, 0.10)):
            height = 0.45 + 0.10 * i
            add_box(prims["gear"], (pack_back, 1.22 + pack_y / 2.0 + height / 2.0, dz), (0.03, height, 0.03))
    # weapon held forward along +X, with the variant's furniture
    length = spec["gun_len"]
    add_box(prims["weapon"], (0.18 + length / 2.0, 1.22, 0.16), (length, 0.07, 0.05))
    add_box(prims["weapon"], (0.26, 1.13, 0.16), (0.06, 0.12, 0.045))  # grip
    for material, centre, size in spec["extras"]:
        add_box(prims[material], centre, size)
    return prims


VARIANTS = {
    # palette and silhouette tells per concept-sheet variant (docs/operator-archetypes.md)
    "op_heavy": {
        "base": "#30302b", "gear": "#191917", "accent": "#4a4a38", "weapon": "#141414",
        "bulk": 1.25, "vest": (0.44, 0.52), "pack": (0.18, 0.42, 0.30),
        "gun_len": 0.72, "antennas": False,
        "extras": [
            ("accent", (0.42, 1.12, 0.16), (0.16, 0.14, 0.10)),   # belt box under the LMG
            ("accent", (0.235, 1.10, 0.0), (0.04, 0.14, 0.30)),   # belt pouches on the vest front
        ],
    },
    "op_medium": {
        "base": "#8a7b5c", "gear": "#4e4636", "accent": "#6b614a", "weapon": "#1c1c1c",
        "bulk": 1.0, "vest": (0.34, 0.44), "pack": (0.14, 0.32, 0.26),
        "gun_len": 0.62, "antennas": False,
        "extras": [
            ("accent", (0.185, 1.08, 0.0), (0.04, 0.12, 0.24)),   # magazine pouches
            ("weapon", (0.56, 1.285, 0.16), (0.10, 0.05, 0.04)),  # optic
        ],
    },
    "op_recon": {
        "base": "#4c5a3a", "gear": "#2f3626", "accent": "#5d6b45", "weapon": "#161616",
        "bulk": 0.9, "vest": (0.28, 0.40), "pack": (0.09, 0.26, 0.20),
        "gun_len": 0.82, "antennas": False,
        "extras": [
            ("weapon", (1.07, 1.22, 0.16), (0.14, 0.055, 0.045)),  # suppressor
            ("weapon", (0.70, 1.295, 0.16), (0.14, 0.05, 0.04)),   # scope
            ("accent", (0.155, 1.30, 0.0), (0.03, 0.09, 0.12)),    # binocular pouch
        ],
    },
    "op_drone_hunter": {
        "base": "#8d9094", "gear": "#565b60", "accent": "#2d6cb5", "weapon": "#1a1a1a",
        "bulk": 1.05, "vest": (0.36, 0.46), "pack": (0.18, 0.44, 0.32),
        "gun_len": 0.56, "antennas": True,
        "extras": [
            ("accent", (0.46, 1.255, 0.16), (0.28, 0.035, 0.052)),  # blue shotgun furniture
            ("accent", (0.195, 1.33, 0.08), (0.04, 0.10, 0.07)),    # RF detector on the vest
        ],
    },
}


def pad(data: bytes, alignment: int, filler: bytes) -> bytes:
    remainder = len(data) % alignment
    return data if remainder == 0 else data + filler * (alignment - remainder)


def write_glb(path: str, name: str, spec: dict) -> tuple[int, int]:
    prims = build_figure(spec)
    colours = {
        "base": rgba(spec["base"]), "gear": rgba(spec["gear"]), "bone": rgba(BONE),
        "weapon": rgba(spec["weapon"]), "accent": rgba(spec["accent"]), "chip": rgba(CHIP),
    }
    order = [m for m in ("base", "gear", "bone", "weapon", "accent") if prims[m]["indices"]]

    binary = bytearray()
    buffer_views: list[dict] = []
    accessors: list[dict] = []

    def push(blob: bytes, target: int) -> int:
        while len(binary) % 4:
            binary.append(0)
        buffer_views.append({"buffer": 0, "byteOffset": len(binary), "byteLength": len(blob), "target": target})
        binary.extend(blob)
        return len(buffer_views) - 1

    def vec3_accessor(rows: list[tuple[float, float, float]], with_bounds: bool) -> int:
        blob = b"".join(struct.pack("<fff", *row) for row in rows)
        view = push(blob, 34962)
        accessor = {"bufferView": view, "componentType": 5126, "count": len(rows), "type": "VEC3"}
        if with_bounds:
            accessor["min"] = [round(min(r[i] for r in rows), 6) for i in range(3)]
            accessor["max"] = [round(max(r[i] for r in rows), 6) for i in range(3)]
        accessors.append(accessor)
        return len(accessors) - 1

    def index_accessor(indices: list[int]) -> int:
        blob = b"".join(struct.pack("<H", i) for i in indices)
        view = push(blob, 34963)
        accessors.append({"bufferView": view, "componentType": 5123, "count": len(indices), "type": "SCALAR"})
        return len(accessors) - 1

    def primitive(material_index: int, prim: dict) -> dict:
        return {
            "attributes": {
                "POSITION": vec3_accessor(prim["positions"], with_bounds=True),
                "NORMAL": vec3_accessor(prim["normals"], with_bounds=False),
            },
            "indices": index_accessor(prim["indices"]),
            "material": material_index,
        }

    materials = [
        {
            "name": material,
            "pbrMetallicRoughness": {
                "baseColorFactor": colours[material], "metallicFactor": 0.0, "roughnessFactor": 0.9,
            },
        }
        for material in order + ["chip"]
    ]
    body = [primitive(i, prims[m]) for i, m in enumerate(order)]
    chip = [primitive(len(order), prims["chip"])]

    gltf = {
        "asset": {"version": "2.0", "generator": "gcity tools/asset_gen/gen_operator_models.py"},
        "scene": 0,
        "scenes": [{"nodes": [0]}],
        "nodes": [
            {"name": name, "mesh": 0, "children": [1]},
            {"name": "StanceChip", "mesh": 1},
        ],
        "meshes": [{"name": name + "_body", "primitives": body}, {"name": "StanceChip", "primitives": chip}],
        "materials": materials,
        "accessors": accessors,
        "bufferViews": buffer_views,
        "buffers": [{"byteLength": len(pad(bytes(binary), 4, b"\x00"))}],
    }

    json_chunk = pad(json.dumps(gltf, separators=(",", ":"), sort_keys=True).encode("utf-8"), 4, b" ")
    bin_chunk = pad(bytes(binary), 4, b"\x00")
    total = 12 + 8 + len(json_chunk) + 8 + len(bin_chunk)
    with open(path, "wb") as handle:
        handle.write(struct.pack("<III", 0x46546C67, 2, total))
        handle.write(struct.pack("<II", len(json_chunk), 0x4E4F534A))
        handle.write(json_chunk)
        handle.write(struct.pack("<II", len(bin_chunk), 0x004E4942))
        handle.write(bin_chunk)

    triangles = sum(len(prims[m]["indices"]) for m in order + ["chip"]) // 3
    return triangles, total


def main() -> int:
    os.makedirs(OUT_DIR, exist_ok=True)
    failures = 0
    for name, spec in VARIANTS.items():
        path = os.path.join(OUT_DIR, name + ".glb")
        triangles, size = write_glb(path, name, spec)
        material_count = MAX_MATERIALS  # base, gear, bone, weapon, accent, chip
        within = triangles <= MAX_TRIANGLES and size <= MAX_BYTES and material_count <= MAX_MATERIALS
        print(f"{name}: {triangles} triangles, {material_count} materials, {size} bytes"
              + ("" if within else "  OVER BUDGET"))
        if not within:
            failures += 1
    return 1 if failures else 0


if __name__ == "__main__":
    raise SystemExit(main())

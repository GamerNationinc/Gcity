#!/usr/bin/env python3
"""Architectural fitness function (design doc §4.2, engineering standards §1.1, §3.7).

Rules, checked over every .gd, .tscn and .tres file:

1. Nothing under sim/ may reference anything under client/: not by resource path
   (preload/load/extends/ext_resource) and not by a class_name declared in client/.
2. Nothing under sim/ may use the engine surfaces that make a simulation
   non-authoritative or non-deterministic: input, rendering, UI, audio, wall-clock
   time, OS queries and the global random functions (the sim uses SimRoot.rng()).
3. content/ holds data only: no scripts, no scenes.
4. The device holds no state (design doc §12.1; M5 spec claim 4): a script under
   client/device/ may declare class-level `var`s only of view types (nodes, scenes,
   callables, strings, bools, StringNames) or from the allow-list of view state
   (`_cursor`, `_scroll`, `_page`, `_open_app`, and the map's own draw cache). An int,
   Array or Dictionary member that could hold an entity id, a count or a copy of the
   sim's tables is refused; panes rebuild from the sim every refresh.
5. The client calls no sim setter (M6 spec claim 3): every public `set_*` method
   declared under sim/ is a mutation, so a client file calling one by name writes sim
   state behind SimRoot.submit(). Actors spawn at site points instead of being placed.

Exit status 0 when clean; 1 with one line per violation otherwise. Standard library only.
"""
from __future__ import annotations

import re
import sys
from pathlib import Path

CODE_SUFFIXES = (".gd", ".tscn", ".tres")

# Rule 1: a sim/ file may only reference res:// paths inside these prefixes.
SIM_ALLOWED_PATH_PREFIXES = ("res://sim/",)

# Rule 2: engine identifiers the sim may not touch. Each entry is (regex, reason).
# Matching is on whole identifiers; comments and doc comments are stripped first.
# The global RNG functions are matched only as free calls: `rng().randi()` on a
# seeded RandomNumberGenerator is the sanctioned form.
SIM_DENYLIST: list[tuple[str, str]] = [
    (r"\bInput\b", "input is a client concern"),
    (r"\bInputEvent\w*\b", "input is a client concern"),
    (r"\bInputMap\b", "input is a client concern"),
    (r"\bDisplayServer\b", "rendering is a client concern"),
    (r"\bRenderingServer\b", "rendering is a client concern"),
    (r"\bAudioServer\b", "audio is a client concern"),
    (r"\bCanvasItem\b", "UI is a client concern"),
    (r"\bCanvasLayer\b", "UI is a client concern"),
    (r"\bControl\b", "UI is a client concern"),
    (r"\bViewport\b", "rendering is a client concern"),
    (r"\bSubViewport\b", "rendering is a client concern"),
    (r"\bWindow\b", "rendering is a client concern"),
    (r"\bCamera2D\b", "rendering is a client concern"),
    (r"\bCamera3D\b", "rendering is a client concern"),
    (r"\bTime\.", "wall-clock time is nondeterministic; the sim only knows ticks"),
    (r"\bOS\.", "OS queries are nondeterministic and platform-bound"),
    (r"\bEngine\.", "engine state (frame counters, time scale) is not sim state"),
    (r"(?<![.\w])randi\s*\(", "global RNG is unseeded; use SimRoot.rng()"),
    (r"(?<![.\w])randf\s*\(", "global RNG is unseeded; use SimRoot.rng()"),
    (r"(?<![.\w])randi_range\s*\(", "global RNG is unseeded; use SimRoot.rng()"),
    (r"(?<![.\w])randf_range\s*\(", "global RNG is unseeded; use SimRoot.rng()"),
    (r"(?<![.\w])randfn\s*\(", "global RNG is unseeded; use SimRoot.rng()"),
    (r"(?<![.\w])randomize\s*\(", "global RNG is unseeded; use SimRoot.rng()"),
    (r"(?<![.\w])rand_from_seed\s*\(", "global RNG is unseeded; use SimRoot.rng()"),
    (r"\.shuffle\s*\(", "Array.shuffle uses the global RNG; shuffle with SimRoot.rng()"),
    (r"\.pick_random\s*\(", "Array.pick_random uses the global RNG; pick with SimRoot.rng()"),
]

# M1 spec claim 15: every gameplay number reads through StatResolver.resolve(). Outside
# the resolver itself nothing under sim/ may read a base or touch modifier storage.
RESOLVER_FILE = "sim/progression/stat_resolver.gd"
RESOLVER_ONLY: list[tuple[str, str]] = [
    (r"\.get_base\s*\(", "bases are the resolver's; gameplay reads resolve()"),
    (r"\b_bases\b", "modifier/base storage is private to the resolver"),
    (r"\b_modifiers\b", "modifier/base storage is private to the resolver"),
]

# M1 spec claim 17: the client reads sim state and submits commands, nothing else. The
# host files build and step the sim; every other client file is a view.
CLIENT_HOST_FILES = {"client/local_host.gd", "client/content_loader.gd"}
CLIENT_DENYLIST: list[tuple[str, str]] = [
    (r"\.step(_n)?\s*\(", "only the host steps the sim"),
    (r"\bSimAssembly\.(build|restore_systems)\s*\(", "only the host builds or restores the sim"),
    (r"\.(spawn|set_base|add_modifier|remove_modifier|set_tags|set_inherits|forget_entity|restore|damage_node"
     r"|consume_chambered|chamber_next|set_busy|allocate|register_system|register_stat|register_modifier_class"
     r"|register_stage|register|subscribe|emit|add)\s*\(", "the client mutates sim state only through SimRoot.submit()"),
]

SIM_SETTER_RE = re.compile(r"^func\s+(set_[A-Za-z0-9_]*)\s*\(", re.MULTILINE)
RES_PATH_RE = re.compile(r'"(res://[^"]*)"')
CLASS_NAME_RE = re.compile(r"^\s*class_name\s+([A-Za-z_][A-Za-z0-9_]*)", re.MULTILINE)
COMMENT_RE = re.compile(r"#.*$", re.MULTILINE)


def strip_comments(text: str) -> str:
    return COMMENT_RE.sub("", text)


def collect_files(root: Path, module: str) -> list[Path]:
    base = root / module
    if not base.is_dir():
        return []
    return sorted(p for p in base.rglob("*") if p.suffix in CODE_SUFFIXES and p.is_file())


def client_class_names(root: Path) -> dict[str, Path]:
    names: dict[str, Path] = {}
    for path in collect_files(root, "client"):
        if path.suffix != ".gd":
            continue
        for match in CLASS_NAME_RE.finditer(path.read_text(encoding="utf-8")):
            names[match.group(1)] = path
    return names


def check_sim_file(path: Path, rel: str, client_classes: dict[str, Path]) -> list[str]:
    text = path.read_text(encoding="utf-8")
    code = strip_comments(text) if path.suffix == ".gd" else text
    problems: list[str] = []
    for line_no, line in enumerate(code.splitlines(), start=1):
        for res_path in RES_PATH_RE.findall(line):
            if not res_path.startswith(SIM_ALLOWED_PATH_PREFIXES):
                problems.append(f"{rel}:{line_no}: sim/ references {res_path}; sim/ may only reference res://sim/")
        for name, declared_in in client_classes.items():
            if re.search(rf"\b{re.escape(name)}\b", line):
                problems.append(
                    f"{rel}:{line_no}: sim/ references client class {name} (declared in {declared_in.as_posix()})"
                )
        if path.suffix == ".gd":
            for pattern, reason in SIM_DENYLIST:
                match = re.search(pattern, line)
                if match:
                    problems.append(f"{rel}:{line_no}: sim/ uses {match.group(0).strip()}: {reason}")
            if rel != RESOLVER_FILE:
                for pattern, reason in RESOLVER_ONLY:
                    match = re.search(pattern, line)
                    if match:
                        problems.append(f"{rel}:{line_no}: {match.group(0).strip()}: {reason}")
    return problems


def sim_setter_names(root: Path) -> set[str]:
    """Rule 5: every public set_* method declared by a script under sim/."""
    names: set[str] = set()
    for path in collect_files(root, "sim"):
        if path.suffix == ".gd":
            names.update(SIM_SETTER_RE.findall(strip_comments(path.read_text(encoding="utf-8"))))
    return names


def check_client_file(path: Path, rel: str, sim_setters: set[str] = frozenset()) -> list[str]:
    if path.suffix != ".gd" or rel in CLIENT_HOST_FILES:
        return []
    code = strip_comments(path.read_text(encoding="utf-8"))
    setter_re = re.compile(r"\.(" + "|".join(sorted(sim_setters)) + r")\s*\(") if sim_setters else None
    problems: list[str] = []
    for line_no, line in enumerate(code.splitlines(), start=1):
        for pattern, reason in CLIENT_DENYLIST:
            match = re.search(pattern, line)
            if match:
                problems.append(f"{rel}:{line_no}: client view calls {match.group(0).strip()}: {reason}")
        if setter_re is not None:
            match = setter_re.search(line)
            if match:
                problems.append(f"{rel}:{line_no}: client calls the sim setter {match.group(1)}(): the client requests, the sim decides (rule 5)")
    return problems


# Rule 4: class-level vars a device script may keep between frames.
DEVICE_STATE_TYPES = ("Control", "Label", "RichTextLabel", "ColorRect", "Node", "PackedScene", "Callable", "String", "bool", "StringName",
                      "DeviceApp", "InputGlyphs", "ContentDb", "Dictionary[StringName, PackedScene]", "PackedVector2Array", "Vector3i", "float")
DEVICE_STATE_NAMES = {"_cursor", "_scroll", "_page", "_open_app", "_last_text", "_last_strip", "_last_status", "_last_prompts", "_note_text", "_note_shown", "_last_key",
                      "_parcels", "_pieces", "_others", "_me", "_me_yaw"}
VAR_RE = re.compile(r"^var\s+(\w+)\s*(?::\s*([\w\[\], ]+?))?\s*(?:=|$)", re.MULTILINE)


def check_device_file(path: Path, rel: str) -> list[str]:
    """Rule 4 for one file under client/device/."""
    text = strip_comments(path.read_text(encoding="utf-8"))
    problems: list[str] = []
    for m in VAR_RE.finditer(text):
        name, declared = m.group(1), (m.group(2) or "").strip()
        if name in DEVICE_STATE_NAMES or declared in DEVICE_STATE_TYPES:
            continue
        problems.append(f"{rel}: `var {name}` ({declared or 'untyped'}) keeps state between frames; the device holds none (rule 4)")
    return problems


def check_content(root: Path) -> list[str]:
    base = root / "content"
    if not base.is_dir():
        return []
    problems: list[str] = []
    for path in sorted(base.rglob("*")):
        if path.is_file() and path.suffix in CODE_SUFFIXES:
            problems.append(f"{path.relative_to(root).as_posix()}: content/ holds data only; no scripts or scenes")
    return problems


def run(root: Path) -> list[str]:
    client_classes = client_class_names(root)
    sim_setters = sim_setter_names(root)
    problems: list[str] = []
    for path in collect_files(root, "client"):
        problems.extend(check_client_file(path, path.relative_to(root).as_posix(), sim_setters))
    for path in collect_files(root, "sim"):
        problems.extend(check_sim_file(path, path.relative_to(root).as_posix(), client_classes))
    problems.extend(check_content(root))
    for path in sorted((root / "client" / "device").rglob("*.gd")):
        problems.extend(check_device_file(path, path.relative_to(root).as_posix()))
    return problems


def main(argv: list[str]) -> int:
    root = Path(argv[1]) if len(argv) > 1 else Path(__file__).resolve().parent.parent
    problems = run(root)
    for problem in problems:
        print(problem)
    if problems:
        print(f"check_dependencies: {len(problems)} violation(s)")
        return 1
    print("check_dependencies: clean")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))

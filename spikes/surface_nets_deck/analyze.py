#!/usr/bin/env python3
"""Turns a soak JSON (+ thermal CSV) and a bench JSON into the markdown tables for
docs/specs/spike-surface-nets-deck.md §5. Standard library only.

usage: analyze.py results/soak-plugged.json [results/soak-plugged-thermal.csv] [results/bench.json]
"""
import csv
import json
import statistics
import sys


def fmt(v, nd=2):
    return f"{v:.{nd}f}" if isinstance(v, float) else str(v)


def soak_tables(path):
    d = json.load(open(path))
    p = d["params"]
    fw = d["final_window"]
    wr = d["whole_run"]
    out = []
    out.append(f"Run: `{path}` — Godot {d['engine']}, {int(p['duration_s'])} s, {p['workers']} workers, "
               f"radius {p['radius']}/±{p['vradius']} chunks, ≤{p['uploads_per_frame']} uploads/frame, "
               f"{p['speed_m_s']} m/s, dig every {p['edit_interval_s']} s, seed {p['seed']}, vsync {p['vsync']}, uncapped.\n")
    out.append("| Metric (final 5 min unless noted) | Value | Pass |")
    out.append("|---|---|---|")
    out.append(f"| Frame time p50 | {fmt(fw['p50_ms'])} ms | |")
    out.append(f"| **Frame time 1% low (p99)** | **{fmt(fw['p99_ms'])} ms** | {'**pass**' if d['pass']['frame_p99_within_25ms'] else '**FAIL**'} (≤ 25.0) |")
    out.append(f"| Frame time 0.1% low (p99.9) | {fmt(fw['p999_ms'])} ms | |")
    out.append(f"| Worst frame | {fmt(fw['max_ms'])} ms | |")
    out.append(f"| Frames over 25 ms | {fw['over_budget_frac']*100:.3f} % | |")
    out.append(f"| Average frame rate | {fmt(fw['fps_avg'],1)} fps | |")
    out.append(f"| **Meshing, amortised per 40 fps frame** (workers + upload) | **{fmt(fw['meshing_ms_per_40fps_frame'])} ms** | {'**pass**' if d['pass']['meshing_within_3ms'] else '**FAIL**'} (≤ 3.0) |")
    out.append(f"| of which main-thread upload per 40 fps frame | {fmt(fw['upload_ms_per_40fps_frame'])} ms | |")
    out.append(f"| Chunks re/meshed per second | {fmt(fw['chunks_per_s'],1)} | |")
    out.append(f"| Worker time per chunk (generation + meshing) | {fmt(fw['worker_us_per_chunk']/1000)} ms | |")
    out.append(f"| Main-thread upload per chunk | {fmt(fw['upload_us_per_chunk']/1000)} ms | |")
    out.append(f"| Whole run: p99 / p99.9 / worst | {fmt(wr['p99_ms'])} / {fmt(wr['p999_ms'])} / {fmt(wr['max_ms'])} ms | |")
    out.append(f"| Whole run: meshing per 40 fps frame | {fmt(wr['meshing_ms_per_40fps_frame'])} ms | |")
    out.append(f"| Generation / meshing per meshed chunk (all workers, whole run) | {d['gen_us_per_meshed_chunk']/1000:.2f} / {d['mesh_us_per_meshed_chunk']/1000:.2f} ms | |")
    out.append(f"| Resident chunks / triangles at end | {d['resident_chunks_end']} / {d['triangles_end']:,} | |")
    out.append(f"| Peak backlog (queued + in flight + waiting) | {d['peak_backlog']} chunks | |")
    out.append(f"| Edits applied | {d['edits']} | |")
    ws = d["worker_stats"]
    out.append(f"| Worker totals: meshed / skipped as air / stale dropped | {ws['meshed']} / {ws['skipped_air']} / {ws['stale_dropped']} | |")
    out.append("")
    out.append("Per minute:")
    out.append("")
    out.append("| min | fps | p50 | p99 | p99.9 | max | >25 ms | meshing ms/40fps-frame | chunks/s | resident | tris | backlog |")
    out.append("|---|---|---|---|---|---|---|---|---|---|---|---|")
    for m in d["minutes"]:
        out.append(f"| {m['minute']} | {m['fps_avg']:.0f} | {m['p50_ms']:.2f} | {m['p99_ms']:.2f} | {m['p999_ms']:.2f} | {m['max_ms']:.1f} | "
                   f"{m['over_budget_frac']*100:.2f}% | {m['meshing_ms_per_40fps_frame']:.2f} | {m['chunks_per_s']:.1f} | "
                   f"{m['resident_chunks']} | {m['triangles']:,} | {m['backlog']} |")
    out.append("")
    return out, d


def thermal_table(path):
    rows = list(csv.DictReader(open(path)))
    if not rows:
        return ["(no thermal samples)"]
    def col(name, conv=float):
        vals = []
        for r in rows:
            try:
                vals.append(conv(r[name]))
            except (ValueError, KeyError):
                pass
        return vals
    n = len(rows)
    first = rows[: max(1, n // 6)]
    last = rows[-max(1, n // 6):]
    def seg(rs, name):
        v = []
        for r in rs:
            try:
                v.append(float(r[name]))
            except (ValueError, KeyError):
                pass
        return (statistics.mean(v) if v else float("nan"))
    out = ["| Sensor | first 5 min (mean) | last 5 min (mean) | peak |", "|---|---|---|---|"]
    for name, label, nd in [("gpu_edge_c", "SoC edge temperature (amdgpu)", 1), ("acpi_c", "ACPI thermal zone", 1),
                            ("cpu_mhz_avg", "CPU clock, mean of 8 threads (MHz)", 0), ("gpu_mhz", "GPU clock (MHz)", 0),
                            ("gpu_power_w", "GPU/SoC power (W)", 2), ("mem_avail_mb", "Memory available (MB)", 0)]:
        vals = col(name)
        if not vals:
            continue
        peak = max(vals) if name != "mem_avail_mb" else min(vals)
        out.append(f"| {label} | {seg(first, name):.{nd}f} | {seg(last, name):.{nd}f} | {peak:.{nd}f}{' (min)' if name == 'mem_avail_mb' else ''} |")
    bat = {r.get("bat_status", "") for r in rows}
    out.append(f"| Battery status during run | {', '.join(sorted(b for b in bat if b))} | | |")
    out.append("")
    return out


def bench_table(path):
    d = json.load(open(path))
    out = [f"Rust vs GDScript, same algorithm, same {len(d['rows'])} chunks (mean of 5 Rust runs each):", "",
           "| chunk | vertices | Rust | GDScript | ratio | equal output |", "|---|---|---|---|---|---|"]
    for r in d["rows"]:
        out.append(f"| {tuple(r['coord'])} | {r['vertices']} | {r['rust_us']/1000:.2f} ms | {r['gdscript_us']/1000:.1f} ms | ×{r['ratio']:.0f} | {'yes' if r['equal'] else 'NO'} |")
    out.append(f"| **total** | | {d['rust_total_us']/1000:.1f} ms | {d['gdscript_total_us']/1000:.0f} ms | **×{d['ratio']:.0f}** | {'all equal' if d['all_equal'] else 'MISMATCH'} |")
    out.append("")
    out.append(f"Tier 1 criterion (≥5× with equal output): {'**pass**' if d['pass_5x_equal_output'] else '**FAIL**'}.")
    out.append("")
    return out


if __name__ == "__main__":
    args = sys.argv[1:]
    if not args:
        sys.exit(__doc__)
    lines, _ = soak_tables(args[0])
    print("\n".join(lines))
    if len(args) > 1 and args[1].endswith(".csv"):
        print("\n".join(thermal_table(args[1])))
        args = args[:1] + args[2:]
    if len(args) > 1:
        print("\n".join(bench_table(args[1])))

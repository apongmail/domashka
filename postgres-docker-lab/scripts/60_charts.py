#!/usr/bin/env python3
"""Графіки з results/benchmark.csv + benchmark_meta.csv → results/charts/*.svg

Медіана трьох прогонів; групований бар-чарт: X = клієнти, серії = варіанти.
Палітра: категоріальні слоти 1–4 (перевірено validate_palette.js, light).
"""
import csv
import statistics as st
from pathlib import Path

import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt

ROOT = Path(__file__).resolve().parent.parent
CHARTS = ROOT / "results" / "charts"
CHARTS.mkdir(parents=True, exist_ok=True)

VARIANTS = ["HOST", "LAYER", "VOLUME", "BIND"]
COLORS = {"HOST": "#2a78d6", "LAYER": "#eb6834", "VOLUME": "#1baf7a", "BIND": "#eda100"}
SURFACE = "#ffffff"
INK = "#0b0b0b"
INK2 = "#52514e"
GRID = "#e6e5e1"

plt.rcParams.update({
    "figure.facecolor": SURFACE, "axes.facecolor": SURFACE,
    "text.color": INK, "axes.edgecolor": GRID,
    "axes.labelcolor": INK2, "xtick.color": INK2, "ytick.color": INK2,
    "font.size": 11, "svg.fonttype": "none",
})

rows = list(csv.DictReader(open(ROOT / "results" / "benchmark.csv")))
meta = {r["variant"]: r for r in csv.DictReader(open(ROOT / "results" / "benchmark_meta.csv"))}
CLIENTS = sorted({int(r["clients"]) for r in rows})


def med(variant, clients, field):
    vals = [float(r[field]) for r in rows
            if r["variant"] == variant and int(r["clients"]) == clients and r[field]]
    return st.median(vals) if vals else 0.0


def grouped_bar(title, ylabel, values, fname, fmt="{:.0f}", groups=None, note=None):
    groups = groups or [str(c) for c in CLIENTS]
    n_g, n_v = len(groups), len(VARIANTS)
    width = 0.19
    fig, ax = plt.subplots(figsize=(8.4, 4.2), dpi=100)
    for vi, var in enumerate(VARIANTS):
        xs = [gi + (vi - (n_v - 1) / 2) * width for gi in range(n_g)]
        ys = values[var]
        ax.bar(xs, ys, width * 0.92, color=COLORS[var], label=var,
               edgecolor=SURFACE, linewidth=1)
        for x, y in zip(xs, ys):
            ax.annotate(fmt.format(y), (x, y), ha="center", va="bottom",
                        fontsize=8.5, color=INK)
    ax.set_xticks(range(n_g), groups)
    ax.set_ylabel(ylabel)
    ax.set_title(title, loc="left", fontsize=13, color=INK, pad=14)
    ax.yaxis.grid(True, color=GRID, linewidth=0.8)
    ax.set_axisbelow(True)
    for s in ("top", "right", "left"):
        ax.spines[s].set_visible(False)
    ax.legend(frameon=False, ncols=n_v, loc="upper left",
              bbox_to_anchor=(0, 1.02), fontsize=9)
    ax.margins(y=0.15)
    if note:
        fig.text(0.01, 0.01, note, fontsize=8, color=INK2)
    fig.tight_layout(rect=(0, 0.03 if note else 0, 1, 1))
    fig.savefig(CHARTS / fname, format="svg")
    plt.close(fig)
    print("wrote", CHARTS / fname)


# 1. TPS
grouped_bar(
    "TPS (медіана 3 прогонів, більше — краще)", "транзакцій/с",
    {v: [med(v, c, "tps") for c in CLIENTS] for v in VARIANTS},
    "tps.svg", groups=[f"{c} кл." for c in CLIENTS])

# 2. Latency
grouped_bar(
    "Середня затримка (медіана 3 прогонів, менше — краще)", "мс",
    {v: [med(v, c, "latency_avg_ms") for c in CLIENTS] for v in VARIANTS},
    "latency.svg", fmt="{:.2f}", groups=[f"{c} кл." for c in CLIENTS])

# 3. Пам'ять: idle + під навантаженням
mem_vals = {v: [float(meta[v]["idle_mem_mb"])] + [med(v, c, "mem_mb") for c in CLIENTS]
            for v in VARIANTS}
grouped_bar(
    "Пам'ять PostgreSQL: idle та під навантаженням", "MB",
    mem_vals, "memory.svg",
    groups=["idle"] + [f"{c} кл." for c in CLIENTS],
    note="docker stats (контейнери) і ps RSS (native) рахують пам'ять по-різному — "
         "порівнювати можна лише порядок величин, див. звіт.")

# 4. Час запуску та ініціалізації pgbench
fig, axes = plt.subplots(1, 2, figsize=(8.4, 3.4), dpi=100)
for ax, field, title, unit, fmt in (
        (axes[0], "startup_ms", "Час запуску PostgreSQL", "мс", "{:.0f}"),
        (axes[1], "init_seconds", "pgbench -i -s 30", "с", "{:.1f}")):
    ys = [float(meta[v][field]) for v in VARIANTS]
    ax.bar(range(len(VARIANTS)), ys, 0.55,
           color=[COLORS[v] for v in VARIANTS], edgecolor=SURFACE, linewidth=1)
    for x, y in enumerate(ys):
        ax.annotate(fmt.format(y), (x, y), ha="center", va="bottom",
                    fontsize=9, color=INK)
    ax.set_xticks(range(len(VARIANTS)), VARIANTS, fontsize=9)
    ax.set_title(title + f" ({unit})", loc="left", fontsize=11, color=INK)
    ax.yaxis.grid(True, color=GRID, linewidth=0.8)
    ax.set_axisbelow(True)
    for s in ("top", "right", "left"):
        ax.spines[s].set_visible(False)
    ax.margins(y=0.2)
fig.tight_layout()
fig.savefig(CHARTS / "startup_init.svg", format="svg")
plt.close(fig)
print("wrote", CHARTS / "startup_init.svg")

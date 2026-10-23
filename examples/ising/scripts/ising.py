"""The 2D Ising model: a sheet of tiny magnets that line up when it is cold and scramble when it is hot.

    python scripts/ising.py configs/ising_L16.json

Each site of an L x L grid holds a magnet pointing up or down. Neighbours that agree lower the energy; heat makes
them flip at random. Cool the grid and, below a critical temperature, most magnets suddenly agree: order appears
out of disorder, a phase change. Lars Onsager solved this model exactly in 1944, so the answer is known:

- the critical temperature is Tc = 2 / ln(1 + sqrt 2) = 2.2692 (in units where the coupling and Boltzmann's
  constant are 1);
- below Tc, an infinitely large grid has magnetization m = (1 - sinh(2/T)^-4)^(1/8), and above it m = 0.

A finite grid cannot jump exactly: its change is smeared over a range of temperatures, and the range narrows as the
grid grows. Running one size per job and comparing them shows that sharpening directly. Far from Tc the simulated
magnetization should match Onsager's to about 0.01; near Tc a finite grid is expected to differ.

Method: Metropolis single-spin flips, fresh all-up start at each temperature, warm-up sweeps discarded, then the
average |m| and the energy per site over the measurement sweeps. Standard library only.

Writes <output>/ising.csv, where <output> is $SIM_OUTPUT_DIR in the cloud and results/<run>/ locally.
"""
import csv
import json
import math
import os
import random
import sys
from pathlib import Path

TC = 2 / math.log(1 + math.sqrt(2))


def onsager_m(t):
    """Magnetization per site of the infinite grid at temperature t (exact)."""
    return (1 - math.sinh(2 / t) ** -4) ** 0.125 if t < TC else 0.0


def run_temperature(size, t, warmup, sweeps, rng):
    """(mean |m|, mean energy per site) over `sweeps` measurement sweeps."""
    n = size * size
    spins = [1] * n
    right = [(i // size) * size + (i + 1) % size for i in range(n)]
    left = [(i // size) * size + (i - 1) % size for i in range(n)]
    down = [(i + size) % n for i in range(n)]
    up = [(i - size) % n for i in range(n)]
    # A flip changes the energy by 2 s (sum of the four neighbours): 0, 4 or 8 when it costs. Accept with exp(-dE/t).
    accept = {4: math.exp(-4 / t), 8: math.exp(-8 / t)}
    rand, randrange = rng.random, rng.randrange
    m_sum = e_sum = 0.0
    for sweep in range(warmup + sweeps):
        for _ in range(n):
            i = randrange(n)
            s = spins[i]
            d_e = 2 * s * (spins[right[i]] + spins[left[i]] + spins[down[i]] + spins[up[i]])
            if d_e <= 0 or rand() < accept[d_e]:
                spins[i] = -s
        if sweep >= warmup:
            m_sum += abs(sum(spins)) / n
            e_sum += -sum(spins[i] * (spins[right[i]] + spins[down[i]]) for i in range(n)) / n
    return m_sum / sweeps, e_sum / sweeps


def main(config_path):
    config_path = Path(config_path)
    cfg = json.loads(config_path.read_text(encoding="utf-8"))
    out = Path(os.environ.get("SIM_OUTPUT_DIR") or Path("results") / config_path.stem)
    out.mkdir(parents=True, exist_ok=True)
    rng = random.Random(cfg["seed"])
    with open(out / "ising.csv", "w", newline="", encoding="utf-8") as fh:
        w = csv.writer(fh)
        w.writerow(["size", "temperature", "magnetization", "onsager_infinite_grid", "difference",
                    "energy_per_site", "sweeps"])
        for t in cfg["temperatures"]:
            m, e = run_temperature(cfg["size"], t, cfg["warmup_sweeps"], cfg["sweeps"], rng)
            exact = onsager_m(t)
            w.writerow([cfg["size"], t, "%.4f" % m, "%.4f" % exact, "%+.4f" % (m - exact), "%.4f" % e,
                        cfg["sweeps"]])
            print("L=%d  T=%.2f  |m| = %.3f   Onsager (infinite grid) %.3f" % (cfg["size"], t, m, exact))


if __name__ == "__main__":
    main(sys.argv[1])

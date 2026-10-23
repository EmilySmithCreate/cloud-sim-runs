"""The birthday problem by simulation: how many people in a room before two of them probably share a birthday?

    python scripts/birthday.py configs/birthday_a.json

For each room size in the config, fill `trials` rooms with random birthdays (365 equally likely days) and count how
often two people share one. The exact answer is known, so the output carries both: a check of the whole cloud loop
against a number nobody has to trust. Standard library only.

Writes <output>/birthday.csv, where <output> is $SIM_OUTPUT_DIR in the cloud and results/<run>/ locally.
"""
import csv
import json
import os
import random
import sys
from pathlib import Path


def exact(people, days=365):
    """Probability that at least two of `people` share a birthday."""
    p_distinct = 1.0
    for k in range(people):
        p_distinct *= (days - k) / days
    return 1.0 - p_distinct


def simulate(people, trials, rng, days=365):
    shared = 0
    for _ in range(trials):
        seen = set()
        for _ in range(people):
            b = rng.randrange(days)
            if b in seen:
                shared += 1
                break
            seen.add(b)
    return shared / trials


def main(config_path):
    config_path = Path(config_path)
    cfg = json.loads(config_path.read_text(encoding="utf-8"))
    out = Path(os.environ.get("SIM_OUTPUT_DIR") or Path("results") / config_path.stem)
    out.mkdir(parents=True, exist_ok=True)
    rng = random.Random(cfg["seed"])
    with open(out / "birthday.csv", "w", newline="", encoding="utf-8") as fh:
        w = csv.writer(fh)
        w.writerow(["people", "trials", "simulated", "exact", "difference"])
        for people in range(cfg["people_from"], cfg["people_to"] + 1):
            sim = simulate(people, cfg["trials"], rng)
            ex = exact(people)
            w.writerow([people, cfg["trials"], "%.5f" % sim, "%.5f" % ex, "%+.5f" % (sim - ex)])
            print("%3d people: simulated %.4f, exact %.4f" % (people, sim, ex))


if __name__ == "__main__":
    main(sys.argv[1])

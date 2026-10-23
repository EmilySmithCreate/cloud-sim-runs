"""Check runs fetched into cloud/inbox/ against their committed configs, and move the ones that pass into results/.

    python infra/cloud-sim/accept_runs.py           # check only; says what would move
    python infra/cloud-sim/accept_runs.py --move    # check, then move every run that passes

The sim_fetch workflow copies finished runs from the results bucket into cloud/inbox/<run>/. A run passes when:

1. it has a _run.json saying it succeeded;
2. configs/<run>.json exists and its SHA-256 is the one recorded in _run.json (that is, the run used the config as
   it is committed; Windows line endings are allowed for);
3. it has at least one output file besides _run.json;
4. results/<run> does not exist yet. Results are added, never overwritten.

Warned about, not refused: an image built from a different commit than the one that submitted the job (a newer push
rebuilt the image while the job waited in the queue). A run that fails stays in the inbox, with the reason printed.
Standard library only.
"""
import hashlib
import json
import shutil
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]


def config_hashes(path):
    """SHA-256 of the file as stored, and with CRLF turned into LF (a Windows checkout of an LF file)."""
    data = path.read_bytes()
    return {hashlib.sha256(data).hexdigest(), hashlib.sha256(data.replace(b"\r\n", b"\n")).hexdigest()}


def check(run_dir, configs, results):
    """(ok, reasons, warnings) for one fetched run folder."""
    name = run_dir.name
    reasons, warnings = [], []
    record_path = run_dir / "_run.json"
    if not record_path.is_file():
        return False, ["no _run.json"], warnings
    record = json.loads(record_path.read_text(encoding="utf-8"))
    if record.get("status") != "succeeded":
        reasons.append("status is %r, not 'succeeded'" % record.get("status"))
    cfg = configs / (name + ".json")
    if not cfg.is_file():
        reasons.append("no committed config configs/%s.json" % name)
    elif record.get("config_sha256") not in config_hashes(cfg):
        reasons.append("configs/%s.json differs from the config the run used" % name)
    if not any(p.name != "_run.json" for p in run_dir.iterdir()):
        reasons.append("no output files")
    if (results / name).exists():
        reasons.append("results/%s already exists" % name)
    submitted, image = record.get("submitted_commit", ""), record.get("image_commit", "")
    if submitted and image and not image.startswith(submitted) and not submitted.startswith(image):
        warnings.append("submitted from %s but the image was built from %s" % (submitted, image[:12]))
    return not reasons, reasons, warnings


def main(argv, root=ROOT):
    inbox, configs, results = root / "cloud" / "inbox", root / "configs", root / "results"
    runs = sorted(p for p in inbox.iterdir() if p.is_dir()) if inbox.is_dir() else []
    if not runs:
        print("nothing in cloud/inbox/")
        return 0
    move = "--move" in argv
    passed = 0
    for run_dir in runs:
        ok, reasons, warnings = check(run_dir, configs, results)
        print("%s  %s" % ("PASS" if ok else "FAIL", run_dir.name))
        for r in reasons:
            print("      " + r)
        for w in warnings:
            print("      warning: " + w)
        if ok:
            passed += 1
            if move:
                results.mkdir(exist_ok=True)
                shutil.move(str(run_dir), str(results / run_dir.name))
    print("%d of %d pass%s" % (passed, len(runs), "; moved into results/" if move and passed else ""))
    return 0 if passed == len(runs) else 1


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))

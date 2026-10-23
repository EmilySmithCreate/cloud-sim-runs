---
name: cloud-sim-runs
description: Run batches of simulations or other long, independent compute jobs on rented AWS cloud CPUs (AWS Batch on Fargate) by pushing a queue file to GitHub, then check their status, fetch results back into the repository and cancel jobs, with no AWS credentials needed on the laptop. Use when the user wants to run many independent simulations, parameter sweeps, Monte Carlo runs, resampling or other jobs too slow or too many for one machine; when they want to set up that cloud machinery in a repository; or when they ask what is running, to fetch results, or to cancel cloud runs.
---

# Cloud simulation runs

One config file describes one run. A queue file lists runs. Pushing the queue file to GitHub builds a container
image from that commit and submits one AWS Batch job per line. Each job runs on its own rented CPU, and its output
goes to a private S3 bucket. Results come back into the repository only when someone asks for them. They count as
results only after a check confirms they came from the committed config.

```
configs/<run>.json --> cloud/queue/<batch>.txt --push--> GitHub Actions --> AWS Batch (Fargate)
                                                                              |
results/<run>/ <-- accept_runs.py <-- cloud/inbox/<run>/ <--fetch-- S3 bucket <--+
```

The agent never holds AWS credentials. Everything goes through GitHub: pushing a file under `cloud/` is how you
submit, check, fetch and cancel. GitHub signs in to AWS with short-lived OIDC tokens.

## First: is it set up in this repository?

Check for all three:

- `infra/cloud-sim/` (Terraform, Dockerfile, `run.sh`)
- `.github/workflows/sim_queue.yml` and its four siblings
- the repository variable `AWS_ACCOUNT_ID` (`gh variable list`)

If any is missing, follow [reference/setup.md](reference/setup.md) before doing anything else. Setup has steps
only a person can do (signing in to AWS once, approving a deploy). Walk the user through them; do not try to get
around them.

## The run contract

A **runner** is a script at `scripts/<runner>.py` (or an executable `scripts/<runner>`). A **config** is
`configs/<run>.json`. In the cloud, the container runs:

```
python scripts/<runner>.py configs/<run>.json
```

with the environment variable `SIM_OUTPUT_DIR` set to an empty folder. The runner writes everything it produces
into that folder. `run.sh` adds `_run.json` beside the outputs, recording the runner, the config's SHA-256, the
commit that submitted the job, the commit the image was built from, start and end times and the exit status.

Rules that keep this checkable:

- Run names (config file names without `.json`) use only letters, digits, `-` and `_`.
- **Seeds go in the config.** A run must be reproducible from its config and its commit alone.
- **A config is never edited after it has been submitted.** To change a run, make a new config with a new
  name. The queue skips any config whose result already exists, so a rerun under the same name does nothing.
- Runners must also work locally: when `SIM_OUTPUT_DIR` is unset, write to `results/<run>/`.

## Running a batch

1. **Write the configs**, one per independent run. Split replicas and parameter points into separate configs:
   parallel jobs are where the speed comes from.
2. **Run one small config locally first** and read its output:
   `SIM_OUTPUT_DIR=/tmp/try python scripts/<runner>.py configs/<small>.json`. A bug found here costs nothing.
3. **Estimate the cost and tell the user before pushing**: jobs × hours per job × the hourly price
   (about $0.05 for 1 vCPU and 2 GB on Fargate in us-east-1; check the current price for other sizes and
   regions). **Get the user's explicit yes** before submitting more than about $5 of compute or more than 100 jobs.
4. **Write the queue file** `cloud/queue/<YYYY-MM-DD>_<label>.txt`, one job per line as `<runner> <run>`.
   Lines starting with `#` are comments. Start it with a comment saying what the batch is for.
5. **Commit the configs and the queue file together, on a branch that is not `main`**, and push. The queue
   workflow never runs on `main` (see Pitfalls).
6. **Read the submission**: `gh run list --workflow sim_queue.yml --limit 3`, then `gh run view <id>`. The run
   summary lists each job submitted or skipped.

## Checking what is running

Write the current time into `cloud/status/request.txt`, commit, push, wait about a minute, then `git pull` and
read `cloud/status/latest.md`. It lists jobs by state and the finished runs in the bucket. `gh run watch` follows
the workflow itself.

Fargate jobs usually take a minute or two to start. RUNNABLE for much longer usually means the vCPU cap
(`max_vcpus`) or the account's Fargate quota is full, not that something broke.

## Fetching results

1. Put the run names or shell patterns (`sweep_a_*`) in `cloud/fetch/request.txt`, one per line, then commit and
   push.
2. Wait for `sim_fetch` to finish, then `git pull`. Runs appear under `cloud/inbox/<run>/`, with a summary in
   `cloud/inbox/FETCHED.md`.
3. Check them: `python infra/cloud-sim/accept_runs.py`. It confirms that each run succeeded, that its config hash
   matches the committed config, and that nothing in `results/` would be overwritten. It warns if the image ran
   code from a different commit than the one that submitted the job.
4. If they pass: `python infra/cloud-sim/accept_runs.py --move`, then commit the move with a message naming the
   runs.
5. **Read the results before saying anything about them.** A run that finished is not a run that worked.

## Cancelling

Every job is named `<run>-<first 7 characters of the submitting commit>`. To cancel a submission, put that
7-character prefix in a new file `cloud/cancel/<YYYY-MM-DD>_<reason>.txt`, then commit and push. Every unfinished
job from that commit stops. Finished results are left alone.

## Pitfalls (each one happened at least once in the setup this skill came from)

- **Merging into `main` resubmits everything.** A merge carries queue files that `main` has not seen. The queue
  workflow therefore ignores `main`, and skips runs that are finished or still running, but do not count on the
  second guard alone.
- **The image tag is `latest`.** A job that waits in the queue while a newer push rebuilds the image runs the
  newer code. `_run.json` records both commits and `accept_runs.py` warns if they differ. Avoid pushing code
  changes while a batch is still queued.
- **No checkpoints means no Spot.** Fargate Spot costs about 70 % less but can stop a job with two minutes'
  notice. Turn on `use_spot` only if the runners can resume or each job is short.
- **GitHub refuses files over 100 MB.** The fetch stops rather than push half a run. Keep outputs small, or
  download large ones by hand.
- **The status and fetch workflows commit back to your branch.** `git pull` after them, and expect them to fail
  on a protected branch.
- **A job that stops early leaves its scratch under `partial/`** in the bucket, which expires after 14 days. It
  is never fetched.

## When a simulation is the right tool

Good fits: no formula gives the answer; many independent runs (sweeps, seeds, resamples); runs that take hours.
Poor fits: a closed-form answer exists; the job needs a GPU or one very large shared memory (use a bigger single
machine, Spark or Dask instead); each job takes seconds, so container start-up dominates (pack many into one
config); or the data may not leave the user's environment. Say so when a request is a poor fit.

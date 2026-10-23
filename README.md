# cloud-sim-runs

I use this skill to run simulations in the cloud quickly. Add it to your codebase, ask your AI coding agent to set
it up, and watch it work.

You describe each run in a small config file and list the runs in a queue file. Pushing the queue file to GitHub
starts one rented cloud CPU per run. When the runs finish, the agent brings the results back into your repository
and checks that each one came from the config you committed. No AWS keys sit on your laptop, and the agent never
holds any.

```
configs/<run>.json --> cloud/queue/<batch>.txt --push--> GitHub Actions --> AWS Batch (Fargate)
                                                                              |
results/<run>/ <-- accept_runs.py <-- cloud/inbox/<run>/ <--fetch-- S3 bucket <--+
```

Each step is a push of a small file: submit (`cloud/queue/`), see what's running (`cloud/status/`), fetch results
(`cloud/fetch/`) and cancel (`cloud/cancel/`). That means you can also do all of it from a phone.

## What's a "skill"?

A skill is a folder of instructions an AI agent loads when a task calls for it. This one is `SKILL.md`, plus
templates for the cloud setup and a worked example. Claude Code finds skills in `.claude/skills/`. With other
agents, point them at `SKILL.md` and ask them to follow it.

## Try it

1. Copy this folder into your project as `.claude/skills/cloud-sim-runs/`, or ask your agent: *"Install the skill
   from https://github.com/EmilySmithCreate/cloud-sim-runs into .claude/skills/."*
2. Ask: *"Set up cloud-sim-runs in this repo."* The agent copies the templates and walks you through the one-time
   AWS steps ([reference/setup.md](reference/setup.md)): about 20 minutes, one script pasted into AWS CloudShell,
   and your approval before anything is created.
3. Ask: *"Run the Ising example in the cloud."* It's the simplest form of the question my physics project asks:
   when one arrangement turns into another, how sharp is the change? (More on that below.) Four jobs each simulate
   a grid of tiny magnets, one grid size per job. The magnets line up when cold and scramble when hot. Lars Onsager
   solved this model exactly in 1944: order appears below a temperature of 2.269, in a known amount. So you can
   check the whole loop against numbers you don't have to take on trust, and watch the change get sharper as the
   grid grows. Cost: about a penny. ([What to expect](examples/ising/README.md).)
4. Then point it at your own question.

You need a GitHub repository, an AWS account you control, and the `gh` command-line tool. Docker and Terraform run
on GitHub, not on your machine.

## Questions it has helped answer

I built this for a hobby physics project ([RecreationalPhysics](https://github.com/EmilySmithCreate/RecreationalPhysics)).
I'm not a physicist. The project tests my own hypothesis about how space might form, using a toy network model built
on a published one. Each question below took dozens of independent runs, each lasting hours. Several of my
predictions failed, and the repository records those failures as prominently as the successes.

- **Can I reproduce a published simulation?** My engine matched one published curve from the model's authors to
  within half a percent. It also showed that two published figures from the same group disagree with each other.
- **When a curled-up network opens into a flat one, is the change sudden, and how much energy does it give off?**
  In the two-dimensional toy, yes: a curled tube lasts thousands of steps, then opens from one spot within a few
  hundred, and gives off exactly the energy calculated in advance.
- **Does a bigger system change sooner?** I predicted it would. It didn't: the wait stayed about the same at every
  size, because the barrier turned out to be one local move.
- **In a sealed box, where energy can't escape, what is left over?** A flat space with a few small knots of fixed
  size. The knots don't multiply as the box grows.
- **Does cooling more slowly heal the leftovers?** The largest kind of knot nearly disappears with slow cooling.
  The smaller kinds don't change at all.
- **Does the same thing happen with three or four directions?** Not so far. In every version I tried, one push
  opened one direction and stopped, and my predictions failed.

## Other questions it fits

Anything where you need many independent runs, each too slow or too numerous for your laptop:

- **A/B test planning:** how many users do you need to detect a 2 % lift? Simulate thousands of experiments.
- **Staffing and queues:** how many agents, cashiers or servers keep the wait under five minutes on a busy day?
- **Forecast and schedule risk:** Monte Carlo over the uncertain inputs, to get a range rather than a single number.
- **Sensitivity sweeps:** how much does an epidemic, traffic or market model's answer move as each input changes?
- **Resampling:** bootstrap confidence intervals or permutation tests too slow to run on one machine.
- **Model sweeps:** cross-validation or hyperparameter grids for CPU models, one grid point per job.
- **Reproducing a paper:** rebuild a published figure from the method the paper describes, then ask the question
  the authors left open.

## When a simulation isn't the answer

If a formula gives the answer, use the formula. If the job needs a GPU, or one very large shared memory, use a
bigger single machine, Spark or Dask instead. If each run takes seconds, the minute or two it takes to start a cloud
container dominates, so pack many runs into one config. And if your data may not leave your own environment, this
setup sends it to an AWS account. Make sure that account is one you're allowed to use.

## What it costs, and the brakes

On Fargate in us-east-1, one CPU with 2 GB costs about **$0.05 an hour**, billed by the second while a job runs and
nothing while idle. A batch of 80 CPU-hours costs about $4. The brakes:

- **At most 16 jobs run at once** (`max_vcpus`), so a mistaken push of 500 jobs runs 16 at a time.
- **At most 200 jobs per push**, and every runner and config is checked before anything is built or billed.
- **Each job stops after 24 hours.** One attempt per job, no automatic retries.
- **A finished run is never run again** under the same name, and nothing is submitted from `main`, so a merge
  can't resubmit old batches.
- **Cancel by commit:** push one 7-character commit prefix and every unfinished job from that push stops.
- **Optional budget email** at 80 % of a monthly amount you choose. It's an alert, not a limit.
- **The simulation can only write results.** The role the job runs as can reach nothing else in the account.

The agent is told to show you the cost estimate and get your yes before submitting more than about $5 or 100 jobs.

## Where this came from

The setup behind this skill has run several hundred jobs for the physics project since September 2026. This
packaged, general version is new. Its scripts were checked locally (the cloud wrapper, the acceptance check, the
Terraform, the workflow files), but this exact copy has not yet run end to end in a fresh AWS account. If something
breaks, please open an issue.

All code and documents here were drafted with Claude (Anthropic), working with me.

## License

MIT. See [LICENSE](LICENSE).

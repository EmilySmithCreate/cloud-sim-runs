# Setting it up in a repository

About 20 minutes the first time, most of it waiting. Needs: a GitHub repository (public or private), an AWS
account the user controls, and the `gh` CLI signed in locally. Docker and Terraform are not needed on the laptop;
GitHub Actions runs both.

Do the steps in order. Steps 4 and 6 are the user's: say what to do and wait for them.

## 1. Copy the templates into the repository

From this skill's folder:

| Copy | To |
|---|---|
| `templates/infra/cloud-sim/` | `infra/cloud-sim/` |
| `templates/workflows/*.yml` | `.github/workflows/` |
| `templates/cloud/` | `cloud/` |

If the repository has no `requirements.txt`, create one (it may be empty). The Dockerfile installs from it.

Add `infra/cloud-sim/run.sh text eol=lf` to `.gitattributes` (create it if needed). A copy saved with Windows line
endings fails inside the Linux container with a confusing "not found" error.

Don't gitignore `cloud/`. Fetched runs are committed on purpose, so that the check and the move into `results/` are
on the record. The fetch workflow refuses any file over 95 MB, so keep outputs small. Download big ones by hand.

## 2. Fit the Dockerfile to the project

`infra/cloud-sim/Dockerfile` copies `scripts/`, `configs/` and `requirements.txt`. If the runners import the
project's own package, also copy its source and install it (there is a commented example in the file). **Pin exact
versions** of anything numerical (Python, NumPy, and so on): a result computed in the cloud should be comparable
with one computed on the laptop.

## 3. Choose the names

The defaults work for one stack per AWS account. To run several, give each repository its own short lowercase name
(`[a-z][a-z0-9-]*`, at most 20 characters) and set it as the repository variable `SIM_NAME` in step 5. The name is
used for the job queue, the image repository, the buckets and the IAM role.

## 4. One-time AWS setup (the user, in AWS CloudShell)

The user opens CloudShell in the AWS console (the `>_` icon in the top bar), in the region they want, and runs
`templates/bootstrap/cloudshell_setup.sh` with their GitHub owner and repository name:

```bash
# paste the script into a file first, or upload it with CloudShell's Actions > Upload file
bash cloudshell_setup.sh <github-owner> <github-repo> [name, default simruns]
```

It creates, once:

- **the OIDC identity provider** that lets GitHub Actions sign in to this account without stored keys;
- **the role `<name>-github`**, which only workflows running on a branch of that one repository can assume.
  It has AdministratorAccess so that Terraform can create the stack. In a shared or company account, ask whoever
  runs it for a narrower policy;
- **the Terraform state bucket** `<name>-tfstate-<account id>` and the lock table `<name>-tf-locks`.

The script is safe to run twice: it skips what already exists. At the end it prints the account ID.

## 5. Set the repository variables

```bash
gh variable set AWS_ACCOUNT_ID --body <12-digit id printed by the script>
gh variable set AWS_REGION --body us-east-1          # only if not us-east-1
gh variable set SIM_NAME --body <name>               # only if not simruns
gh variable set SIM_BUDGET_EMAIL --body <email>      # optional: a monthly cost alert
gh variable set SIM_MONTHLY_BUDGET_USD --body 25     # optional, default 25
```

These are variables, not secrets: none of them grants access to anything. The account ID is kept out of the files
anyway, so that the repository can be public.

## 6. Deploy the stack (the user approves)

Commit everything from steps 1 and 2 and push. Then run the deploy workflow as a dry run and read the plan:

```bash
gh workflow run sim_deploy.yml -f action=dry-run
gh run watch
```

The plan should create about 20 resources: the compute environment, job queue, job definition, results bucket,
image repository, three IAM roles, a log group and a security group, plus the budget if an email was set. **Show
the user the plan's summary line and get their yes**, then run:

```bash
gh workflow run sim_deploy.yml -f action=deploy
```

Nothing is billed until a job runs. An idle stack costs close to nothing: a few cents a month for stored images
and results.

`workflow_dispatch` workflows can only be started from the default branch once they exist there. If the user
works on another branch, merge the templates into the default branch first, or start the deploy from the Actions
tab with that branch selected.

## 7. Try the example

Copy `examples/ising/` into the repository (its `scripts/`, `configs/` and `cloud/queue/` files go into the
folders of the same names), then:

1. Run the smallest job locally, `python scripts/ising.py configs/ising_L8.json` (a few seconds), and read
   `results/ising_L8/ising.csv`.
2. On a branch that is not `main`, commit the example and push.
3. Follow SKILL.md: check status, fetch `ising_*`, accept.
4. Compare the four sizes with the expectations in `examples/ising/README.md`.

The model is the 2D Ising model, solved exactly by Onsager, so the example checks the whole loop against numbers
nobody has to trust. The four jobs together cost about a penny.

## Taking it down

`terraform destroy` from `infra/cloud-sim/` with the account's credentials removes the stack. The results bucket
refuses to be deleted while it holds files (`force_destroy = false`); empty it first if you mean it. The state
bucket, lock table, role and OIDC provider from step 4 are removed by hand.

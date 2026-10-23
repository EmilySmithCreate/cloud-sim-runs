# Every value here can be overridden with TF_VAR_<name>; sim_deploy.yml passes the first ones from repository
# variables, so nothing account-specific is written in the files.

variable "aws_account_id" {
  description = "The AWS account this stack lives in (repository variable AWS_ACCOUNT_ID)"
  type        = string

  validation {
    condition     = can(regex("^[0-9]{12}$", var.aws_account_id))
    error_message = "aws_account_id must be a 12-digit AWS account id."
  }
}

variable "name" {
  description = "Short name for the queue, image repository, buckets and roles (repository variable SIM_NAME)"
  type        = string
  default     = "simruns"

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{0,19}$", var.name))
    error_message = "name must be lowercase letters, digits and hyphens, starting with a letter, at most 20 characters."
  }
}

variable "region" {
  description = "AWS region (repository variable AWS_REGION)"
  type        = string
  default     = "us-east-1"
}

variable "budget_email" {
  description = "If set, a monthly AWS Budget emails this address at 80 % and 100 % of monthly_budget_usd"
  type        = string
  default     = ""
}

variable "monthly_budget_usd" {
  description = "The monthly budget, in US dollars, for the alert above. An alert, not a limit: nothing is stopped."
  type        = number
  default     = 25
}

# Size of one job. Fargate allows 1 vCPU with 2 to 8 GB in 1 GB steps; 2 vCPU with 4 to 16 GB; and so on. A
# single-threaded runner gains nothing from more vCPUs: split the work into more jobs instead.
variable "job_vcpu" {
  type    = string
  default = "1"
}

variable "job_memory_mb" {
  type    = string
  default = "2048"
}

# The most vCPUs running at once, so the most jobs at once at 1 vCPU each. This is the main brake on cost: a
# mistaken push of 500 jobs runs 16 at a time, not 500. It cannot exceed the account's Fargate vCPU quota (Service
# Quotas > AWS Fargate > Fargate On-Demand vCPU resource count; new accounts often start low).
variable "max_vcpus" {
  type    = number
  default = 16
}

# Wall-clock ceiling per job, so that a stuck job cannot bill for ever.
variable "job_timeout_hours" {
  type    = number
  default = 24
}

# Fargate Spot is about 70 % cheaper and can stop a job with two minutes' notice. Leave this off unless the runners
# can resume where they stopped, or each job is short enough that losing one is cheap.
variable "use_spot" {
  type    = bool
  default = false
}

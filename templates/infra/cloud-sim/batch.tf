# AWS Batch on Fargate: no servers to manage, billed per second while a job runs, nothing billed while idle.

resource "aws_security_group" "job" {
  name        = "${var.name}-job"
  description = "Outbound only: pull the image, write results to S3"
  vpc_id      = data.aws_vpc.default.id

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_batch_compute_environment" "main" {
  # The name carries the capacity type, so switching use_spot creates a new environment before removing the old
  # one: Batch will not change the type of a live compute environment in place.
  compute_environment_name = "${var.name}-${var.use_spot ? "spot" : "ondemand"}"
  type                     = "MANAGED"
  service_role             = aws_iam_role.batch_service.arn

  compute_resources {
    type               = var.use_spot ? "FARGATE_SPOT" : "FARGATE"
    max_vcpus          = var.max_vcpus
    subnets            = data.aws_subnets.default.ids
    security_group_ids = [aws_security_group.job.id]
  }

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_batch_job_queue" "main" {
  name     = var.name
  state    = "ENABLED"
  priority = 1

  compute_environment_order {
    order               = 1
    compute_environment = aws_batch_compute_environment.main.arn
  }
}

resource "aws_cloudwatch_log_group" "job" {
  name              = "/aws/batch/${var.name}"
  retention_in_days = 90
}

# The container takes the runner, the run name and the submitting commit, runs the one against the other, and
# copies the outputs to S3. Nothing is written back to the repository from here: a result comes back only when
# someone fetches it and accepts it.
resource "aws_batch_job_definition" "run" {
  name                  = "${var.name}-run"
  type                  = "container"
  platform_capabilities = ["FARGATE"]
  propagate_tags        = true

  timeout {
    attempt_duration_seconds = var.job_timeout_hours * 3600
  }

  # One attempt. A retry would restart the run from its beginning with the same seed: the same hours to reach the
  # same place.
  retry_strategy {
    attempts = 1
  }

  container_properties = jsonencode({
    image      = "${aws_ecr_repository.runner.repository_url}:latest"
    command    = ["Ref::runner", "Ref::run", "Ref::commit"]
    jobRoleArn = aws_iam_role.job.arn

    executionRoleArn = aws_iam_role.execution.arn
    networkConfiguration = {
      assignPublicIp = "ENABLED"
    }
    fargatePlatformConfiguration = {
      platformVersion = "LATEST"
    }
    resourceRequirements = [
      { type = "VCPU", value = var.job_vcpu },
      { type = "MEMORY", value = var.job_memory_mb },
    ]
    environment = [
      { name = "RESULTS_BUCKET", value = aws_s3_bucket.results.id },
    ]
    logConfiguration = {
      logDriver = "awslogs"
      options = {
        "awslogs-group"         = aws_cloudwatch_log_group.job.name
        "awslogs-region"        = var.region
        "awslogs-stream-prefix" = "job"
      }
    }
  })

  # Defaults only; every submission names all three.
  parameters = {
    runner = "missing"
    run    = "missing"
    commit = "unknown"
  }
}
